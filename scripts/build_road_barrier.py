"""Blender-side builder for the road-cover concrete barrier (run inside Blender via bpy).

Usage (from an execute_blender_code call):

    exec(compile(open(r"C:/Programming/S&Box/scripts/build_road_barrier.py").read(),
                 "build_road_barrier", "exec"), globals())
    build_road_barrier()

Replaces the old 19-stacked-dev-box RoadCover_Northwest_Barrier with ONE clean swept
Jersey / K-rail concrete barrier mesh.

Conventions (match the project asset pipeline -- see scripts/build_fallen_log.py):
  * Real meters. Length runs along Blender +X, centred on X. Bottom rests at Z = 0.
  * One material slot "Concrete" (must match the remap key in
    scripts/road_cover_northwest_barrier_asset_pipeline.json).
  * Tiling is baked into the UVs so road_barrier_concrete.vmat stays at TexCoordScale [1,1].
  * Outward normals (bmesh recalc) -- inward faces are culled in s&box.
  * All geometry parented under one root empty RoadBarrierNorthwest_Root (export scope).

Envelope reproduces the old cover footprint so it still works as cover in the same spot
and the collision footprint matches: 4.27 m long x 0.86 m base x ~2.0 m tall. In-game that
is meters x 39.37 (prefab Visual scale 15.5): ~168u long x ~34u base x ~79u tall.
"""

import math
import bpy
import bmesh

TEX_DIR = r"C:/Programming/S&Box/Assets/materials/environment"
CONCRETE_TEX = dict(color=TEX_DIR + "/road_barrier_concrete_color.png",
                    normal=TEX_DIR + "/road_barrier_concrete_normal.png",
                    rough=TEX_DIR + "/road_barrier_concrete_rough.png",
                    ao=TEX_DIR + "/road_barrier_concrete_ao.png")

LENGTH = 4.27          # m, along +X
HALF_L = LENGTH / 2.0
NL = 28                # length segments
TILE_M = 1.0           # concrete tile size for baked UVs
WEATHER_AMP = 0.012    # m, subtle cast-concrete surface wobble (y in/out only)

# Closed NJ/Jersey half-section, listed around the cross-section (Y-Z plane):
# bottom-right -> up the +Y face -> across the flat top -> down the -Y face -> bottom-left.
# The bottom edge (last point -> first point) closes the polygon on the ground.
#                 (y,      z)
PROFILE = [
    (0.430, 0.000),   # 0  base outer corner (+Y)
    (0.430, 0.090),   # 1  vertical toe kick top
    (0.305, 0.340),   # 2  end of steep lower batter
    (0.155, 1.400),   # 3  kink to gentle upper batter
    (0.115, 1.920),   # 4  start of top chamfer
    (0.090, 2.000),   # 5  top-right corner
    (-0.090, 2.000),  # 6  top-left corner
    (-0.115, 1.920),  # 7
    (-0.155, 1.400),  # 8
    (-0.305, 0.340),  # 9
    (-0.430, 0.090),  # 10
    (-0.430, 0.000),  # 11 base outer corner (-Y)
]
NP = len(PROFILE)

# corners kept crisp (no surface wobble): the flat-top run and the two top chamfer points
NO_WOBBLE = {4, 5, 6, 7}

# a few faked chips: (ring fraction along length, profile index, pull-in m, pull-up m)
CHIPS = [
    (0.06, 11, 0.05, 0.04),
    (0.52, 0, 0.04, 0.05),
    (0.88, 1, 0.05, 0.03),
]


def _clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for col in (bpy.data.meshes, bpy.data.materials):
        for d in list(col):
            if d.users == 0:
                col.remove(d)


def _make_concrete_material():
    mat = bpy.data.materials.new("Concrete")          # explicit slot name
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0.0
    try:
        col = nt.nodes.new("ShaderNodeTexImage")
        col.image = bpy.data.images.load(CONCRETE_TEX["color"], check_existing=True)
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    except Exception as exc:
        print("WARN colour", CONCRETE_TEX["color"], exc)
    try:
        rgh = nt.nodes.new("ShaderNodeTexImage")
        rgh.image = bpy.data.images.load(CONCRETE_TEX["rough"], check_existing=True)
        rgh.image.colorspace_settings.name = "Non-Color"
        nt.links.new(rgh.outputs["Color"], bsdf.inputs["Roughness"])
    except Exception as exc:
        print("WARN rough", CONCRETE_TEX["rough"], exc)
    try:
        nrm = nt.nodes.new("ShaderNodeTexImage")
        nrm.image = bpy.data.images.load(CONCRETE_TEX["normal"], check_existing=True)
        nrm.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = 1.0
        nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    except Exception as exc:
        print("WARN normal", CONCRETE_TEX["normal"], exc)
    return mat


