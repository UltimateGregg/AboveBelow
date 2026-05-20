#!/usr/bin/env python3
"""
Create the `house_rural` two-story farmhouse arena prop in Blender.

The authored dimensions use game units directly:
- -Y is forward/north.
- +Z is up.
- Ground floor occupies z=0..400.
- Loft walk surface is at z=300.
- Roof gameplay/readability band starts at z=620.

Run from Blender:
  blender --background --python scripts/create_rural_farmhouse_arena.py

Set COMBINE_FOR_EXPORT to False if you want to inspect the individual authoring
objects before export. The default combined mesh preserves the material slots
and material indices expected by S&Box/FBX export.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ASSET_NAME = "house_rural"
OUTPUT_OBJECT_NAME = "HouseRuralMesh"
COMBINE_FOR_EXPORT = True

WIDTH = 540.0
DEPTH = 460.0
WALL_THICKNESS = 14.0
GROUND_Z_MIN = 0.0
GROUND_Z_MAX = 400.0
LOFT_Z = 300.0
EAVE_Z = 620.0
RIDGE_Z = 675.0

SCRIPT_PATH = Path(__file__).resolve() if "__file__" in globals() else Path.cwd() / "create_rural_farmhouse_arena.py"
PROJECT_ROOT = SCRIPT_PATH.parents[1] if SCRIPT_PATH.parent.name == "scripts" else Path(r"C:\Programming\S&Box")
BLEND_PATH = PROJECT_ROOT / "environment_model.blend" / f"{ASSET_NAME}.blend"

MATERIAL_SPECS = {
    # Weathered cream/tan siding. Slight roughness keeps the look natural in Blender preview.
    "M_Wall_Siding": ((0.70, 0.62, 0.47, 1.0), 0.0, 0.88),
    # Rust-brown metal roof for a strong farmhouse silhouette from drone view.
    "M_Roof_Metal": ((0.48, 0.20, 0.10, 1.0), 0.55, 0.46),
    # Dark structural timber posts and beams.
    "M_Structural_Frame": ((0.18, 0.11, 0.07, 1.0), 0.0, 0.82),
    # Bright ladder metal for fast gameplay read.
    "M_Ladder": ((0.78, 0.88, 0.92, 1.0), 0.8, 0.30),
    # Bright safety/sniper railing accent.
    "M_Sniper_Railing": ((0.95, 0.78, 0.20, 1.0), 0.65, 0.34),
    # Darker door/window surround material marking entry points.
    "M_Entry_Frame": ((0.16, 0.10, 0.06, 1.0), 0.0, 0.72),
    # Pale concrete/aged support material for foundation and base posts.
    "M_Foundation": ((0.58, 0.56, 0.48, 1.0), 0.0, 0.80),
}

MATERIAL_ASSETS = {
    "M_Wall_Siding": {
        "texture": "materials/environment/house_rural_siding_color.png",
        "vmat": "Assets/materials/environment/house_rural_siding.vmat",
        "pattern": "siding",
        "seed": 11,
    },
    "M_Roof_Metal": {
        "texture": "materials/environment/house_rural_roof_color.png",
        "vmat": "Assets/materials/environment/house_rural_roof.vmat",
        "pattern": "roof",
        "seed": 17,
    },
    "M_Structural_Frame": {
        "texture": "materials/environment/house_rural_frame_color.png",
        "vmat": "Assets/materials/environment/house_rural_frame.vmat",
        "pattern": "wood",
        "seed": 23,
    },
    "M_Ladder": {
        "texture": "materials/environment/house_rural_ladder_color.png",
        "vmat": "Assets/materials/environment/house_rural_ladder.vmat",
        "pattern": "metal",
        "seed": 29,
    },
    "M_Sniper_Railing": {
        "texture": "materials/environment/house_rural_railing_color.png",
        "vmat": "Assets/materials/environment/house_rural_railing.vmat",
        "pattern": "painted_metal",
        "seed": 31,
    },
    "M_Entry_Frame": {
        "texture": "materials/environment/house_rural_entry_color.png",
        "vmat": "Assets/materials/environment/house_rural_entry.vmat",
        "pattern": "wood",
        "seed": 37,
    },
    "M_Foundation": {
        "texture": "materials/environment/house_rural_foundation_color.png",
        "vmat": "Assets/materials/environment/house_rural_foundation.vmat",
        "pattern": "concrete",
        "seed": 41,
    },
}


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def make_material(name: str) -> bpy.types.Material:
    color, metallic, roughness = MATERIAL_SPECS[name]
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        for input_name, value in (
            ("Base Color", color),
            ("Metallic", metallic),
            ("Roughness", roughness),
        ):
            socket = bsdf.inputs.get(input_name)
            if socket is not None:
                socket.default_value = value
    return mat


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def signed_noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = (value ^ (value >> 13)) * 1274126177
    value = (value ^ (value >> 16)) & 0xFFFFFFFF
    return (value / 0xFFFFFFFF) * 2.0 - 1.0


def texture_rgb(material_name: str, x: int, y: int, size: int) -> tuple[float, float, float]:
    color, _metallic, _roughness = MATERIAL_SPECS[material_name]
    base = color[:3]
    asset = MATERIAL_ASSETS[material_name]
    seed = int(asset["seed"])
    pattern = str(asset["pattern"])
    u = x / max(1, size - 1)
    v = y / max(1, size - 1)
    noise = signed_noise(x // 3, y // 3, seed)

    if pattern == "siding":
        board_line = 1.0 if y % 18 in (0, 1) else 0.0
        weather = 0.045 * math.sin((u * 18.0 + noise) * math.tau) + 0.025 * signed_noise(x, y // 9, seed + 3)
        shade = weather - board_line * 0.18
    elif pattern == "roof":
        seam = 1.0 if x % 20 in (0, 1) else 0.0
        rust = 0.08 * max(0.0, signed_noise(x // 8, y // 8, seed + 5))
        shade = rust - seam * 0.10 + 0.025 * math.sin(v * math.tau * 9.0)
    elif pattern in {"wood", "concrete"}:
        grain = 0.06 * math.sin((u * 32.0 + signed_noise(x // 6, y // 5, seed + 7)) * math.tau)
        speckle = 0.045 * signed_noise(x, y, seed + 13)
        shade = grain + speckle
    else:
        diagonal = 1.0 if (x + y) % 28 in (0, 1) else 0.0
        shade = 0.035 * noise + diagonal * 0.05

    return tuple(clamp01(channel + shade) for channel in base)


def save_color_texture(material_name: str, texture_resource: str, size: int = 128) -> None:
    texture_path = PROJECT_ROOT / "Assets" / texture_resource
    texture_path.parent.mkdir(parents=True, exist_ok=True)
    image_name = Path(texture_resource).stem
    existing = bpy.data.images.get(image_name)
    if existing is not None:
        bpy.data.images.remove(existing)

    image = bpy.data.images.new(image_name, size, size, alpha=True)
    pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            pixels.extend((*texture_rgb(material_name, x, y, size), 1.0))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(texture_path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def write_vmat(material_name: str, vmat_relative: str, texture_resource: str) -> None:
    _color, metallic, roughness = MATERIAL_SPECS[material_name]
    vmat_path = PROJECT_ROOT / vmat_relative
    vmat_path.parent.mkdir(parents=True, exist_ok=True)
    vmat_path.write_text(
        "\n".join(
            [
                '"Layer0"',
                "{",
                '\t"shader"\t\t"shaders/complex.shader"',
                f'\t"TextureColor"\t\t"{texture_resource}"',
                '\t"g_flModelTintAmount"\t\t"1.000000"',
                '\t"g_vColorTint"\t\t"[1.000000 1.000000 1.000000 0.000000]"',
                f'\t"g_flMetalness"\t\t"{metallic:.6f}"',
                f'\t"g_flRoughness"\t\t"{roughness:.6f}"',
                '\t"g_bFogEnabled"\t\t"1"',
                '\t"g_vTexCoordScale"\t\t"[1.000 1.000]"',
                '\t"g_vTexCoordOffset"\t\t"[0.000 0.000]"',
                '\t"g_vTexCoordScrollSpeed"\t\t"[0.000 0.000]"',
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_material_assets() -> None:
    for material_name, asset in MATERIAL_ASSETS.items():
        texture_resource = str(asset["texture"])
        save_color_texture(material_name, texture_resource)
        write_vmat(material_name, str(asset["vmat"]), texture_resource)


def create_root() -> bpy.types.Object:
    root = bpy.data.objects.new("HouseRural_Root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 60.0
    root["axis_forward"] = "-Y"
    root["axis_up"] = "+Z"
    root["gameplay_ground_floor"] = "z=0..400"
    root["gameplay_loft"] = "walk surface at z=300"
    root["gameplay_roof"] = "roof edge/railing band starts at z=620"
    bpy.context.scene.collection.objects.link(root)
    return root


def assign_projected_uvs(obj: bpy.types.Object, scale: float = 0.012) -> None:
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")

    uv_layer = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        normal = poly.normal
        axis = max(range(3), key=lambda index: abs(normal[index]))
        for loop_index in poly.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if axis == 0:
                uv_layer[loop_index].uv = (vertex.y * scale, vertex.z * scale)
            elif axis == 1:
                uv_layer[loop_index].uv = (vertex.x * scale, vertex.z * scale)
            else:
                uv_layer[loop_index].uv = (vertex.x * scale, vertex.y * scale)


def finish_mesh_object(obj: bpy.types.Object, material_name: str, bevel: float = 0.0) -> bpy.types.Object:
    obj.data.materials.append(make_material(material_name))
    for poly in obj.data.polygons:
        poly.material_index = 0
    assign_projected_uvs(obj)

    if bevel > 0.0:
        bevel_mod = obj.modifiers.new("small readable bevels", "BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = 1
        bevel_mod.affect = "EDGES"

    normal_mod = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    normal_mod.keep_sharp = True
    return obj


def box(
    name: str,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    material_name: str,
    parent: bpy.types.Object,
    bevel: float = 0.0,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.parent = parent
    return finish_mesh_object(obj, material_name, bevel)


def mesh_object(
    name: str,
    verts: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material_name: str,
    parent: bpy.types.Object,
    bevel: float = 0.0,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    return finish_mesh_object(obj, material_name, bevel)


def opening_contains(opening: dict[str, float], horizontal: float, z: float, horizontal_key: str) -> bool:
    h1 = opening[f"{horizontal_key}1"]
    h2 = opening[f"{horizontal_key}2"]
    return h1 < horizontal < h2 and opening["z1"] < z < opening["z2"]


def add_wall_x(
    prefix: str,
    y: float,
    x_min: float,
    x_max: float,
    z_min: float,
    z_max: float,
    openings: list[dict[str, float]],
    parent: bpy.types.Object,
) -> list[bpy.types.Object]:
    xs = {x_min, x_max}
    zs = {z_min, z_max}
    for opening in openings:
        xs.update((opening["x1"], opening["x2"]))
        zs.update((opening["z1"], opening["z2"]))

    objects: list[bpy.types.Object] = []
    for x1, x2 in zip(sorted(xs), sorted(xs)[1:]):
        for z1, z2 in zip(sorted(zs), sorted(zs)[1:]):
            if x2 - x1 < 0.1 or z2 - z1 < 0.1:
                continue
            center_x = (x1 + x2) * 0.5
            center_z = (z1 + z2) * 0.5
            if any(opening_contains(opening, center_x, center_z, "x") for opening in openings):
                continue
            objects.append(
                box(
                    f"{prefix}_Panel_{len(objects) + 1:02d}",
                    (center_x, y, center_z),
                    (x2 - x1, WALL_THICKNESS, z2 - z1),
                    "M_Wall_Siding",
                    parent,
                    bevel=0.6,
                )
            )
    return objects


def add_wall_y(
    prefix: str,
    x: float,
    y_min: float,
    y_max: float,
    z_min: float,
    z_max: float,
    openings: list[dict[str, float]],
    parent: bpy.types.Object,
) -> list[bpy.types.Object]:
    ys = {y_min, y_max}
    zs = {z_min, z_max}
    for opening in openings:
        ys.update((opening["y1"], opening["y2"]))
        zs.update((opening["z1"], opening["z2"]))

    objects: list[bpy.types.Object] = []
    for y1, y2 in zip(sorted(ys), sorted(ys)[1:]):
        for z1, z2 in zip(sorted(zs), sorted(zs)[1:]):
            if y2 - y1 < 0.1 or z2 - z1 < 0.1:
                continue
            center_y = (y1 + y2) * 0.5
            center_z = (z1 + z2) * 0.5
            if any(opening_contains(opening, center_y, center_z, "y") for opening in openings):
                continue
            objects.append(
                box(
                    f"{prefix}_Panel_{len(objects) + 1:02d}",
                    (x, center_y, center_z),
                    (WALL_THICKNESS, y2 - y1, z2 - z1),
                    "M_Wall_Siding",
                    parent,
                    bevel=0.6,
                )
            )
    return objects


def add_frame_x(
    prefix: str,
    y: float,
    x1: float,
    x2: float,
    z1: float,
    z2: float,
    parent: bpy.types.Object,
    include_sill: bool,
) -> list[bpy.types.Object]:
    sign = -1.0 if y < 0.0 else 1.0
    frame = 9.0
    depth = WALL_THICKNESS + 8.0
    frame_y = y + sign * 4.0
    width = x2 - x1
    height = z2 - z1
    parts = [
        box(f"{prefix}_Frame_L", (x1 - frame * 0.5, frame_y, (z1 + z2) * 0.5), (frame, depth, height + frame), "M_Entry_Frame", parent, 0.8),
        box(f"{prefix}_Frame_R", (x2 + frame * 0.5, frame_y, (z1 + z2) * 0.5), (frame, depth, height + frame), "M_Entry_Frame", parent, 0.8),
        box(f"{prefix}_Frame_T", ((x1 + x2) * 0.5, frame_y, z2 + frame * 0.5), (width + frame * 2.0, depth, frame), "M_Entry_Frame", parent, 0.8),
    ]
    if include_sill:
        parts.append(
            box(
                f"{prefix}_Frame_B",
                ((x1 + x2) * 0.5, frame_y, z1 - frame * 0.5),
                (width + frame * 2.0, depth, frame),
                "M_Entry_Frame",
                parent,
                0.8,
            )
        )
    return parts


def add_frame_y(
    prefix: str,
    x: float,
    y1: float,
    y2: float,
    z1: float,
    z2: float,
    parent: bpy.types.Object,
    include_sill: bool,
) -> list[bpy.types.Object]:
    sign = -1.0 if x < 0.0 else 1.0
    frame = 9.0
    depth = WALL_THICKNESS + 8.0
    frame_x = x + sign * 4.0
    width = y2 - y1
    height = z2 - z1
    parts = [
        box(f"{prefix}_Frame_L", (frame_x, y1 - frame * 0.5, (z1 + z2) * 0.5), (depth, frame, height + frame), "M_Entry_Frame", parent, 0.8),
        box(f"{prefix}_Frame_R", (frame_x, y2 + frame * 0.5, (z1 + z2) * 0.5), (depth, frame, height + frame), "M_Entry_Frame", parent, 0.8),
        box(f"{prefix}_Frame_T", (frame_x, (y1 + y2) * 0.5, z2 + frame * 0.5), (depth, width + frame * 2.0, frame), "M_Entry_Frame", parent, 0.8),
    ]
    if include_sill:
        parts.append(
            box(
                f"{prefix}_Frame_B",
                (frame_x, (y1 + y2) * 0.5, z1 - frame * 0.5),
                (depth, width + frame * 2.0, frame),
                "M_Entry_Frame",
                parent,
                0.8,
            )
        )
    return parts


def add_railing_x(
    prefix: str,
    y: float,
    x1: float,
    x2: float,
    base_z: float,
    parent: bpy.types.Object,
    height: float = 72.0,
) -> list[bpy.types.Object]:
    x_low, x_high = sorted((x1, x2))
    length = x_high - x_low
    mid = (x_low + x_high) * 0.5
    posts = [x_low, x_high]
    if length > 150.0:
        posts.append(mid)

    parts = [
        box(f"{prefix}_Rail_Top", (mid, y, base_z + height), (length, 6.0, 6.0), "M_Sniper_Railing", parent, 0.5),
        box(f"{prefix}_Rail_Mid", (mid, y, base_z + height * 0.52), (length, 5.0, 5.0), "M_Sniper_Railing", parent, 0.5),
    ]
    for index, post_x in enumerate(posts):
        parts.append(
            box(
                f"{prefix}_Post_{index + 1:02d}",
                (post_x, y, base_z + height * 0.5),
                (7.0, 7.0, height),
                "M_Sniper_Railing",
                parent,
                0.5,
            )
        )
    return parts


def add_railing_y(
    prefix: str,
    x: float,
    y1: float,
    y2: float,
    base_z: float,
    parent: bpy.types.Object,
    height: float = 72.0,
) -> list[bpy.types.Object]:
    y_low, y_high = sorted((y1, y2))
    length = y_high - y_low
    mid = (y_low + y_high) * 0.5
    posts = [y_low, y_high]
    if length > 150.0:
        posts.append(mid)

    parts = [
        box(f"{prefix}_Rail_Top", (x, mid, base_z + height), (6.0, length, 6.0), "M_Sniper_Railing", parent, 0.5),
        box(f"{prefix}_Rail_Mid", (x, mid, base_z + height * 0.52), (5.0, length, 5.0), "M_Sniper_Railing", parent, 0.5),
    ]
    for index, post_y in enumerate(posts):
        parts.append(
            box(
                f"{prefix}_Post_{index + 1:02d}",
                (x, post_y, base_z + height * 0.5),
                (7.0, 7.0, height),
                "M_Sniper_Railing",
                parent,
                0.5,
            )
        )
    return parts


def add_ladder(parent: bpy.types.Object) -> list[bpy.types.Object]:
    # One continuous ladder on the north (-Y) side. It reaches the loft at z=300
    # and continues to the roof edge band at z=620.
    y = -DEPTH * 0.5 - 26.0
    x = -205.0
    z_min = 0.0
    z_max = 635.0
    height = z_max - z_min
    parts = [
        box("North_Ladder_Rail_W", (x - 15.0, y, z_min + height * 0.5), (5.0, 5.0, height), "M_Ladder", parent, 0.35),
        box("North_Ladder_Rail_E", (x + 15.0, y, z_min + height * 0.5), (5.0, 5.0, height), "M_Ladder", parent, 0.35),
        box("North_Ladder_Loft_Landing_Mark", (x, y - 2.0, LOFT_Z), (46.0, 8.0, 7.0), "M_Ladder", parent, 0.35),
    ]

    rung_count = 20
    for index in range(rung_count):
        z = z_min + 28.0 + index * ((height - 56.0) / (rung_count - 1))
        parts.append(
            box(
                f"North_Ladder_Rung_{index + 1:02d}",
                (x, y - 2.0, z),
                (36.0, 5.0, 5.0),
                "M_Ladder",
                parent,
                0.25,
            )
        )
    return parts


def add_gable_roof(parent: bpy.types.Object) -> bpy.types.Object:
    roof_width = WIDTH + 60.0
    roof_depth = DEPTH + 60.0
    half_w = roof_width * 0.5
    half_d = roof_depth * 0.5
    thickness = 18.0

    top = [
        (-half_w, -half_d, EAVE_Z),
        (0.0, -half_d, RIDGE_Z),
        (half_w, -half_d, EAVE_Z),
        (-half_w, half_d, EAVE_Z),
        (0.0, half_d, RIDGE_Z),
        (half_w, half_d, EAVE_Z),
    ]
    bottom = [(x, y, z - thickness) for x, y, z in top]
    verts = top + bottom
    faces = [
        (0, 1, 4, 3),  # west roof slope
        (1, 2, 5, 4),  # east roof slope
        (6, 9, 10, 7),  # underside west
        (7, 10, 11, 8),  # underside east
        (0, 3, 9, 6),  # west eave fascia
        (2, 8, 11, 5),  # east eave fascia
        (3, 4, 10, 9),  # south gable thickness
        (4, 5, 11, 10),
        (0, 6, 7, 1),  # north gable thickness
        (1, 7, 8, 2),
        (0, 2, 1),  # north visible triangle
        (3, 4, 5),  # south visible triangle
    ]
    return mesh_object("Pitched_Rust_Metal_Roof", verts, faces, "M_Roof_Metal", parent, bevel=1.2)


def add_gable_siding(parent: bpy.types.Object, y: float, name: str) -> bpy.types.Object:
    half_w = WIDTH * 0.5
    verts = [
        (-half_w, y, EAVE_Z - 4.0),
        (half_w, y, EAVE_Z - 4.0),
        (0.0, y, RIDGE_Z - 10.0),
    ]
    faces = [(0, 1, 2)]
    return mesh_object(name, verts, faces, "M_Wall_Siding", parent, bevel=0.0)


def add_foundation(parent: bpy.types.Object) -> list[bpy.types.Object]:
    half_w = WIDTH * 0.5
    half_d = DEPTH * 0.5
    parts: list[bpy.types.Object] = []
    for ix, x in enumerate((-half_w + 35.0, 0.0, half_w - 35.0)):
        for iy, y in enumerate((-half_d + 35.0, half_d - 35.0)):
            parts.append(
                box(
                    f"Foundation_Post_{ix + 1}_{iy + 1}",
                    (x, y, -18.0),
                    (36.0, 36.0, 72.0),
                    "M_Foundation",
                    parent,
                    0.8,
                )
            )

    parts.extend(
        [
            box("Foundation_Sill_North", (0.0, -half_d, 18.0), (WIDTH, 18.0, 22.0), "M_Foundation", parent, 0.7),
            box("Foundation_Sill_South", (0.0, half_d, 18.0), (WIDTH, 18.0, 22.0), "M_Foundation", parent, 0.7),
            box("Foundation_Sill_West", (-half_w, 0.0, 18.0), (18.0, DEPTH, 22.0), "M_Foundation", parent, 0.7),
            box("Foundation_Sill_East", (half_w, 0.0, 18.0), (18.0, DEPTH, 22.0), "M_Foundation", parent, 0.7),
        ]
    )
    return parts


def add_structural_frame(parent: bpy.types.Object) -> list[bpy.types.Object]:
    half_w = WIDTH * 0.5
    half_d = DEPTH * 0.5
    parts: list[bpy.types.Object] = []

    for x in (-half_w, half_w):
        for y in (-half_d, half_d):
            parts.append(
                box(
                    f"Dark_Timber_Corner_Post_{'E' if x > 0 else 'W'}_{'S' if y > 0 else 'N'}",
                    (x, y, EAVE_Z * 0.5),
                    (18.0, 18.0, EAVE_Z),
                    "M_Structural_Frame",
                    parent,
                    0.9,
                )
            )

    for z, label in ((GROUND_Z_MAX, "Ground_Top"), (LOFT_Z, "Loft_Band"), (EAVE_Z, "Roof_Plate")):
        parts.extend(
            [
                box(f"{label}_Beam_North", (0.0, -half_d, z), (WIDTH, 16.0, 16.0), "M_Structural_Frame", parent, 0.7),
                box(f"{label}_Beam_South", (0.0, half_d, z), (WIDTH, 16.0, 16.0), "M_Structural_Frame", parent, 0.7),
                box(f"{label}_Beam_West", (-half_w, 0.0, z), (16.0, DEPTH, 16.0), "M_Structural_Frame", parent, 0.7),
                box(f"{label}_Beam_East", (half_w, 0.0, z), (16.0, DEPTH, 16.0), "M_Structural_Frame", parent, 0.7),
            ]
        )

    # Two interior supports make the loft read as structural without adding many triangles.
    for x in (-105.0, 105.0):
        parts.append(box(f"Interior_Loft_Support_{x:+.0f}", (x, 0.0, LOFT_Z * 0.5), (14.0, 14.0, LOFT_Z), "M_Structural_Frame", parent, 0.7))
    return parts


def add_loft(parent: bpy.types.Object) -> list[bpy.types.Object]:
    parts = [
        # The top of this floor is exactly z=300, matching the gameplay-access target.
        box("Loft_Walk_Surface", (0.0, -18.0, LOFT_Z - 9.0), (470.0, 350.0, 18.0), "M_Structural_Frame", parent, 0.7),
        box("Loft_Ladder_Cutout_Trim", (-205.0, -177.0, LOFT_Z + 2.0), (92.0, 10.0, 10.0), "M_Entry_Frame", parent, 0.6),
    ]

    # Loft perimeter railing, with a north-side gap aligned to the ladder.
    parts.extend(add_railing_x("Loft_Railing_South", 165.0, -235.0, 235.0, LOFT_Z, parent, height=68.0))
    parts.extend(add_railing_y("Loft_Railing_West", -235.0, -165.0, 165.0, LOFT_Z, parent, height=68.0))
    parts.extend(add_railing_y("Loft_Railing_East", 235.0, -165.0, 165.0, LOFT_Z, parent, height=68.0))
    parts.extend(add_railing_x("Loft_Railing_North_East", -165.0, -130.0, 235.0, LOFT_Z, parent, height=68.0))
    return parts


def add_roof_corner_railings(parent: bpy.types.Object) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    rail_z = EAVE_Z
    x_edge = WIDTH * 0.5 + 20.0
    y_edge = DEPTH * 0.5 + 22.0
    corner_run = 115.0

    for x_sign in (-1.0, 1.0):
        for y_sign in (-1.0, 1.0):
            corner_label = ("E" if x_sign > 0 else "W") + ("S" if y_sign > 0 else "N")
            x_outer = x_sign * x_edge
            y_outer = y_sign * y_edge
            parts.extend(
                add_railing_x(
                    f"Roof_{corner_label}_Edge_Rail_X",
                    y_outer,
                    x_outer,
                    x_outer - x_sign * corner_run,
                    rail_z,
                    parent,
                    height=52.0,
                )
            )
            parts.extend(
                add_railing_y(
                    f"Roof_{corner_label}_Edge_Rail_Y",
                    x_outer,
                    y_outer,
                    y_outer - y_sign * corner_run,
                    rail_z,
                    parent,
                    height=52.0,
                )
            )
    return parts


def add_wall_shell(parent: bpy.types.Object) -> list[bpy.types.Object]:
    half_w = WIDTH * 0.5
    half_d = DEPTH * 0.5
    parts: list[bpy.types.Object] = []

    north_openings = [
        {"x1": -48.0, "x2": 48.0, "z1": 0.0, "z2": 228.0},  # primary door
        {"x1": -170.0, "x2": -98.0, "z1": 138.0, "z2": 240.0},
        {"x1": 98.0, "x2": 170.0, "z1": 138.0, "z2": 240.0},
    ]
    south_openings = [
        {"x1": -188.0, "x2": -112.0, "z1": 135.0, "z2": 245.0},
        {"x1": 112.0, "x2": 188.0, "z1": 135.0, "z2": 245.0},
    ]
    side_openings = [
        {"y1": -78.0, "y2": 8.0, "z1": 132.0, "z2": 242.0},
        {"y1": 88.0, "y2": 174.0, "z1": 132.0, "z2": 242.0},
    ]
    upper_front_openings = [
        {"x1": -56.0, "x2": 56.0, "z1": 468.0, "z2": 560.0},
    ]
    upper_side_openings = [
        {"y1": -52.0, "y2": 52.0, "z1": 470.0, "z2": 560.0},
    ]

    parts.extend(add_wall_x("North_Ground_Wall", -half_d, -half_w, half_w, GROUND_Z_MIN, GROUND_Z_MAX, north_openings, parent))
    parts.extend(add_wall_x("South_Ground_Wall", half_d, -half_w, half_w, GROUND_Z_MIN, GROUND_Z_MAX, south_openings, parent))
    parts.extend(add_wall_y("West_Ground_Wall", -half_w, -half_d, half_d, GROUND_Z_MIN, GROUND_Z_MAX, side_openings, parent))
    parts.extend(add_wall_y("East_Ground_Wall", half_w, -half_d, half_d, GROUND_Z_MIN, GROUND_Z_MAX, side_openings, parent))

    parts.extend(add_wall_x("North_Loft_Wall", -half_d, -half_w, half_w, GROUND_Z_MAX, EAVE_Z, upper_front_openings, parent))
    parts.extend(add_wall_x("South_Loft_Wall", half_d, -half_w, half_w, GROUND_Z_MAX, EAVE_Z, upper_front_openings, parent))
    parts.extend(add_wall_y("West_Loft_Wall", -half_w, -half_d, half_d, GROUND_Z_MAX, EAVE_Z, upper_side_openings, parent))
    parts.extend(add_wall_y("East_Loft_Wall", half_w, -half_d, half_d, GROUND_Z_MAX, EAVE_Z, upper_side_openings, parent))
    parts.extend([add_gable_siding(parent, -half_d - 0.5, "North_Gable_Siding"), add_gable_siding(parent, half_d + 0.5, "South_Gable_Siding")])

    for opening in north_openings:
        parts.extend(add_frame_x("North_Door" if opening["z1"] == 0.0 else f"North_Window_{len(parts)}", -half_d, opening["x1"], opening["x2"], opening["z1"], opening["z2"], parent, include_sill=opening["z1"] > 0.0))
    for opening in south_openings:
        parts.extend(add_frame_x(f"South_Window_{len(parts)}", half_d, opening["x1"], opening["x2"], opening["z1"], opening["z2"], parent, include_sill=True))
    for x, label in ((-half_w, "West"), (half_w, "East")):
        for opening in side_openings:
            parts.extend(add_frame_y(f"{label}_Window_{len(parts)}", x, opening["y1"], opening["y2"], opening["z1"], opening["z2"], parent, include_sill=True))
        for opening in upper_side_openings:
            parts.extend(add_frame_y(f"{label}_Loft_Window", x, opening["y1"], opening["y2"], opening["z1"], opening["z2"], parent, include_sill=True))
    for y, label in ((-half_d, "North"), (half_d, "South")):
        for opening in upper_front_openings:
            parts.extend(add_frame_x(f"{label}_Loft_Window", y, opening["x1"], opening["x2"], opening["z1"], opening["z2"], parent, include_sill=True))

    return parts


def add_siding_courses(parent: bpy.types.Object) -> list[bpy.types.Object]:
    # Sparse raised courses give a weathered-board read without producing a dense mesh.
    half_w = WIDTH * 0.5
    half_d = DEPTH * 0.5
    parts: list[bpy.types.Object] = []
    for z in (70.0, 125.0, 180.0, 255.0, 335.0, 445.0, 505.0, 565.0):
        parts.extend(
            [
                box(f"Siding_Course_North_{int(z)}", (0.0, -half_d - 8.0, z), (WIDTH - 26.0, 3.0, 5.0), "M_Wall_Siding", parent, 0.2),
                box(f"Siding_Course_South_{int(z)}", (0.0, half_d + 8.0, z), (WIDTH - 26.0, 3.0, 5.0), "M_Wall_Siding", parent, 0.2),
                box(f"Siding_Course_West_{int(z)}", (-half_w - 8.0, 0.0, z), (3.0, DEPTH - 26.0, 5.0), "M_Wall_Siding", parent, 0.2),
                box(f"Siding_Course_East_{int(z)}", (half_w + 8.0, 0.0, z), (3.0, DEPTH - 26.0, 5.0), "M_Wall_Siding", parent, 0.2),
            ]
        )
    return parts


def apply_modifiers(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.type != "MESH":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            except RuntimeError:
                obj.modifiers.remove(modifier)


def combine_meshes(objects: list[bpy.types.Object], root: bpy.types.Object) -> bpy.types.Object:
    mesh_objects = [obj for obj in objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError("No mesh objects were created.")

    apply_modifiers(mesh_objects)
    bpy.ops.object.select_all(action="DESELECT")
    active = mesh_objects[0]
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()

    joined = bpy.context.object
    joined.name = OUTPUT_OBJECT_NAME
    joined.data.name = f"{OUTPUT_OBJECT_NAME}_mesh"
    joined.parent = root
    joined["axis_forward"] = "-Y"
    joined["axis_up"] = "+Z"
    joined["material_contract"] = ",".join(MATERIAL_SPECS.keys())
    return joined


def build_farmhouse() -> bpy.types.Object:
    reset_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    root = create_root()
    objects: list[bpy.types.Object] = []
    objects.extend(add_foundation(root))
    objects.extend(add_wall_shell(root))
    objects.extend(add_siding_courses(root))
    objects.extend(add_structural_frame(root))
    objects.extend(add_loft(root))
    objects.extend(add_ladder(root))
    objects.append(add_gable_roof(root))
    objects.extend(add_roof_corner_railings(root))

    final_object = combine_meshes(objects, root) if COMBINE_FOR_EXPORT else root
    return final_object


def main() -> None:
    write_material_assets()
    build_farmhouse()
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"Created {OUTPUT_OBJECT_NAME} at {BLEND_PATH}")
    print("Material slots:", ", ".join(MATERIAL_SPECS.keys()))


if __name__ == "__main__":
    main()
