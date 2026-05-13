from __future__ import annotations

import math
import random
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "Assets" / "models"
MATERIALS = ROOT / "Assets" / "materials" / "environment"
BLEND_DIR = ROOT / "environment_model.blend"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


def assign_material(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0


def save_noise_texture(path: Path, base: tuple[float, float, float], variance: float, seed: int) -> None:
    rng = random.Random(seed)
    width = height = 256
    image = bpy.data.images.new(path.stem, width, height, alpha=True)
    pixels: list[float] = []

    for y in range(height):
        for x in range(width):
            grain = rng.uniform(-variance, variance)
            stripe = 0.08 * math.sin((x + seed) * 0.09) + 0.04 * math.sin((y + seed) * 0.17)
            for channel in base:
                pixels.append(max(0.0, min(1.0, channel + grain + stripe)))
            pixels.append(1.0)

    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()


def write_vmat(path: Path, texture: str, roughness: float) -> None:
    path.write_text(
        "\n".join(
            [
                '"Layer0"',
                "{",
                '\t"shader"\t\t"shaders/complex.shader"',
                f'\t"TextureColor"\t\t"{texture}"',
                '\t"g_flModelTintAmount"\t\t"1.000000"',
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


def write_vmdl(path: Path, mesh: str, remaps: list[tuple[str, str]]) -> None:
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
                "\t\t\t\t\t\tuse_global_default = true",
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


def create_pine() -> list[bpy.types.Object]:
    bark = make_material("TerrainPineBark", (0.33, 0.21, 0.12, 1.0))
    needles = make_material("TerrainPineNeedles", (0.08, 0.28, 0.15, 1.0))
    objects: list[bpy.types.Object] = []

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.28, depth=3.6, location=(0, 0, 1.8))
    trunk = bpy.context.object
    trunk.name = "TerrainPine_Trunk"
    assign_material(trunk, bark)
    objects.append(trunk)

    cone_specs = [
        (2.9, 4.8, 3.3),
        (2.3, 4.3, 5.6),
        (1.7, 3.7, 7.8),
        (1.05, 2.6, 9.7),
    ]
    for index, (radius, depth, z) in enumerate(cone_specs):
        bpy.ops.mesh.primitive_cone_add(vertices=18, radius1=radius, radius2=0.22, depth=depth, location=(0, 0, z))
        cone = bpy.context.object
        cone.name = f"TerrainPine_Needles_{index + 1}"
        assign_material(cone, needles)
        for poly in cone.data.polygons:
            poly.use_smooth = False
        objects.append(cone)

    return objects


def create_rock() -> list[bpy.types.Object]:
    rock_mat = make_material("TerrainRock", (0.38, 0.36, 0.32, 1.0))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.8, location=(0, 0, 0.62))
    rock = bpy.context.object
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

    save_noise_texture(MATERIALS / "terrain_pine_needles_color.png", (0.07, 0.26, 0.13), 0.07, 11)
    save_noise_texture(MATERIALS / "terrain_pine_bark_color.png", (0.30, 0.19, 0.11), 0.08, 23)
    save_noise_texture(MATERIALS / "terrain_rock_color.png", (0.38, 0.36, 0.32), 0.09, 37)

    write_vmat(
        MATERIALS / "terrain_pine_needles.vmat",
        "materials/environment/terrain_pine_needles_color.png",
        0.88,
    )
    write_vmat(
        MATERIALS / "terrain_pine_bark.vmat",
        "materials/environment/terrain_pine_bark_color.png",
        0.82,
    )
    write_vmat(
        MATERIALS / "terrain_rock.vmat",
        "materials/environment/terrain_rock_color.png",
        0.93,
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
            ("TerrainPineNeedles", "materials/environment/terrain_pine_needles.vmat"),
        ],
    )
    write_vmdl(
        MODELS / "terrain_rock.vmdl",
        "models/terrain_rock.fbx",
        [("TerrainRock", "materials/environment/terrain_rock.vmat")],
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_DIR / "terrain_assets.blend"))


if __name__ == "__main__":
    main()
