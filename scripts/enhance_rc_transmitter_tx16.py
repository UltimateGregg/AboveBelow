"""
Rebuild the RC transmitter as a TX16-style controller.

Run inside Blender through the project MCP bridge. The script replaces the
source scene with a multi-part, export-friendly controller while keeping the
configured root object name `RC_Transmitter` for the asset pipeline.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
BLEND_PATH = PROJECT_ROOT / "weapons_model.blend" / "rc_transmitter.blend"
PREVIEW_PATH = PROJECT_ROOT / "screenshots" / "rc_transmitter_tx16_preview.png"
TEXTURE_DIR = PROJECT_ROOT / "Assets" / "materials" / "weapons"


try:
    result
except NameError:
    result = {}


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for curve_data in list(bpy.data.curves):
        bpy.data.curves.remove(curve_data)


def make_mat(name: str, color, metallic: float, roughness: float, texture_name: str | None = None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        return mat

    for node in list(nodes):
        if node.name.startswith("RC_Generated_"):
            nodes.remove(node)

    if texture_name:
        texture_path = TEXTURE_DIR / texture_name
        if texture_path.exists():
            tex = nodes.new("ShaderNodeTexImage")
            tex.name = "RC_Generated_Texture"
            tex.image = bpy.data.images.load(str(texture_path), check_existing=True)
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = color
    else:
        bsdf.inputs["Base Color"].default_value = color

    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def materials():
    return {
        "polymer": make_mat("RC_Polymer", (0.075, 0.078, 0.08, 1.0), 0.03, 0.72, "rc_polymer_color.png"),
        "screen": make_mat("RC_Screen", (0.02, 0.2, 0.32, 1.0), 0.05, 0.18, "rc_screen_color.png"),
        "antenna": make_mat("RC_Antenna", (0.025, 0.025, 0.025, 1.0), 0.18, 0.56, "rc_antenna_color.png"),
        "rubber": make_mat("RC_Rubber", (0.008, 0.008, 0.009, 1.0), 0.0, 0.9, "rc_rubber_color.png"),
        "metal": make_mat("RC_Metal", (0.55, 0.56, 0.55, 1.0), 0.85, 0.32, "rc_metal_color.png"),
        "label": make_mat("RC_LabelWhite", (0.85, 0.87, 0.82, 1.0), 0.0, 0.62, "rc_label_color.png"),
        "accent": make_mat("RC_AccentBlue", (0.08, 0.36, 0.8, 1.0), 0.1, 0.34, "rc_accent_blue_color.png"),
    }


def finish(obj, mat, bevel: float = 0.035, segments: int = 1):
    if hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    if obj.type == "MESH":
        if bevel > 0:
            bevel_mod = obj.modifiers.new("soft production bevel", "BEVEL")
            bevel_mod.width = bevel
            bevel_mod.segments = segments
            bevel_mod.affect = "EDGES"
        normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
        normal_mod.keep_sharp = True
    return obj


def parented(obj, parent):
    obj.parent = parent
    return obj


def box(name, loc, scale, mat, parent, bevel=0.035, rot=(0.0, 0.0, 0.0), segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel, segments)
    return parented(obj, parent)


def cylinder(name, loc, radius, depth, mat, parent, vertices=32, rot=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return parented(obj, parent)


def cylinder_between(name, start, end, radius, mat, parent, vertices=24, bevel=0.0):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    length = direction.length
    if length <= 0.0001:
        raise ValueError(f"Zero-length cylinder requested for {name}")
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=(start_v + end_v) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return parented(obj, parent)


def torus(name, loc, mat, parent, major=0.32, minor=0.04, rot=(math.pi / 2.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=56,
        minor_segments=12,
        major_radius=major,
        minor_radius=minor,
        location=loc,
        rotation=rot,
    )
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return parented(obj, parent)


def sphere(name, loc, scale, mat, parent, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=12, radius=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(obj, mat, 0.0)
    return parented(obj, parent)


def label(name, text, loc, size, mat, parent, rot=(math.radians(90), 0.0, 0.0), align="CENTER"):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = align
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.008
    obj.data.resolution_u = 2
    obj.data.materials.append(mat)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return parented(obj, parent)


def add_shell(root, mats):
    polymer = mats["polymer"]
    rubber = mats["rubber"]
    accent = mats["accent"]
    metal = mats["metal"]
    label_mat = mats["label"]

    box("Center_Faceplate_Shell", (0.0, 0.0, 1.42), (4.25, 1.9, 3.45), polymer, root, 0.18, segments=3)
    box("Upper_Shoulder_Shell", (0.0, 0.0, 3.34), (5.65, 1.75, 1.08), polymer, root, 0.16, segments=3)
    box("Left_Grip_Shell", (-2.5, 0.02, 0.52), (1.42, 1.78, 2.65), polymer, root, 0.22, rot=(0.0, math.radians(-9), 0.0), segments=3)
    box("Right_Grip_Shell", (2.5, 0.02, 0.52), (1.42, 1.78, 2.65), polymer, root, 0.22, rot=(0.0, math.radians(9), 0.0), segments=3)
    box("Left_Rubber_Grip_Insert", (-2.72, -0.91, 0.34), (0.8, 0.12, 1.82), rubber, root, 0.08, rot=(0.0, math.radians(-9), 0.0), segments=2)
    box("Right_Rubber_Grip_Insert", (2.72, -0.91, 0.34), (0.8, 0.12, 1.82), rubber, root, 0.08, rot=(0.0, math.radians(9), 0.0), segments=2)

    box("Top_Carry_Handle", (0.0, 0.2, 4.3), (3.9, 0.38, 0.32), polymer, root, 0.1, segments=2)
    cylinder_between("Left_Handle_Post", (-1.9, 0.2, 3.82), (-1.9, 0.2, 4.3), 0.16, polymer, root, 24, 0.01)
    cylinder_between("Right_Handle_Post", (1.9, 0.2, 3.82), (1.9, 0.2, 4.3), 0.16, polymer, root, 24, 0.01)
    cylinder_between("Folding_Antenna", (0.0, 0.05, 3.9), (0.0, 0.18, 5.25), 0.07, mats["antenna"], root, 24, 0.004)
    sphere("Antenna_Round_Tip", (0.0, 0.18, 5.35), (0.11, 0.11, 0.11), mats["antenna"], root)

    box("Blue_Status_Lens", (0.0, -0.98, 2.85), (0.5, 0.08, 0.16), accent, root, 0.025)
    label("Brand_Label_RADIOMASTER_STYLE", "TX16", (0.0, -1.02, 2.62), 0.22, label_mat, root)
    label("Small_Label_OPEN_RADIO", "OPEN RADIO", (0.0, -1.02, 2.38), 0.11, label_mat, root)
    cylinder("Center_Power_Button", (0.0, -1.03, 2.18), 0.18, 0.08, accent, root, 36, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.006)
    cylinder("Lanyard_Metal_Ring", (0.0, -1.05, 3.08), 0.14, 0.07, metal, root, 36, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.004)


def add_screen(root, mats):
    screen = mats["screen"]
    polymer = mats["polymer"]
    rubber = mats["rubber"]
    label_mat = mats["label"]
    accent = mats["accent"]

    box("Screen_Bevel_Frame", (0.0, -1.02, 0.02), (2.72, 0.16, 1.23), rubber, root, 0.065, segments=2)
    box("Color_Telemetry_Screen", (0.0, -1.115, 0.02), (2.36, 0.055, 0.92), screen, root, 0.025)

    # Screen UI geometry so the display reads in Blender even before game import.
    box("Screen_Header_Bar", (0.0, -1.15, 0.35), (2.08, 0.018, 0.08), accent, root, 0.003)
    label("Screen_Text_EdgeTX", "EDGETX", (-0.75, -1.165, 0.36), 0.09, label_mat, root)
    label("Screen_Text_Model", "DVP QUAD", (0.66, -1.165, 0.36), 0.075, label_mat, root)
    label("Screen_Text_RSSI", "RSSI 98", (-0.78, -1.165, 0.05), 0.075, label_mat, root)
    label("Screen_Text_BAT", "15.8V", (-0.8, -1.165, -0.16), 0.075, label_mat, root)
    for i, height in enumerate([0.12, 0.19, 0.27, 0.35]):
        box(f"Screen_Telem_Bar_{i}", (0.58 + i * 0.18, -1.16, -0.18 + height * 0.5), (0.08, 0.014, height), accent, root, 0.002)
    box("Screen_Horizon_Line", (0.58, -1.16, 0.02), (0.72, 0.014, 0.025), label_mat, root, 0.002)

    for side, x in (("Left", -1.64), ("Right", 1.64)):
        for i, z in enumerate([-0.18, 0.08, 0.34]):
            box(f"{side}_Screen_Menu_Button_{i}", (x, -1.07, z), (0.35, 0.08, 0.14), rubber, root, 0.025)
    label("Left_Button_Label_RTN", "RTN", (-1.64, -1.13, -0.38), 0.065, label_mat, root)
    label("Right_Button_Label_PAGE", "PAGE", (1.64, -1.13, -0.38), 0.065, label_mat, root)


def add_gimbals_and_sticks(root, mats):
    polymer = mats["polymer"]
    rubber = mats["rubber"]
    metal = mats["metal"]
    label_mat = mats["label"]

    for side, x in (("Left", -1.42), ("Right", 1.42)):
        torus(f"{side}_Gimbal_Outer_Bezel", (x, -1.07, 1.55), metal, root, major=0.54, minor=0.05)
        cylinder(f"{side}_Gimbal_Dark_Recess", (x, -1.08, 1.55), 0.48, 0.055, rubber, root, 48, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.004)
        torus(f"{side}_Gimbal_Inner_Bezel", (x, -1.135, 1.55), polymer, root, major=0.31, minor=0.035)
        box(f"{side}_Gimbal_Horizontal_Cross", (x, -1.17, 1.55), (0.82, 0.035, 0.075), metal, root, 0.006)
        box(f"{side}_Gimbal_Vertical_Cross", (x, -1.17, 1.55), (0.075, 0.035, 0.82), metal, root, 0.006)

        # The stick points directly out from the controller face along -Y.
        base = (x, -1.18, 1.55)
        tip = (x, -1.78, 1.55)
        cylinder_between(f"{side}_Straight_Out_Stick_Shaft", base, tip, 0.055, metal, root, 20, 0.003)
        cylinder(f"{side}_Knurled_Stick_Cap", tip, 0.16, 0.16, rubber, root, 32, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.006)
        for notch in range(8):
            angle = (math.tau / 8) * notch
            nx = x + math.cos(angle) * 0.12
            nz = 1.55 + math.sin(angle) * 0.12
            box(f"{side}_Stick_Cap_Knurl_{notch}", (nx, -1.875, nz), (0.035, 0.025, 0.08), metal, root, 0.002, rot=(0.0, 0.0, angle))

        for i, z in enumerate([1.0, 2.1]):
            box(f"{side}_Vertical_Trim_{i}", (x + (0.76 if side == "Left" else -0.76), -1.06, z), (0.16, 0.08, 0.48), rubber, root, 0.025)
        for i, tx in enumerate([x - 0.34, x + 0.34]):
            box(f"{side}_Horizontal_Trim_{i}", (tx, -1.06, 0.78), (0.42, 0.08, 0.13), rubber, root, 0.025)
        label(f"{side}_Gimbal_Label", "HALL", (x, -1.14, 2.3), 0.08, label_mat, root)


def add_top_controls(root, mats):
    rubber = mats["rubber"]
    metal = mats["metal"]
    label_mat = mats["label"]
    accent = mats["accent"]

    for i, x in enumerate([-2.25, -1.5, 1.5, 2.25]):
        box(f"Top_Toggle_Base_{i}", (x, -0.82, 3.8), (0.42, 0.22, 0.16), rubber, root, 0.025)
        cylinder_between(f"Top_Toggle_Lever_{i}", (x, -0.9, 3.88), (x, -1.04, 4.35), 0.045, metal, root, 18, 0.002)
        sphere(f"Top_Toggle_Cap_{i}", (x, -1.05, 4.42), (0.095, 0.095, 0.095), rubber, root)

    for i, x in enumerate([-0.82, 0.82]):
        cylinder(f"S{i + 1}_Rotary_Knob_Base", (x, -0.88, 3.73), 0.27, 0.11, metal, root, 40, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.005)
        cylinder(f"S{i + 1}_Rotary_Knob_Rubber", (x, -1.0, 3.73), 0.22, 0.12, rubber, root, 40, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.004)
        label(f"S{i + 1}_Knob_Label", f"S{i + 1}", (x, -1.12, 3.38), 0.08, label_mat, root)

    for i, x in enumerate([-0.55, -0.33, -0.11, 0.11, 0.33, 0.55]):
        cylinder(f"Six_Position_Button_{i}", (x, -1.0, 3.12), 0.07, 0.06, accent if i == 0 else rubber, root, 24, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.003)
    label("Six_Button_Label", "FMODE", (0.0, -1.09, 3.28), 0.07, label_mat, root)


def add_speakers_and_fasteners(root, mats):
    rubber = mats["rubber"]
    metal = mats["metal"]
    label_mat = mats["label"]

    for side, x in (("Left", -2.02), ("Right", 2.02)):
        box(f"{side}_Speaker_Recess", (x, -1.035, -0.18), (0.72, 0.07, 0.38), rubber, root, 0.035)
        for i, z in enumerate([-0.29, -0.18, -0.07]):
            box(f"{side}_Speaker_Slot_{i}", (x, -1.09, z), (0.5, 0.03, 0.026), metal, root, 0.002)
    for i, (x, z) in enumerate([(-2.35, 2.78), (2.35, 2.78), (-2.35, -0.55), (2.35, -0.55), (-0.95, 2.72), (0.95, 2.72)]):
        cylinder(f"Faceplate_Screw_{i}", (x, -1.05, z), 0.07, 0.045, metal, root, 24, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.002)
    label("Left_Grip_Label", "LS", (-2.76, -1.06, 1.92), 0.08, label_mat, root)
    label("Right_Grip_Label", "RS", (2.76, -1.06, 1.92), 0.08, label_mat, root)


def add_preview() -> None:
    bpy.ops.object.light_add(type="AREA", location=(0.0, -7.0, 6.2))
    key = bpy.context.object
    key.name = "Preview_Key_Light"
    key.data.energy = 680
    key.data.size = 5.0

    bpy.ops.object.light_add(type="AREA", location=(-4.0, 4.5, 5.0))
    fill = bpy.context.object
    fill.name = "Preview_Fill_Light"
    fill.data.energy = 180
    fill.data.size = 4.5

    bpy.ops.object.camera_add(location=(0.0, -10.5, 2.0))
    cam = bpy.context.object
    cam.name = "Preview_Camera"
    target = Vector((0.0, 0.0, 1.75))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 7.45
    bpy.context.scene.camera = cam

    if bpy.context.scene.world is not None:
        bpy.context.scene.world.color = (0.055, 0.055, 0.055)


def save_preview() -> str | None:
    try:
        PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.scene.render.engine = "BLENDER_EEVEE"
        bpy.context.scene.render.resolution_x = 1200
        bpy.context.scene.render.resolution_y = 1000
        bpy.context.scene.eevee.taa_render_samples = 64
        bpy.context.scene.render.filepath = str(PREVIEW_PATH)
        bpy.ops.render.render(write_still=True)
        return str(PREVIEW_PATH)
    except Exception as exc:
        print(f"Preview render skipped: {exc}")
        return None


def main():
    clear_scene()
    mats = materials()

    root = bpy.data.objects.new("RC_Transmitter", None)
    bpy.context.collection.objects.link(root)

    add_shell(root, mats)
    add_screen(root, mats)
    add_gimbals_and_sticks(root, mats)
    add_top_controls(root, mats)
    add_speakers_and_fasteners(root, mats)
    add_preview()

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    preview = save_preview()

    mesh_objects = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    result.update(
        {
            "saved": str(BLEND_PATH),
            "preview": preview,
            "root": root.name,
            "mesh_count": len(mesh_objects),
            "materials": sorted(mat.name for mat in bpy.data.materials if mat.name.startswith("RC_")),
            "stick_orientation": "both sticks project straight out from the controller front along -Y",
        }
    )


main()
