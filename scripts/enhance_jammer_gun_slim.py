"""
Rebuild the drone jammer as a slimmer directional jammer.

Run inside Blender through the project MCP bridge. Keeps the root name
`Jammer_Gun` and material slot names expected by jammer_gun_asset_pipeline.json.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
BLEND_PATH = PROJECT_ROOT / "weapons_model.blend" / "jammer_gun.blend"
PREVIEW_PATH = PROJECT_ROOT / "screenshots" / "jammer_gun_slim_preview.png"
TEXTURE_DIR = PROJECT_ROOT / "Assets" / "materials"

try:
    result
except NameError:
    result = {}


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for curve in list(bpy.data.curves):
        bpy.data.curves.remove(curve)


def material(name: str, color, metallic: float, roughness: float, texture: str | None = None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        return mat

    for node in list(nodes):
        if node.name.startswith("Jammer_Generated_"):
            nodes.remove(node)

    if texture:
        texture_path = TEXTURE_DIR / texture
        if texture_path.exists():
            tex = nodes.new("ShaderNodeTexImage")
            tex.name = "Jammer_Generated_Texture"
            image = bpy.data.images.load(str(texture_path), check_existing=True)
            image.reload()
            tex.image = image
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


def build_materials():
    return {
        "body": material("Body_Tactical", (0.055, 0.06, 0.062, 1.0), 0.12, 0.78, "jammer_body_color.png"),
        "antenna": material("Antenna_Metal", (0.45, 0.46, 0.44, 1.0), 0.9, 0.34, "jammer_antenna_color.png"),
        "led": material("LED_Accent", (0.0, 0.85, 1.0, 1.0), 0.0, 0.12, "jammer_led_color.png"),
    }


def finish(obj, mat, bevel: float = 0.025, segments: int = 1):
    if hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    if obj.type == "MESH":
        if bevel > 0:
            bevel_mod = obj.modifiers.new("production bevel", "BEVEL")
            bevel_mod.width = bevel
            bevel_mod.segments = segments
            bevel_mod.affect = "EDGES"
        normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
        normal_mod.keep_sharp = True
    return obj


def attach(obj, parent):
    obj.parent = parent
    return obj


def box(name, loc, scale, mat, parent, bevel=0.025, rot=(0.0, 0.0, 0.0), segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel, segments)
    return attach(obj, parent)


def cylinder(name, loc, radius, depth, mat, parent, vertices=32, rot=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return attach(obj, parent)


def cylinder_between(name, start, end, radius, mat, parent, vertices=24, bevel=0.0):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    length = direction.length
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=(start_v + end_v) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, bevel)
    return attach(obj, parent)


def label(name, text, loc, size, mat, parent, rot=(math.radians(90), 0.0, 0.0)):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.006
    obj.data.resolution_u = 2
    obj.data.materials.append(mat)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return attach(obj, parent)


def side_label(name, text, loc, size, mat, parent, side: str):
    """Place readable text on a side face with baseline along weapon length."""
    bpy.ops.object.text_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.006
    obj.data.resolution_u = 2
    obj.data.materials.append(mat)

    normal_x = 1.0 if side == "right" else -1.0
    baseline_y = 1.0 if side == "right" else -1.0
    matrix = Matrix(
        (
            (0.0, 0.0, normal_x),
            (baseline_y, 0.0, 0.0),
            (0.0, 1.0, 0.0),
        )
    )
    obj.rotation_euler = matrix.to_euler()

    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, mat, 0.0)
    return attach(obj, parent)


def object_bounds(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "min": Vector((min(c[i] for c in corners) for i in range(3))),
        "max": Vector((max(c[i] for c in corners) for i in range(3))),
        "center": Vector((sum(c[i] for c in corners) / 8.0 for i in range(3))),
    }


def seat_side_panel_group(root, overlap=0.008):
    receiver = bpy.data.objects.get("Receiver_Slim_Main")
    left_panel = bpy.data.objects.get("Side_Panel_Left")
    right_panel = bpy.data.objects.get("Side_Panel_Right")
    if receiver is None or left_panel is None or right_panel is None:
        return

    bpy.context.view_layer.update()
    receiver_bounds = object_bounds(receiver)
    left_bounds = object_bounds(left_panel)
    right_bounds = object_bounds(right_panel)
    left_half_x = (left_bounds["max"].x - left_bounds["min"].x) / 2.0
    right_half_x = (right_bounds["max"].x - right_bounds["min"].x) / 2.0
    left_delta = (receiver_bounds["min"].x + overlap - left_half_x) - left_bounds["center"].x
    right_delta = (receiver_bounds["max"].x - overlap + right_half_x) - right_bounds["center"].x

    left_names = {"Side_Panel_Left", "Side_Label_RF_JAM_Left"}
    right_names = {"Side_Panel_Right", "Side_Label_RF_JAM_Right"}
    for obj in bpy.context.scene.objects:
        if obj.name in left_names or obj.name.startswith("Panel_Screw_Left_"):
            obj.location.x += left_delta
            obj.parent = root
        elif obj.name in right_names or obj.name.startswith("Panel_Screw_Right_"):
            obj.location.x += right_delta
            obj.parent = root


def seat_driven_elements_on_collar(root, overlap=0.008):
    collar = bpy.data.objects.get("Emitter_Muzzle_Collar")
    left = bpy.data.objects.get("Driven_Element_Left")
    right = bpy.data.objects.get("Driven_Element_Right")
    if collar is None or left is None or right is None:
        return

    bpy.context.view_layer.update()
    collar_bounds = object_bounds(collar)
    left_bounds = object_bounds(left)
    right_bounds = object_bounds(right)
    left_half_x = (left_bounds["max"].x - left_bounds["min"].x) / 2.0
    right_half_x = (right_bounds["max"].x - right_bounds["min"].x) / 2.0
    left_half_y = (left_bounds["max"].y - left_bounds["min"].y) / 2.0
    right_half_y = (right_bounds["max"].y - right_bounds["min"].y) / 2.0

    left.location.x += (collar_bounds["min"].x + overlap - left_half_x) - left_bounds["center"].x
    right.location.x += (collar_bounds["max"].x - overlap + right_half_x) - right_bounds["center"].x
    left.location.y += (collar_bounds["min"].y - left_half_y + overlap) - left_bounds["center"].y
    right.location.y += (collar_bounds["min"].y - right_half_y + overlap) - right_bounds["center"].y
    left.parent = root
    right.parent = root


def add_body(root, mats):
    body = mats["body"]
    antenna = mats["antenna"]
    led = mats["led"]

    box("Receiver_Slim_Main", (0.0, 0.2, 0.18), (0.78, 2.82, 0.62), body, root, 0.065, segments=2)
    box("Receiver_Tapered_Nose", (0.0, -1.46, 0.2), (0.64, 0.88, 0.5), body, root, 0.055, segments=2)
    box("Electronics_Pod_Low_Profile", (0.0, 0.48, 0.72), (0.66, 1.28, 0.24), body, root, 0.035, segments=2)
    box("Top_Rail_Slim", (0.0, -0.1, 0.99), (0.44, 2.58, 0.1), body, root, 0.018)
    for i, y in enumerate([-1.18, -0.76, -0.34, 0.08, 0.5, 0.92]):
        box(f"Top_Rail_Lug_{i}", (0.0, y, 1.13), (0.52, 0.12, 0.08), body, root, 0.009)

    box("Pistol_Grip_Mount_Block", (0.0, 0.72, -0.2), (0.42, 0.42, 0.26), body, root, 0.035)
    box("Pistol_Grip_Slim", (0.0, 0.98, -0.84), (0.36, 0.34, 1.28), body, root, 0.055, rot=(math.radians(-8), 0.0, 0.0), segments=2)
    box("Grip_Backstrap_Texture", (0.0, 1.13, -0.86), (0.29, 0.04, 0.92), body, root, 0.018, rot=(math.radians(-8), 0.0, 0.0))
    for i, z in enumerate([-1.18, -0.92, -0.66, -0.4]):
        box(f"Grip_Finger_Groove_{i}", (0.0, 0.79, z), (0.32, 0.045, 0.055), antenna, root, 0.006)

    box("Trigger_Guard_Front_Post", (0.0, -0.23, -0.45), (0.34, 0.08, 0.42), body, root, 0.018)
    box("Trigger_Guard_Bottom_Bar", (0.0, 0.17, -0.75), (0.34, 0.72, 0.09), body, root, 0.018)
    box("Trigger_Guard_Rear_Post", (0.0, 0.5, -0.46), (0.34, 0.08, 0.48), body, root, 0.018)
    cylinder_between("Trigger_Curved_Metal", (0.0, -0.02, -0.32), (0.0, 0.1, -0.7), 0.028, antenna, root, 18, 0.002)
    box("Foregrip_Rail_Clamp", (0.0, -1.48, -0.18), (0.34, 0.45, 0.2), body, root, 0.025)
    box("Foregrip_Short", (0.0, -1.56, -0.74), (0.34, 0.28, 1.04), body, root, 0.05, rot=(math.radians(3), 0.0, 0.0), segments=2)
    box("Foregrip_End_Cap", (0.0, -1.6, -1.29), (0.36, 0.3, 0.09), antenna, root, 0.012)

    box("Skeleton_Stock_Top_Strut", (0.0, 1.92, 0.55), (0.36, 1.35, 0.2), body, root, 0.04)
    box("Skeleton_Stock_Bottom_Strut", (0.0, 1.95, -0.02), (0.32, 1.1, 0.16), body, root, 0.035)
    box("Compact_Buttpad", (0.0, 2.58, 0.24), (0.52, 0.14, 0.88), body, root, 0.05, segments=2)

    box("Side_Panel_Left", (-0.43, -0.02, 0.22), (0.032, 2.02, 0.42), body, root, 0.014)
    box("Side_Panel_Right", (0.43, -0.02, 0.22), (0.032, 2.02, 0.42), body, root, 0.014)
    for i, y in enumerate([-0.8, -0.25, 0.3, 0.85]):
        cylinder(f"Panel_Screw_Left_{i}", (-0.455, y, 0.38), 0.044, 0.024, antenna, root, 20, rot=(0.0, math.pi / 2.0, 0.0), bevel=0.002)
        cylinder(f"Panel_Screw_Right_{i}", (0.455, y, 0.38), 0.044, 0.024, antenna, root, 20, rot=(0.0, math.pi / 2.0, 0.0), bevel=0.002)

    label("Mode_Label_RF_JAM", "RF JAM", (0.0, -0.15, 0.66), 0.14, led, root)
    label("Grip_Label_COUNTER_UAV", "C-UAV", (0.0, 1.02, -0.08), 0.11, led, root)
    side_label("Side_Label_RF_JAM_Left", "RF JAM", (-0.472, -0.05, 0.28), 0.16, led, root, "left")
    side_label("Side_Label_RF_JAM_Right", "RF JAM", (0.472, -0.05, 0.28), 0.16, led, root, "right")
    seat_side_panel_group(root)


def add_emitter(root, mats):
    body = mats["body"]
    antenna = mats["antenna"]
    led = mats["led"]

    cylinder_between("Emitter_Muzzle_Boom", (0.0, -2.0, 0.22), (0.0, -5.85, 0.22), 0.07, antenna, root, 32, 0.004)
    cylinder("Emitter_Muzzle_Collar", (0.0, -2.05, 0.22), 0.28, 0.26, body, root, 32, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.01)
    cylinder("Emitter_Muzzle_Tip", (0.0, -5.98, 0.22), 0.16, 0.28, antenna, root, 32, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.006)

    for i, y in enumerate([-2.58, -3.08, -3.68, -4.32, -5.05]):
        span = 0.95 - i * 0.07
        cylinder_between(f"Yagi_Director_{i}", (-span * 0.5, y, 0.22), (span * 0.5, y, 0.22), 0.035, antenna, root, 18, 0.002)
        cylinder_between(f"Yagi_Director_Vert_{i}", (0.0, y, 0.22 - span * 0.28), (0.0, y, 0.22 + span * 0.28), 0.027, antenna, root, 18, 0.002)

    cylinder_between("Driven_Element_Left", (-0.46, -2.28, 0.22), (-0.46, -2.28, 0.98), 0.035, antenna, root, 18, 0.002)
    cylinder_between("Driven_Element_Right", (0.46, -2.28, 0.22), (0.46, -2.28, 0.98), 0.035, antenna, root, 18, 0.002)
    seat_driven_elements_on_collar(root)
    cylinder_between("Shielded_Cable_Run", (-0.32, -2.0, -0.03), (-0.32, -0.8, 0.23), 0.032, antenna, root, 18, 0.002)
    cylinder("Emitter_LED_Ring", (0.0, -5.78, 0.22), 0.18, 0.035, led, root, 32, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.002)


def add_scope(root, mats):
    body = mats["body"]
    antenna = mats["antenna"]
    led = mats["led"]

    # Compact optic above the lowered cable run. The cyan lens is now part of
    # this scope assembly instead of floating alone on the receiver.
    cylinder_between("Scope_Tube", (0.0, -1.36, 0.92), (0.0, 0.1, 0.92), 0.2, body, root, 40, 0.006)
    cylinder("Scope_Front_Housing", (0.0, -1.46, 0.92), 0.26, 0.2, body, root, 40, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.008)
    cylinder("Scope_Rear_Housing", (0.0, 0.18, 0.92), 0.24, 0.18, body, root, 40, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.008)
    cylinder("Scope_Front_Cyan_Lens", (0.0, -1.58, 0.92), 0.19, 0.035, led, root, 40, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.004)
    cylinder("Scope_Rear_Glass", (0.0, 0.29, 0.92), 0.16, 0.03, antenna, root, 32, rot=(math.pi / 2.0, 0.0, 0.0), bevel=0.002)
    box("Scope_Low_Mount_Front", (0.0, -1.05, 0.65), (0.28, 0.16, 0.28), body, root, 0.02)
    box("Scope_Low_Mount_Rear", (0.0, -0.2, 0.65), (0.28, 0.16, 0.28), body, root, 0.02)
    box("Scope_Mount_Rail_Clamp", (0.0, -0.62, 0.5), (0.42, 0.98, 0.1), antenna, root, 0.012)


def add_preview() -> None:
    bpy.ops.object.light_add(type="AREA", location=(-3.5, -6.5, 5.0))
    key = bpy.context.object
    key.name = "Preview_Key_Light"
    key.data.energy = 640
    key.data.size = 4.8

    bpy.ops.object.light_add(type="AREA", location=(4.0, 2.5, 4.0))
    fill = bpy.context.object
    fill.name = "Preview_Fill_Light"
    fill.data.energy = 180
    fill.data.size = 4.2

    bpy.ops.object.camera_add(location=(5.0, -8.2, 3.1))
    cam = bpy.context.object
    cam.name = "Preview_Camera"
    target = Vector((0.0, -1.6, 0.05))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 7.4
    bpy.context.scene.camera = cam
    if bpy.context.scene.world is not None:
        bpy.context.scene.world.color = (0.045, 0.047, 0.047)


def save_preview() -> str | None:
    try:
        PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.scene.render.engine = "BLENDER_EEVEE"
        bpy.context.scene.render.resolution_x = 1400
        bpy.context.scene.render.resolution_y = 900
        bpy.context.scene.eevee.taa_render_samples = 64
        bpy.context.scene.render.filepath = str(PREVIEW_PATH)
        bpy.ops.render.render(write_still=True)
        return str(PREVIEW_PATH)
    except Exception as exc:
        print(f"Preview render skipped: {exc}")
        return None


def main():
    clear_scene()
    mats = build_materials()
    root = bpy.data.objects.new("Jammer_Gun", None)
    bpy.context.collection.objects.link(root)

    add_body(root, mats)
    add_emitter(root, mats)
    add_scope(root, mats)
    add_preview()

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    preview = save_preview()

    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    result.update(
        {
            "saved": str(BLEND_PATH),
            "preview": preview,
            "root": root.name,
            "mesh_count": len(meshes),
            "materials": sorted(mat.name for mat in bpy.data.materials if mat.name in {"Body_Tactical", "Antenna_Metal", "LED_Accent"}),
            "style": "slimmer directional jammer with compact receiver and yagi emitter",
        }
    )


main()
