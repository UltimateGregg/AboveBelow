"""Blender-side builder for the split-rail park-fence kit (run inside Blender via bpy).

Usage (from an execute_blender_code call):

    exec(compile(open(r"C:/Programming/S&Box/scripts/build_park_fence.py").read(),
                 "build_park_fence", "exec"), globals())
    build_park_fence("straight")    # or "corner" / "gate_frame" / "gate_leaf"

Conventions (match the project asset pipeline, same as build_fallen_log.py):
  * Real meters. Posts stand along +Z; rails run along Blender +X. Bottom rests at
    Z = 0 -- EXCEPT "gate_leaf", whose origin is the HINGE at ground (0,0,0) so the
    vmdl pivots about the hinge like log_cabin_door (the leaf floats with clearance).
  * Material slot names: "Wood", "Endgrain", "Metal" (must match the remap keys in
    scripts/fence_split_rail*_asset_pipeline.json). Only gate_leaf uses "Metal".
  * Flat-shaded rough-hewn timber (no smooth) -- posts/rails are faceted, riven look.
  * Outward normals (recalc) -- inward faces are culled in s&box.
  * Everything parented under one root empty Fence<Label>_Root (export scope).
  * Tiling baked into UVs so the vmats stay at g_vTexCoordScale [1,1].
    UV: U = around the section, V = along the piece length (grain runs along V).

Nothing here saves or renders; the caller controls that.
"""

import math
import bpy
import bmesh
from mathutils import Vector

TEX_DIR = r"C:/Programming/S&Box/Assets/materials/environment"
MAT_TEX = {
    "Wood": dict(color=TEX_DIR + "/fence_wood_color.png",
                 normal=TEX_DIR + "/fence_wood_normal.png",
                 rough=TEX_DIR + "/fence_wood_rough.png"),
    "Endgrain": dict(color=TEX_DIR + "/fence_endgrain_color.png",
                     normal=TEX_DIR + "/fence_endgrain_normal.png",
                     rough=TEX_DIR + "/fence_endgrain_rough.png"),
}

# material slot indices
M_WOOD, M_END, M_METAL = 0, 1, 2

TILE = 0.5            # metres of length per grain tile (V)
AROUND = 1.0         # texture wraps once around the section (U)

# shared kit dimensions (metres)
BAY = 3.0            # straight-bay length (post spacing)
RAIL_Z = (0.40, 0.78, 1.16)   # three rail heights
POST_W = 0.07        # half-width of a standard post (0.14 m square)
POST_H = 1.32
HEAVY_W = 0.09       # half-width of corner / gate posts (0.18 m)
HEAVY_H = 1.50
RAIL_RW, RAIL_RH = 0.060, 0.045   # split-rail half extents (0.12 x 0.09)

LABELS = {
    "straight":   "SplitRail",
    "corner":     "SplitRailCorner",
    "gate_frame": "SplitRailGateFrame",
    "gate_leaf":  "SplitRailGateLeaf",
}


# ----------------------------------------------------------------------------- scene / materials
def _clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for col in (bpy.data.meshes, bpy.data.materials):
        for d in list(col):
            if d.users == 0:
                col.remove(d)


def _make_materials(need_metal):
    mats = []
    for name in (["Wood", "Endgrain"] + (["Metal"] if need_metal else [])):
        mat = bpy.data.materials.new(name)              # explicit slot name
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if name == "Metal":
            bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.20, 1.0)
            bsdf.inputs["Metallic"].default_value = 0.85
            bsdf.inputs["Roughness"].default_value = 0.5
            mats.append(mat)
            continue
        bsdf.inputs["Metallic"].default_value = 0.0
        spec = MAT_TEX[name]
        col = nt.nodes.new("ShaderNodeTexImage")
        try:
            col.image = bpy.data.images.load(spec["color"], check_existing=True)
            nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        except Exception as exc:
            print("WARN colour", spec["color"], exc)
        try:
            rgh = nt.nodes.new("ShaderNodeTexImage")
            rgh.image = bpy.data.images.load(spec["rough"], check_existing=True)
            rgh.image.colorspace_settings.name = "Non-Color"
            nt.links.new(rgh.outputs["Color"], bsdf.inputs["Roughness"])
        except Exception as exc:
            print("WARN rough", spec.get("rough"), exc)
        try:
            nrm = nt.nodes.new("ShaderNodeTexImage")
            nrm.image = bpy.data.images.load(spec["normal"], check_existing=True)
            nrm.image.colorspace_settings.name = "Non-Color"
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        except Exception as exc:
            print("WARN normal", spec.get("normal"), exc)
        mats.append(mat)
    return mats


# ----------------------------------------------------------------------------- mesh buffer
class MeshBuf:
    def __init__(self):
        self.v = []
        self.faces = []   # (idx_tuple, mat_index, uv_tuple)

    def add_v(self, co):
        self.v.append(tuple(co))
        return len(self.v) - 1

    def add_face(self, idx, mat, uv):
        self.faces.append((tuple(idx), mat, tuple(uv)))


