#!/usr/bin/env python3
"""
Build the burnt_car_wreck environment asset source and S&Box asset files.

This script writes image-backed materials and a Blender source scene, then the
normal asset pipeline exports FBX/VMDL from that source.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import subprocess
import textwrap
import uuid
from pathlib import Path

from PIL import Image, ImageDraw


ASSET = "burnt_car_wreck"
ROOT = Path(__file__).resolve().parents[1]
BLENDER_SOURCE = ROOT / "environment_model.blend" / f"{ASSET}.blend"
MATERIAL_DIR = ROOT / "Assets" / "materials" / "environment"
MODEL_DIR = ROOT / "Assets" / "models"
PREFAB_PATH = ROOT / "Assets" / "prefabs" / "environment" / f"{ASSET}.prefab"
CONFIG_PATH = ROOT / "scripts" / f"{ASSET}_asset_pipeline.json"
BRIEF_PATH = ROOT / "docs" / "assets" / "briefs" / f"{ASSET}.md"
BUILD_SCRIPT_PATH = ROOT / ".tmpbuild" / f"build_{ASSET}_blender.py"

GUID_NAMESPACE = uuid.UUID("ad56f01a-6ce2-43e8-8888-8b65e920ec17")
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"

MATERIALS = {
    "BurntCar_CharredPaint": {
        "stem": "burnt_car_charred_paint",
        "base": [(18, 17, 15), (35, 32, 29), (91, 37, 28), (113, 63, 33)],
        "metalness": 0.35,
        "roughness": 0.94,
    },
    "BurntCar_BlisteredMetal": {
        "stem": "burnt_car_blistered_metal",
        "base": [(42, 43, 42), (67, 64, 58), (95, 84, 69), (26, 25, 24)],
        "metalness": 0.75,
        "roughness": 0.82,
    },
    "BurntCar_Rust": {
        "stem": "burnt_car_rust",
        "base": [(91, 43, 19), (139, 71, 26), (169, 93, 35), (49, 31, 21)],
        "metalness": 0.15,
        "roughness": 0.9,
    },
    "BurntCar_SootInterior": {
        "stem": "burnt_car_soot_interior",
        "base": [(8, 8, 8), (24, 23, 22), (46, 44, 41), (70, 65, 59)],
        "metalness": 0.05,
        "roughness": 0.98,
    },
    "BurntCar_Rubber": {
        "stem": "burnt_car_rubber",
        "base": [(4, 4, 4), (17, 16, 15), (37, 35, 32), (59, 57, 53)],
        "metalness": 0.0,
        "roughness": 0.96,
    },
    "BurntCar_Glass": {
        "stem": "burnt_car_broken_glass",
        "base": [(13, 21, 24), (28, 43, 48), (49, 68, 72), (94, 117, 118)],
        "metalness": 0.0,
        "roughness": 0.38,
    },
    "BurntCar_Ash": {
        "stem": "burnt_car_ash",
        "base": [(45, 44, 42), (73, 70, 65), (99, 96, 89), (27, 26, 25)],
        "metalness": 0.0,
        "roughness": 1.0,
    },
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def asset_resource(path: Path) -> str:
    return path.relative_to(ROOT / "Assets").as_posix()


def stable_guid(name: str, suffix: str) -> str:
    return str(uuid.uuid5(GUID_NAMESPACE, f"{name}:{suffix}"))


def ensure_dirs() -> None:
    for path in [
        BLENDER_SOURCE.parent,
        MATERIAL_DIR,
        MODEL_DIR,
        PREFAB_PATH.parent,
        CONFIG_PATH.parent,
        BRIEF_PATH.parent,
        BUILD_SCRIPT_PATH.parent,
    ]:
        path.mkdir(parents=True, exist_ok=True)


def noisy_color(rng: random.Random, palette: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    base = rng.choice(palette)
    return tuple(max(0, min(255, channel + rng.randint(-18, 18))) for channel in base)


def write_texture_set(stem: str, palette: list[tuple[int, int, int]], roughness: float) -> None:
    rng = random.Random(stem)
    size = 256

    color = Image.new("RGB", (size, size))
    pixels = color.load()
    for y in range(size):
        for x in range(size):
            stripe = (x * 3 + y * 5 + rng.randint(0, 40)) % 97
            local_palette = palette
            if stripe < 6:
                local_palette = palette[-2:] + palette[:1]
            pixels[x, y] = noisy_color(rng, local_palette)

    draw = ImageDraw.Draw(color)
    for _ in range(70):
        x0 = rng.randint(-30, size)
        y0 = rng.randint(-30, size)
        length = rng.randint(18, 100)
        angle = rng.uniform(-0.9, 0.9)
        x1 = x0 + int(math.cos(angle) * length)
        y1 = y0 + int(math.sin(angle) * length)
        shade = noisy_color(rng, palette)
        draw.line((x0, y0, x1, y1), fill=shade, width=rng.randint(1, 4))
    for _ in range(40):
        x = rng.randint(0, size)
        y = rng.randint(0, size)
        radius = rng.randint(2, 13)
        shade = noisy_color(rng, palette)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=shade)

    normal = Image.new("RGB", (size, size), (128, 128, 255))
    normal_pixels = normal.load()
    for y in range(size):
        for x in range(size):
            n = rng.randint(-5, 5)
            normal_pixels[x, y] = (128 + n, 128 - n, 255)

    rough = Image.new("RGB", (size, size))
    rough_pixels = rough.load()
    base_rough = int(max(0, min(255, roughness * 255)))
    for y in range(size):
        for x in range(size):
            value = max(0, min(255, base_rough + rng.randint(-20, 20)))
            rough_pixels[x, y] = (value, value, value)

    ao = Image.new("RGB", (size, size))
    ao_pixels = ao.load()
    for y in range(size):
        for x in range(size):
            value = max(0, min(255, 220 + rng.randint(-35, 20)))
            ao_pixels[x, y] = (value, value, value)

    color.save(MATERIAL_DIR / f"{stem}_color.png")
    normal.save(MATERIAL_DIR / f"{stem}_normal.png")
    rough.save(MATERIAL_DIR / f"{stem}_rough.png")
    ao.save(MATERIAL_DIR / f"{stem}_ao.png")


def write_vmat(stem: str, metalness: float, roughness: float) -> None:
    text = f'''"Layer0"
{{
\t"shader"\t\t"shaders/complex.shader"
\t"TextureColor"\t\t"materials/environment/{stem}_color.png"
\t"TextureNormal"\t\t"materials/environment/{stem}_normal.png"
\t"TextureRoughness"\t\t"materials/environment/{stem}_rough.png"
\t"TextureAmbientOcclusion"\t\t"materials/environment/{stem}_ao.png"
\t"g_flModelTintAmount"\t\t"1.000000"
\t"g_vColorTint"\t\t"[1.000000 1.000000 1.000000 0.000000]"
\t"g_flMetalness"\t\t"{metalness:.6f}"
\t"g_flRoughness"\t\t"{roughness:.6f}"
\t"g_flAmbientOcclusionDirectDiffuse"\t\t"0.300000"
\t"g_flAmbientOcclusionDirectSpecular"\t\t"0.250000"
\t"g_bFogEnabled"\t\t"1"
\t"g_vTexCoordScale"\t\t"[1.000 1.000]"
\t"g_vTexCoordOffset"\t\t"[0.000 0.000]"
\t"g_vTexCoordScrollSpeed"\t\t"[0.000 0.000]"
}}
'''
    (MATERIAL_DIR / f"{stem}.vmat").write_text(text, encoding="utf-8")


def write_material_files() -> None:
    for material in MATERIALS.values():
        write_texture_set(material["stem"], material["base"], float(material["roughness"]))
        write_vmat(material["stem"], float(material["metalness"]), float(material["roughness"]))


def renderer_component() -> dict:
    return {
        "__type": "Sandbox.ModelRenderer",
        "__guid": stable_guid("BurntCarWreck", "renderer"),
        "__enabled": True,
        "Flags": 0,
        "BodyGroups": 18446744073709551615,
        "CreateAttachments": False,
        "LodOverride": None,
        "MaterialGroup": None,
        "MaterialOverride": None,
        "Materials": None,
        "Model": "models/burnt_car_wreck.vmdl",
        "OnComponentDestroy": None,
        "OnComponentDisabled": None,
        "OnComponentEnabled": None,
        "OnComponentFixedUpdate": None,
        "OnComponentStart": None,
        "OnComponentUpdate": None,
        "RenderOptions": {
            "GameLayer": True,
            "OverlayLayer": False,
            "BloomLayer": False,
            "AfterUILayer": False,
        },
        "RenderType": "On",
        "Tint": "1,1,1,1",
    }


def model_collider_component() -> dict:
    return {
        "__type": "Sandbox.ModelCollider",
        "__guid": stable_guid("BurntCarWreck", "model_collider"),
        "__enabled": True,
        "Flags": 0,
        "IsTrigger": False,
        "Model": "models/burnt_car_wreck.vmdl",
        "Static": True,
        "Surface": None,
        "SurfaceVelocity": "0,0,0",
    }


def write_prefab() -> None:
    prefab = {
        "RootObject": {
            "__guid": stable_guid("BurntCarWreck", "root"),
            "Flags": 0,
            "Name": "BurntCarWreck",
            "Enabled": True,
            "NetworkMode": 2,
            "Components": [],
            "Children": [
                {
                    "__guid": stable_guid("BurntCarWreck_Visual", "object"),
                    "Flags": 0,
                    "Name": "Visual",
                    "Position": "0,0,0",
                    "Rotation": "0,0,0,1",
                    "Scale": "1,1,1",
                    "Enabled": True,
                    "Components": [renderer_component(), model_collider_component()],
                    "Children": [],
                }
            ],
            "__variables": [],
            "__properties": {
                "FixedUpdateFrequency": 50,
                "MaxFixedUpdates": 5,
                "NetworkFrequency": 30,
                "NetworkInterpolation": True,
                "PhysicsSubSteps": 1,
                "ThreadedAnimation": True,
                "TimeScale": 1,
                "UseFixedUpdate": True,
                "Metadata": {},
            },
        },
        "ShowInMenu": False,
        "MenuPath": "Drone vs Players/Environment/Burnt Car Wreck",
        "MenuIcon": "directions_car",
        "DontBreakAsTemplate": False,
        "ResourceVersion": 1,
        "__references": [],
        "__version": 1,
    }
    PREFAB_PATH.write_text(json.dumps(prefab, indent=2) + "\n", encoding="utf-8")


def write_config() -> None:
    remap = {
        material_name: f"materials/environment/{data['stem']}.vmat"
        for material_name, data in MATERIALS.items()
    }
    config = {
        "source_blend": "environment_model.blend/burnt_car_wreck.blend",
        "root_object": "BurntCarRoot",
        "target_fbx": "Assets/models/burnt_car_wreck.fbx",
        "target_vmdl": "Assets/models/burnt_car_wreck.vmdl",
        "model_resource_path": "models/burnt_car_wreck.vmdl",
        "prefab": "Assets/prefabs/environment/burnt_car_wreck.prefab",
        "visual_object": "Visual",
        "visual_scale": "1,1,1",
        "visual_tint": "1,1,1,1",
        "clear_material_override": True,
        "clear_visual_children": False,
        "category": "environment",
        "verify_fbx": True,
        "required_object": ["BurntCarWreckMesh"],
        "object_type": ["EMPTY", "MESH"],
        "combine_meshes": True,
        "combined_object_name": "BurntCarWreckMesh",
        "material_remap": remap,
        "vmdl_material_source_suffix": "",
        "vmdl_use_global_default": False,
        "strict_vmdl_material_sources": True,
        "allow_default_color_texture": False,
        "global_scale": 1.0,
        "axis_forward": "-Y",
        "axis_up": "Z",
        "physics_shapes": [
            {
                "type": "box",
                "surface_prop": "metal",
                "collision_tags": "solid",
                "origin": [0, 0, 34],
                "dimensions": [252, 112, 68],
            }
        ],
    }
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def write_brief() -> None:
    text = """# burnt_car_wreck

