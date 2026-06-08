from __future__ import annotations

import math
import random
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
BLEND_PATH = ROOT / "environment_model.blend" / "bouneurmaum_park_sign.blend"
MATERIAL_DIR = ROOT / "Assets" / "materials" / "environment"

SIGN_NAME = "BouneurmaumParkSign"
FRONT_Y = -0.105

MAT_FACE = "BouneurmaumSignWoodFace"
MAT_BROWN = "BouneurmaumSignDarkBrown"
MAT_CREAM = "BouneurmaumSignCream"


def ensure_dirs() -> None:
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)


def save_color_texture(path: Path, width: int, height: int, pixel_fn) -> None:
    image = bpy.data.images.new(path.stem, width=width, height=height, alpha=True)
    pixels: list[float] = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixel_fn(x, y, width, height)
            pixels.extend((r, g, b, a))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def make_textures() -> None:
    rng = random.Random(42)
    grain_offsets = [rng.uniform(-0.08, 0.08) for _ in range(128)]

    def wood_face(x: int, y: int, w: int, h: int):
        u = x / max(1, w - 1)
        v = y / max(1, h - 1)
        band = math.sin((v * 32.0) + 0.65 * math.sin(u * 11.0))
        fine = math.sin((v * 115.0) + grain_offsets[y % len(grain_offsets)] * 18.0)
        streak = 1.0 if abs(band) > 0.90 else 0.0
        variation = 0.030 * band + 0.012 * fine - 0.045 * streak
        return (
            max(0.0, min(1.0, 0.78 + variation)),
            max(0.0, min(1.0, 0.63 + variation * 0.75)),
            max(0.0, min(1.0, 0.42 + variation * 0.55)),
            1.0,
        )

    def dark_brown(x: int, y: int, w: int, h: int):
        n = 0.012 * math.sin((x * 0.19) + (y * 0.07))
        return (0.265 + n, 0.135 + n * 0.6, 0.075 + n * 0.35, 1.0)

    def cream(x: int, y: int, w: int, h: int):
        n = 0.010 * math.sin((x * 0.11) + (y * 0.13))
        return (0.88 + n, 0.78 + n, 0.61 + n * 0.5, 1.0)

    save_color_texture(MATERIAL_DIR / "bouneurmaum_sign_wood_face_color.png", 512, 512, wood_face)
    save_color_texture(MATERIAL_DIR / "bouneurmaum_sign_dark_brown_color.png", 64, 64, dark_brown)
    save_color_texture(MATERIAL_DIR / "bouneurmaum_sign_cream_color.png", 64, 64, cream)


def create_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.82
        bsdf.inputs["Metallic"].default_value = 0.0
    mat.diffuse_color = color
    return mat


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def rounded_sign_outline(
    top_width: float,
    bottom_width: float,
    height: float,
    radius: float,
    bottom_z: float = 0.0,
    segments: int = 8,
) -> list[tuple[float, float]]:
    top_z = bottom_z + height
    bw = bottom_width * 0.5
    tw = top_width * 0.5
    r = radius
    points: list[tuple[float, float]] = []

    points.append((-bw + r, bottom_z))
    points.append((bw - r, bottom_z))

    cx, cz = bw - r, bottom_z + r
    for i in range(1, segments + 1):
        a = math.radians(-90.0 + (90.0 * i / segments))
        points.append((cx + r * math.cos(a), cz + r * math.sin(a)))

    points.append((tw, top_z - r))

    cx, cz = tw - r, top_z - r
    for i in range(1, segments + 1):
        a = math.radians(0.0 + (90.0 * i / segments))
        points.append((cx + r * math.cos(a), cz + r * math.sin(a)))

    points.append((-tw + r, top_z))

    cx, cz = -tw + r, top_z - r
    for i in range(1, segments + 1):
        a = math.radians(90.0 + (90.0 * i / segments))
        points.append((cx + r * math.cos(a), cz + r * math.sin(a)))

    points.append((-bw, bottom_z + r))

    cx, cz = -bw + r, bottom_z + r
    for i in range(1, segments + 1):
        a = math.radians(180.0 + (90.0 * i / segments))
        points.append((cx + r * math.cos(a), cz + r * math.sin(a)))

    return points


