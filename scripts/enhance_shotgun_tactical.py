#!/usr/bin/env python3
"""Rebuild the shotgun Blender source with a more detailed game-ready model."""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(os.environ.get("SBOX_PROJECT_ROOT", r"C:\Programming\S&Box"))
BLEND_PATH = ROOT / "weapons_model.blend" / "shotgun.blend"
PREVIEW_PATH = ROOT / "screenshots" / "shotgun_tactical_preview.png"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_mat(name: str, color: tuple[float, float, float, float], roughness: float, metalness: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metalness
    mat.diffuse_color = color
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def parent(obj, root):
    obj.parent = root
    return obj


def bevel(obj, width: float, segments: int = 2):
    if width > 0:
        mod = obj.modifiers.new("Soft bevel", "BEVEL")
        mod.width = width
        mod.segments = segments
        mod.affect = "EDGES"
    norm = obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    norm.keep_sharp = True
    return obj


def cube(name: str, loc, dims, mat, root, bevel_width: float = 0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bevel(obj, bevel_width)
    parent(obj, root)
    return obj


def cylinder_y(name: str, loc, radius: float, depth: float, mat, root, vertices: int = 48, bevel_width: float = 0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=(math.pi / 2, 0, 0))
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    bevel(obj, bevel_width, 1)
    parent(obj, root)
    return obj


def cylinder_z(name: str, loc, radius: float, depth: float, mat, root, vertices: int = 32, bevel_width: float = 0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    bevel(obj, bevel_width, 1)
    parent(obj, root)
    return obj


def sphere(name: str, loc, scale, mat, root, segments: int = 24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=12, radius=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bevel(obj, 0.0)
    parent(obj, root)
    return obj


def tapered_box(name: str, loc, length: float, width_front: float, width_rear: float, height_front: float, height_rear: float, mat, root):
    y0 = -length / 2
    y1 = length / 2
    wf = width_front / 2
    wr = width_rear / 2
    hf = height_front / 2
    hr = height_rear / 2
    verts = [
        (-wf, y0, -hf), (wf, y0, -hf), (wf, y0, hf), (-wf, y0, hf),
        (-wr, y1, -hr), (wr, y1, -hr), (wr, y1, hr), (-wr, y1, hr),
    ]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    assign(obj, mat)
    bevel(obj, 0.045, 3)
    parent(obj, root)
    return obj


def text_mesh(name: str, text: str, loc, rot, size: float, mat, root):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.012
    obj.data.resolution_u = 3
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    assign(obj, mat)
    bevel(obj, 0.003, 1)
    parent(obj, root)
    return obj


def set_origin_and_names(root) -> None:
    for obj in bpy.data.objects:
        obj.select_set(False)
    root.select_set(True)
    bpy.context.view_layer.objects.active = root


def build_model() -> None:
    clear_scene()

    mats = {
        "metal": make_mat("Shotgun_Metal", (0.055, 0.062, 0.064, 1), 0.34, 0.86),
        "wood": make_mat("Shotgun_Wood", (0.34, 0.18, 0.075, 1), 0.56, 0.0),
        "rubber": make_mat("Shotgun_Rubber", (0.015, 0.016, 0.015, 1), 0.84, 0.0),
        "shell": make_mat("Shotgun_Shell", (0.65, 0.045, 0.035, 1), 0.48, 0.03),
        "sight": make_mat("Shotgun_SightPaint", (0.9, 0.78, 0.38, 1), 0.35, 0.2),
    }

    root = bpy.data.objects.new("Shotgun", None)
    bpy.context.collection.objects.link(root)

    metal = mats["metal"]
    wood = mats["wood"]
    rubber = mats["rubber"]
    shell = mats["shell"]
    sight = mats["sight"]

    # Main metal structure.
    cube("Receiver_Main_Bevelled", (0, -0.12, 0.03), (0.92, 3.82, 1.04), metal, root, 0.055)
    cube("Receiver_Top_Strap", (0, -0.15, 0.64), (0.62, 3.2, 0.18), metal, root, 0.025)
    cube("Receiver_Bottom_TriggerPlate", (0, 0.2, -0.54), (0.54, 1.35, 0.18), metal, root, 0.025)
    cube("Receiver_Loading_Gate", (0, -0.85, -0.56), (0.44, 1.2, 0.08), metal, root, 0.018)

    cylinder_y("Barrel_DarkBlued_Steel", (0, -7.65, 0.37), 0.235, 10.9, metal, root, 64, 0.005)
    cylinder_y("Barrel_Inner_Muzzle_Shadow", (0, -13.15, 0.37), 0.18, 0.045, rubber, root, 48, 0.0)
    cylinder_y("Barrel_Muzzle_Crown", (0, -13.05, 0.37), 0.285, 0.2, metal, root, 64, 0.01)
    cylinder_y("Magazine_Tube", (0, -7.25, -0.19), 0.185, 8.85, metal, root, 48, 0.004)
    cylinder_y("Magazine_Tube_Endcap", (0, -11.82, -0.19), 0.225, 0.32, metal, root, 48, 0.008)
    cylinder_y("Magazine_Tube_ReceiverSocket", (0, -2.75, -0.19), 0.23, 0.45, metal, root, 48, 0.008)

    for idx, y in enumerate([-11.2, -9.45]):
        cube(f"Barrel_Tube_Clamp_{idx+1}", (0, y, 0.08), (0.74, 0.22, 0.86), metal, root, 0.035)
        cube(f"Clamp_Screw_Left_{idx+1}", (-0.41, y, 0.08), (0.06, 0.26, 0.18), metal, root, 0.012)
        cube(f"Clamp_Screw_Right_{idx+1}", (0.41, y, 0.08), (0.06, 0.26, 0.18), metal, root, 0.012)

    # Top rib and sights.
    cube("Vent_Rib_Base", (0, -7.95, 0.66), (0.18, 8.9, 0.055), metal, root, 0.01)
    for i, y in enumerate([-11.8, -10.55, -9.3, -8.05, -6.8, -5.55, -4.3]):
        cube(f"Vent_Rib_Post_{i+1}", (0, y, 0.57), (0.13, 0.12, 0.22), metal, root, 0.008)
    sphere("Front_Bead_Sight_Brass", (0, -12.67, 0.77), (0.075, 0.075, 0.06), sight, root, 24)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.018, major_segments=32, minor_segments=8, location=(0, 1.2, 0.76), rotation=(math.pi / 2, 0, 0))
    rear = bpy.context.object
    rear.name = "Rear_Ghost_Ring_Sight"
    assign(rear, metal)
    parent(rear, root)
    cube("Rear_Sight_Base", (0, 1.18, 0.62), (0.36, 0.18, 0.12), metal, root, 0.015)

    # Wood stock and pump.
    tapered_box("Walnut_Stock_Tapered", (0, 5.18, -0.12), 6.4, 0.72, 1.04, 0.9, 1.32, wood, root)
    cube("Walnut_Cheek_Riser", (0, 4.55, 0.62), (0.76, 4.7, 0.26), wood, root, 0.055)
    cube("Rubber_Recoil_Pad_Textured", (0, 8.55, -0.12), (1.08, 0.35, 1.43), rubber, root, 0.055)
    for z in [-0.52, -0.26, 0.0, 0.26]:
        cube(f"Recoil_Pad_Groove_{z:.2f}", (0, 8.74, z), (1.11, 0.035, 0.045), metal, root, 0.006)

    cube("Pistol_Grip_Neck_Block", (0, 1.74, -0.58), (0.58, 0.78, 0.42), wood, root, 0.04)
    cube("Pistol_Grip_Slim_Wood", (0, 2.28, -1.16), (0.54, 0.78, 1.45), wood, root, 0.075, rot=(math.radians(-10), 0, 0))
    for i, z in enumerate([-1.55, -1.28, -1.01]):
        cube(f"Pistol_Grip_Finger_Groove_{i+1}", (0, 1.92, z), (0.58, 0.08, 0.08), rubber, root, 0.01)

    cube("Pump_Foreend_Walnut_Core", (0, -4.42, -0.22), (0.92, 2.95, 0.78), wood, root, 0.08)
    for i, y in enumerate([-5.55, -5.15, -4.75, -4.35, -3.95, -3.55, -3.15]):
        cube(f"Pump_Raised_Rib_{i+1}", (0, y, -0.64), (0.98, 0.08, 0.09), wood, root, 0.012)
        cube(f"Pump_Left_Checkering_{i+1}", (-0.49, y, -0.18), (0.035, 0.08, 0.52), rubber, root, 0.006)
        cube(f"Pump_Right_Checkering_{i+1}", (0.49, y, -0.18), (0.035, 0.08, 0.52), rubber, root, 0.006)
    cylinder_y("Pump_Action_Bar_Left", (-0.33, -4.45, -0.5), 0.035, 3.9, metal, root, 16, 0.002)
    cylinder_y("Pump_Action_Bar_Right", (0.33, -4.45, -0.5), 0.035, 3.9, metal, root, 16, 0.002)

    # Receiver details.
    cube("Right_Ejection_Port_Dark", (0.472, -0.42, 0.22), (0.026, 0.92, 0.34), rubber, root, 0.006)
    cube("Right_Ejection_Port_Bright_Edge", (0.49, -0.42, 0.43), (0.025, 0.96, 0.035), metal, root, 0.004)
    cylinder_y("Bolt_Handle_Knob", (0.62, 0.38, 0.28), 0.08, 0.34, metal, root, 24, 0.006)
    cube("Bolt_Handle_Stem", (0.51, 0.38, 0.28), (0.24, 0.08, 0.08), metal, root, 0.01)
    cube("Crossbolt_Safety_Red_Dot", (0.474, 1.02, -0.1), (0.024, 0.11, 0.11), shell, root, 0.01)
    cube("Serial_Plate_Left", (-0.472, -0.22, 0.2), (0.026, 1.15, 0.22), metal, root, 0.006)
    text_mesh("Receiver_Text_12GA_Left", "12 GA", (-0.492, -0.22, 0.22), (math.pi / 2, 0, -math.pi / 2), 0.22, sight, root)
    text_mesh("Receiver_Text_AB12_Right", "AB-12", (0.492, -0.02, 0.02), (math.pi / 2, 0, math.pi / 2), 0.18, sight, root)

    # Trigger group.
    cube("Trigger_Guard_Front_Post", (0, -1.23, -0.77), (0.14, 0.1, 0.54), metal, root, 0.02)
    cube("Trigger_Guard_Rear_Post", (0, -0.42, -0.78), (0.14, 0.1, 0.48), metal, root, 0.02)
    cube("Trigger_Guard_Bottom_Bar", (0, -0.82, -1.02), (0.52, 0.78, 0.13), metal, root, 0.028)
    cube("Curved_Trigger", (0, -0.76, -0.82), (0.16, 0.19, 0.48), metal, root, 0.03, rot=(math.radians(8), 0, 0))

    # Side saddle shells.
    cube("Side_Saddle_Plate", (-0.53, 0.0, -0.08), (0.08, 2.05, 0.76), rubber, root, 0.025)
    for i, y in enumerate([-0.72, -0.24, 0.24, 0.72]):
        cylinder_z(f"Side_Saddle_Red_Shell_{i+1}", (-0.61, y, -0.08), 0.095, 0.62, shell, root, 32, 0.004)
        cylinder_z(f"Side_Saddle_Brass_Cap_Top_{i+1}", (-0.61, y, 0.25), 0.097, 0.06, sight, root, 32, 0.002)
        cylinder_z(f"Side_Saddle_Brass_Cap_Bottom_{i+1}", (-0.61, y, -0.41), 0.097, 0.06, sight, root, 32, 0.002)

    # Sling loops and screw heads.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.018, major_segments=28, minor_segments=8, location=(0, 7.45, -0.86), rotation=(0, math.pi / 2, 0))
    sling = bpy.context.object
    sling.name = "Rear_Sling_Loop"
    assign(sling, metal)
    parent(sling, root)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.105, minor_radius=0.014, major_segments=28, minor_segments=8, location=(0, -9.35, -0.67), rotation=(0, math.pi / 2, 0))
    sling = bpy.context.object
    sling.name = "Forward_Sling_Loop"
    assign(sling, metal)
    parent(sling, root)

    for i, (x, y, z) in enumerate([(0.475, -1.36, 0.35), (0.475, 1.08, 0.35), (-0.475, -1.36, 0.35), (-0.475, 1.08, 0.35)]):
        cylinder_y(f"Receiver_Screw_{i+1}", (x, y, z), 0.065, 0.026, sight, root, 24, 0.002)

    # Camera and lighting for visible review.
    bpy.ops.object.light_add(type="AREA", location=(0, -5.0, 6.0))
    light = bpy.context.object
    light.name = "Preview_Key_Light"
    light.data.energy = 450
    light.data.size = 5.0

    bpy.ops.object.light_add(type="POINT", location=(-4.0, 2.5, 3.0))
    fill = bpy.context.object
    fill.name = "Preview_Fill_Light"
    fill.data.energy = 90

    bpy.ops.object.camera_add(location=(4.2, -10.7, 3.2), rotation=(math.radians(67), 0, math.radians(23)))
    cam = bpy.context.object
    cam.name = "Preview_Camera"
    bpy.context.scene.camera = cam
    direction = Vector((0, -2.5, 0.0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 42

    available_engines = {item.identifier for item in bpy.context.scene.render.bl_rna.properties["engine"].enum_items}
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in available_engines else "BLENDER_EEVEE"
    if hasattr(bpy.context.scene, "eevee"):
        bpy.context.scene.eevee.taa_render_samples = 64
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.render.resolution_x = 1600
    bpy.context.scene.render.resolution_y = 900

    set_origin_and_names(root)


def save_preview() -> None:
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.opengl(write_still=True, view_context=False)


def main() -> None:
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != BLEND_PATH.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(BLEND_PATH))
    elif not bpy.data.filepath:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    build_model()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    save_preview()
    print(f"Enhanced shotgun saved to {BLEND_PATH}")
    print(f"Preview saved to {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