## Asset

- Name: burnt_car_wreck
- Category: environment
- Profile: Environment and Prop

## S&Box Targets

- Prefab: Assets/prefabs/environment/burnt_car_wreck.prefab
- Model: Assets/models/burnt_car_wreck.vmdl
- Blender source: environment_model.blend/burnt_car_wreck.blend
- Scene placement: replaces the two lane barricade placeholders in Assets/scenes/main.scene.

## Reference Notes

- Damaged sedan-sized wreck used as soldier-scale road cover.
- Burn state should read from drone height: blackened roof/cabin, blistered paint, exposed rusty metal, missing glass, warped hood, ruined tires, ash scatter, and loose debris.
- It should not look like a clean car with a dark tint; the silhouette needs collapsed panels and broken openings.

## Production Quality Targets

- Large body mass blocks sightlines like the original barricade placeholders.
- Close-up silhouette includes deformed panels, exposed frame/engine elements, wheel rims, tire remnants, shattered glass, soot patches, and ground debris.
- Materials are image-backed and split into charred paint, blistered metal, rust, soot interior, rubber, glass, and ash.
- Origin sits at ground center so scene placement can use road-level Z values.

## Material Plan

- BurntCar_CharredPaint: blackened paint with red/brown scorched remnants.
- BurntCar_BlisteredMetal: exposed dull metal and heat staining.
- BurntCar_Rust: orange/brown corrosion on open edges and panels.
- BurntCar_SootInterior: black interior shell and burned cabin void.
- BurntCar_Rubber: charred tire remnants.
- BurntCar_Glass: dark broken glass shards.
- BurntCar_Ash: ash, debris, and scorched ground fragments.