def asymmetric_outer_outline() -> list[tuple[float, float]]:
    return [
        (-1.70, 0.00),
        (1.58, 0.00),
        (1.68, 0.02),
        (1.78, 0.09),
        (1.84, 0.20),
        (1.86, 0.34),
        (1.91, 0.86),
        (1.97, 1.42),
        (1.99, 1.70),
        (1.95, 1.92),
        (1.84, 2.14),
        (1.66, 2.26),
        (0.70, 2.22),
        (-0.55, 2.12),
        (-1.58, 2.02),
        (-1.85, 1.95),
        (-2.04, 1.78),
        (-2.14, 1.51),
        (-2.11, 1.18),
        (-2.03, 0.74),
        (-1.94, 0.34),
        (-1.85, 0.11),
    ]


def asymmetric_face_outline() -> list[tuple[float, float]]:
    return [
        (-1.55, 0.82),
        (1.53, 0.82),
        (1.64, 0.84),
        (1.73, 0.92),
        (1.77, 1.05),
        (1.79, 1.72),
        (1.74, 1.94),
        (1.61, 2.09),
        (0.62, 2.06),
        (-0.38, 1.98),
        (-1.48, 1.88),
        (-1.67, 1.82),
        (-1.79, 1.67),
        (-1.82, 1.46),
        (-1.78, 0.98),
        (-1.70, 0.88),
    ]


def add_planar_uv(mesh: bpy.types.Mesh) -> None:
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active
    xs = [vertex.co.x for vertex in mesh.vertices]
    zs = [vertex.co.z for vertex in mesh.vertices]
    min_x, max_x = min(xs), max(xs)
    min_z, max_z = min(zs), max(zs)
    span_x = max(0.001, max_x - min_x)
    span_z = max(0.001, max_z - min_z)

    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            uv_layer.data[loop_index].uv = (
                (vertex.co.x - min_x) / span_x,
                (vertex.co.z - min_z) / span_z,
            )


def apply_bevel(obj: bpy.types.Object, width: float, segments: int = 2) -> None:
    bevel = obj.modifiers.new("soft_beveled_edges", "BEVEL")
    bevel.width = width
    bevel.segments = segments
    bevel.affect = "EDGES"
    normal = obj.modifiers.new("weighted_normals", "WEIGHTED_NORMAL")
    normal.keep_sharp = True

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    bpy.ops.object.modifier_apply(modifier=normal.name)