# ----------------------------------------------------------------------------- profiles
def _square(a):
    return [(-a, -a), (a, -a), (a, a), (-a, a)]


def _rect(rw, rh):
    return [(-rw, -rh), (rw, -rh), (rw, rh), (-rw, rh)]


def _octagon(rw, rh):
    pts = []
    for k in range(8):
        ang = 2.0 * math.pi * (k + 0.5) / 8
        pts.append((rw * math.cos(ang), rh * math.sin(ang)))
    return pts


def _basis(axis):
    a = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
    right = a.cross(ref).normalized()
    up = right.cross(a).normalized()
    return right, up


# ----------------------------------------------------------------------------- beam (post / rail / stile / brace)
def _beam(buf, start, end, profile, mat_side=M_WOOD, mat_cap=M_END, *,
          scale0=1.0, scale1=1.0, sag=0.0, nseg=6,
          cap_start=True, cap_end=True, point_cap=0.0, wobble=0.0, seed=0):
    """Extrude `profile` from start to end. profile = list of (right,up) offsets.

    point_cap > 0 finishes the end as a shallow pyramid (post tops). sag bows the
    centre-line down by `sag` metres at mid-span (rails). wobble adds a small
    per-ring scale jitter for a riven look.
    """
    start = Vector(start)
    end = Vector(end)
    axis = end - start
    length = axis.length
    right, up = _basis(axis)
    npf = len(profile)
    R = max(max(abs(r), abs(u)) for (r, u) in profile)

    rings = []
    for i in range(nseg + 1):
        t = i / nseg
        c = start + axis * t
        cz = c.z - sag * math.sin(math.pi * t)
        s = scale0 * (1 - t) + scale1 * t
        if wobble:
            s *= 1.0 + wobble * math.sin(t * 9.0 + seed)
        ring = []
        for (r, u) in profile:
            co = Vector((c.x, c.y, cz)) + right * (r * s) + up * (u * s)
            ring.append(buf.add_v((co.x, co.y, co.z)))
        rings.append(ring)

    for i in range(nseg):
        va = (length * i / nseg) / TILE
        vb = (length * (i + 1) / nseg) / TILE
        for j in range(npf):
            jn = (j + 1) % npf
            a0, a1 = rings[i][j], rings[i][jn]
            b0, b1 = rings[i + 1][j], rings[i + 1][jn]
            ua = (j / npf) * AROUND
            ub = ((j + 1) / npf) * AROUND
            buf.add_face((a0, b0, b1, a1), mat_side, ((ua, va), (ua, vb), (ub, vb), (ub, va)))

    def _capuv(p):
        return (0.5 + p[0] / (2.2 * R), 0.5 + p[1] / (2.2 * R))

    if cap_start:
        cs = buf.add_v((start.x, start.y, start.z))
        for j in range(npf):
            jn = (j + 1) % npf
            buf.add_face((cs, rings[0][jn], rings[0][j]), mat_cap,
                         ((0.5, 0.5), _capuv(profile[jn]), _capuv(profile[j])))
    if cap_end:
        if point_cap > 0.0:
            apex = end + axis.normalized() * point_cap
            aid = buf.add_v((apex.x, apex.y, apex.z))
            for j in range(npf):
                jn = (j + 1) % npf
                buf.add_face((aid, rings[-1][j], rings[-1][jn]), mat_cap,
                             ((0.5, 0.5), _capuv(profile[j]), _capuv(profile[jn])))
        else:
            ce = buf.add_v((end.x, end.y, end.z))
            for j in range(npf):
                jn = (j + 1) % npf
                buf.add_face((ce, rings[-1][j], rings[-1][jn]), mat_cap,
                             ((0.5, 0.5), _capuv(profile[j]), _capuv(profile[jn])))
    return rings[0], rings[-1]


# ----------------------------------------------------------------------------- composites
def _post(buf, cx, cy, half_w, height, *, base_z=0.0):
    """Square hewn post, slight taper, shallow pointed (water-shedding) top."""
    _beam(buf, (cx, cy, base_z), (cx, cy, base_z + height), _square(half_w),
          scale0=1.0, scale1=0.86, nseg=3, point_cap=half_w * 0.9, cap_start=True)


def _rail(buf, start, end, *, sag=0.03, seed=0):
    """Split rail: rounded-octagon section, slight sag + riven wobble."""
    _beam(buf, start, end, _octagon(RAIL_RW, RAIL_RH),
          scale0=0.92, scale1=0.92, sag=sag, nseg=10, wobble=0.05, seed=seed)


def _board(buf, start, end, rw, rh, *, mat_side=M_WOOD, point_cap=0.0):
    """Flat sawn board (gate stile / rail / brace), rectangular section."""
    _beam(buf, start, end, _rect(rw, rh), mat_side=mat_side, nseg=2,
          point_cap=point_cap)


# ----------------------------------------------------------------------------- variants
def _build_straight(buf):
    _post(buf, 0.0, 0.0, POST_W, POST_H)
    for k, z in enumerate(RAIL_Z):
        # rails embed slightly into this post and reach the next post at x=BAY
        _rail(buf, (-0.03, 0.0, z), (BAY, 0.0, z), seed=k * 3 + 1)


