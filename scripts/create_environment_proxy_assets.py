from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "Assets" / "models"
MATERIALS = ROOT / "Assets" / "materials" / "environment"
BLEND_DIR = ROOT / "environment_model.blend"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    texture: Path | None = None,
    alpha_blend: bool = False,
    alpha_mask: Path | None = None,
) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = False
    if texture:
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        output = nodes.new(type="ShaderNodeOutputMaterial")
        principled = nodes.new(type="ShaderNodeBsdfPrincipled")
        texcoord = nodes.new(type="ShaderNodeTexCoord")
        tex = nodes.new(type="ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(texture), check_existing=True)
        mat.node_tree.links.new(texcoord.outputs["UV"], tex.inputs["Vector"])
        mat.node_tree.links.new(tex.outputs["Color"], principled.inputs["Base Color"])
        if alpha_blend:
            alpha_tex = tex
            if alpha_mask:
                alpha_tex = nodes.new(type="ShaderNodeTexImage")
                alpha_tex.image = bpy.data.images.load(str(alpha_mask), check_existing=True)
                alpha_tex.image.colorspace_settings.name = "Non-Color"
                mat.node_tree.links.new(texcoord.outputs["UV"], alpha_tex.inputs["Vector"])
            mat.node_tree.links.new(alpha_tex.outputs["Alpha"], principled.inputs["Alpha"])
            mat.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
        else:
            mat.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    if alpha_blend:
        mat.blend_method = "CLIP"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
        if hasattr(mat, "alpha_threshold"):
            mat.alpha_threshold = 0.30
        mat.show_transparent_back = True
    return mat


def assign_material(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0


def save_rgba_texture(path: Path, width: int, height: int, pixels: list[float]) -> None:
    image = bpy.data.images.new(path.stem, width, height, alpha=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()


def save_noise_texture(path: Path, base: tuple[float, float, float], variance: float, seed: int) -> None:
    rng = random.Random(seed)
    width = height = 256
    pixels: list[float] = []

    for y in range(height):
        for x in range(width):
            grain = rng.uniform(-variance, variance)
            stripe = 0.08 * math.sin((x + seed) * 0.09) + 0.04 * math.sin((y + seed) * 0.17)
            for channel in base:
                pixels.append(max(0.0, min(1.0, channel + grain + stripe)))
            pixels.append(1.0)

    save_rgba_texture(path, width, height, pixels)


def save_bark_texture(path: Path, seed: int) -> None:
    rng = random.Random(seed)
    width = height = 512
    crack_centers = [rng.uniform(0.0, width) for _ in range(34)]
    pixels: list[float] = []

    for y in range(height):
        for x in range(width):
            vertical_tone = 0.08 * math.sin((x + seed) * 0.055)
            fine_grain = 0.035 * math.sin((x * 0.42) + math.sin(y * 0.06) * 2.0)
            rough = rng.uniform(-0.035, 0.035)
            crack = 0.0
            for center in crack_centers:
                waviness = math.sin((y + center) * 0.035) * 7.0
                distance = abs(x - (center + waviness))
                if distance < 2.5:
                    crack += (2.5 - distance) * 0.08

            highlight = 0.05 if ((x / width) + math.sin(y * 0.025) * 0.05) % 0.22 < 0.035 else 0.0
            r = 0.34 + vertical_tone + fine_grain + rough + highlight - crack
            g = 0.22 + vertical_tone * 0.45 + fine_grain * 0.55 + rough * 0.7 - crack * 0.75
            b = 0.12 + fine_grain * 0.30 + rough * 0.35 - crack * 0.45
            pixels.extend([max(0.03, min(0.62, r)), max(0.025, min(0.42, g)), max(0.02, min(0.24, b)), 1.0])

    save_rgba_texture(path, width, height, pixels)


def blend_pixel(
    pixels: list[float],
    width: int,
    height: int,
    x: int,
    y: int,
    color: tuple[float, float, float, float],
) -> None:
    if x < 0 or x >= width or y < 0 or y >= height:
        return
    index = ((height - 1 - y) * width + x) * 4
    source_alpha = color[3]
    target_alpha = pixels[index + 3]
    out_alpha = source_alpha + target_alpha * (1.0 - source_alpha)
    if out_alpha <= 0.0:
        return
    for channel in range(3):
        pixels[index + channel] = (
            color[channel] * source_alpha + pixels[index + channel] * target_alpha * (1.0 - source_alpha)
        ) / out_alpha
    pixels[index + 3] = out_alpha


def paint_line(
    pixels: list[float],
    width: int,
    height: int,
    start: tuple[float, float],
    end: tuple[float, float],
    radius: float,
    color: tuple[float, float, float, float],
) -> None:
    x1, y1 = start
    x2, y2 = end
    steps = max(1, int(math.hypot(x2 - x1, y2 - y1) * 1.4))
    radius_i = max(1, math.ceil(radius))
    for step in range(steps + 1):
        t = step / steps
        x = x1 + (x2 - x1) * t
        y = y1 + (y2 - y1) * t
        for yy in range(int(y) - radius_i, int(y) + radius_i + 1):
            for xx in range(int(x) - radius_i, int(x) + radius_i + 1):
                distance = math.hypot(xx - x, yy - y)
                if distance <= radius:
                    alpha = color[3] * max(0.0, 1.0 - distance / max(radius, 0.001))
                    blend_pixel(pixels, width, height, xx, yy, (color[0], color[1], color[2], alpha))


def paint_ellipse(
    pixels: list[float],
    width: int,
    height: int,
    center: tuple[float, float],
    radius_x: float,
    radius_y: float,
    color: tuple[float, float, float, float],
) -> None:
    cx, cy = center
    min_x = int(max(0, cx - radius_x))
    max_x = int(min(width - 1, cx + radius_x))
    min_y = int(max(0, cy - radius_y))
    max_y = int(min(height - 1, cy + radius_y))
    for yy in range(min_y, max_y + 1):
        for xx in range(min_x, max_x + 1):
            dx = (xx - cx) / max(radius_x, 0.001)
            dy = (yy - cy) / max(radius_y, 0.001)
            distance = math.sqrt(dx * dx + dy * dy)
            if distance <= 1.0:
                alpha = color[3] * (1.0 - distance) ** 0.75
                blend_pixel(pixels, width, height, xx, yy, (color[0], color[1], color[2], alpha))


def save_pine_card_textures(color_path: Path, trans_path: Path, seed: int, sweep: float) -> None:
    rng = random.Random(seed)
    width = 512
    height = 256
    pixels = [0.0] * (width * height * 4)

    branch_color = (0.22, 0.13, 0.065, 0.96)
    twig_color = (0.13, 0.08, 0.04, 0.86)
    shadow_green = (0.025, 0.105, 0.055, 0.52)
    needle_colors = [
        (0.035, 0.16, 0.08, 0.82),
        (0.055, 0.23, 0.11, 0.86),
        (0.09, 0.32, 0.145, 0.82),
        (0.16, 0.43, 0.20, 0.68),
    ]

    base_y = height * (0.47 + rng.uniform(-0.04, 0.04))
    main_points: list[tuple[float, float]] = []
    for i in range(11):
        t = i / 10.0
        x = width * (0.06 + t * 0.88)
        y = base_y + math.sin(t * math.pi * 1.1 + sweep) * 15.0 + (t - 0.5) * 18.0 * sweep
        main_points.append((x, y))

    foliage_centers: list[tuple[float, float, float, float]] = []
    for i in range(2, 10):
        anchor = main_points[i]
        t = i / 10.0
        rx = rng.uniform(48.0, 76.0) * (1.05 - abs(t - 0.56) * 0.35)
        ry = rng.uniform(24.0, 42.0)
        offset = rng.uniform(-18.0, 18.0)
        center = (anchor[0] + rng.uniform(-10.0, 18.0), anchor[1] + offset)
        foliage_centers.append((center[0], center[1], rx, ry))
        paint_ellipse(pixels, width, height, center, rx, ry, shadow_green)

    for start, end in zip(main_points, main_points[1:]):
        paint_line(pixels, width, height, start, end, 5.2, branch_color)

    for i in range(1, len(main_points) - 1):
        x, y = main_points[i]
        for side in (-1, 1):
            twig_len = rng.uniform(36.0, 82.0)
            twig_angle = rng.uniform(0.34, 0.92) * side
            end = (x + math.cos(twig_angle) * twig_len, y + math.sin(twig_angle) * twig_len * 0.6)
            paint_line(pixels, width, height, (x, y), end, rng.uniform(1.5, 2.7), twig_color)

    for _ in range(560):
        cx, cy, rx, ry = rng.choice(foliage_centers)
        angle = rng.uniform(0.0, math.tau)
        radius = math.sqrt(rng.random())
        start = (
            cx + math.cos(angle) * rx * radius,
            cy + math.sin(angle) * ry * radius,
        )
        lean = rng.uniform(-0.42, 0.42) + sweep * 0.20
        length = rng.uniform(18.0, 42.0)
        end = (
            start[0] + math.cos(lean) * length,
            start[1] + math.sin(lean) * length * 0.38 + rng.uniform(-4.0, 4.0),
        )
        paint_line(pixels, width, height, start, end, rng.uniform(0.75, 1.65), rng.choice(needle_colors))

    save_rgba_texture(color_path, width, height, pixels)

    trans_pixels: list[float] = []
    for index in range(0, len(pixels), 4):
        alpha = 1.0 if pixels[index + 3] > 0.08 else 0.0
        trans_pixels.extend([alpha, alpha, alpha, alpha])
    save_rgba_texture(trans_path, width, height, trans_pixels)


def write_vmat(
    path: Path,
    texture: str,
    roughness: float,
    translucency: str | None = None,
    alpha_test: bool = False,
    model_tint_amount: float = 0.0,
) -> None:
    extra_lines: list[str] = []
    if alpha_test:
        extra_lines.extend(
            [
                '\t"F_ALPHA_TEST"\t\t"1"',
                '\t"g_flAlphaTestReference"\t\t"0.380000"',
            ]
        )
    if translucency:
        extra_lines.append(f'\t"TextureTranslucency"\t\t"{translucency}"')

    path.write_text(
        "\n".join(
            [
                '"Layer0"',
                "{",
                '\t"shader"\t\t"shaders/complex.shader"',
                f'\t"TextureColor"\t\t"{texture}"',
                *extra_lines,
                f'\t"g_flModelTintAmount"\t\t"{model_tint_amount:.6f}"',
                '\t"g_vColorTint"\t\t"[1.000000 1.000000 1.000000 0.000000]"',
                '\t"g_flMetalness"\t\t"0.000000"',
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


def write_vmdl(path: Path, mesh: str, remaps: list[tuple[str, str]], use_global_default: bool = True) -> None:
    remap_lines: list[str] = []
    for source, target in remaps:
        remap_lines.extend(
            [
                "",
                "\t\t\t\t\t\t\t{",
                f'\t\t\t\t\t\t\t\tfrom = "{source}"',
                f'\t\t\t\t\t\t\t\tto = "{target}"',
                "\t\t\t\t\t\t\t},",
            ]
        )

    path.write_text(
        "\n".join(
            [
                "<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc29:version{3cec427c-1b0e-4d48-a90a-0436f33a6041} -->",
                "{",
                "\trootNode = ",
                "\t{",
                '\t\t_class = "RootNode"',
                "\t\tchildren = ",
                "\t\t[",
                "\t\t\t{",
                '\t\t\t\t_class = "MaterialGroupList"',
                "\t\t\t\tchildren = ",
                "\t\t\t\t[",
                "\t\t\t\t\t{",
                '\t\t\t\t\t\t_class = "DefaultMaterialGroup"',
                "\t\t\t\t\t\tremaps = ",
                "\t\t\t\t\t\t[",
                *remap_lines,
                "\t\t\t\t\t\t]",
                f"\t\t\t\t\t\tuse_global_default = {str(use_global_default).lower()}",
                '\t\t\t\t\t\tglobal_default_material = "materials/default.vmat"',
                "\t\t\t\t\t},",
                "\t\t\t\t]",
                "\t\t\t},",
                "\t\t\t{",
                '\t\t\t\t_class = "RenderMeshList"',
                "\t\t\t\tchildren = ",
                "\t\t\t\t[",
                "\t\t\t\t\t{",
                '\t\t\t\t\t\t_class = "RenderMeshFile"',
                '\t\t\t\t\t\tname = "LOD0"',
                f'\t\t\t\t\t\tfilename = "{mesh}"',
                "\t\t\t\t\t\timport_translation = [ 0.0, 0.0, 0.0 ]",
                "\t\t\t\t\t\timport_rotation = [ 0.0, 0.0, 0.0 ]",
                "\t\t\t\t\t\timport_scale = 1.0",
                '\t\t\t\t\t\talign_origin_x_type = "None"',
                '\t\t\t\t\t\talign_origin_y_type = "None"',
                '\t\t\t\t\t\talign_origin_z_type = "None"',
                '\t\t\t\t\t\tparent_bone = ""',
                "\t\t\t\t\t\timport_filter = ",
                "\t\t\t\t\t\t{",
                "\t\t\t\t\t\t\texclude_by_default = false",
                "\t\t\t\t\t\t\texception_list = [  ]",
                "\t\t\t\t\t\t}",
                "\t\t\t\t\t},",
                "\t\t\t\t]",
                "\t\t\t},",
                "\t\t]",
                '\t\tmodel_archetype = ""',
                '\t\tprimary_associated_entity = ""',
                '\t\tanim_graph_name = ""',
                "\t}",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def export_selected(path: Path) -> None:
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        apply_scale_options="FBX_SCALE_NONE",
        path_mode="AUTO",
        add_leaf_bones=False,
    )


def apply_mesh_transform(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def parent_object(obj: bpy.types.Object, parent: bpy.types.Object) -> bpy.types.Object:
    obj.parent = parent
    return obj


def active_object() -> bpy.types.Object:
    obj = bpy.context.view_layer.objects.active
    if obj is None:
        raise RuntimeError("Expected Blender to create an active object")
    return obj


def join_mesh_objects(name: str, root: bpy.types.Object, objects: list[bpy.types.Object]) -> bpy.types.Object:
    mesh_objects = [obj for obj in objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError(f"{name} needs at least one mesh object to join")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    bpy.ops.object.join()
    joined = active_object()
    joined.name = name
    joined.data.name = f"{name}_mesh"
    joined.parent = root
    for poly in joined.data.polygons:
        poly.use_smooth = False
    return joined


def create_tapered_cylinder(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius_start: float,
    radius_end: float,
    vertices: int,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    start_vec = Vector(start)
    end_vec = Vector(end)
    direction = end_vec - start_vec
    length = direction.length
    if length <= 0.001:
        raise ValueError(f"{name} needs distinct start and end points")

    midpoint = start_vec + direction * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_start,
        radius2=radius_end,
        depth=length,
        location=midpoint,
    )
    obj = active_object()
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    assign_material(obj, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    apply_mesh_transform(obj)
    return parent_object(obj, parent)


def create_needle_clump(
    name: str,
    center: tuple[float, float, float],
    yaw_degrees: float,
    length: float,
    width: float,
    thickness: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1.0, location=center)
    clump = active_object()
    clump.name = name
    clump.scale = (length, width, thickness)
    clump.rotation_euler = (math.radians(3.0), math.radians(-5.0), math.radians(yaw_degrees))
    assign_material(clump, mat)
    for poly in clump.data.polygons:
        poly.use_smooth = False
    apply_mesh_transform(clump)
    return parent_object(clump, parent)


def create_foliage_card(
    name: str,
    center: Vector,
    yaw_degrees: float,
    length: float,
    height: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    yaw = math.radians(yaw_degrees)
    x_axis = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    z_axis = Vector((0.0, 0.0, 1.0))
    half_x = x_axis * (length * 0.5)
    half_z = z_axis * (height * 0.5)
    verts = [
        center - half_x - half_z,
        center + half_x - half_z,
        center + half_x + half_z,
        center - half_x + half_z,
        center + half_x - half_z,
        center - half_x - half_z,
        center - half_x + half_z,
        center + half_x + half_z,
    ]
    faces = [(0, 1, 2, 3), (4, 5, 6, 7)]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata([tuple(vertex) for vertex in verts], [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    uvs = [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
        (1.0, 0.0),
        (0.0, 0.0),
        (0.0, 1.0),
        (1.0, 1.0),
    ]
    for loop, uv in zip(uv_layer.data, uvs):
        loop.uv = uv

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_material(obj, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return parent_object(obj, parent)


def create_pine() -> list[bpy.types.Object]:
    bark = make_material("TerrainPineBark", (0.36, 0.23, 0.12, 1.0), MATERIALS / "terrain_pine_bark_color.png")
    card_a = make_material(
        "TerrainPineNeedlesCardA",
        (0.08, 0.30, 0.15, 1.0),
        MATERIALS / "terrain_pine_needles_card_a_color.png",
        alpha_blend=True,
        alpha_mask=MATERIALS / "terrain_pine_needles_card_a_trans.png",
    )
    card_b = make_material(
        "TerrainPineNeedlesCardB",
        (0.10, 0.34, 0.16, 1.0),
        MATERIALS / "terrain_pine_needles_card_b_color.png",
        alpha_blend=True,
        alpha_mask=MATERIALS / "terrain_pine_needles_card_b_trans.png",
    )
    objects: list[bpy.types.Object] = []

    root = bpy.data.objects.new("TerrainPine_Root", None)
    bpy.context.scene.collection.objects.link(root)
    objects.append(root)

    bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.22, radius2=0.08, depth=15.2, location=(0, 0, 7.6))
    trunk = active_object()
    trunk.name = "TerrainPine_Trunk"
    assign_material(trunk, bark)
    for poly in trunk.data.polygons:
        poly.use_smooth = False
    parent_object(trunk, root)
    objects.append(trunk)

    dead_stub_specs = [
        (4.2, 25, 0.55),
        (5.5, 205, 0.72),
        (6.8, 325, 0.62),
        (8.0, 145, 0.82),
    ]
    for index, (z, angle_degrees, length) in enumerate(dead_stub_specs, start=1):
        angle = math.radians(angle_degrees)
        start = (math.cos(angle) * 0.10, math.sin(angle) * 0.10, z)
        end = (math.cos(angle) * length, math.sin(angle) * length, z + 0.08)
        objects.append(
            create_tapered_cylinder(
                f"TerrainPine_DeadStub_{index}",
                start,
                end,
                0.045,
                0.015,
                7,
                bark,
                root,
            )
        )

    whorl_specs = [
        (10.05, 2.95, [8, 118, 238, 310], 0.060),
        (10.65, 2.65, [55, 175, 292], 0.052),
        (11.65, 2.25, [18, 138, 258], 0.046),
        (12.65, 1.75, [82, 202, 326], 0.040),
        (13.60, 1.28, [30, 158, 278], 0.034),
        (14.42, 0.78, [102, 242], 0.028),
    ]

    branch_index = 1
    clump_index = 1
    rng = random.Random(19)
    for z, length, angles, base_radius in whorl_specs:
        for angle_degrees in angles:
            angle = math.radians(angle_degrees + rng.uniform(-7.0, 7.0))
            direction = Vector((math.cos(angle), math.sin(angle), 0.0))
            perpendicular = Vector((-direction.y, direction.x, 0.0))
            start_vec = Vector((direction.x * 0.12, direction.y * 0.12, z))
            end_vec = Vector((direction.x * length, direction.y * length, z + rng.uniform(0.12, 0.34)))

            objects.append(
                create_tapered_cylinder(
                    f"TerrainPine_Branch_{branch_index}",
                    tuple(start_vec),
                    tuple(end_vec),
                    base_radius,
                    max(0.012, base_radius * 0.35),
                    7,
                    bark,
                    root,
                )
            )

            twig_count = 2 if length > 1.1 else 1
            for twig in range(twig_count):
                twig_offset = 0.58 + twig * 0.18
                twig_start = start_vec.lerp(end_vec, twig_offset)
                side = -1.0 if twig % 2 == 0 else 1.0
                twig_end = twig_start + direction * (0.38 + rng.uniform(-0.06, 0.05))
                twig_end += perpendicular * side * (0.22 + rng.uniform(-0.04, 0.06))
                twig_end.z += 0.08 + rng.uniform(-0.04, 0.06)
                objects.append(
                    create_tapered_cylinder(
                        f"TerrainPine_Twig_{branch_index}_{twig + 1}",
                        tuple(twig_start),
                        tuple(twig_end),
                        max(0.014, base_radius * 0.35),
                        0.008,
                        6,
                        bark,
                        root,
                    )
                )

            card_length = max(0.90, length * 0.58)
            card_height = max(0.34, length * 0.22)
            for pad in range(2 if length > 1.4 else 1):
                along = 0.70 + pad * 0.15
                side = (pad - 0.5) * 0.22
                center_vec = start_vec.lerp(end_vec, min(0.96, along))
                center_vec += perpendicular * side
                center_vec.z += rng.uniform(0.04, 0.18)
                material = card_a if (branch_index + pad) % 2 == 0 else card_b
                objects.append(
                    create_foliage_card(
                        f"TerrainPine_NeedlesCard_{clump_index}",
                        center_vec,
                        math.degrees(angle) + rng.uniform(-10.0, 10.0),
                        card_length * rng.uniform(0.86, 1.14),
                        card_height * rng.uniform(0.85, 1.18),
                        material,
                        root,
                    )
                )
                clump_index += 1
                if length > 1.7:
                    objects.append(
                        create_foliage_card(
                            f"TerrainPine_NeedlesCard_{clump_index}",
                            center_vec + Vector((0.0, 0.0, rng.uniform(-0.04, 0.05))),
                            math.degrees(angle) + 62.0 + rng.uniform(-8.0, 8.0),
                            card_length * rng.uniform(0.65, 0.88),
                            card_height * rng.uniform(0.75, 1.05),
                            card_b if material == card_a else card_a,
                            root,
                        )
                    )
                    clump_index += 1

            branch_index += 1

    joined = join_mesh_objects("TerrainPine_SourceMesh", root, objects)
    return [root, joined]


def create_rock() -> list[bpy.types.Object]:
    rock_mat = make_material("TerrainRock", (0.38, 0.36, 0.32, 1.0))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.8, location=(0, 0, 0.62))
    rock = active_object()
    rock.name = "TerrainBoulder"

    rng = random.Random(42)
    for vertex in rock.data.vertices:
        world = vertex.co
        horizontal = math.sqrt(world.x * world.x + world.y * world.y)
        bulge = 0.78 + rng.uniform(-0.18, 0.2)
        if world.z > 0:
            bulge += 0.08
        world.x *= bulge * (1.12 if horizontal > 35 else 0.96)
        world.y *= (0.72 + rng.uniform(-0.08, 0.16))
        world.z *= 0.58 + rng.uniform(-0.08, 0.08)

    min_z = min(vertex.co.z for vertex in rock.data.vertices)
    for vertex in rock.data.vertices:
        vertex.co.z -= min_z
    rock.location = (0, 0, 0)

    assign_material(rock, rock_mat)
    for poly in rock.data.polygons:
        poly.use_smooth = False

    return [rock]


def main() -> None:
    MODELS.mkdir(parents=True, exist_ok=True)
    MATERIALS.mkdir(parents=True, exist_ok=True)
    BLEND_DIR.mkdir(parents=True, exist_ok=True)

    save_bark_texture(MATERIALS / "terrain_pine_bark_color.png", 23)
    save_pine_card_textures(
        MATERIALS / "terrain_pine_needles_card_a_color.png",
        MATERIALS / "terrain_pine_needles_card_a_trans.png",
        31,
        -0.4,
    )
    save_pine_card_textures(
        MATERIALS / "terrain_pine_needles_card_b_color.png",
        MATERIALS / "terrain_pine_needles_card_b_trans.png",
        47,
        0.5,
    )
    save_noise_texture(MATERIALS / "terrain_rock_color.png", (0.38, 0.36, 0.32), 0.09, 37)

    write_vmat(
        MATERIALS / "terrain_pine_bark.vmat",
        "materials/environment/terrain_pine_bark_color.png",
        0.82,
    )
    write_vmat(
        MATERIALS / "terrain_pine_needles_card_a.vmat",
        "materials/environment/terrain_pine_needles_card_a_color.png",
        0.86,
        "materials/environment/terrain_pine_needles_card_a_trans.png",
        alpha_test=True,
    )
    write_vmat(
        MATERIALS / "terrain_pine_needles_card_b.vmat",
        "materials/environment/terrain_pine_needles_card_b_color.png",
        0.88,
        "materials/environment/terrain_pine_needles_card_b_trans.png",
        alpha_test=True,
    )
    write_vmat(
        MATERIALS / "terrain_rock.vmat",
        "materials/environment/terrain_rock_color.png",
        0.93,
        model_tint_amount=1.0,
    )

    reset_scene()
    pine_objects = create_pine()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pine_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pine_objects[0]
    export_selected(MODELS / "terrain_pine.fbx")

    bpy.ops.object.select_all(action="DESELECT")
    rock_objects = create_rock()
    for obj in rock_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rock_objects[0]
    export_selected(MODELS / "terrain_rock.fbx")

    write_vmdl(
        MODELS / "terrain_pine.vmdl",
        "models/terrain_pine.fbx",
        [
            ("TerrainPineBark", "materials/environment/terrain_pine_bark.vmat"),
            ("TerrainPineNeedlesCardA", "materials/environment/terrain_pine_needles_card_a.vmat"),
            ("TerrainPineNeedlesCardB", "materials/environment/terrain_pine_needles_card_b.vmat"),
        ],
    )
    write_vmdl(
        MODELS / "terrain_rock.vmdl",
        "models/terrain_rock.fbx",
        [("TerrainRock", "materials/environment/terrain_rock.vmat")],
        use_global_default=False,
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_DIR / "terrain_assets.blend"))


if __name__ == "__main__":
    main()
