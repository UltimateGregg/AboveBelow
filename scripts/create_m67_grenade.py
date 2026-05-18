import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BLEND_PATH = PROJECT_ROOT / "weapons_model.blend" / "frag_grenade.blend"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_material(name, color, roughness, metallic):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return material


def shade_smooth(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_bevel(obj, amount, segments):
    bevel = obj.modifiers.new(name="Small bevels", type="BEVEL")
    bevel.width = amount
    bevel.segments = segments
    bevel.affect = "EDGES"
    weighted = obj.modifiers.new(name="Weighted metal normals", type="WEIGHTED_NORMAL")
    weighted.keep_sharp = True
    return bevel, weighted


def add_uv_sphere(name, radius, location, material, segments=64, rings=32, rough_cast=False):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=radius,
        location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.data.materials.append(material)

    if rough_cast:
        random.seed(67)
        for vert in obj.data.vertices:
            direction = vert.co.normalized()
            noise = random.uniform(-0.018, 0.028)
            latitude_fade = max(0.25, min(1.0, abs(direction.z) + 0.45))
            vert.co += direction * noise * latitude_fade

    shade_smooth(obj)
    return obj


def add_cylinder(name, radius, depth, location, material, vertices=64, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.data.materials.append(material)
    shade_smooth(obj)
    return obj


def add_beveled_cube(name, location, scale, material, rotation=(0, 0, 0), bevel=0.03, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.scale = scale
    obj.data.materials.append(material)
    apply_scale(obj)
    add_bevel(obj, bevel, segments)
    return obj


def add_tapered_fuze(name, material):
    verts = [
        (-0.34, -0.28, 2.38),
        (0.34, -0.28, 2.38),
        (0.34, 0.28, 2.38),
        (-0.34, 0.28, 2.38),
        (-0.27, -0.24, 3.15),
        (0.27, -0.24, 3.15),
        (0.27, 0.24, 3.15),
        (-0.27, 0.24, 3.15),
    ]
    faces = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    add_bevel(obj, 0.04, 3)
    return obj


def add_curved_safety_lever(material):
    mesh = bpy.data.meshes.new("SafetyLever_mesh")
    bm = bmesh.new()

    # A long spoon-like lever that starts at the top hinge and drops down the
    # side of the grenade, matching the silhouette of the reference M67 top.
    centerline = [
        Vector((0.36, 0.17, 3.14)),
        Vector((0.62, 0.18, 3.04)),
        Vector((0.82, 0.16, 2.70)),
        Vector((0.92, 0.12, 2.18)),
        Vector((0.88, 0.10, 1.58)),
    ]
    half_width = 0.105
    thickness = 0.045
    rings = []

    for point in centerline:
        row = []
        for y_offset in (-half_width, half_width):
            for z_offset in (-thickness, thickness):
                row.append(bm.verts.new((point.x, point.y + y_offset, point.z + z_offset)))
        rings.append(row)

    bm.verts.ensure_lookup_table()
    for index in range(len(rings) - 1):
        a = rings[index]
        b = rings[index + 1]
        bm.faces.new((a[0], b[0], b[1], a[1]))
        bm.faces.new((a[2], a[3], b[3], b[2]))
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((a[1], b[1], b[3], a[3]))
    bm.faces.new((rings[0][0], rings[0][1], rings[0][3], rings[0][2]))
    bm.faces.new((rings[-1][0], rings[-1][2], rings[-1][3], rings[-1][1]))

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new("SafetyLever", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    add_bevel(obj, 0.018, 2)
    return obj


def add_pull_ring(material):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.34,
        minor_radius=0.035,
        major_segments=72,
        minor_segments=12,
        location=(0.47, -0.46, 2.83),
        rotation=(math.radians(88), math.radians(8), math.radians(12)),
    )
    ring = bpy.context.active_object
    ring.name = "PullRing"
    ring.data.name = "PullRing_mesh"
    ring.data.materials.append(material)
    shade_smooth(ring)
    return ring


def parent_to(root, objects):
    for obj in objects:
        obj.parent = root


def build_grenade():
    clear_scene()

    body_mat = make_material("Grenade_Body", (0.28, 0.33, 0.16, 1.0), 0.86, 0.0)
    metal_mat = make_material("Grenade_Pin", (0.74, 0.72, 0.66, 1.0), 0.28, 0.92)

    root = bpy.data.objects.new("Frag_Grenade", None)
    bpy.context.collection.objects.link(root)

    created = []
    body = add_uv_sphere("Body", 1.12, (0, 0, 1.16), body_mat, rough_cast=True)
    body.scale = (1.04, 1.04, 0.98)
    apply_scale(body)
    created.append(body)

    created.append(add_cylinder("FlatBottom", 0.83, 0.08, (0, 0, 0.08), body_mat, vertices=72))
    created.append(add_cylinder("OliveNeckCollar", 0.47, 0.22, (0, 0, 2.20), body_mat, vertices=72))
    created.append(add_cylinder("OliveFuzeBaseRing", 0.39, 0.20, (0, 0, 2.38), body_mat, vertices=72))

    created.append(add_tapered_fuze("SilverFuzeBody", metal_mat))
    created.append(add_beveled_cube("FuzeTopPlate", (0.08, 0, 3.18), (0.50, 0.36, 0.09), metal_mat, bevel=0.035, segments=3))
    created.append(add_cylinder("HingeTube", 0.075, 0.62, (0.17, -0.02, 3.24), metal_mat, vertices=32, rotation=(math.radians(90), 0, 0)))
    created.append(add_cylinder("PullPin", 0.035, 0.74, (0.37, -0.05, 2.94), metal_mat, vertices=24, rotation=(math.radians(86), 0, 0)))
    created.append(add_pull_ring(metal_mat))
    created.append(add_curved_safety_lever(metal_mat))

    # Small circular side detail on the fuze body. It uses the same material
    # slot as the rest of the fuze so the existing S&Box remap stays stable.
    hole = add_cylinder("FuzeSideDetail", 0.048, 0.018, (0.345, -0.12, 2.91), metal_mat, vertices=24, rotation=(0, math.radians(90), 0))
    created.append(hole)

    parent_to(root, created)

    for obj in created:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


build_grenade()
