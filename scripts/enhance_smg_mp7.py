"""Rebuild the SMG MP7 source model with production-ready detail."""

from __future__ import annotations

import math
from pathlib import Path

import bpy


ROOT = Path(r"C:\Programming\S&Box")
BLEND_PATH = ROOT / "weapons_model.blend" / "smg_mp7.blend"
TEXTURE_DIR = ROOT / "Assets" / "materials" / "weapons"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)


def make_mat(name: str, color: tuple[float, float, float, float], metalness: float, roughness: float, texture: str):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        tex_path = TEXTURE_DIR / texture
        if tex_path.exists():
            tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
            tex.name = "SMG_Generated_Texture"
            tex.image = bpy.data.images.load(str(tex_path), check_existing=True)
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = color
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metalness
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat


def materials():
    return {
        "polymer": make_mat("SMG_Polymer", (0.03, 0.034, 0.038, 1.0), 0.03, 0.72, "smg_polymer_color.png"),
        "metal": make_mat("SMG_Metal", (0.34, 0.37, 0.39, 1.0), 0.78, 0.42, "smg_metal_color.png"),
        "accent": make_mat("SMG_Accent", (0.55, 0.60, 0.55, 1.0), 0.16, 0.48, "smg_accent_color.png"),
        "sights": make_mat("SMG_Sights", (0.02, 0.025, 0.025, 1.0), 0.08, 0.24, "smg_sights_color.png"),
    }


PARTS: list[bpy.types.Object] = []