## Scale and Orientation

- Length is roughly 250 S&Box units, width 110, height 80.
- Local X is vehicle length, local Y is width, and local Z is up.
- Root origin is ground center.

## Collision

- The exported modeldoc includes one coarse static metal box shape for the wreck body.
- Scene instances also use Sandbox.ModelCollider so collision coverage stays attached to the visible model.

## Visual Review Plan

- Render a Blender preview before export from a three-quarter ground/drone-readable angle.
- Run Blender quality, material texture, asset-production, modeldoc, prefab, and scene/collision checks after export.
- Verify in the S&Box editor when available because static checks do not prove runtime lighting or walk-into-cover behavior.

## Acceptance Checklist

- [x] Collision expectations are documented separately from visual mesh export.
- [x] Repeated props have stable names and avoid giant bounds.
- [x] Blockout dev-box collider sync remains a separate workflow.
"""
    BRIEF_PATH.write_text(text, encoding="utf-8")


def write_blender_build_script() -> None:
    material_payload = {
        name: {
            "color": [channel / 255.0 for channel in data["base"][0]],
            "metalness": data["metalness"],
            "roughness": data["roughness"],
        }
        for name, data in MATERIALS.items()
    }
    script = '''
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

BLEND_OUT = Path(r"__BLEND_OUT__")
MATERIALS = __MATERIALS_PAYLOAD__

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.render.engine = "BLENDER_EEVEE"

root = bpy.data.objects.new("BurntCarRoot", None)
bpy.context.scene.collection.objects.link(root)

materials = {}
for name, data in MATERIALS.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*data["color"], 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*data["color"], 1.0)
        bsdf.inputs["Metallic"].default_value = float(data["metalness"])
        bsdf.inputs["Roughness"].default_value = float(data["roughness"])
    materials[name] = mat


def assign_material(obj, mat_name):
    obj.data.materials.clear()
    obj.data.materials.append(materials[mat_name])


def apply_transform(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def add_weighted_normals(obj, bevel=0.0):
    if bevel > 0:
        modifier = obj.modifiers.new("soft burned bevels", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.affect = "EDGES"
    normal = obj.modifiers.new("weighted soot normals", "WEIGHTED_NORMAL")
    normal.keep_sharp = True


def ensure_planar_uv(obj):
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data
    mesh.calc_loop_triangles()
    for poly in mesh.polygons:
        normal = poly.normal
        axis = max(range(3), key=lambda i: abs(normal[i]))
        for loop_index in poly.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if axis == 2:
                uv = (vertex.x * 0.018, vertex.y * 0.018)
            elif axis == 1:
                uv = (vertex.x * 0.018, vertex.z * 0.018)
            else:
                uv = (vertex.y * 0.018, vertex.z * 0.018)
            uv_layer[loop_index].uv = uv


def parent(obj):
    obj.parent = root
    return obj


def box(name, loc, dims, mat, rot=(0, 0, 0), bevel=1.0, dent=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    assign_material(obj, mat)
    apply_transform(obj)
    if dent:
        rng = random.Random(name)
        for vertex in obj.data.vertices:
            if vertex.co.z > 0:
                vertex.co.z += rng.uniform(-dent, dent * 0.45)
            if abs(vertex.co.y) > dims[1] * 0.35:
                vertex.co.y += rng.uniform(-dent * 0.25, dent * 0.25)
            vertex.co.x += rng.uniform(-dent * 0.18, dent * 0.18)
        obj.data.update()
    ensure_planar_uv(obj)
    add_weighted_normals(obj, bevel)
    return parent(obj)


def cylinder_between(name, start, end, radius, mat, vertices=12, bevel=0.0):
    start_v = Vector(start)
    end_v = Vector(end)
    mid = (start_v + end_v) * 0.5
    direction = end_v - start_v
    length = direction.length
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=mid)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    assign_material(obj, mat)
    apply_transform(obj)
    ensure_planar_uv(obj)
    add_weighted_normals(obj, bevel)
    return parent(obj)


def torus(name, loc, major_radius, minor_radius, mat, rot=(math.pi / 2, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=48,
        minor_segments=10,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=loc,
        rotation=rot,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, mat)
    apply_transform(obj)
    ensure_planar_uv(obj)
    add_weighted_normals(obj, 0.0)
    return parent(obj)


def cylinder(name, loc, radius, depth, mat, vertices=32, rot=(math.pi / 2, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, mat)
    apply_transform(obj)
    ensure_planar_uv(obj)
    add_weighted_normals(obj, 0.0)
    return parent(obj)


def triangle(name, verts, mat):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata([tuple(v) for v in verts], [], [(0, 1, 2)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_material(obj, mat)
    ensure_planar_uv(obj)
    add_weighted_normals(obj, 0.0)
    return parent(obj)


# Crushed main shell and panels.
box("Body_CrushedLowerShell", (0, 0, 32), (238, 102, 34), "BurntCar_CharredPaint", bevel=5.0, dent=7.5)
box("Body_LeftRocker_RustSplit", (0, -56, 25), (226, 7, 18), "BurntCar_Rust", bevel=2.5, dent=2.0)
box("Body_RightRocker_RustSplit", (0, 56, 25), (226, 7, 18), "BurntCar_Rust", bevel=2.5, dent=2.0)
box("Hood_WarpedOpen", (76, 0, 58), (93, 93, 7), "BurntCar_CharredPaint", rot=(0, math.radians(-9), 0), bevel=3.0, dent=9.0)
box("Trunk_CavedPanel", (-91, 0, 52), (76, 92, 8), "BurntCar_BlisteredMetal", rot=(0, math.radians(6), math.radians(2)), bevel=2.5, dent=7.0)
box("Roof_CollapsedSootPlate", (-6, 0, 78), (112, 87, 8), "BurntCar_SootInterior", rot=(math.radians(3), math.radians(-5), math.radians(1)), bevel=3.0, dent=10.0)
box("Cabin_FireBlackInterior", (-6, 0, 58), (92, 78, 38), "BurntCar_SootInterior", bevel=2.0, dent=6.0)

# Door skins and broken window frames.
for side, y in [("Left", -56), ("Right", 56)]:
    box(f"Door_{side}_FrontLowerSkin", (25, y, 47), (58, 5, 31), "BurntCar_CharredPaint", rot=(0, 0, math.radians(2 if y < 0 else -2)), bevel=1.4, dent=5.0)
    box(f"Door_{side}_RearLowerSkin", (-42, y, 45), (52, 5, 28), "BurntCar_BlisteredMetal", rot=(0, 0, math.radians(-3 if y < 0 else 3)), bevel=1.4, dent=4.5)
    for x, label in [(58, "A"), (8, "B"), (-55, "C")]:
        cylinder_between(f"Cabin_{side}_{label}PillarBent", (x, y, 45), (x + (-8 if label == "A" else 6), y * 0.92, 83), 2.2, "BurntCar_Rust", vertices=8, bevel=0.1)
    cylinder_between(f"Cabin_{side}_TopRailTwisted", (62, y, 82), (-62, y * 0.96, 76), 2.0, "BurntCar_Rust", vertices=8, bevel=0.1)
    cylinder_between(f"Cabin_{side}_BeltRail", (65, y, 58), (-66, y, 54), 1.7, "BurntCar_BlisteredMetal", vertices=8)

# Front and rear damaged hardware.
box("EngineBlock_ExposedBlackMass", (104, 0, 41), (34, 45, 26), "BurntCar_SootInterior", bevel=2.0, dent=3.0)
box("Radiator_RustedCore", (131, 0, 35), (6, 74, 25), "BurntCar_Rust", rot=(0, math.radians(2), 0), bevel=0.8, dent=2.0)
for y in [-28, -14, 0, 14, 28]:
    cylinder_between(f"Radiator_BentSlat_{y}", (134, y, 24), (133, y + 4, 50), 0.85, "BurntCar_BlisteredMetal", vertices=6)
box("FrontBumper_HangingTwist", (135, -3, 23), (10, 105, 11), "BurntCar_BlisteredMetal", rot=(math.radians(1), math.radians(-4), math.radians(3)), bevel=1.5, dent=5.0)
box("RearBumper_SaggingRust", (-135, 4, 24), (10, 101, 12), "BurntCar_Rust", rot=(math.radians(-1), math.radians(3), math.radians(-2)), bevel=1.5, dent=4.0)

# Wheels, ruined tires, rims, and hubs.
for x in [-82, 82]:
    for y in [-61, 61]:
        side = "L" if y < 0 else "R"
        front = "F" if x > 0 else "R"
        torus(f"Wheel_{front}{side}_CharredTireRing", (x, y, 22), 16.5, 5.4, "BurntCar_Rubber")
        cylinder(f"Wheel_{front}{side}_ExposedRim", (x, y, 22), 11.0, 17.5, "BurntCar_BlisteredMetal", vertices=24)
        cylinder(f"Wheel_{front}{side}_BurnedHub", (x, y, 22), 5.2, 19.5, "BurntCar_Rust", vertices=16)
        for i in range(5):
            angle = i * math.tau / 5
            z = 22 + math.sin(angle) * 9.0
            xx = x + math.cos(angle) * 9.0
            cylinder_between(f"Wheel_{front}{side}_RimSpoke_{i}", (x, y, 22), (xx, y, z), 0.9, "BurntCar_BlisteredMetal", vertices=6)

# Frame rails and cross members visible through the burned cabin.
for y in [-31, 31]:
    cylinder_between(f"FrameRail_{y}", (-116, y, 24), (124, y, 27), 2.3, "BurntCar_BlisteredMetal", vertices=8)
for x in [-92, -35, 25, 86]:
    cylinder_between(f"FrameCrossMember_{x}", (x, -37, 25), (x + random.Random(x).uniform(-5, 5), 37, 25), 1.9, "BurntCar_Rust", vertices=8)

# Shattered glass shards.
rng = random.Random(815)
glass_sources = [
    (52, -46, 70), (18, -48, 72), (-32, -47, 69),
    (52, 46, 70), (18, 48, 72), (-32, 47, 69),
    (58, 0, 72), (-65, 0, 67),
]
for index, center in enumerate(glass_sources):
    cx, cy, cz = center
    for piece in range(3):
        spread = rng.uniform(7, 16)
        verts = [
            (cx + rng.uniform(-spread, spread), cy + rng.uniform(-3, 3), cz + rng.uniform(-spread * 0.4, spread)),
            (cx + rng.uniform(-spread, spread), cy + rng.uniform(-3, 3), cz + rng.uniform(-spread, spread * 0.6)),
            (cx + rng.uniform(-spread, spread), cy + rng.uniform(-3, 3), cz + rng.uniform(-spread, spread)),
        ]
        triangle(f"GlassShard_{index}_{piece}", verts, "BurntCar_Glass")

# Scorch patches, ash, loose sheet metal, and nearby debris.
for index in range(34):
    x = rng.uniform(-125, 130)
    y = rng.choice([-1, 1]) * rng.uniform(38, 74)
    z = rng.uniform(5, 42)
    dims = (rng.uniform(7, 22), rng.uniform(1.0, 3.0), rng.uniform(2, 10))
    mat = rng.choice(["BurntCar_Rust", "BurntCar_BlisteredMetal", "BurntCar_CharredPaint"])
    rot = (rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4), rng.uniform(-0.8, 0.8))
    box(f"TornPanelShard_{index:02d}", (x, y, z), dims, mat, rot=rot, bevel=0.5, dent=1.2)

for index in range(42):
    x = rng.uniform(-140, 140)
    y = rng.uniform(-67, 67)
    z = rng.uniform(0.8, 3.5)
    dims = (rng.uniform(3, 16), rng.uniform(2, 12), rng.uniform(0.5, 2.2))
    mat = rng.choice(["BurntCar_Ash", "BurntCar_Rust", "BurntCar_Rubber"])
    rot = (0, 0, rng.uniform(0, math.tau))
    box(f"GroundDebris_{index:02d}", (x, y, z), dims, mat, rot=rot, bevel=0.25, dent=0.3)

for index, (x, y, z) in enumerate([(72, -23, 65), (34, 18, 80), (-24, -19, 79), (-94, 28, 56), (119, 31, 43)]):
    box(f"SootPatch_RaisedScale_{index}", (x, y, z), (rng.uniform(18, 34), 1.0, rng.uniform(9, 18)), "BurntCar_Ash", rot=(rng.uniform(-0.4, 0.4), rng.uniform(-0.2, 0.2), rng.uniform(-0.6, 0.6)), bevel=0.2, dent=0.5)

for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.select_set(False)
        ensure_planar_uv(obj)

BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
'''
    script = script.replace("__BLEND_OUT__", str(BLENDER_SOURCE))
    script = script.replace("__MATERIALS_PAYLOAD__", repr(material_payload))
    BUILD_SCRIPT_PATH.write_text(textwrap.dedent(script).lstrip(), encoding="utf-8")


def run_blender(blender_exe: str) -> None:
    command = [
        blender_exe,
        "--background",
        "--python-exit-code",
        "1",
        "--python",
        str(BUILD_SCRIPT_PATH),
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if completed.stdout:
        print(completed.stdout.strip())
    if completed.stderr:
        print(completed.stderr.strip())
    if completed.returncode != 0:
        raise RuntimeError(f"Blender asset build failed with exit code {completed.returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create the burnt car wreck source asset.")
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER)
    args = parser.parse_args()

    ensure_dirs()
    write_material_files()
    write_prefab()
    write_config()
    write_brief()
    write_blender_build_script()
    run_blender(args.blender_exe)

    print(f"Wrote Blender source: {rel(BLENDER_SOURCE)}")
    print(f"Wrote asset config: {rel(CONFIG_PATH)}")
    print(f"Wrote prefab seed: {rel(PREFAB_PATH)}")
    print(f"Wrote asset brief: {rel(BRIEF_PATH)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
