"""
Create a more realistic M4 variant from the currently open Blender scene.

Run inside the visible Blender session through the project Blender MCP bridge.
The script saves the open scene to a new .blend first so the original source
file remains untouched, then adds detail geometry and procedural materials.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
OUTPUT_BLEND = PROJECT_ROOT / "weapons_model.blend" / "assault_rifle_m4_realistic.blend"
PREVIEW_PATH = PROJECT_ROOT / "screenshots" / "assault_rifle_m4_realistic_preview.png"
DETAIL_FLAG = "m4_realistic_detail"
DETAIL_PREFIX = "RDetail_"

try:
    result
except NameError:
    result = {}


def save_variant_before_editing() -> None:
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))


def root_object():
    root = bpy.data.objects.get("AssaultRifle_M4")
    if root is None:
        root = bpy.data.objects.new("AssaultRifle_M4", None)
        bpy.context.collection.objects.link(root)
    return root


def remove_previous_details() -> int:
    removed = 0
    for obj in list(bpy.data.objects):
        if obj.get(DETAIL_FLAG) or obj.name.startswith(DETAIL_PREFIX):
            data = obj.data
            data_type = obj.type
            bpy.data.objects.remove(obj, do_unlink=True)
            if data and data.users == 0:
                if data_type == "MESH":
                    bpy.data.meshes.remove(data)
                elif data_type == "CURVE":
                    bpy.data.curves.remove(data)
                elif data_type == "FONT":
                    bpy.data.curves.remove(data)
            removed += 1
    return removed


def get_bsdf(mat):
    if not mat.use_nodes:
        mat.use_nodes = True
    return mat.node_tree.nodes.get("Principled BSDF")


def material(name: str, base, accent, metallic: float, roughness: float, bump_strength: float = 0.05):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = base
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = get_bsdf(mat)
    if bsdf is None:
        return mat

    for node in list(nodes):
        if node.name.startswith("Realistic_"):
            nodes.remove(node)

    noise = nodes.new("ShaderNodeTexNoise")
    noise.name = "Realistic_Surface_Noise"
    noise.inputs["Scale"].default_value = 42.0
    noise.inputs["Detail"].default_value = 13.0
    noise.inputs["Roughness"].default_value = 0.62

    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.name = "Realistic_Color_Variation"
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = base
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = accent

    bump = nodes.new("ShaderNodeBump")
    bump.name = "Realistic_Fine_Bump"
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.08

    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = roughness
    if "Normal" in bsdf.inputs:
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def build_materials():
    return {
        "receiver": material(
            "M4_Receiver",
            (0.022, 0.024, 0.026, 1.0),
            (0.085, 0.088, 0.084, 1.0),
            0.55,
            0.48,
            0.035,
        ),
        "polymer": material(
            "M4_Polymer",
            (0.011, 0.012, 0.013, 1.0),
            (0.055, 0.058, 0.055, 1.0),
            0.02,
            0.82,
            0.075,
        ),
        "rubber": material(
            "M4_Rubber",
            (0.004, 0.004, 0.004, 1.0),
            (0.035, 0.035, 0.033, 1.0),
            0.0,
            0.93,
            0.11,
        ),
        "bare": material(
            "M4_BareMetal",
            (0.58, 0.57, 0.54, 1.0),
            (0.9, 0.88, 0.78, 1.0),
            0.9,
            0.31,
            0.02,
        ),
        "accent": material(
            "M4_Accent",
            (0.07, 0.072, 0.07, 1.0),
            (0.16, 0.16, 0.15, 1.0),
            0.35,
            0.6,
            0.04,
        ),
        "markings": material(
            "M4_Markings",
            (0.7, 0.69, 0.62, 1.0),
            (0.96, 0.94, 0.82, 1.0),
            0.05,
            0.72,
            0.0,
        ),
        "shadow": material(
            "M4_DarkRecess",
            (0.0, 0.0, 0.0, 1.0),
            (0.018, 0.018, 0.018, 1.0),
            0.0,
            0.98,
            0.0,
        ),
    }


def tag(obj, parent=None):
    obj[DETAIL_FLAG] = True
    if parent is not None:
        obj.parent = parent
    return obj


def finish(obj, mat, bevel: float = 0.02, segments: int = 1):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    if bevel > 0:
        bevel_mod = obj.modifiers.new("realistic bevels", "BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = segments
        bevel_mod.affect = "EDGES"
    normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    normal_mod.keep_sharp = True
    return obj


def box(name, loc, scale, mat, bevel=0.02, rot=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = DETAIL_PREFIX + name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return tag(obj, parent)


def cylinder(
    name,
    loc,
    radius,
    depth,
    mat,
    vertices=32,
    rot=(0.0, math.pi / 2.0, 0.0),
    bevel=0.0,
    parent=None,
):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = DETAIL_PREFIX + name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return tag(obj, parent)


def torus(name, loc, mat, major=0.22, minor=0.035, rot=(0.0, math.pi / 2.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=40,
        minor_segments=10,
        major_radius=major,
        minor_radius=minor,
        location=loc,
        rotation=rot,
    )
    obj = bpy.context.object
    obj.name = DETAIL_PREFIX + name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return tag(obj, parent)


def curve(name, points, mat, bevel_depth=0.035, parent=None):
    data = bpy.data.curves.new(DETAIL_PREFIX + name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 3
    data.bevel_depth = bevel_depth
    data.bevel_resolution = 3
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (co[0], co[1], co[2], 1.0)
    data.materials.append(mat)
    obj = bpy.data.objects.new(DETAIL_PREFIX + name, data)
    bpy.context.collection.objects.link(obj)
    return tag(obj, parent)


def label(name, text, loc, size, mat, rot=(math.radians(90), 0.0, 0.0), parent=None):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = DETAIL_PREFIX + name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.01
    obj.data.resolution_u = 2
    obj.data.materials.append(mat)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return tag(obj, parent)


def add_handguard(root, mats):
    receiver = mats["receiver"]
    shadow = mats["shadow"]
    bare = mats["bare"]
    accent = mats["accent"]

    cylinder("Delta_Ring_Taper", (4.05, 0.0, 1.62), 0.95, 0.46, receiver, vertices=44, bevel=0.018, parent=root)
    cylinder("Barrel_Nut_Ring", (4.42, 0.0, 1.62), 0.82, 0.36, accent, vertices=40, bevel=0.012, parent=root)
    cylinder("Muzzle_Crown_Dark_Bore", (20.62, 0.0, 1.66), 0.16, 0.08, shadow, vertices=32, bevel=0.0, parent=root)

    for side, y in (("Left", -0.93), ("Right", 0.93)):
        for row, z in enumerate((1.22, 1.75)):
            for i, x in enumerate([5.2, 6.35, 7.5, 8.65, 9.8, 10.95, 12.1]):
                box(
                    f"Handguard_{side}_Mlok_{row}_{i}",
                    (x, y, z),
                    (0.72, 0.035, 0.18),
                    shadow,
                    0.018,
                    parent=root,
                )
        for i, x in enumerate([4.8, 6.0, 7.2, 8.4, 9.6, 10.8, 12.0]):
            cylinder(
                f"Handguard_{side}_HexScrew_{i}",
                (x, y * 1.01, 2.2),
                0.075,
                0.045,
                bare,
                vertices=6,
                rot=(math.pi / 2.0, 0.0, 0.0),
                bevel=0.002,
                parent=root,
            )


def add_receiver_controls(root, mats):
    receiver = mats["receiver"]
    accent = mats["accent"]
    bare = mats["bare"]
    shadow = mats["shadow"]
    markings = mats["markings"]

    box("Bolt_Visible_In_Ejection_Port", (1.02, -0.783, 1.91), (1.72, 0.035, 0.3), bare, 0.008, parent=root)
    cylinder(
        "Dust_Cover_Hinge_Pin",
        (1.02, -0.83, 2.19),
        0.045,
        2.25,
        bare,
        vertices=14,
        rot=(0.0, math.pi / 2.0, 0.0),
        bevel=0.001,
        parent=root,
    )
    box("Mag_Release_Button", (-0.55, -0.815, 0.94), (0.34, 0.07, 0.22), accent, 0.012, parent=root)
    cylinder(
        "Trigger_Pin_Left",
        (-2.27, -0.78, 0.67),
        0.08,
        0.07,
        bare,
        vertices=18,
        rot=(math.pi / 2.0, 0.0, 0.0),
        parent=root,
    )
    cylinder(
        "Hammer_Pin_Left",
        (-2.82, -0.78, 1.09),
        0.08,
        0.07,
        bare,
        vertices=18,
        rot=(math.pi / 2.0, 0.0, 0.0),
        parent=root,
    )

    for i, x in enumerate([1.3, 1.65, 2.0]):
        cylinder(
            f"Forward_Assist_Serration_{i}",
            (x, 1.245, 1.91),
            0.17,
            0.035,
            shadow,
            vertices=18,
            rot=(math.pi / 2.0, 0.0, 0.0),
            bevel=0.001,
            parent=root,
        )

    curve(
        "Curved_Trigger_Profile",
        [(-2.43, -0.18, 0.26), (-2.34, -0.18, 0.08), (-2.31, -0.18, -0.17), (-2.42, -0.18, -0.42)],
        accent,
        0.035,
        root,
    )
    box("Trigger_Guard_Inner_Shadow", (-2.42, -0.01, -0.1), (1.0, 0.8, 0.08), shadow, 0.012, parent=root)
    label("Selector_Fire_Mark", "FIRE", (-2.13, -0.804, 1.42), 0.16, markings, parent=root)
    label("Receiver_Serial", "M4A1  5.56 NATO", (0.25, 0.804, 1.05), 0.14, markings, rot=(math.radians(90), 0.0, math.radians(180)), parent=root)
    box("Charging_Handle_Latch_Left", (-4.52, -0.75, 2.32), (0.35, 0.18, 0.16), receiver, 0.012, parent=root)


def add_magazine(root, mats):
    polymer = mats["polymer"]
    accent = mats["accent"]
    shadow = mats["shadow"]
    bare = mats["bare"]

    for side, y in (("Left", -0.56), ("Right", 0.56)):
        for i, z in enumerate([-2.68, -2.25, -1.82, -1.39, -0.96]):
            box(
                f"Magazine_{side}_Stamped_Rib_{i}",
                (0.18 + 0.05 * i, y, z),
                (1.18, 0.055, 0.08),
                accent,
                0.01,
                rot=(0.0, math.radians(-8), 0.0),
                parent=root,
            )
        for i, z in enumerate([-2.44, -1.72, -1.0]):
            cylinder(
                f"Magazine_{side}_Witness_Hole_{i}",
                (0.05, y * 1.01, z),
                0.085,
                0.035,
                shadow,
                vertices=20,
                rot=(math.pi / 2.0, 0.0, 0.0),
                bevel=0.001,
                parent=root,
            )

    box("Magazine_Follower_Glimpse", (-0.57, 0.0, -0.72), (0.62, 0.86, 0.08), bare, 0.01, parent=root)
    box("Magazine_Baseplate_Lip", (0.54, 0.0, -3.31), (1.85, 1.24, 0.12), polymer, 0.028, rot=(0.0, math.radians(-9), 0.0), parent=root)


def add_stock_and_grip(root, mats):
    polymer = mats["polymer"]
    rubber = mats["rubber"]
    accent = mats["accent"]
    shadow = mats["shadow"]
    bare = mats["bare"]

    for side, y in (("Left", -0.69), ("Right", 0.69)):
        box(f"Stock_{side}_Sling_Window", (-9.38, y, 1.28), (1.3, 0.045, 0.5), shadow, 0.035, parent=root)
        box(f"Stock_{side}_Cheek_Rib", (-8.45, y, 2.34), (1.9, 0.07, 0.12), polymer, 0.018, parent=root)
        box(f"Stock_{side}_Adjustment_Slot", (-7.25, y, 0.82), (1.2, 0.05, 0.2), shadow, 0.018, parent=root)



def add_sights(root, mats):
    receiver = mats["receiver"]
    bare = mats["bare"]
    shadow = mats["shadow"]
    markings = mats["markings"]

    torus("Rear_Aperture_Ring_Large", (-2.13, -0.01, 3.48), receiver, major=0.27, minor=0.035, parent=root)
    torus("Rear_Aperture_Ring_Small", (-2.13, -0.01, 3.48), shadow, major=0.115, minor=0.022, parent=root)
    cylinder("Rear_Sight_Windage_Knob", (-2.13, 0.64, 3.42), 0.13, 0.18, bare, vertices=18, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.004, parent=root)
    for i, y in enumerate([-0.58, 0.58]):
        box(f"Rear_Sight_Protective_Ear_{i}", (-2.12, y, 3.47), (0.2, 0.12, 0.72), receiver, 0.018, parent=root)
    box("Front_Sight_A_Frame_Left", (13.05, -0.36, 2.62), (0.18, 0.13, 1.08), receiver, 0.012, rot=(0.0, math.radians(-10), 0.0), parent=root)
    box("Front_Sight_A_Frame_Right", (13.05, 0.36, 2.62), (0.18, 0.13, 1.08), receiver, 0.012, rot=(0.0, math.radians(-10), 0.0), parent=root)
    cylinder("Front_Sight_Adjustment_Pin", (13.0, 0.0, 3.48), 0.075, 0.42, bare, vertices=14, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.002, parent=root)
    label("Rail_TMark_12", "T12", (2.6, -0.52, 3.03), 0.12, markings, parent=root)
    label("Rail_TMark_18", "T18", (5.9, -0.52, 3.08), 0.12, markings, parent=root)
    label("Rail_TMark_24", "T24", (9.2, -0.52, 3.08), 0.12, markings, parent=root)


def add_surface_wear(root, mats):
    random.seed(44)
    bare = mats["bare"]
    shadow = mats["shadow"]

    wear_zones = [
        {"name": "Receiver", "x": (-3.6, 3.2), "y": -0.825, "z": (1.0, 2.12), "count": 28},
        {"name": "Handguard", "x": (4.8, 12.8), "y": -1.005, "z": (1.0, 2.35), "count": 28},
        {"name": "Magazine", "x": (-0.45, 0.85), "y": -0.462, "z": (-2.9, -0.9), "count": 20},
        {"name": "Stock", "x": (-10.6, -7.1), "y": -0.72, "z": (0.8, 2.2), "count": 16},
    ]

    for zone in wear_zones:
        for i in range(zone["count"]):
            x = random.uniform(*zone["x"])
            z = random.uniform(*zone["z"])
            length = random.uniform(0.08, 0.32)
            height = random.uniform(0.008, 0.028)
            mat = bare if random.random() > 0.22 else shadow
            box(
                f"Wear_{zone['name']}_{i:02}",
                (x, zone["y"], z),
                (length, 0.012, height),
                mat,
                0.001,
                rot=(0.0, random.uniform(-0.25, 0.25), 0.0),
                parent=root,
            )


def add_preview_camera_and_lighting(root):
    for obj in list(bpy.data.objects):
        if obj.name.startswith(DETAIL_PREFIX + "Preview_"):
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.light_add(type="AREA", location=(1.5, -9.0, 8.5))
    key = bpy.context.object
    key.name = DETAIL_PREFIX + "Preview_Key_Light"
    key.data.energy = 1050
    key.data.size = 5.5
    tag(key)

    bpy.ops.object.light_add(type="AREA", location=(-8.0, 6.0, 4.5))
    rim = bpy.context.object
    rim.name = DETAIL_PREFIX + "Preview_Rim_Light"
    rim.data.energy = 420
    rim.data.size = 4.0
    tag(rim)

    bpy.ops.object.camera_add(location=(3.6, -43.0, 7.2))
    cam = bpy.context.object
    cam.name = DETAIL_PREFIX + "Preview_Camera"
    direction = Vector((3.7, 0.0, 0.55)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 34.0
    bpy.context.scene.camera = cam
    tag(cam)

    if bpy.context.scene.world is not None:
        bpy.context.scene.world.color = (0.055, 0.055, 0.055)

    bpy.context.view_layer.objects.active = root
    root.select_set(True)


def save_preview() -> str | None:
    try:
        PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.scene.render.engine = "BLENDER_EEVEE"
        bpy.context.scene.render.resolution_x = 1600
        bpy.context.scene.render.resolution_y = 900
        bpy.context.scene.eevee.taa_render_samples = 64
        bpy.context.scene.render.filepath = str(PREVIEW_PATH)
        bpy.ops.render.render(write_still=True)
        return str(PREVIEW_PATH)
    except Exception as exc:
        print(f"Preview render skipped: {exc}")
        return None


def main():
    starting_file = bpy.data.filepath
    save_variant_before_editing()
    root = root_object()
    removed = remove_previous_details()
    mats = build_materials()

    add_handguard(root, mats)
    add_receiver_controls(root, mats)
    add_magazine(root, mats)
    add_stock_and_grip(root, mats)
    add_sights(root, mats)
    add_surface_wear(root, mats)
    add_preview_camera_and_lighting(root)

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    preview = save_preview()

    detail_objects = [obj for obj in bpy.data.objects if obj.get(DETAIL_FLAG)]
    result.update(
        {
            "starting_file": starting_file,
            "saved_variant": str(OUTPUT_BLEND),
            "preview": preview,
            "root": root.name,
            "removed_previous_detail_objects": removed,
            "detail_object_count": len(detail_objects),
            "mesh_count": sum(1 for obj in bpy.data.objects if obj.type == "MESH"),
            "materials": sorted(mats.keys()),
        }
    )


main()
