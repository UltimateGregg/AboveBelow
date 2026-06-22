"""Blender-side builder for the fallen-log cover set (run inside Blender via bpy).

Usage (from an execute_blender_code call):

    exec(compile(open(r"C:/Programming/S&Box/scripts/build_fallen_log.py").read(),
                 "build_fallen_log", "exec"), globals())
    build_fallen_log("straight")        # or "angled" / "hollow" / "mossy"

Conventions (match the project asset pipeline):
  * Real meters. Length runs along Blender +X. Bottom rests at Z = 0.
  * Material slot names: "Bark", "Endgrain", "Moss" (must match the remap keys
    in scripts/fallen_log_<variant>_asset_pipeline.json).
  * Every mesh gets outward normals (recalc) -- inward normals are culled in s&box.
  * All parts parented under one root empty FallenLog<Variant>_Root (export scope).
  * Tiling is baked into the UVs so the vmats stay at g_vTexCoordScale [1,1].

Nothing here saves or renders; the caller controls that.
"""

import math
import bpy
import bmesh
from mathutils import Vector, Matrix

TEX_DIR = r"C:/Programming/S&Box/Assets/materials/environment"
MAT_TEX = {
    "Bark": dict(color=TEX_DIR + "/fallen_log_bark_color.png",
                 normal=TEX_DIR + "/fallen_log_bark_normal.png",
                 rough=TEX_DIR + "/fallen_log_bark_rough.png"),
    "Endgrain": dict(color=TEX_DIR + "/fallen_log_endgrain_color.png",
                     normal=TEX_DIR + "/fallen_log_endgrain_normal.png",
                     rough=TEX_DIR + "/fallen_log_endgrain_rough.png"),
    "Moss": dict(color=TEX_DIR + "/fallen_log_moss_color.png",
                 normal=TEX_DIR + "/fallen_log_moss_normal.png",
                 rough=TEX_DIR + "/fallen_log_moss_rough.png"),
}

# material slot indices
M_BARK, M_END, M_MOSS = 0, 1, 2

VARIANTS = {
    # r0/r1 = base/tip radius (m); bend = lateral banana (m); lean = deg tip lift
    "straight": dict(length=7.0, r0=0.48, r1=0.31, bend=0.12, lean=0.0,
                     hollow=None, moss=False, seed=1, label="Straight"),
    "angled":   dict(length=6.0, r0=0.46, r1=0.30, bend=0.10, lean=22.0,
                     hollow=None, moss=False, seed=2, label="Angled"),
    "hollow":   dict(length=5.5, r0=0.55, r1=0.46, bend=0.08, lean=0.0,
                     hollow=0.80, moss=False, seed=3, label="Hollow"),  # hollow=bore frac of radius (thin wall)
    "mossy":    dict(length=7.0, r0=0.50, r1=0.33, bend=0.14, lean=0.0,
                     hollow=None, moss=True, seed=4, label="Mossy"),
}

NR = 24    # radial segments
NL = 22    # length segments
AROUND_REPEATS = 4.0
METERS_PER_TILE = 1.7


# ----------------------------------------------------------------------------- helpers
def _bark_noise(theta, x, seed):
    """Small radial perturbation, mostly circumferential -> vertical bark ridges."""
    return (0.55 * math.sin(theta * 5.0 + seed * 1.7)
            + 0.25 * math.sin(theta * 11.0 - x * 1.1 + seed)
            + 0.12 * math.sin(theta * 19.0 + x * 0.6)
            + 0.08 * math.sin(theta * 3.0 + x * 2.3 + seed * 0.5))


def _clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for col in (bpy.data.meshes, bpy.data.materials):
        for d in list(col):
            if d.users == 0:
                col.remove(d)