def finish(obj: bpy.types.Object, mat: bpy.types.Material, bevel: float = 0.03, segments: int = 1) -> bpy.types.Object:
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    if bevel > 0:
        bevel_mod = obj.modifiers.new("production bevel", "BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = segments
        bevel_mod.affect = "EDGES"
    normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    normal_mod.keep_sharp = True
    PARTS.append(obj)
    return obj


def box(name: str, loc, scale, mat, bevel=0.035, rot=(0.0, 0.0, 0.0), segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, mat, bevel, segments)


def cylinder_y(name: str, loc, radius: float, depth: float, mat, vertices=32, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=loc,
        rotation=(math.pi / 2.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, mat, bevel)


def cylinder_z(name: str, loc, radius: float, depth: float, mat, vertices=32, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, mat, bevel)


def label(name: str, text: str, loc, size: float, mat, rot=(math.radians(90), 0.0, 0.0)):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
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
    return finish(obj, mat, 0.0)


def add_screw_pair(name: str, y: float, z: float, mats) -> None:
    for x in (-1.03, 1.03):
        screw = cylinder_y(f"{name}_{'L' if x < 0 else 'R'}", (x, y, z), 0.095, 0.045, mats["metal"], 24, 0.003)
        screw.rotation_euler[1] = math.radians(90)


def build_model() -> bpy.types.Object:
    mats = materials()
    polymer = mats["polymer"]
    metal = mats["metal"]
    accent = mats["accent"]
    sights = mats["sights"]

    box("Upper_Receiver_Core", (0.0, -1.1, 3.25), (1.86, 12.35, 2.08), metal, 0.10, segments=3)
    box("Lower_Polymer_Housing", (0.0, 0.05, 2.05), (1.78, 9.55, 1.34), polymer, 0.09, segments=3)
    box("Ejection_Port_Recess", (0.99, -2.65, 3.68), (0.07, 1.74, 0.54), sights, 0.012)
    box("Bolt_Cover_Plate", (1.035, -2.65, 3.68), (0.035, 1.2, 0.36), accent, 0.008)

    box("Top_Picatinny_Base", (0.0, -1.0, 4.52), (1.52, 10.7, 0.26), metal, 0.035)
    for i, y in enumerate([v * 0.74 - 5.7 for v in range(14)]):
        box(f"Top_Rail_Tooth_{i:02d}", (0.0, y, 4.86), (1.42, 0.32, 0.34), metal, 0.025)

    box("Left_Side_Rail", (-1.07, -2.55, 3.1), (0.16, 5.8, 0.34), metal, 0.025)
    box("Right_Side_Rail", (1.07, -2.55, 3.1), (0.16, 5.8, 0.34), metal, 0.025)
    for i, y in enumerate([-5.0, -4.15, -3.3, -2.45, -1.6, -0.75]):
        box(f"Left_Side_Rail_Notch_{i}", (-1.16, y, 3.1), (0.12, 0.28, 0.47), metal, 0.01)
        box(f"Right_Side_Rail_Notch_{i}", (1.16, y, 3.1), (0.12, 0.28, 0.47), metal, 0.01)

    cylinder_y("Outer_Barrel_Shroud", (0.0, -7.92, 3.3), 0.42, 2.35, metal, 40, 0.01)
    cylinder_y("Dark_Muzzle_Bore", (0.0, -9.22, 3.3), 0.24, 0.34, sights, 32, 0.004)
    cylinder_y("Muzzle_Ring", (0.0, -8.94, 3.3), 0.52, 0.36, accent, 40, 0.006)
    cylinder_y("Inner_Barrel", (0.0, -9.06, 3.3), 0.15, 0.72, sights, 32, 0.003)

    box("Folding_Foregrip_Base", (0.0, -4.55, 1.18), (1.18, 1.12, 0.42), polymer, 0.07, segments=2)
    box("Folded_Vertical_Grip", (0.0, -4.3, 0.15), (0.76, 0.62, 1.72), polymer, 0.10, rot=(math.radians(-7), 0.0, 0.0), segments=3)
    for x in (-0.42, 0.42):
        cylinder_y("Foregrip_Pivot_L" if x < 0 else "Foregrip_Pivot_R", (x, -4.92, 1.2), 0.13, 0.12, metal, 24, 0.004)

    box("Trigger_Guard_Front", (0.0, -0.9, 1.04), (0.24, 0.18, 0.95), polymer, 0.045)
    box("Trigger_Guard_Bottom", (0.0, -0.22, 0.64), (0.3, 1.44, 0.22), polymer, 0.045)
    box("Trigger_Guard_Back", (0.0, 0.5, 1.02), (0.24, 0.18, 0.86), polymer, 0.045)
    box("Curved_Trigger", (0.0, -0.12, 0.88), (0.22, 0.26, 0.84), sights, 0.04, rot=(math.radians(-15), 0.0, 0.0))

    box("Pistol_Grip_Core", (0.0, 1.85, 0.52), (1.18, 1.18, 2.55), polymer, 0.14, rot=(math.radians(-8), 0.0, 0.0), segments=4)
    for i, z in enumerate([-0.38, 0.08, 0.54, 1.0]):
        box(f"Grip_Texture_Rib_{i}", (0.0, 1.27, z), (1.26, 0.12, 0.1), accent, 0.018, rot=(math.radians(-8), 0.0, 0.0))
    box("Magazine_Well", (0.0, 2.84, 1.46), (1.46, 1.0, 1.24), polymer, 0.08, rot=(math.radians(-3), 0.0, 0.0), segments=2)
    box("Transparent_Magazine_Body", (0.0, 3.05, -0.82), (1.08, 0.78, 3.22), accent, 0.075, rot=(math.radians(-4), 0.0, 0.0), segments=2)
    for i, z in enumerate([-1.75, -1.15, -0.55, 0.05]):
        box(f"Magazine_Round_Window_{i}", (0.0, 2.64, z), (0.78, 0.05, 0.18), sights, 0.008, rot=(math.radians(-4), 0.0, 0.0))
    box("Magazine_Baseplate", (0.0, 3.15, -2.55), (1.28, 0.94, 0.34), polymer, 0.07, rot=(math.radians(-4), 0.0, 0.0))

    cylinder_y("Left_Stock_Rail", (-0.5, 6.8, 3.18), 0.08, 4.9, metal, 20, 0.003)
    cylinder_y("Right_Stock_Rail", (0.5, 6.8, 3.18), 0.08, 4.9, metal, 20, 0.003)
    box("Rear_Stock_Block", (0.0, 5.08, 3.18), (1.5, 0.48, 0.72), polymer, 0.06)
    box("Extended_Butt_Pad", (0.0, 9.42, 3.12), (1.72, 0.44, 1.62), polymer, 0.10, segments=3)
    box("Rubber_Butt_Insert", (0.0, 9.67, 3.12), (1.44, 0.12, 1.34), sights, 0.055)

    box("Rear_Iron_Sight", (0.0, 3.36, 5.22), (1.0, 0.34, 0.46), sights, 0.03)
    box("Front_Iron_Sight", (0.0, -6.65, 5.16), (0.9, 0.3, 0.42), sights, 0.03)
    box("Rear_Glow_Dot", (0.0, 3.14, 5.4), (0.2, 0.04, 0.11), accent, 0.006)
    box("Front_Glow_Dot", (0.0, -6.86, 5.32), (0.18, 0.04, 0.1), accent, 0.006)

    box("Ambi_Selector_Left", (-1.08, 0.88, 2.84), (0.1, 0.55, 0.18), accent, 0.018, rot=(0.0, 0.0, math.radians(20)))
    box("Ambi_Selector_Right", (1.08, 0.88, 2.84), (0.1, 0.55, 0.18), accent, 0.018, rot=(0.0, 0.0, math.radians(-20)))
    box("Charging_Handle", (0.0, 4.02, 4.22), (1.14, 0.34, 0.26), metal, 0.035)
    label("Receiver_Marking_MP7", "MP7", (0.0, -1.12, 4.08), 0.36, accent)
    label("Receiver_Marking_AB", "AB 4.6", (-0.72, 0.66, 3.9), 0.16, accent)

    for y, z in [(-5.9, 3.92), (-3.7, 2.42), (-0.45, 3.88), (2.4, 2.36), (4.9, 3.78)]:
        add_screw_pair(f"Receiver_Screw_{str(y).replace('.', '_').replace('-', 'm')}", y, z, mats)

    for obj in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    root = bpy.context.object
    root.name = "SMG_MP7"
    root.data.name = "SMG_MP7_mesh"
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")

    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.shade_smooth()
    return root


def add_review_camera_and_lights() -> None:
    bpy.ops.object.light_add(type="AREA", location=(0.0, -4.2, 8.0))
    key = bpy.context.object
    key.name = "SMG_Key_Area_Light"
    key.data.energy = 550
    key.data.size = 5.5

    bpy.ops.object.light_add(type="POINT", location=(-4.0, 2.5, 4.0))
    fill = bpy.context.object
    fill.name = "SMG_Fill_Light"
    fill.data.energy = 95

    bpy.ops.object.camera_add(location=(5.8, -12.0, 6.1), rotation=(math.radians(62), 0.0, math.radians(27)))
    camera = bpy.context.object
    bpy.context.scene.camera = camera
    camera.name = "SMG_Review_Camera"
    camera.data.lens = 48
    camera.data.dof.use_dof = True
    camera.data.dof.focus_distance = 12.0
    camera.data.dof.aperture_fstop = 7.5


def main() -> None:
    clear_scene()
    root = build_model()
    add_review_camera_and_lights()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"Saved enhanced {root.name}: vertices={len(root.data.vertices)}, polygons={len(root.data.polygons)}")


main()