def create_prism(
    name: str,
    outline: list[tuple[float, float]],
    depth: float,
    y_center: float,
    material: bpy.types.Material,
    bevel: float,
) -> bpy.types.Object:
    n = len(outline)
    front_y = y_center - depth * 0.5
    back_y = y_center + depth * 0.5
    vertices = [(x, front_y, z) for x, z in outline] + [(x, back_y, z) for x, z in outline]
    faces: list[list[int]] = [list(range(n)), list(reversed(range(n, n * 2)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, j + n, i + n])

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.materials.append(material)
    add_planar_uv(mesh)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    apply_bevel(obj, bevel)
    return obj


def create_box(
    name: str,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    material: bpy.types.Material,
    bevel: float,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}Mesh"
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    add_planar_uv(obj.data)
    apply_bevel(obj, bevel)
    return obj


def create_pine(
    prefix: str,
    x: float,
    z: float,
    scale: float,
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    y = FRONT_Y - 0.035
    depth = 0.045

    def tri(name: str, center_z: float, width: float, height: float):
        outline = [
            (x - width * 0.5, center_z - height * 0.5),
            (x + width * 0.5, center_z - height * 0.5),
            (x, center_z + height * 0.5),
        ]
        parts.append(create_prism(name, outline, depth, y, material, 0.006))

    parts.append(
        create_box(
            f"{prefix}_Trunk",
            (x, y - 0.01, z + 0.13 * scale),
            (0.13 * scale, depth, 0.27 * scale),
            material,
            0.005,
        )
    )
    tri(f"{prefix}_LowerBoughs", z + 0.38 * scale, 0.72 * scale, 0.55 * scale)
    tri(f"{prefix}_MiddleBoughs", z + 0.63 * scale, 0.58 * scale, 0.52 * scale)
    tri(f"{prefix}_TopBoughs", z + 0.89 * scale, 0.43 * scale, 0.55 * scale)
    return parts


def add_text(
    name: str,
    body: str,
    font_path: Path,
    size: float,
    location: tuple[float, float, float],
    material: bpy.types.Material,
    max_width: float,
    max_height: float | None = None,
    extrude: float = 0.032,
    bevel_depth: float = 0.004,
) -> bpy.types.Object:
    bpy.ops.object.text_add(location=location, rotation=(math.radians(90.0), 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}Curve"
    obj.data.body = body
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = extrude
    obj.data.bevel_depth = bevel_depth
    obj.data.bevel_resolution = 2
    obj.data.resolution_u = 16
    if font_path.exists():
        obj.data.font = bpy.data.fonts.load(str(font_path))
    obj.data.materials.append(material)

    bpy.context.view_layer.update()
    width = obj.dimensions.x
    height = obj.dimensions.z
    scale = 1.0
    if width > max_width:
        scale = min(scale, max_width / width)
    if max_height is not None and height > max_height:
        scale = min(scale, max_height / height)
    obj.scale = (scale, scale, scale)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.object
    mesh_obj.name = name
    mesh_obj.data.name = f"{name}Mesh"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if not mesh_obj.data.materials:
        mesh_obj.data.materials.append(material)
    add_planar_uv(mesh_obj.data)
    return mesh_obj


def add_screw(name: str, x: float, z: float, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=36,
        radius=0.055,
        depth=0.030,
        location=(x, FRONT_Y - 0.045, z),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}Mesh"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(material)
    add_planar_uv(obj.data)
    apply_bevel(obj, 0.006, 2)
    return obj


def parent_all(root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        obj.parent = root


def frame_camera() -> None:
    bpy.ops.object.light_add(type="AREA", location=(0.0, -4.0, 4.0))
    light = bpy.context.object
    light.name = "Preview_KeyLight"
    light.data.energy = 450.0
    light.data.size = 4.0

    bpy.ops.object.camera_add(location=(0.0, -5.2, 1.35), rotation=(math.radians(78.0), 0.0, 0.0))
    camera = bpy.context.object
    bpy.context.scene.camera = camera
    camera.name = "Preview_Camera"
    camera.data.lens = 35.0


def main() -> None:
    ensure_dirs()
    clear_scene()
    make_textures()

    mat_face = create_material(MAT_FACE, (0.78, 0.63, 0.42, 1.0))
    mat_brown = create_material(MAT_BROWN, (0.27, 0.14, 0.08, 1.0))
    mat_cream = create_material(MAT_CREAM, (0.88, 0.78, 0.61, 1.0))

    root = bpy.data.objects.new(f"{SIGN_NAME}Root", None)
    bpy.context.collection.objects.link(root)

    objects: list[bpy.types.Object] = []

    body_outline = asymmetric_outer_outline()
    objects.append(create_prism("OuterDarkBrownBoard", body_outline, 0.18, 0.0, mat_brown, 0.025))

    face_outline = asymmetric_face_outline()
    objects.append(create_prism("InsetWoodFace", face_outline, 0.035, FRONT_Y, mat_face, 0.014))

    divider_outline = [
        (-1.78, 0.755),
        (1.74, 0.755),
        (1.78, 0.815),
        (-1.82, 0.815),
    ]
    objects.append(create_prism("DarkLowerDivider", divider_outline, 0.055, FRONT_Y - 0.020, mat_brown, 0.006))

    script_font = Path("C:/Windows/Fonts/segoescb.ttf")
    sans_font = Path("C:/Windows/Fonts/arialbd.ttf")
    objects.append(
        add_text(
            "WelcomeToText",
            "Welcome to",
            script_font,
            0.71,
            (-0.5901693105697632, FRONT_Y - 0.080, 1.689031720161438),
            mat_brown,
            max_width=3.00,
            max_height=0.70,
            extrude=0.034,
            bevel_depth=0.005,
        )
    )
    objects.append(
        add_text(
            "BouneurmaumText",
            "Bouneurmaum",
            sans_font,
            0.45,
            (-0.6033071279525757, FRONT_Y - 0.078, 1.2515662908554077),
            mat_brown,
            max_width=3.00,
            max_height=0.50,
            extrude=0.030,
            bevel_depth=0.003,
        )
    )
    objects.append(
        add_text(
            "NationalParkText",
            "NATIONAL PARK",
            sans_font,
            0.32,
            (0.0, FRONT_Y - 0.080, 0.36),
            mat_cream,
            max_width=3.35,
            max_height=0.34,
            extrude=0.030,
            bevel_depth=0.003,
        )
    )

    objects.extend(create_pine("SmallLeftPine", 0.8297061920166016, 1.10, 0.58, mat_brown))
    objects.extend(create_pine("CenterPine", 1.1797062158584595, 1.02, 0.78, mat_brown))
    objects.extend(create_pine("SmallRightPine", 1.5097062587738037, 1.12, 0.56, mat_brown))

    objects.append(add_screw("TopMountScrew", 0.0, 2.08, mat_brown))
    objects.append(add_screw("LowerMountScrew", 0.0, 0.16, mat_brown))

    parent_all(root, objects)

    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.cycles.samples = 64
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.unit_settings.system = "METRIC"

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


if __name__ == "__main__":
    main()