def _make_materials(need_moss):
    mats = []
    for name in (["Bark", "Endgrain"] + (["Moss"] if need_moss else [])):
        spec = MAT_TEX[name]
        mat = bpy.data.materials.new(name)            # explicit slot name
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Metallic"].default_value = 0.0
        # base colour
        col = nt.nodes.new("ShaderNodeTexImage")
        try:
            col.image = bpy.data.images.load(spec["color"], check_existing=True)
            nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        except Exception as exc:
            print("WARN colour", spec["color"], exc)
        # roughness (non-colour data)
        try:
            rgh = nt.nodes.new("ShaderNodeTexImage")
            rgh.image = bpy.data.images.load(spec["rough"], check_existing=True)
            rgh.image.colorspace_settings.name = "Non-Color"
            nt.links.new(rgh.outputs["Color"], bsdf.inputs["Roughness"])
        except Exception as exc:
            print("WARN rough", spec.get("rough"), exc)
        # normal map
        try:
            nrm = nt.nodes.new("ShaderNodeTexImage")
            nrm.image = bpy.data.images.load(spec["normal"], check_existing=True)
            nrm.image.colorspace_settings.name = "Non-Color"
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.inputs["Strength"].default_value = 1.0
            nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        except Exception as exc:
            print("WARN normal", spec.get("normal"), exc)
        mats.append(mat)
    return mats


class MeshBuf:
    """Accumulates verts/faces with per-face material index and per-loop UVs."""
    def __init__(self):
        self.v = []
        self.faces = []   # list of (idx_tuple, mat_index, uv_tuple)

    def add_v(self, co):
        self.v.append(co)
        return len(self.v) - 1

    def add_face(self, idx, mat, uv):
        self.faces.append((tuple(idx), mat, tuple(uv)))


def _ring(buf, cx, cy, cz, radius, bend_y, seed, broken=0.0):
    """One ring of NR verts in the Y-Z plane at x=cx. Returns vert indices + meta."""
    ids = []
    meta = []  # (theta, x) for UV
    for j in range(NR):
        theta = 2.0 * math.pi * j / NR
        nz = _bark_noise(theta, cx, seed)
        rr = radius * (1.0 + 0.07 * nz)
        x = cx
        if broken:
            x += broken * radius * (0.5 * math.sin(theta * 7 + seed) + 0.5 * math.sin(theta * 3 - seed))
        y = cy + bend_y + rr * math.cos(theta)
        z = cz + rr * math.sin(theta)
        ids.append(buf.add_v((x, y, z)))
        meta.append((theta, x))
    return ids, meta


def _bridge(buf, ring_a, meta_a, ring_b, meta_b, mat, moss_seed=None):
    """Quad strip between two rings, outward winding, UVs baked for tiling."""
    for j in range(NR):
        jn = (j + 1) % NR
        a0, a1 = ring_a[j], ring_a[jn]
        b0, b1 = ring_b[j], ring_b[jn]
        # u around, v along
        ua = (j / NR) * AROUND_REPEATS
        ub = ((j + 1) / NR) * AROUND_REPEATS
        va = meta_a[j][1] / METERS_PER_TILE
        vb = meta_b[j][1] / METERS_PER_TILE
        face_mat = mat
        if moss_seed is not None:
            theta_mid = 2.0 * math.pi * (j + 0.5) / NR
            up = math.sin(theta_mid)
            patch = 0.5 * math.sin(theta_mid * 3 + moss_seed) + 0.5 * math.sin(va * 2.0 + moss_seed)
            if up > 0.30 and patch > -0.15:
                face_mat = M_MOSS
        buf.add_face((a0, b0, b1, a1), face_mat,
                     ((ua, va), (ua, vb), (ub, vb), (ub, va)))


def _cap(buf, ring, meta, cx, cy, cz, radius, bend_y, mat, flip, jitter=0.0, seed=0):
    """Triangle fan to a center vertex; UVs map the disc to 0..1 of the texture."""
    cxx = cx + (jitter * radius * 0.5 if jitter else 0.0)
    center = buf.add_v((cxx, cy + bend_y, cz))
    for j in range(NR):
        jn = (j + 1) % NR
        # planar disc UV from (y,z) relative to centre
        def duv(vid):
            x, y, z = buf.v[vid]
            return (0.5 + (y - (cy + bend_y)) / (2.2 * radius),
                    0.5 + (z - cz) / (2.2 * radius))
        if flip:
            tri = (center, ring[jn], ring[j])
        else:
            tri = (center, ring[j], ring[jn])
        buf.add_face(tri, mat, (( 0.5, 0.5), duv(tri[1]), duv(tri[2])))