class MeshBuf:
    """Accumulates verts/faces with per-loop UVs (single material)."""
    def __init__(self):
        self.v = []
        self.faces = []   # list of (idx_tuple, uv_tuple)

    def add_v(self, co):
        self.v.append(co)
        return len(self.v) - 1

    def add_face(self, idx, uv):
        self.faces.append((tuple(idx), tuple(uv)))


def _wobble(x, i):
    """Small deterministic surface perturbation (mostly circumferential ridges)."""
    return (0.55 * math.sin(x * 2.3 + i * 1.7)
            + 0.30 * math.sin(x * 5.1 - i * 0.9)
            + 0.15 * math.sin(x * 11.0 + i * 0.5))


def _profile_arclength():
    """Cumulative arc length around the closed cross-section, for the U coordinate."""
    cum = [0.0]
    for i in range(1, NP):
        ay, az = PROFILE[i - 1]
        by, bz = PROFILE[i]
        cum.append(cum[-1] + math.hypot(by - ay, bz - az))
    return cum


def build_road_barrier():
    _clear_scene()
    buf = MeshBuf()
    cum = _profile_arclength()

    # chip lookup: nearest ring index -> {profile index: (pull_in, pull_up)}
    chip_map = {}
    for frac, pidx, pin, pup in CHIPS:
        ri = round(frac * NL)
        chip_map.setdefault(ri, {})[pidx] = (pin, pup)

    rings = []     # list of vertex-id rings
    metas = []     # list of per-ring (u_list reused from cum, x)
    for ri in range(NL + 1):
        t = ri / NL
        x = -HALF_L + t * LENGTH
        ids = []
        for pi, (py, pz) in enumerate(PROFILE):
            y, z = py, pz
            if pi not in NO_WOBBLE:
                w = _wobble(x, pi)
                # push side faces in/out along Y only; keep Z exact (clean top + ground)
                y = py + WEATHER_AMP * w * (1.0 if py >= 0 else -1.0)
            # chips: pull a corner vertex inward + up on selected rings
            if ri in chip_map and pi in chip_map[ri]:
                pin, pup = chip_map[ri][pi]
                y = y - pin * (1.0 if py >= 0 else -1.0)
                z = z + pup
            ids.append(buf.add_v((x, y, z)))
        rings.append(ids)
        metas.append(x)

    # ---- side quads (bridge consecutive rings around the full closed profile)
    for ri in range(NL):
        xa, xb = metas[ri], metas[ri + 1]
        va = xa / TILE_M
        vb = xb / TILE_M
        for pi in range(NP):
            pj = (pi + 1) % NP
            a0, a1 = rings[ri][pi], rings[ri][pj]
            b0, b1 = rings[ri + 1][pi], rings[ri + 1][pj]
            ua = cum[pi] / TILE_M
            ub = (cum[pj] if pj != 0 else cum[-1] + 0.001) / TILE_M
            buf.add_face((a0, b0, b1, a1),
                         ((ua, va), (ua, vb), (ub, vb), (ub, va)))

    # ---- end caps (triangle fan from cross-section centroid), planar UV from (y,z)
    def cap(ring, x_end, flip):
        cy = sum(buf.v[i][1] for i in ring) / NP
        cz = sum(buf.v[i][2] for i in ring) / NP
        center = buf.add_v((x_end, cy, cz))

        def duv(vid):
            _, y, z = buf.v[vid]
            return (y + 0.5, z)
        for pi in range(NP):
            pj = (pi + 1) % NP
            if flip:
                tri = (center, ring[pj], ring[pi])
            else:
                tri = (center, ring[pi], ring[pj])
            buf.add_face(tri, ((cy + 0.5, cz), duv(tri[1]), duv(tri[2])))

    cap(rings[0], -HALF_L, flip=True)
    cap(rings[-1], HALF_L, flip=False)

    # ---- build mesh
    mesh = bpy.data.meshes.new("RoadBarrierNorthwestMesh")
    mesh.from_pydata([tuple(co) for co in buf.v], [], [f[0] for f in buf.faces])
    mesh.update()

    mat = _make_concrete_material()
    mesh.materials.append(mat)

    uvlay = mesh.uv_layers.new(name="UVMap")
    for poly, (_idx, uv) in zip(mesh.polygons, buf.faces):
        poly.material_index = 0
        for k, li in enumerate(poly.loop_indices):
            uvlay.data[li].uv = uv[k]

    mesh.validate(clean_customdata=False)

    # outward normals (s&box culls inward)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new("RoadBarrierNorthwestMesh", mesh)
    bpy.context.collection.objects.link(obj)
    for p in mesh.polygons:           # crisp cast-concrete facets
        p.use_smooth = False

    root = bpy.data.objects.new("RoadBarrierNorthwest_Root", None)
    bpy.context.collection.objects.link(root)
    obj.parent = root

    dims = obj.dimensions
    print("BUILT road_barrier verts=", len(mesh.vertices), "polys=", len(mesh.polygons),
          "dims(m)=", tuple(round(d, 3) for d in dims),
          "minz=", round(min(v.co.z for v in mesh.vertices), 4))
    return obj