def _build_corner(buf):
    _post(buf, 0.0, 0.0, HEAVY_W, HEAVY_H)
    # rail stubs entering from +X and +Y (a 90-degree junction / end post)
    for k, z in enumerate(RAIL_Z):
        _rail(buf, (-0.02, 0.0, z), (0.55, 0.0, z), sag=0.012, seed=k + 10)
        _rail(buf, (0.0, -0.02, z), (0.0, 0.55, z), sag=0.012, seed=k + 20)


def _build_gate_frame(buf):
    # two sturdy gate posts flanking the opening (along +X); short outer stubs tie
    # into the adjoining fence run on both sides.
    GAP = 1.85
    _post(buf, 0.0, 0.0, HEAVY_W, HEAVY_H)
    _post(buf, GAP, 0.0, HEAVY_W, HEAVY_H)
    for k, z in enumerate(RAIL_Z):
        _rail(buf, (-0.45, 0.0, z), (0.0, 0.0, z), sag=0.012, seed=k + 30)        # left tie-in
        _rail(buf, (GAP, 0.0, z), (GAP + 0.45, 0.0, z), sag=0.012, seed=k + 40)   # right tie-in


def _build_gate_leaf(buf):
    # Hinge axis is vertical Z through the origin (0,0,0) at ground. Leaf lies along
    # +X when closed, floating with ground clearance; SwingDoor yaws it about Z.
    LEAF = 1.55       # latch-stile x
    Z0, Z1 = 0.22, 1.18
    TH = 0.025        # half thickness in Y (board ~0.05 thick)
    # vertical stiles (hinge + latch). along +Z -> right=+Y, up=+X
    _board(buf, (0.05, 0.0, Z0), (0.05, 0.0, Z1), TH + 0.005, 0.045)   # hinge stile
    _board(buf, (LEAF, 0.0, Z0), (LEAF, 0.0, Z1), TH + 0.005, 0.040)   # latch stile
    # horizontal rails. along +X -> right=-Y, up=+Z
    for z in (Z0 + 0.06, 0.70, Z1 - 0.06):
        _board(buf, (0.0, 0.0, z), (LEAF + 0.02, 0.0, z), TH, 0.050)
    # diagonal brace (bottom-hinge -> top-latch), thin board in the X-Z plane
    _board(buf, (0.10, 0.0, Z0 + 0.08), (LEAF - 0.08, 0.0, Z1 - 0.08), TH * 0.9, 0.045)
    # metal hinge straps + latch (Metal slot). short beams along +X
    for z in (Z0 + 0.10, Z1 - 0.10):
        _beam(buf, (-0.03, 0.0, z), (0.22, 0.0, z), _rect(0.06, 0.018),
              mat_side=M_METAL, mat_cap=M_METAL, nseg=1)
    _beam(buf, (LEAF - 0.04, 0.0, 0.72), (LEAF + 0.10, 0.0, 0.72), _rect(0.05, 0.016),
          mat_side=M_METAL, mat_cap=M_METAL, nseg=1)


_BUILDERS = {
    "straight": _build_straight,
    "corner": _build_corner,
    "gate_frame": _build_gate_frame,
    "gate_leaf": _build_gate_leaf,
}


def build_park_fence(piece):
    if piece not in _BUILDERS:
        raise ValueError(f"unknown piece '{piece}'; expected one of {list(_BUILDERS)}")
    label = LABELS[piece]
    need_metal = (piece == "gate_leaf")

    _clear_scene()
    buf = MeshBuf()
    _BUILDERS[piece](buf)

    # rest on Z=0 -- except the gate leaf, whose origin must stay at the hinge (z=0)
    if piece != "gate_leaf":
        minz = min(co[2] for co in buf.v)
        buf.v = [(co[0], co[1], co[2] - minz) for co in buf.v]

    mesh = bpy.data.meshes.new(label + "Mesh")
    mesh.from_pydata([Vector(co) for co in buf.v], [], [f[0] for f in buf.faces])
    mesh.update()

    for m in _make_materials(need_metal):
        mesh.materials.append(m)

    uvlay = mesh.uv_layers.new(name="UVMap")
    for poly, (idx, mat, uv) in zip(mesh.polygons, buf.faces):
        poly.material_index = mat
        for k, li in enumerate(poly.loop_indices):
            uvlay.data[li].uv = uv[k]

    mesh.validate(clean_customdata=False)

    # outward normals; flat-shaded (rough-hewn timber)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = False
    mesh.update()

    obj = bpy.data.objects.new("Fence" + label + "Mesh", mesh)
    bpy.context.collection.objects.link(obj)

    root = bpy.data.objects.new("Fence" + label + "_Root", None)
    bpy.context.collection.objects.link(root)
    obj.parent = root

    dims = obj.dimensions
    print("BUILT", piece, "verts=", len(mesh.vertices), "polys=", len(mesh.polygons),
          "dims(m)=", tuple(round(d, 3) for d in dims),
          "minz=", round(min(v.co.z for v in mesh.vertices), 4))
    return obj