def _annulus(buf, outer, ometa, inner, imeta, mat, flip):
    """End ring connecting outer rim to inner rim (hollow log wall thickness)."""
    for j in range(NR):
        jn = (j + 1) % NR
        o0, o1, i0, i1 = outer[j], outer[jn], inner[j], inner[jn]
        u0, u1 = j / NR, (j + 1) / NR
        if flip:
            quad = (o0, o1, i1, i0)
        else:
            quad = (o0, i0, i1, o1)
        buf.add_face(quad, mat, ((u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)))


def _add_stub(buf, base, direction, base_r, tip_r, length, seed):
    """A short broken branch stub: tapered cylinder + endgrain tip cap."""
    d = direction.normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))
    side = d.cross(up).normalized()
    up2 = side.cross(d).normalized()
    nseg = 4
    rings = []
    for i in range(nseg + 1):
        t = i / nseg
        c = base + d * (length * t)
        r = base_r * (1 - t) + tip_r * t
        ring = []
        for j in range(8):
            a = 2 * math.pi * j / 8
            rr = r * (1.0 + 0.12 * math.sin(a * 3 + seed + t * 4))
            co = c + side * (rr * math.cos(a)) + up2 * (rr * math.sin(a))
            ring.append(buf.add_v((co.x, co.y, co.z)))
        rings.append(ring)
    for i in range(nseg):
        for j in range(8):
            jn = (j + 1) % 8
            buf.add_face((rings[i][j], rings[i + 1][j], rings[i + 1][jn], rings[i][jn]),
                         M_BARK, ((0, 0), (0, 1), (1, 1), (1, 0)))
    # tip cap (endgrain)
    tip_c = base + d * length
    cid = buf.add_v((tip_c.x, tip_c.y, tip_c.z))
    for j in range(8):
        jn = (j + 1) % 8
        buf.add_face((cid, rings[-1][j], rings[-1][jn]), M_END,
                     ((0.5, 0.5), (0.2, 0.5), (0.5, 0.8)))


# ----------------------------------------------------------------------------- variants
def _build_solid(buf, cfg):
    length, r0, r1 = cfg["length"], cfg["r0"], cfg["r1"]
    bend, seed = cfg["bend"], cfg["seed"]
    cz = r0
    moss_seed = seed * 3.1 if cfg["moss"] else None
    rings, metas, bends = [], [], []
    for i in range(NL + 1):
        t = i / NL
        cx = t * length
        radius = r0 * (1 - t) + r1 * t
        by = bend * math.sin(math.pi * t)
        broken = 0.0 if i < NL - 1 else 0.6  # last segment jagged
        ids, meta = _ring(buf, cx, 0.0, cz, radius, by, seed, broken=broken)
        rings.append(ids); metas.append(meta); bends.append(by)
    for i in range(NL):
        _bridge(buf, rings[i], metas[i], rings[i + 1], metas[i + 1], M_BARK, moss_seed)
    # base end: sawn flat; tip end: broken
    r_base = r0
    r_tip = r1
    _cap(buf, rings[0], metas[0], 0.0, 0.0, cz, r_base, bends[0], M_END, flip=True)
    _cap(buf, rings[-1], metas[-1], length, 0.0, cz, r_tip, bends[-1], M_END,
         flip=False, jitter=-0.8, seed=seed)
    # branch stubs
    stub_specs = [(0.30, 70), (0.55, 200), (0.78, 320)]
    for frac, ang_deg in stub_specs:
        t = frac
        cx = t * length
        radius = r0 * (1 - t) + r1 * t
        by = bend * math.sin(math.pi * t)
        a = math.radians(ang_deg)
        outdir = Vector((0.25, math.cos(a), abs(math.sin(a)) * 0.8 + 0.3)).normalized()
        base = Vector((cx, by + radius * 0.7 * math.cos(a), cz + radius * 0.7 * math.sin(a)))
        _add_stub(buf, base, outdir, base_r=0.09, tip_r=0.05,
                  length=0.30 + 0.12 * (frac), seed=seed + frac)


