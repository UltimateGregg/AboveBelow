"""
Build a detailed M4-style assault rifle asset in Blender.

This is intentionally procedural so the asset can be regenerated and tweaked
quickly while the S&Box export pipeline stays deterministic.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
BLEND_PATH = PROJECT_ROOT / "weapon_model.blend" / "assault_rifle_m4.blend"
PREVIEW_PATH = PROJECT_ROOT / "screenshots" / "assault_rifle_m4_preview.png"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        if material.name.startswith("M4_"):
            bpy.data.materials.remove(material)


def make_material(name: str, color: tuple[float, float, float, float], metallic: float, roughness: float):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def apply_finish(obj, material, bevel: float = 0.04, segments: int = 1) -> None:
    obj.data.materials.append(material)
    if bevel > 0:
        bevel_mod = obj.modifiers.new("small bevels", "BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = segments
        bevel_mod.affect = "EDGES"
    normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    normal_mod.keep_sharp = True


def box(name: str, loc, scale, material, bevel: float = 0.04, rot=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_finish(obj, material, bevel)
    obj.parent = parent
    return obj


def cylinder(
    name: str,
    loc,
    radius: float,
    depth: float,
    material,
    vertices: int = 32,
    rot=(0.0, math.pi / 2.0, 0.0),
    bevel: float = 0.0,
    parent=None,
):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    apply_finish(obj, material, bevel, segments=1)
    obj.parent = parent
    return obj


def text_label(name: str, text: str, loc, size: float, material, rot=(math.radians(90), 0.0, 0.0), parent=None):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.015
    obj.data.resolution_u = 2
    obj.data.materials.append(material)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.parent = parent
    return obj


def add_rail_lugs(parent, material) -> None:
    # Top receiver rail and handguard rail. Small repeated blocks read well in S&Box.
    for i, x in enumerate([v * 0.55 for v in range(-9, 24)]):
        z = 2.78 if x < 4.4 else 2.86
        width = 0.62 if i % 2 == 0 else 0.48
        box(f"Top_Rail_Lug_{i:02}", (x, 0.0, z), (0.34, 1.24, 0.22), material, 0.015, parent=parent)
        box(f"Top_Rail_Slot_{i:02}", (x, 0.0, z + 0.19), (0.2, width, 0.08), material, 0.008, parent=parent)

    # Side and lower rail nubs on the handguard.
    for i, x in enumerate([5.2 + v * 0.78 for v in range(15)]):
        box(f"Left_Handguard_Rail_{i:02}", (x, -1.1, 1.48), (0.42, 0.18, 0.32), material, 0.012, parent=parent)
        box(f"Right_Handguard_Rail_{i:02}", (x, 1.1, 1.48), (0.42, 0.18, 0.32), material, 0.012, parent=parent)
        box(f"Bottom_Handguard_Rail_{i:02}", (x, 0.0, 0.42), (0.42, 0.74, 0.16), material, 0.012, parent=parent)


def build_rifle():
    receiver = make_material("M4_Receiver", (0.035, 0.037, 0.04, 1.0), 0.35, 0.52)
    polymer = make_material("M4_Polymer", (0.018, 0.019, 0.021, 1.0), 0.03, 0.76)
    rubber = make_material("M4_Rubber", (0.006, 0.006, 0.007, 1.0), 0.0, 0.9)
    bare = make_material("M4_BareMetal", (0.65, 0.66, 0.64, 1.0), 0.8, 0.36)
    accent = make_material("M4_Accent", (0.11, 0.115, 0.12, 1.0), 0.18, 0.62)
    markings = make_material("M4_Markings", (0.78, 0.78, 0.72, 1.0), 0.05, 0.7)

    root = bpy.data.objects.new("AssaultRifle_M4", None)
    bpy.context.collection.objects.link(root)

    parts = []

    def add(obj):
        parts.append(obj)
        return obj

    # Receiver group.
    add(box("Upper_Receiver_Forged_Block", (0.0, 0.0, 1.78), (8.2, 1.42, 1.02), receiver, 0.08, parent=root))
    add(box("Lower_Receiver_Magwell_Block", (-1.1, 0.0, 0.74), (5.6, 1.34, 1.22), receiver, 0.08, parent=root))
    add(box("Rear_Takedown_Lug", (-4.15, 0.0, 1.12), (0.8, 1.24, 1.15), receiver, 0.055, parent=root))
    add(box("Forward_Assist_Housing", (2.4, 0.84, 1.92), (1.25, 0.32, 0.36), receiver, 0.035, rot=(0.0, 0.0, math.radians(12)), parent=root))
    add(cylinder("Forward_Assist_Button", (1.78, 1.06, 1.91), 0.16, 0.28, accent, vertices=18, rot=(math.pi / 2, 0.0, 0.0), bevel=0.01, parent=root))
    add(box("Ejection_Port_Cover", (1.05, -0.735, 1.92), (2.08, 0.055, 0.42), accent, 0.012, parent=root))
    add(box("Bolt_Catch", (-1.42, -0.78, 1.12), (0.32, 0.08, 0.72), accent, 0.015, parent=root))
    add(cylinder("Selector_Switch", (-2.55, -0.76, 1.18), 0.18, 0.07, accent, vertices=20, rot=(math.pi / 2, 0.0, 0.0), bevel=0.006, parent=root))
    add(cylinder("Receiver_Pin_Front", (1.58, -0.77, 0.98), 0.13, 0.08, bare, vertices=18, rot=(math.pi / 2, 0.0, 0.0), parent=root))
    add(cylinder("Receiver_Pin_Rear", (-3.3, -0.77, 0.98), 0.13, 0.08, bare, vertices=18, rot=(math.pi / 2, 0.0, 0.0), parent=root))
    add(box("Charging_Handle_T", (-4.08, 0.0, 2.36), (1.12, 1.72, 0.18), accent, 0.025, parent=root))
    add(box("Charging_Handle_Stem", (-3.72, 0.0, 2.2), (1.04, 0.34, 0.18), accent, 0.02, parent=root))

    # Handguard, barrel, gas system, muzzle.
    add(box("Carbine_Handguard_Core", (7.9, 0.0, 1.58), (7.5, 1.72, 1.5), polymer, 0.12, parent=root))
    add(box("Handguard_Top_Bridge", (7.9, 0.0, 2.38), (7.8, 1.24, 0.34), receiver, 0.04, parent=root))
    add(cylinder("Barrel_Outer", (13.15, 0.0, 1.66), 0.2, 12.2, receiver, vertices=32, bevel=0.01, parent=root))
    add(cylinder("Barrel_Muzzle_Thread", (19.45, 0.0, 1.66), 0.24, 0.76, bare, vertices=32, bevel=0.01, parent=root))
    add(cylinder("Birdcage_Muzzle_Device", (20.08, 0.0, 1.66), 0.36, 0.96, receiver, vertices=32, bevel=0.015, parent=root))
    for i, angle in enumerate([0, 60, 120, 180, 240, 300]):
        y = math.cos(math.radians(angle)) * 0.345
        z = 1.66 + math.sin(math.radians(angle)) * 0.345
        add(box(f"Muzzle_Port_{i:02}", (20.2, y, z), (0.5, 0.055, 0.14), bare, 0.006, parent=root))
    add(box("Gas_Block_A2_Base", (13.0, 0.0, 2.16), (0.7, 1.02, 0.74), receiver, 0.04, parent=root))
    add(box("Front_Sight_Left_Wing", (13.0, -0.27, 2.84), (0.18, 0.14, 1.15), receiver, 0.018, parent=root))
    add(box("Front_Sight_Right_Wing", (13.0, 0.27, 2.84), (0.18, 0.14, 1.15), receiver, 0.018, parent=root))
    add(box("Front_Sight_Post", (13.0, 0.0, 3.15), (0.1, 0.1, 0.84), bare, 0.01, parent=root))
    add(cylinder("Gas_Tube", (8.7, 0.0, 2.54), 0.055, 9.2, bare, vertices=16, bevel=0.003, parent=root))
    add_rail_lugs(root, receiver)

    # Magazine, grip, trigger.
    add(box("Magazine_Well_Angled", (-0.55, 0.0, -0.12), (1.7, 1.18, 1.34), receiver, 0.055, rot=(0.0, math.radians(-4), 0.0), parent=root))
    add(box("Magazine_Upper_Curve", (-0.15, 0.0, -1.12), (1.55, 1.05, 1.35), polymer, 0.075, rot=(0.0, math.radians(-5), 0.0), parent=root))
    add(box("Magazine_Lower_Curve", (0.18, 0.0, -2.25), (1.42, 1.0, 1.55), polymer, 0.075, rot=(0.0, math.radians(-9), 0.0), parent=root))
    add(box("Magazine_Baseplate", (0.36, 0.0, -3.12), (1.65, 1.14, 0.28), rubber, 0.04, rot=(0.0, math.radians(-9), 0.0), parent=root))
    add(box("Pistol_Grip_Core", (-3.0, 0.0, -0.82), (1.05, 1.0, 2.25), polymer, 0.09, rot=(0.0, math.radians(-14), 0.0), parent=root))
    for i, z in enumerate([-1.55, -1.1, -0.65]):
        add(box(f"Grip_Texture_Rib_{i}", (-2.78, -0.54, z), (0.78, 0.08, 0.12), rubber, 0.012, rot=(0.0, math.radians(-14), 0.0), parent=root))
        add(box(f"Grip_Texture_Rib_R_{i}", (-2.78, 0.54, z), (0.78, 0.08, 0.12), rubber, 0.012, rot=(0.0, math.radians(-14), 0.0), parent=root))
    add(box("Trigger_Guard_Front", (-1.58, 0.0, 0.1), (0.18, 1.06, 0.46), receiver, 0.025, parent=root))
    add(box("Trigger_Guard_Bottom", (-2.38, 0.0, -0.18), (1.54, 1.02, 0.16), receiver, 0.025, parent=root))
    add(box("Trigger_Guard_Rear", (-3.16, 0.0, 0.12), (0.18, 1.02, 0.54), receiver, 0.025, parent=root))
    add(box("Trigger_Curved_Visible", (-2.42, -0.01, -0.08), (0.22, 0.18, 0.72), accent, 0.025, rot=(0.0, math.radians(-12), 0.0), parent=root))

    # Stock assembly.
    add(cylinder("Buffer_Tube", (-7.05, 0.0, 1.32), 0.28, 5.0, receiver, vertices=28, bevel=0.008, parent=root))
    add(box("Castle_Nut", (-4.8, 0.0, 1.32), (0.38, 0.92, 0.78), receiver, 0.035, parent=root))
    add(box("Adjustable_Stock_Body", (-9.05, 0.0, 1.32), (4.0, 1.28, 1.35), polymer, 0.12, parent=root))
    add(box("Stock_Cheek_Ridge", (-8.78, 0.0, 2.12), (3.2, 1.08, 0.36), polymer, 0.08, parent=root))
    add(box("Stock_Bottom_Rail", (-8.58, 0.0, 0.38), (2.8, 0.74, 0.28), polymer, 0.055, parent=root))
    add(box("Buttpad_Rubber", (-11.34, 0.0, 1.3), (0.38, 1.46, 1.8), rubber, 0.08, parent=root))
    add(box("Stock_Adjustment_Lever", (-7.82, -0.78, 0.64), (1.12, 0.16, 0.22), accent, 0.02, parent=root))

    # Sights and top details.
    add(box("Rear_Sight_Base", (-2.15, 0.0, 3.08), (1.18, 1.02, 0.34), receiver, 0.035, parent=root))
    add(box("Rear_Sight_Aperture_Left", (-2.12, -0.28, 3.46), (0.18, 0.16, 0.58), receiver, 0.015, parent=root))
    add(box("Rear_Sight_Aperture_Right", (-2.12, 0.28, 3.46), (0.18, 0.16, 0.58), receiver, 0.015, parent=root))
    add(box("Rear_Sight_Crossbar", (-2.12, 0.0, 3.72), (0.22, 0.72, 0.12), receiver, 0.01, parent=root))
    add(box("Sling_Loop_Front", (4.5, -0.88, 1.05), (0.16, 0.16, 0.78), bare, 0.018, parent=root))
    add(box("Sling_Loop_Rear", (-5.0, -0.76, 1.0), (0.16, 0.16, 0.7), bare, 0.018, parent=root))

    # Receiver markings are raised very slightly so they survive export.
    add(text_label("Marking_SAFE", "SAFE", (-2.82, -0.792, 1.5), 0.22, markings, parent=root))
    add(text_label("Marking_SEMI", "SEMI", (-2.08, -0.792, 1.02), 0.18, markings, parent=root))
    add(text_label("Marking_556", "5.56", (0.9, -0.792, 1.38), 0.2, markings, parent=root))
    add(text_label("Marking_DVP", "DVP-4", (-0.15, 0.792, 1.24), 0.18, markings, rot=(math.radians(90), 0.0, math.radians(180)), parent=root))

    # Organize view and set origin near the firing hand.
    bpy.context.view_layer.objects.active = root
    root.location = (0.0, 0.0, 0.0)

    for obj in parts:
        obj.select_set(False)
    root.select_set(True)

    return root, parts


def add_camera_and_lights() -> None:
    bpy.ops.object.light_add(type="AREA", location=(2.0, -8.0, 8.0))
    key = bpy.context.object
    key.name = "Preview_Key_Light"
    key.data.energy = 600
    key.data.size = 5.0

    bpy.ops.object.light_add(type="POINT", location=(-8.0, 4.0, 4.0))
    rim = bpy.context.object
    rim.name = "Preview_Rim_Light"
    rim.data.energy = 120

    bpy.ops.object.camera_add(location=(4.0, -44.0, 7.6))
    cam = bpy.context.object
    direction = Vector((4.0, 0.0, 0.6)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 30.0
    bpy.context.scene.camera = cam


def save_preview() -> None:
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.render.resolution_x = 1400
    bpy.context.scene.render.resolution_y = 800
    bpy.context.scene.eevee.taa_render_samples = 48
    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    root, parts = build_rifle()
    add_camera_and_lights()

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    # Keep preview best-effort; the model file is the authoritative output.
    try:
        save_preview()
    except Exception as exc:  # pragma: no cover - Blender runtime feedback only
        print(f"Preview render skipped: {exc}")

    result = {
        "blend_path": str(BLEND_PATH),
        "preview_path": str(PREVIEW_PATH),
        "root": root.name,
        "mesh_part_count": len(parts),
        "object_count": len(bpy.data.objects),
        "materials": [mat.name for mat in bpy.data.materials if mat.name.startswith("M4_")],
    }
    print(result)


main()