def _build_hollow(buf, cfg):
    length, r0, r1 = cfg["length"], cfg["r0"], cfg["r1"]
    bend, seed = cfg["bend"], cfg["seed"]
    inner_frac = cfg["hollow"]   # bore radius as a fraction of the outer radius
    cz = r0
    out_rings, out_meta, in_rings, in_meta, bends = [], [], [], [], []
    for i in range(NL + 1):
        t = i / NL
        cx = t * length
        radius = r0 * (1 - t) + r1 * t
        by = bend * math.sin(math.pi * t)
        broken = 0.7 if (i == 0 or i == NL) else 0.0
        inner = radius * inner_frac * (1.0 + 0.04 * math.sin(t * 9 + seed))  # thin wall
        oids, ometa = _ring(buf, cx, 0.0, cz, radius, by, seed, broken=broken)
        iids, imeta = _ring(buf, cx, 0.0, cz, inner,
                            by, seed + 50, broken=broken * 0.6)
        out_rings.append(oids); out_meta.append(ometa)
        in_rings.append(iids); in_meta.append(imeta); bends.append(by)
    for i in range(NL):
        _bridge(buf, out_rings[i], out_meta[i], out_rings[i + 1], out_meta[i + 1], M_BARK)
    # inner wall (flip winding so normals face the bore)
    for i in range(NL):
        _bridge(buf, in_rings[i + 1], in_meta[i + 1], in_rings[i], in_meta[i], M_END)
    # end annuli (wall thickness rings)
    _annulus(buf, out_rings[0], out_meta[0], in_rings[0], in_meta[0], M_END, flip=True)
    _annulus(buf, out_rings[-1], out_meta[-1], in_rings[-1], in_meta[-1], M_END, flip=False)
    # a couple of stubs
    for frac, ang_deg in [(0.35, 60), (0.7, 250)]:
        t = frac
        cx = t * length
        radius = r0 * (1 - t) + r1 * t
        by = bend * math.sin(math.pi * t)
        a = math.radians(ang_deg)
        outdir = Vector((0.2, math.cos(a), abs(math.sin(a)) * 0.8 + 0.3)).normalized()
        base = Vector((cx, by + radius * 0.8 * math.cos(a), cz + radius * 0.8 * math.sin(a)))
        _add_stub(buf, base, outdir, 0.08, 0.045, 0.28, seed + frac)


def build_fallen_log(variant):
    cfg = VARIANTS[variant]
    _clear_scene()
    buf = MeshBuf()
    if cfg["hollow"]:
        _build_hollow(buf, cfg)
    else:
        _build_solid(buf, cfg)

    # lean (angled variant): rotate about base pivot around Y so the tip lifts
    if cfg["lean"]:
        ang = math.radians(cfg["lean"])
        rot = Matrix.Rotation(ang, 4, 'Y')
        pivot = Vector((0.0, 0.0, cfg["r0"]))
        buf.v = [tuple(rot @ (Vector(co) - pivot) + pivot) for co in buf.v]

    # drop so the lowest point rests on Z = 0
    minz = min(co[2] for co in buf.v)
    buf.v = [(co[0], co[1], co[2] - minz) for co in buf.v]

    mesh = bpy.data.meshes.new(cfg["label"] + "Mesh")
    mesh.from_pydata([Vector(co) for co in buf.v],
                     [], [f[0] for f in buf.faces])
    mesh.update()

    mats = _make_materials(cfg["moss"])
    for m in mats:
        mesh.materials.append(m)

    uvlay = mesh.uv_layers.new(name="UVMap")
    for poly, (idx, mat, uv) in zip(mesh.polygons, buf.faces):
        poly.material_index = mat
        for k, li in enumerate(poly.loop_indices):
            uvlay.data[li].uv = uv[k]

    mesh.validate(clean_customdata=False)

    # outward normals (s&box culls inward) -- recalc via bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new(cfg["label"] + "Mesh", mesh)
    bpy.context.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True

    root = bpy.data.objects.new("FallenLog" + cfg["label"] + "_Root", None)
    bpy.context.collection.objects.link(root)
    obj.parent = root

    # report
    dims = obj.dimensions
    print("BUILT", variant, "verts=", len(mesh.vertices), "polys=", len(mesh.polygons),
          "dims(m)=", tuple(round(d, 3) for d in dims),
          "minz=", round(min(v.co.z for v in mesh.vertices), 4))
    return obj
