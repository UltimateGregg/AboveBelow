#!/usr/bin/env python3
"""
Generate the authored building meshes and keep the S&Box prefab/scene graphs in
sync with those meshes.

Run blend generation inside Blender:
  blender --background --python scripts/building_architecture_pipeline.py -- --generate-blends

Run JSON wiring with normal Python:
  python scripts/building_architecture_pipeline.py --write-configs --write-prefabs --update-scene
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BLEND_DIR = ROOT / "environment_model.blend"
MODEL_DIR = ROOT / "Assets" / "models"
PREFAB_DIR = ROOT / "Assets" / "prefabs" / "environment"
SCENE_PATH = ROOT / "Assets" / "scenes" / "main.scene"
SCRIPTS_DIR = ROOT / "scripts"
ENV_MATERIAL_DIR = ROOT / "Assets" / "materials" / "environment"

HOUSE_TEXTURE_SEEDS = {
    "house_large": 4101,
    "house_small": 5101,
}

HOUSE_LARGE_MATERIAL_REMAP = {
    "M_HouseLarge_Siding": "materials/environment/house_large_siding.vmat",
    "M_HouseLarge_Roof": "materials/environment/house_large_roof.vmat",
    "M_HouseLarge_Foundation": "materials/environment/house_large_foundation.vmat",
    "M_HouseLarge_Trim": "materials/environment/house_large_trim.vmat",
    "M_HouseLarge_InteriorWood": "materials/environment/house_large_interior_wood.vmat",
    "M_HouseLarge_Glass": "materials/environment/house_large_glass.vmat",
    "M_HouseLarge_Metal": "materials/environment/house_large_metal.vmat",
    "M_HouseLarge_TacticalPatch": "materials/environment/house_large_tactical_patch.vmat",
    "M_HouseLarge_DirtMask": "materials/environment/house_large_dirt_mask.vmat",
}

HOUSE_SMALL_MATERIAL_REMAP = {
    "M_HouseSmall_Siding": "materials/environment/house_small_siding.vmat",
    "M_HouseSmall_Roof": "materials/environment/house_small_roof.vmat",
    "M_HouseSmall_Foundation": "materials/environment/house_small_foundation.vmat",
    "M_HouseSmall_Trim": "materials/environment/house_small_trim.vmat",
    "M_HouseSmall_InteriorWood": "materials/environment/house_small_interior_wood.vmat",
    "M_HouseSmall_Glass": "materials/environment/house_small_glass.vmat",
    "M_HouseSmall_Metal": "materials/environment/house_small_metal.vmat",
    "M_HouseSmall_TacticalPatch": "materials/environment/house_small_tactical_patch.vmat",
    "M_HouseSmall_DirtMask": "materials/environment/house_small_dirt_mask.vmat",
}

MATERIAL_COLORS = {
    "M_HouseLarge_Siding": (0.64, 0.58, 0.49, 1.0),
    "M_HouseLarge_Roof": (0.36, 0.32, 0.28, 1.0),
    "M_HouseLarge_Foundation": (0.42, 0.41, 0.37, 1.0),
    "M_HouseLarge_Trim": (0.78, 0.74, 0.65, 1.0),
    "M_HouseLarge_InteriorWood": (0.29, 0.20, 0.14, 1.0),
    "M_HouseLarge_Glass": (0.22, 0.35, 0.39, 0.55),
    "M_HouseLarge_Metal": (0.37, 0.38, 0.37, 1.0),
    "M_HouseLarge_TacticalPatch": (0.36, 0.35, 0.25, 1.0),
    "M_HouseLarge_DirtMask": (0.30, 0.24, 0.17, 1.0),
    "M_HouseSmall_Siding": (0.46, 0.55, 0.52, 1.0),
    "M_HouseSmall_Roof": (0.24, 0.31, 0.32, 1.0),
    "M_HouseSmall_Foundation": (0.40, 0.40, 0.36, 1.0),
    "M_HouseSmall_Trim": (0.66, 0.64, 0.55, 1.0),
    "M_HouseSmall_InteriorWood": (0.27, 0.18, 0.12, 1.0),
    "M_HouseSmall_Glass": (0.20, 0.33, 0.37, 0.55),
    "M_HouseSmall_Metal": (0.32, 0.34, 0.34, 1.0),
    "M_HouseSmall_TacticalPatch": (0.30, 0.34, 0.24, 1.0),
    "M_HouseSmall_DirtMask": (0.28, 0.22, 0.16, 1.0),
}


def stable_guid(*parts: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "/".join(parts)))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def clamp_byte(value: float) -> int:
    return max(0, min(255, int(round(value))))


def hash_noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393 + y * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFF
    value = (value ^ (value >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((value ^ (value >> 16)) & 0xFFFF) / 65535.0


def mix_color(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(clamp_byte(a[i] + (b[i] - a[i]) * t) for i in range(3))


def normal_from_height(height: list[list[int]], strength: float = 3.0) -> "Image.Image":
    from PIL import Image

    size = len(height)
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            left = height[y][(x - 1) % size]
            right = height[y][(x + 1) % size]
            up = height[(y - 1) % size][x]
            down = height[(y + 1) % size][x]
            dx = (left - right) / 255.0 * strength
            dy = (up - down) / 255.0 * strength
            dz = 1.0
            length = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
            pixels[x, y] = (
                clamp_byte((dx / length * 0.5 + 0.5) * 255),
                clamp_byte((dy / length * 0.5 + 0.5) * 255),
                clamp_byte((dz / length * 0.5 + 0.5) * 255),
            )
    return image


def texture_pixel(role: str, x: int, y: int, size: int, seed: int, palette: tuple[tuple[int, int, int], tuple[int, int, int]]) -> tuple[tuple[int, int, int], int, int, int]:
    nx = x / max(1, size - 1)
    ny = y / max(1, size - 1)
    coarse = hash_noise(x // 18, y // 18, seed)
    fine = hash_noise(x, y, seed + 37)
    streak = hash_noise(x // 9, 0, seed + 71)
    color_t = 0.35 * coarse + 0.16 * fine
    height = 128 + int((coarse - 0.5) * 46 + (fine - 0.5) * 18)
    rough = 175 + int((1.0 - coarse) * 42)
    ao = 222 - int((1.0 - fine) * 30)

    if role == "siding":
        plank = int(y / max(1, size / 13))
        seam = min(y % max(1, int(size / 13)), max(1, int(size / 13)) - (y % max(1, int(size / 13))))
        color_t += (plank % 4) * 0.035
        if seam <= 2:
            color_t -= 0.18
            height -= 42
            ao -= 42
        if x % max(1, int(size / 23)) <= 1:
            color_t -= 0.06
            height -= 18
        color_t += math.sin(nx * math.tau * 5.0) * 0.035
    elif role == "roof":
        panel_width = max(12, int(size / 11))
        seam = x % panel_width
        color_t += math.sin(ny * math.tau * 2.0 + streak * 2.0) * 0.05
        if seam <= 2 or seam >= panel_width - 2:
            color_t -= 0.14
            height += 34
            rough += 18
        if hash_noise(x // 28, y // 80, seed + 100) > 0.82:
            color_t += 0.18
            rough += 20
    elif role == "foundation":
        block_w = max(24, int(size / 6))
        block_h = max(18, int(size / 9))
        if x % block_w <= 2 or y % block_h <= 2:
            color_t -= 0.22
            height -= 48
            ao -= 44
        color_t += 0.08 * hash_noise(x // 7, y // 7, seed + 5)
    elif role == "trim":
        if x % max(8, int(size / 14)) <= 2:
            color_t -= 0.09
            height += 20
        color_t += math.sin((nx + ny) * math.tau * 3.0) * 0.025
    elif role == "interior_wood":
        color_t += math.sin(nx * math.tau * 18.0 + coarse * 2.0) * 0.08
        if x % max(18, int(size / 8)) <= 2:
            color_t -= 0.12
            height -= 24
            ao -= 28
    elif role == "glass":
        color_t += ny * 0.16
        if hash_noise(x // 5, y // 40, seed + 19) > 0.73:
            color_t += 0.20
            rough += 24
        height = 128
        ao = 238
    elif role == "metal":
        color_t += math.sin((nx + ny) * math.tau * 8.0) * 0.04
        if hash_noise(x // 3, y // 32, seed + 29) > 0.86:
            color_t += 0.18
            height += 18
    elif role == "tactical_patch":
        weave = ((x // 8) + (y // 8)) % 2
        color_t += 0.08 if weave else -0.04
        if x % max(24, int(size / 6)) <= 1 or y % max(24, int(size / 6)) <= 1:
            height -= 22
            ao -= 26
    elif role == "dirt_mask":
        distance = math.sqrt((nx - 0.5) ** 2 + (ny - 0.5) ** 2)
        color_t += (1.0 - distance) * 0.22
        if hash_noise(x // 10, y // 10, seed + 41) > 0.68:
            color_t += 0.18
            rough += 24
            ao -= 22

    color = mix_color(palette[0], palette[1], color_t)
    return color, clamp_byte(height), clamp_byte(rough), clamp_byte(ao)


def write_texture_set(prefix: str, role: str, seed: int, size: int, palette: tuple[tuple[int, int, int], tuple[int, int, int]], maps: tuple[str, ...]) -> dict[str, str]:
    from PIL import Image

    color_image = Image.new("RGB", (size, size))
    height: list[list[int]] = [[128] * size for _ in range(size)]
    rough_image = Image.new("L", (size, size))
    ao_image = Image.new("L", (size, size))

    color_pixels = color_image.load()
    rough_pixels = rough_image.load()
    ao_pixels = ao_image.load()
    for y in range(size):
        for x in range(size):
            color, h, rough, ao = texture_pixel(role, x, y, size, seed, palette)
            color_pixels[x, y] = color
            height[y][x] = h
            rough_pixels[x, y] = rough
            ao_pixels[x, y] = ao

    outputs: dict[str, str] = {}
    files = {
        "TextureColor": (f"{prefix}_color.png", color_image),
        "TextureNormal": (f"{prefix}_normal.png", normal_from_height(height)),
        "TextureRoughness": (f"{prefix}_rough.png", rough_image),
        "TextureAmbientOcclusion": (f"{prefix}_ao.png", ao_image),
    }
    for key in maps:
        file_name, image = files[key]
        image.save(ENV_MATERIAL_DIR / file_name)
        outputs[key] = f"materials/environment/{file_name}"
    return outputs


def write_vmat(path: Path, textures: dict[str, str], metalness: float, roughness: float, tint: tuple[float, float, float], alpha: float = 0.0) -> None:
    lines = [
        '"Layer0"',
        "{",
        '\t"shader"\t\t"shaders/complex.shader"',
    ]
    for key in ("TextureColor", "TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"):
        if key in textures:
            lines.append(f'\t"{key}"\t\t"{textures[key]}"')
    lines.extend(
        [
            '\t"g_flModelTintAmount"\t\t"1.000000"',
            f'\t"g_vColorTint"\t\t"[{tint[0]:.6f} {tint[1]:.6f} {tint[2]:.6f} {alpha:.6f}]"',
            f'\t"g_flMetalness"\t\t"{metalness:.6f}"',
            f'\t"g_flRoughness"\t\t"{roughness:.6f}"',
            '\t"g_bFogEnabled"\t\t"1"',
            '\t"g_vTexCoordScale"\t\t"[1.000 1.000]"',
            '\t"g_vTexCoordOffset"\t\t"[0.000 0.000]"',
            '\t"g_vTexCoordScrollSpeed"\t\t"[0.000 0.000]"',
            "}",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def material_specs(asset_name: str) -> list[dict[str, Any]]:
    large = asset_name == "house_large"
    source_prefix = "M_HouseLarge" if large else "M_HouseSmall"
    file_prefix = "house_large" if large else "house_small"
    palettes = {
        "siding": ((142, 130, 110), (194, 182, 155)) if large else ((96, 122, 116), (156, 175, 163)),
        "roof": ((67, 62, 56), (133, 102, 80)) if large else ((48, 68, 70), (109, 125, 118)),
        "foundation": ((83, 82, 75), (151, 145, 132)),
        "trim": ((164, 154, 130), (224, 216, 188)) if large else ((135, 131, 108), (198, 195, 170)),
        "interior_wood": ((61, 40, 26), (133, 84, 48)),
        "glass": ((48, 78, 88), (158, 184, 184)),
        "metal": ((65, 66, 64), (148, 150, 145)),
        "tactical_patch": ((76, 80, 53), (142, 132, 88)) if large else ((63, 82, 55), (130, 141, 94)),
        "dirt_mask": ((62, 45, 29), (142, 108, 66)),
    }
    return [
        {"source": f"{source_prefix}_Siding", "file": f"{file_prefix}_siding", "role": "siding", "size": 512, "maps": ("TextureColor", "TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["siding"], "metalness": 0.0, "roughness": 0.78},
        {"source": f"{source_prefix}_Roof", "file": f"{file_prefix}_roof", "role": "roof", "size": 512, "maps": ("TextureColor", "TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["roof"], "metalness": 0.35, "roughness": 0.68},
        {"source": f"{source_prefix}_Foundation", "file": f"{file_prefix}_foundation", "role": "foundation", "size": 512, "maps": ("TextureColor", "TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["foundation"], "metalness": 0.0, "roughness": 0.86},
        {"source": f"{source_prefix}_Trim", "file": f"{file_prefix}_trim", "role": "trim", "size": 512, "maps": ("TextureColor", "TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["trim"], "metalness": 0.0, "roughness": 0.74},
        {"source": f"{source_prefix}_InteriorWood", "file": f"{file_prefix}_interior_wood", "role": "interior_wood", "size": 512, "maps": ("TextureColor", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["interior_wood"], "metalness": 0.0, "roughness": 0.82},
        {"source": f"{source_prefix}_Glass", "file": f"{file_prefix}_glass", "role": "glass", "size": 256, "maps": ("TextureColor",), "palette": palettes["glass"], "metalness": 0.0, "roughness": 0.24, "alpha": 0.25},
        {"source": f"{source_prefix}_Metal", "file": f"{file_prefix}_metal", "role": "metal", "size": 256, "maps": ("TextureColor", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["metal"], "metalness": 0.55, "roughness": 0.61},
        {"source": f"{source_prefix}_TacticalPatch", "file": f"{file_prefix}_tactical_patch", "role": "tactical_patch", "size": 256, "maps": ("TextureColor", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["tactical_patch"], "metalness": 0.0, "roughness": 0.88},
        {"source": f"{source_prefix}_DirtMask", "file": f"{file_prefix}_dirt_mask", "role": "dirt_mask", "size": 256, "maps": ("TextureColor", "TextureRoughness", "TextureAmbientOcclusion"), "palette": palettes["dirt_mask"], "metalness": 0.0, "roughness": 0.94},
    ]


def write_materials() -> None:
    ENV_MATERIAL_DIR.mkdir(parents=True, exist_ok=True)
    for asset_name, base_seed in HOUSE_TEXTURE_SEEDS.items():
        for index, spec in enumerate(material_specs(asset_name)):
            textures = write_texture_set(
                spec["file"],
                spec["role"],
                base_seed + index * 97,
                spec["size"],
                spec["palette"],
                spec["maps"],
            )
            source_color = MATERIAL_COLORS[spec["source"]]
            write_vmat(
                ENV_MATERIAL_DIR / f"{spec['file']}.vmat",
                textures,
                spec["metalness"],
                spec["roughness"],
                source_color[:3],
                float(spec.get("alpha", 0.0)),
            )
    print("Wrote tactical house materials and textures.")


def base_gameobject(name: str, position: str = "0,0,0") -> dict[str, Any]:
    return {
        "__guid": stable_guid("building-template", name, "go"),
        "Flags": 0,
        "Name": name,
        "Position": position,
        "Rotation": "0,0,0,1",
        "Scale": "1,1,1",
        "Enabled": True,
        "Components": [],
        "Children": [],
    }


def model_renderer(model: str, name: str) -> dict[str, Any]:
    return {
        "__type": "Sandbox.ModelRenderer",
        "__guid": stable_guid("building-template", name, "renderer"),
        "BodyGroups": 18446744073709551615,
        "CreateAttachments": False,
        "Model": model,
        "RenderType": "On",
        "Tint": "1,1,1,1",
    }


def box_collider(name: str, scale: str, center: str = "0,0,0", trigger: bool = False) -> dict[str, Any]:
    return {
        "__type": "Sandbox.BoxCollider",
        "__guid": stable_guid("building-template", name, "box"),
        "Center": center,
        "Scale": scale,
        "Static": True,
        "IsTrigger": trigger,
    }


def ladder_volume(name: str, top_exit: str) -> dict[str, Any]:
    return {
        "__type": "DroneVsPlayers.LadderVolume",
        "__guid": stable_guid("building-template", name, "ladder-volume"),
        "AutoConfigureCollider": True,
        "GrabPadding": 18,
        "UseTopExit": True,
        "TopExitLocalOffset": top_exit,
        "TopExitTriggerDistance": 32,
        "BottomExitTriggerDistance": 8,
    }


def visual_child(name: str, model: str) -> dict[str, Any]:
    child = base_gameobject("Model_Visual")
    child["__guid"] = stable_guid(name, "Model_Visual", "go")
    child["Components"] = [model_renderer(model, name)]
    return child


def collision_child(name: str, position: str, scale: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [box_collider(name, scale)]
    return child


def trigger_child(name: str, position: str, scale: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [box_collider(name, scale, trigger=True)]
    return child


def ladder_child(name: str, position: str, collider_center: str, collider_scale: str, top_exit: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [
        ladder_volume(name, top_exit),
        box_collider(name, collider_scale, center=collider_center, trigger=True),
    ]
    return child


def legacy_large_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Large", "models/house_large.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Basement", "0,0,-170", "240,240,20"),
            collision_child("Collision_Floor_Ground", "0,0,-2.211", "240,240,20"),
            collision_child("Collision_Floor_Loft", "0,0,273.482", "220,220,20"),
            collision_child("Collision_Roof", "0,0,489.571", "313.786,308.094,62.179"),
            collision_child("Collision_Basement_North", "0,-125,-76.105", "240,10,167.789"),
            collision_child("Collision_Basement_South", "0,125,-76.105", "240,10,167.789"),
            collision_child("Collision_Basement_West", "-125,0,-76.105", "10,240,167.789"),
            collision_child("Collision_Basement_East_A", "125,-70,-76.105", "10,100,167.789"),
            collision_child("Collision_Basement_East_B", "125,70,-76.105", "10,100,167.789"),
            collision_child("Collision_Wall_South_Left", "-76,125,135.635", "88,10,255.692"),
            collision_child("Collision_Wall_South_Right", "76,125,135.635", "88,10,255.692"),
            collision_child("Collision_Wall_South_Lintel", "0,125,211.741", "64,10,103.482"),
            collision_child("Collision_Wall_North_Left", "-80,-125,135.635", "80,10,255.692"),
            collision_child("Collision_Wall_North_Right", "80,-125,135.635", "80,10,255.692"),
            collision_child("Collision_Wall_North_Sill", "0,-125,47.895", "80,10,80.211"),
            collision_child("Collision_Wall_North_Header", "0,-125,211.741", "80,10,103.482"),
            collision_child("Collision_Wall_West_Lower", "-125,-80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_West_Upper", "-125,80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_West_Sill", "-125,0,47.895", "10,80,80.211"),
            collision_child("Collision_Wall_West_Header", "-125,0,211.741", "10,80,103.482"),
            collision_child("Collision_Wall_East_Lower", "125,-80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_East_Upper", "125,80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_East_Sill", "125,0,47.895", "10,80,80.211"),
            collision_child("Collision_Wall_East_Header", "125,0,211.741", "10,80,103.482"),
            collision_child("Collision_UpperWall_South_Left", "-73,115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_South_Right", "73,115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_South_Header", "0,115,429.241", "72,10,58.482"),
            collision_child("Collision_UpperWall_North_Left", "-73,-115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_North_Right", "73,-115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_North_Sill", "0,-115,311.741", "72,10,56.518"),
            collision_child("Collision_UpperWall_North_Header", "0,-115,429.241", "72,10,58.482"),
            collision_child("Collision_UpperWall_West_Lower", "-115,-73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_West_Upper", "-115,73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_West_Sill", "-115,0,311.741", "10,72,56.518"),
            collision_child("Collision_UpperWall_West_Header", "-115,0,429.241", "10,72,58.482"),
            collision_child("Collision_UpperWall_East_Lower", "115,-73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_East_Upper", "115,73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_East_Sill", "115,0,311.741", "10,72,56.518"),
            collision_child("Collision_UpperWall_East_Header", "115,0,429.241", "10,72,58.482"),
            collision_child("Collision_Interior_Wall_Left", "-65,25,135.635", "110,10,255.692"),
            collision_child("Collision_Interior_Wall_Right", "85,25,135.635", "70,10,255.692"),
            collision_child("Collision_Stairs_Down", "80,80,-76.105", "42,58,167.789"),
            collision_child("Collision_Parapet_North", "0,-135,535", "270,10,45"),
            collision_child("Collision_Parapet_South", "0,135,535", "270,10,45"),
            collision_child("Collision_Parapet_East", "135,0,535", "10,270,45"),
            collision_child("Collision_Parapet_West", "-135,0,535", "10,270,45"),
            ladder_child("Ladder_To_Loft", "-50,-104,7.789", "0,0,137.846", "30,30,275.692", "0,54,275.692"),
            ladder_child("Ladder_To_Roof", "-50,-54,283.482", "0,0,87.5", "30,30,175", "0,54,175"),
            trigger_child("Zone_Foyer", "0,105,70", "110,50,100"),
            trigger_child("Zone_LivingArea", "-55,-25,90", "150,100,140"),
            trigger_child("Zone_Kitchen", "70,60,90", "90,100,140"),
            trigger_child("Zone_Basement", "0,0,-76.105", "220,220,167.789"),
            trigger_child("Zone_Loft", "0,0,323.482", "220,220,80"),
            trigger_child("Zone_Roof", "0,0,489.571", "313.786,308.094,70"),
        ]
    )
    return children


def legacy_small_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Small", "models/house_small.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Ground", "0,0,10", "180,180,20"),
            collision_child("Collision_Floor_Loft", "0,-38,240", "110,95,18"),
            collision_child("Collision_Roof", "0,0,365", "195,195,26"),
            collision_child("Collision_Wall_South_Left", "-60,90,110", "60,10,220"),
            collision_child("Collision_Wall_South_Right", "60,90,110", "60,10,220"),
            collision_child("Collision_Wall_South_Lintel", "0,90,185", "60,10,70"),
            collision_child("Collision_Wall_North_Left", "-62,-90,110", "56,10,220"),
            collision_child("Collision_Wall_North_Right", "62,-90,110", "56,10,220"),
            collision_child("Collision_Wall_North_Sill", "0,-90,42", "68,10,84"),
            collision_child("Collision_Wall_North_Header", "0,-90,185", "68,10,70"),
            collision_child("Collision_Wall_West_Lower", "-90,-55,110", "10,70,220"),
            collision_child("Collision_Wall_West_Upper", "-90,55,110", "10,70,220"),
            collision_child("Collision_Wall_West_Sill", "-90,0,42", "10,70,84"),
            collision_child("Collision_Wall_West_Header", "-90,0,185", "10,70,70"),
            collision_child("Collision_Wall_East", "90,0,110", "10,180,220"),
            collision_child("Collision_UpperWall_South_Left", "-48,74,295", "42,10,110"),
            collision_child("Collision_UpperWall_South_Right", "48,74,295", "42,10,110"),
            collision_child("Collision_UpperWall_South_Header", "0,74,328", "54,10,44"),
            collision_child("Collision_UpperWall_North_Left", "-48,-74,295", "42,10,110"),
            collision_child("Collision_UpperWall_North_Right", "48,-74,295", "42,10,110"),
            collision_child("Collision_UpperWall_North_Sill", "0,-74,260", "54,10,38"),
            collision_child("Collision_UpperWall_North_Header", "0,-74,328", "54,10,44"),
            collision_child("Collision_UpperWall_West_Lower", "-74,-46,295", "10,46,110"),
            collision_child("Collision_UpperWall_West_Upper", "-74,46,295", "10,46,110"),
            collision_child("Collision_UpperWall_West_Sill", "-74,0,260", "10,50,38"),
            collision_child("Collision_UpperWall_West_Header", "-74,0,328", "10,50,44"),
            collision_child("Collision_UpperWall_East", "74,0,295", "10,145,110"),
            collision_child("Collision_Interior_Wall", "25,12,110", "85,10,200"),
            collision_child("Collision_Parapet_North", "0,-98,392", "195,10,42"),
            collision_child("Collision_Parapet_South", "0,98,392", "195,10,42"),
            collision_child("Collision_Parapet_East", "98,0,392", "10,195,42"),
            collision_child("Collision_Parapet_West", "-98,0,392", "10,195,42"),
            ladder_child("Ladder_To_Loft", "0,-82,0", "0,0,121", "24,26,242", "0,52,252"),
            ladder_child("Ladder_To_Roof", "0,-35,240", "0,0,70", "24,26,140", "0,50,140"),
            trigger_child("Zone_Entry", "0,70,70", "95,50,100"),
            trigger_child("Zone_MainRoom", "-35,-15,90", "110,110,130"),
            trigger_child("Zone_SideRoom", "55,20,90", "70,110,130"),
            trigger_child("Zone_Loft", "0,-38,265", "110,95,70"),
            trigger_child("Zone_Roof", "0,0,392", "195,195,60"),
        ]
    )
    return children


def large_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Large", "models/house_large.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Basement", "-92,12,-118", "300,245,18"),
            collision_child("Collision_Floor_Ground", "0,0,8", "500,388,18"),
            collision_child("Collision_Floor_Loft", "-22,-20,238", "360,285,18"),
            collision_child("Collision_Roof_Main", "0,0,410", "560,418,36"),
            collision_child("Collision_Roof_Access", "-112,-90,386", "92,66,16"),
            collision_child("Collision_Foundation_North", "0,-204,26", "520,16,68"),
            collision_child("Collision_Foundation_South", "0,204,26", "520,16,68"),
            collision_child("Collision_Foundation_West", "-260,0,26", "16,396,68"),
            collision_child("Collision_Foundation_East", "260,0,26", "16,396,68"),
            collision_child("Collision_Foundation_Cellar_North", "-92,-116,-62", "300,12,112"),
            collision_child("Collision_Foundation_Cellar_West", "-248,12,-62", "12,245,112"),
            collision_child("Collision_Wall_North_Left", "-150,-198,118", "190,14,224"),
            collision_child("Collision_Wall_North_Right", "152,-198,118", "184,14,224"),
            collision_child("Collision_Wall_North_Header", "0,-198,204", "110,14,52"),
            collision_child("Collision_Wall_South_Left", "-176,198,118", "150,14,224"),
            collision_child("Collision_Wall_South_Right", "168,198,118", "156,14,224"),
            collision_child("Collision_Wall_South_DoorHeader", "0,198,214", "116,14,40"),
            collision_child("Collision_Wall_West_Lower", "-264,-90,118", "14,158,224"),
            collision_child("Collision_Wall_West_Upper", "-264,116,118", "14,176,224"),
            collision_child("Collision_Wall_East_Lower", "264,-116,118", "14,128,224"),
            collision_child("Collision_Wall_East_Upper", "264,102,118", "14,180,224"),
            collision_child("Collision_Wall_Loft_North_Left", "-118,-184,304", "162,12,118"),
            collision_child("Collision_Wall_Loft_North_Right", "132,-184,304", "144,12,118"),
            collision_child("Collision_Wall_Loft_West", "-206,-42,304", "12,214,118"),
            collision_child("Collision_Wall_Loft_East", "206,-42,304", "12,214,118"),
            collision_child("Collision_Porch_FrontDeck", "0,240,26", "460,72,20"),
            collision_child("Collision_Porch_SideDeck", "-276,20,26", "44,210,20"),
            collision_child("Collision_Porch_FrontRail_West", "-162,270,88", "106,10,34"),
            collision_child("Collision_Porch_FrontRail_East", "162,270,88", "106,10,34"),
            collision_child("Collision_InteriorCover_KitchenWall", "74,28,112", "14,220,205"),
            collision_child("Collision_InteriorCover_LivingWall", "-96,-32,112", "170,14,205"),
            collision_child("Collision_InteriorCover_Crate_01", "-138,60,52", "62,44,64"),
            collision_child("Collision_InteriorCover_Crate_02", "-42,76,52", "62,44,64"),
            collision_child("Collision_InteriorCover_Crate_03", "116,-44,52", "62,44,64"),
            collision_child("Collision_InteriorCover_CellarSupply", "-156,76,-72", "96,52,60"),
            collision_child("Collision_RoofCover_FightingPosition_Front", "108,-72,420", "132,16,52"),
            collision_child("Collision_RoofCover_FightingPosition_Side", "180,-8,420", "16,112,52"),
            collision_child("Collision_RoofCover_LowWall", "72,-154,414", "152,14,42"),
            collision_child("Collision_Stairs_Down", "180,138,-40", "92,92,120"),
            ladder_child("Ladder_To_Loft", "-170,-170,26", "0,0,110", "36,36,220", "0,54,220"),
            ladder_child("Ladder_To_Roof", "-118,-104,244", "0,0,73", "34,34,146", "0,54,146"),
            trigger_child("Zone_Foyer", "0,166,86", "145,84,138"),
            trigger_child("Zone_LivingArea", "-92,-24,104", "220,190,160"),
            trigger_child("Zone_Kitchen", "120,42,104", "180,180,160"),
            trigger_child("Zone_Basement", "-92,12,-72", "300,245,110"),
            trigger_child("Zone_Loft", "-22,-20,284", "360,285,92"),
            trigger_child("Zone_Roof", "0,-48,430", "420,300,110"),
            trigger_child("Zone_Porch", "0,248,78", "500,112,126"),
        ]
    )
    return children


def small_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Small", "models/house_small.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Ground", "0,0,8", "304,220,16"),
            collision_child("Collision_Floor_Loft", "-28,-32,206", "196,136,16"),
            collision_child("Collision_Roof_Main", "-12,0,330", "350,260,34"),
            collision_child("Collision_Porch_Deck", "-54,148,22", "188,58,18"),
            collision_child("Collision_Porch_Rail_Left", "-98,174,72", "64,9,28"),
            collision_child("Collision_LeanTo_Floor", "170,38,12", "56,126,14"),
            collision_child("Collision_LeanTo_Wall_East", "204,38,76", "10,126,128"),
            collision_child("Collision_LeanTo_Wall_North", "170,-28,76", "56,10,128"),
            collision_child("Collision_Wall_North_Left", "-88,-114,104", "116,12,192"),
            collision_child("Collision_Wall_North_Right", "94,-114,104", "112,12,192"),
            collision_child("Collision_Wall_South_Left", "-108,114,104", "76,12,192"),
            collision_child("Collision_Wall_South_Right", "104,114,104", "88,12,192"),
            collision_child("Collision_Wall_West", "-154,0,104", "12,220,192"),
            collision_child("Collision_Wall_East_Back", "154,-54,104", "12,112,192"),
            collision_child("Collision_Wall_East_Front", "154,70,104", "12,76,192"),
            collision_child("Collision_Wall_Loft_North", "-28,-118,258", "190,10,92"),
            collision_child("Collision_Wall_Loft_West", "-130,-32,258", "10,136,92"),
            collision_child("Collision_InteriorCover_HalfWall", "38,18,86", "12,138,140"),
            collision_child("Collision_InteriorCover_Crate", "-78,30,48", "58,42,56"),
            collision_child("Collision_InteriorCover_LeanToBlock", "202,80,50", "42,42,62"),
            collision_child("Collision_RoofCover_LowCover", "54,-84,322", "92,14,38"),
            collision_child("Collision_RoofCover_Bag", "12,-88,342", "74,18,16"),
            ladder_child("Ladder_To_Loft", "-94,-78,18", "0,0,94", "32,34,188", "0,50,188"),
            ladder_child("Ladder_To_Roof", "-72,-82,212", "0,0,52", "30,32,104", "0,48,104"),
            trigger_child("Zone_Entry", "-54,110,72", "116,70,116"),
            trigger_child("Zone_MainRoom", "-42,-6,90", "190,180,138"),
            trigger_child("Zone_SideRoom", "118,38,82", "112,130,120"),
            trigger_child("Zone_Loft", "-28,-32,234", "196,136,72"),
            trigger_child("Zone_Roof", "-12,-18,334", "240,190,82"),
            trigger_child("Zone_Porch", "-54,148,70", "188,72,108"),
        ]
    )
    return children


def prefab_payload(name: str, children: list[dict[str, Any]], existing_path: Path) -> dict[str, Any]:
    existing = load_json(existing_path) if existing_path.exists() else {}
    root = (existing.get("RootObject") or {}).copy()
    root_guid = root.get("__guid", stable_guid(name, "root"))
    root = {
        "__guid": root_guid,
        "Flags": root.get("Flags", 0),
        "Name": name,
        "Enabled": True,
        "NetworkMode": root.get("NetworkMode", 2),
        "Components": root.get("Components", []),
        "Children": children,
    }
    payload = {"RootObject": root}
    for key in ("ShowInMenu", "MenuPath", "MenuIcon", "DontBreakAsTemplate", "ResourceVersion", "__references", "__version", "Meta"):
        if key in existing:
            payload[key] = existing[key]
    if "Meta" not in payload and name == "House_Large":
        payload["Meta"] = {"Version": 2}
    return payload


def write_prefabs() -> None:
    write_json(PREFAB_DIR / "House_Large.prefab", prefab_payload("House_Large", large_house_children(), PREFAB_DIR / "House_Large.prefab"))
    write_json(PREFAB_DIR / "House_Small.prefab", prefab_payload("House_Small", small_house_children(), PREFAB_DIR / "House_Small.prefab"))


def config_payload(asset_name: str, combined_name: str, root_object: str, material_remap: dict[str, str]) -> dict[str, Any]:
    return {
        "source_blend": f"environment_model.blend/{asset_name}.blend",
        "root_object": root_object,
        "target_fbx": f"Assets/models/{asset_name}.fbx",
        "target_vmdl": f"Assets/models/{asset_name}.vmdl",
        "model_resource_path": f"models/{asset_name}.vmdl",
        "combine_meshes": True,
        "combined_object_name": combined_name,
        "material_remap": material_remap,
        "vmdl_use_global_default": False,
        "strict_vmdl_material_sources": True,
        "verify_fbx": True,
        "required_object": [combined_name],
        "object_type": ["EMPTY", "MESH"],
        "global_scale": 0.0254,
        "axis_forward": "-Y",
        "axis_up": "Z",
    }


def write_configs() -> None:
    write_json(SCRIPTS_DIR / "house_large_asset_pipeline.json", config_payload("house_large", "HouseLargeMesh", "HouseLarge_Root", HOUSE_LARGE_MATERIAL_REMAP))
    write_json(SCRIPTS_DIR / "house_small_asset_pipeline.json", config_payload("house_small", "HouseSmallMesh", "HouseSmall_Root", HOUSE_SMALL_MATERIAL_REMAP))


def freshen_guids(node: dict[str, Any], prefix: str, path: str = "") -> dict[str, Any]:
    clone = copy.deepcopy(node)
    name = clone.get("Name", "node")
    current_path = f"{path}/{name}"
    if "__guid" in clone:
        clone["__guid"] = stable_guid(prefix, current_path, "go")
    for index, component in enumerate(clone.get("Components", []) or []):
        if "__guid" in component:
            component["__guid"] = stable_guid(prefix, current_path, f"component-{index}", component.get("__type", "component"))
    clone["Children"] = [freshen_guids(child, prefix, current_path) for child in clone.get("Children", []) or []]
    return clone


def update_scene() -> None:
    scene = load_json(SCENE_PATH)
    replacements = {
        "House_Large": large_house_children(),
        "House_Small": small_house_children(),
    }
    changed = 0

    def visit(node: dict[str, Any]) -> None:
        nonlocal changed
        name = str(node.get("Name", ""))
        for building, children in replacements.items():
            if name.startswith(f"{building}_"):
                prefix = f"scene:{node.get('__guid', name)}:{building}"
                node["Children"] = [freshen_guids(child, prefix) for child in children]
                changed += 1
                return
        for child in node.get("Children", []) or []:
            if isinstance(child, dict):
                visit(child)

    for child in scene.get("GameObjects", []) or []:
        if isinstance(child, dict):
            visit(child)
    if "RootObject" in scene and isinstance(scene["RootObject"], dict):
        visit(scene["RootObject"])

    if changed == 0:
        raise RuntimeError("No House_Large_* or House_Small_* scene instances were found.")
    write_json(SCENE_PATH, scene)
    print(f"Updated {changed} scene building instance(s).")


def generate_legacy_blends() -> None:
    try:
        import bpy
        from mathutils import Vector
    except ImportError as exc:
        raise RuntimeError("--generate-blends must run inside Blender") from exc

    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    def reset_scene() -> None:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()

    active_root = {"object": None}

    def create_root(name: str):
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 42.0
        root["sbox_asset_root"] = True
        root["sbox_asset_category"] = "environment"
        bpy.context.scene.collection.objects.link(root)
        active_root["object"] = root
        return root

    def material(name: str):
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = MATERIAL_COLORS[name]
        return mat

    def assign_uvs(obj) -> None:
        mesh = obj.data
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        uv_layer = mesh.uv_layers.active.data
        for poly in mesh.polygons:
            normal = poly.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                if axis == 0:
                    uv_layer[loop_index].uv = (co.y * 0.03, co.z * 0.03)
                elif axis == 1:
                    uv_layer[loop_index].uv = (co.x * 0.03, co.z * 0.03)
                else:
                    uv_layer[loop_index].uv = (co.x * 0.03, co.y * 0.03)

    def box(name: str, center: tuple[float, float, float], size: tuple[float, float, float], mat_name: str):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
        obj = bpy.context.view_layer.objects.active
        obj.name = name
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        obj.dimensions = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.data.materials.append(material(mat_name))
        assign_uvs(obj)
        if min(size) >= 4:
            bevel_width = min(3.0, min(size) * 0.18)
            bevel = obj.modifiers.new("Small bevels for readable edges", "BEVEL")
            bevel.width = bevel_width
            bevel.segments = 1
            bevel.affect = "EDGES"
            obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        return obj

    def roof(name: str, width: float, depth: float, eave_z: float, ridge_z: float, mat_name: str):
        hw = width * 0.5
        hd = depth * 0.5
        verts = [
            (-hw, -hd, eave_z),
            (0, -hd, ridge_z),
            (hw, -hd, eave_z),
            (-hw, hd, eave_z),
            (0, hd, ridge_z),
            (hw, hd, eave_z),
        ]
        faces = [(0, 1, 4, 3), (1, 2, 5, 4), (0, 3, 5, 2), (0, 2, 1), (3, 4, 5)]
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        obj.data.materials.append(material(mat_name))
        assign_uvs(obj)
        bevel = obj.modifiers.new("Small bevels for readable roof edges", "BEVEL")
        bevel.width = 2.0
        bevel.segments = 1
        bevel.affect = "EDGES"
        obj.modifiers.new("Weighted roof normals", "WEIGHTED_NORMAL")
        return obj

    def ladder(name: str, x: float, y: float, z: float, height: float, mat_name: str):
        objs = [
            box(f"{name}_Rail_L", (x - 7, y, z + height * 0.5), (3, 4, height), mat_name),
            box(f"{name}_Rail_R", (x + 7, y, z + height * 0.5), (3, 4, height), mat_name),
        ]
        rung_count = max(4, int(height / 32))
        for index in range(rung_count):
            rz = z + 24 + index * ((height - 48) / max(1, rung_count - 1))
            objs.append(box(f"{name}_Rung_{index + 1:02d}", (x, y - 1, rz), (18, 3, 3), mat_name))
        return objs

    def save_current(path: Path) -> None:
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        print(f"Saved {path}")

    def make_large() -> None:
        reset_scene()
        create_root("HouseLarge_Root")
        box("Floor_Basement", (0, 0, -170), (240, 240, 20), "Material_Concrete")
        box("Floor_Ground", (0, 0, -2.211), (240, 240, 20), "Material_Concrete")
        box("Basement_Wall_North", (0, -125, -76.105), (240, 10, 167.789), "Material_Concrete")
        box("Basement_Wall_South", (0, 125, -76.105), (240, 10, 167.789), "Material_Concrete")
        box("Basement_Wall_West", (-125, 0, -76.105), (10, 240, 167.789), "Material_Concrete")
        box("Basement_Wall_East_A", (125, -70, -76.105), (10, 100, 167.789), "Material_Concrete")
        box("Basement_Wall_East_B", (125, 70, -76.105), (10, 100, 167.789), "Material_Concrete")
        for name, center, size in [
            ("Wall_South_Left", (-76, 125, 135.635), (88, 10, 255.692)),
            ("Wall_South_Right", (76, 125, 135.635), (88, 10, 255.692)),
            ("Wall_South_Lintel", (0, 125, 211.741), (64, 10, 103.482)),
            ("Wall_North_Left", (-80, -125, 135.635), (80, 10, 255.692)),
            ("Wall_North_Right", (80, -125, 135.635), (80, 10, 255.692)),
            ("Wall_North_Sill", (0, -125, 47.895), (80, 10, 80.211)),
            ("Wall_North_Header", (0, -125, 211.741), (80, 10, 103.482)),
            ("Wall_West_Lower", (-125, -80, 135.635), (10, 80, 255.692)),
            ("Wall_West_Upper", (-125, 80, 135.635), (10, 80, 255.692)),
            ("Wall_West_Sill", (-125, 0, 47.895), (10, 80, 80.211)),
            ("Wall_West_Header", (-125, 0, 211.741), (10, 80, 103.482)),
            ("Wall_East_Lower", (125, -80, 135.635), (10, 80, 255.692)),
            ("Wall_East_Upper", (125, 80, 135.635), (10, 80, 255.692)),
            ("Wall_East_Sill", (125, 0, 47.895), (10, 80, 80.211)),
            ("Wall_East_Header", (125, 0, 211.741), (10, 80, 103.482)),
        ]:
            box(name, center, size, "Material_Brick")
        for name, center, size in [
            ("Upper_Wall_South_Left", (-73, 115, 370.982), (74, 10, 175)),
            ("Upper_Wall_South_Right", (73, 115, 370.982), (74, 10, 175)),
            ("Upper_Wall_South_Header", (0, 115, 429.241), (72, 10, 58.482)),
            ("Upper_Wall_North_Left", (-73, -115, 370.982), (74, 10, 175)),
            ("Upper_Wall_North_Right", (73, -115, 370.982), (74, 10, 175)),
            ("Upper_Wall_North_Sill", (0, -115, 311.741), (72, 10, 56.518)),
            ("Upper_Wall_North_Header", (0, -115, 429.241), (72, 10, 58.482)),
            ("Upper_Wall_West_Lower", (-115, -73, 370.982), (10, 74, 175)),
            ("Upper_Wall_West_Upper", (-115, 73, 370.982), (10, 74, 175)),
            ("Upper_Wall_West_Sill", (-115, 0, 311.741), (10, 72, 56.518)),
            ("Upper_Wall_West_Header", (-115, 0, 429.241), (10, 72, 58.482)),
            ("Upper_Wall_East_Lower", (115, -73, 370.982), (10, 74, 175)),
            ("Upper_Wall_East_Upper", (115, 73, 370.982), (10, 74, 175)),
            ("Upper_Wall_East_Sill", (115, 0, 311.741), (10, 72, 56.518)),
            ("Upper_Wall_East_Header", (115, 0, 429.241), (10, 72, 58.482)),
            ("Upper_Window_North_TopTrim", (0, -122, 392), (84, 4, 8)),
            ("Upper_Window_North_BottomTrim", (0, -122, 354), (84, 4, 8)),
            ("Upper_Window_East_TopTrim", (122, 0, 392), (4, 84, 8)),
            ("Upper_Window_East_BottomTrim", (122, 0, 354), (4, 84, 8)),
        ]:
            box(name, center, size, "Material_Brick" if "Window" not in name else "Material_Glass")
        box("Wall_Interior_Left", (-65, 25, 135.635), (110, 10, 255.692), "Material_Wood")
        box("Wall_Interior_Right", (85, 25, 135.635), (70, 10, 255.692), "Material_Wood")
        for name, center, size in [
            ("Door_Frame_Front_L", (-32.747, 116.887, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Front_R", (31.759, 116.887, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Back_L", (47.424, 20.731, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Back_R", (91.656, 20.731, 62.789), (5.529, 7.326, 150)),
            ("Window_Frame_North_Top", (0, -132, 150), (92, 4, 8)),
            ("Window_Frame_North_Bottom", (0, -132, 100), (92, 4, 8)),
            ("Window_Frame_West_Top", (-132, 0, 150), (4, 92, 8)),
            ("Window_Frame_West_Bottom", (-132, 0, 100), (4, 92, 8)),
            ("Window_Frame_East_Top", (132, 0, 150), (4, 92, 8)),
            ("Window_Frame_East_Bottom", (132, 0, 100), (4, 92, 8)),
            ("Corner_Post_SW", (-132, 132, 150), (12, 12, 300)),
            ("Corner_Post_SE", (132, 132, 150), (12, 12, 300)),
            ("Corner_Post_NW", (-132, -132, 150), (12, 12, 300)),
            ("Corner_Post_NE", (132, -132, 150), (12, 12, 300)),
            ("Upper_Corner_Post_SW", (-106, 106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_SE", (106, 106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_NW", (-106, -106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_NE", (106, -106, 392), (10, 10, 190)),
        ]:
            box(name, center, size, "Material_Glass" if "Window" in name else "Material_Wood")
        box("Stairs_Down", (80, 80, -76.105), (42, 58, 167.789), "Material_Concrete")
        box("Floor_Loft", (0, 0, 273.482), (220, 220, 20), "Material_Wood")
        box("Loft_Safety_Rail", (0, -112, 303.482), (220, 6, 36), "Material_Wood")
        ladder("Ladder_To_Loft", -50, -104, 7.789, 275.692, "Material_Metal")
        ladder("Ladder_To_Roof", -50, -54, 283.482, 175, "Material_Metal")
        roof("Roof_Sloped", 313.786, 308.094, 458.482, 520.661, "Material_Metal")
        for name, center, size in [
            ("Parapet_North", (0, -135, 535), (270, 10, 45)),
            ("Parapet_South", (0, 135, 535), (270, 10, 45)),
            ("Parapet_East", (135, 0, 535), (10, 270, 45)),
            ("Parapet_West", (-135, 0, 535), (10, 270, 45)),
            ("Roof_Ridge", (0, 0, 524.661), (16, 260, 8)),
        ]:
            box(name, center, size, "Material_Metal")
        save_current(BLEND_DIR / "house_large.blend")

    def make_small() -> None:
        reset_scene()
        create_root("HouseSmall_Root")
        box("Floor_Ground", (0, 0, 10), (180, 180, 20), "Material_Concrete")
        for name, center, size in [
            ("Wall_South_Left", (-60, 90, 110), (60, 10, 220)),
            ("Wall_South_Right", (60, 90, 110), (60, 10, 220)),
            ("Wall_South_Lintel", (0, 90, 185), (60, 10, 70)),
            ("Wall_North_Left", (-62, -90, 110), (56, 10, 220)),
            ("Wall_North_Right", (62, -90, 110), (56, 10, 220)),
            ("Wall_North_Sill", (0, -90, 42), (68, 10, 84)),
            ("Wall_North_Header", (0, -90, 185), (68, 10, 70)),
            ("Wall_West_Lower", (-90, -55, 110), (10, 70, 220)),
            ("Wall_West_Upper", (-90, 55, 110), (10, 70, 220)),
            ("Wall_West_Sill", (-90, 0, 42), (10, 70, 84)),
            ("Wall_West_Header", (-90, 0, 185), (10, 70, 70)),
            ("Wall_East", (90, 0, 110), (10, 180, 220)),
        ]:
            box(name, center, size, "Material_Brick")
        for name, center, size in [
            ("Upper_Wall_South_Left", (-48, 74, 295), (42, 10, 110)),
            ("Upper_Wall_South_Right", (48, 74, 295), (42, 10, 110)),
            ("Upper_Wall_South_Header", (0, 74, 328), (54, 10, 44)),
            ("Upper_Wall_North_Left", (-48, -74, 295), (42, 10, 110)),
            ("Upper_Wall_North_Right", (48, -74, 295), (42, 10, 110)),
            ("Upper_Wall_North_Sill", (0, -74, 260), (54, 10, 38)),
            ("Upper_Wall_North_Header", (0, -74, 328), (54, 10, 44)),
            ("Upper_Wall_West_Lower", (-74, -46, 295), (10, 46, 110)),
            ("Upper_Wall_West_Upper", (-74, 46, 295), (10, 46, 110)),
            ("Upper_Wall_West_Sill", (-74, 0, 260), (10, 50, 38)),
            ("Upper_Wall_West_Header", (-74, 0, 328), (10, 50, 44)),
            ("Upper_Wall_East", (74, 0, 295), (10, 145, 110)),
            ("Upper_Corner_Post_SW", (-76, 76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_SE", (76, 76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_NW", (-76, -76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_NE", (76, -76, 300), (10, 10, 120)),
        ]:
            box(name, center, size, "Material_Brick")
        box("Wall_Interior", (25, 12, 110), (85, 10, 200), "Material_Wood")
        for name, center, size in [
            ("Door_Frame_Front_L", (-32, 90, 72), (6, 8, 144)),
            ("Door_Frame_Front_R", (32, 90, 72), (6, 8, 144)),
            ("Window_Frame_North_Top", (0, -94, 158), (68, 4, 8)),
            ("Window_Frame_North_Bottom", (0, -94, 78), (68, 4, 8)),
            ("Window_Frame_West_Top", (-94, 0, 158), (4, 68, 8)),
            ("Window_Frame_West_Bottom", (-94, 0, 78), (4, 68, 8)),
            ("Corner_Post_SW", (-92, 92, 112), (10, 10, 224)),
            ("Corner_Post_SE", (92, 92, 112), (10, 10, 224)),
            ("Corner_Post_NW", (-92, -92, 112), (10, 10, 224)),
            ("Corner_Post_NE", (92, -92, 112), (10, 10, 224)),
        ]:
            box(name, center, size, "Material_Glass" if "Window" in name else "Material_Wood")
        box("Floor_Loft", (0, -38, 240), (110, 95, 18), "Material_Wood")
        box("Loft_Safety_Rail", (0, -88, 270), (110, 6, 36), "Material_Wood")
        ladder("Ladder_To_Loft", 0, -82, 0, 242, "Material_Metal")
        ladder("Ladder_To_Roof", 0, -35, 240, 140, "Material_Metal")
        roof("Roof_Sloped", 205, 205, 350, 408, "Material_Metal")
        for name, center, size in [
            ("Parapet_North", (0, -98, 392), (195, 10, 42)),
            ("Parapet_South", (0, 98, 392), (195, 10, 42)),
            ("Parapet_East", (98, 0, 392), (10, 195, 42)),
            ("Parapet_West", (-98, 0, 392), (10, 195, 42)),
            ("Roof_Ridge", (0, 0, 410), (14, 205, 8)),
        ]:
            box(name, center, size, "Material_Metal")
        save_current(BLEND_DIR / "house_small.blend")

    make_large()
    make_small()


def generate_blends() -> None:
    try:
        import bpy
    except ImportError as exc:
        raise RuntimeError("--generate-blends must run inside Blender") from exc

    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    active_root = {"object": None}

    def reset_scene() -> None:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()
        for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
            for datablock in list(datablocks):
                if datablock.users == 0:
                    datablocks.remove(datablock)

    def create_root(name: str):
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 48.0
        root["sbox_asset_root"] = True
        root["sbox_asset_category"] = "environment"
        bpy.context.scene.collection.objects.link(root)
        active_root["object"] = root
        return root

    def material(name: str):
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = MATERIAL_COLORS[name]
        if "Glass" in name:
            mat.use_nodes = False
            mat.blend_method = "BLEND"
        return mat

    def assign_uvs(obj) -> None:
        mesh = obj.data
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        uv_layer = mesh.uv_layers.active.data
        for poly in mesh.polygons:
            normal = poly.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                if axis == 0:
                    uv_layer[loop_index].uv = (co.y * 0.018, co.z * 0.018)
                elif axis == 1:
                    uv_layer[loop_index].uv = (co.x * 0.018, co.z * 0.018)
                else:
                    uv_layer[loop_index].uv = (co.x * 0.018, co.y * 0.018)

    def finalize_mesh(obj, mat_name: str, bevel_width: float = 1.5):
        obj.data.materials.append(material(mat_name))
        assign_uvs(obj)
        if bevel_width > 0:
            bevel = obj.modifiers.new("Readable construction-edge bevel", "BEVEL")
            bevel.width = bevel_width
            bevel.segments = 1
            bevel.affect = "EDGES"
        obj.modifiers.new("Weighted construction normals", "WEIGHTED_NORMAL")
        return obj

    def box(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        mat_name: str,
        rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
        bevel_width: float | None = None,
    ):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rotation)
        obj = bpy.context.view_layer.objects.active
        obj.name = name
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        obj.dimensions = size
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        if bevel_width is None:
            bevel_width = min(2.4, max(0.35, min(size) * 0.18))
        return finalize_mesh(obj, mat_name, bevel_width)

    def gable_roof(
        name: str,
        center: tuple[float, float, float],
        width: float,
        depth: float,
        eave_z: float,
        ridge_z: float,
        mat_name: str,
        ridge_axis: str = "Y",
    ):
        cx, cy, _ = center
        hw = width * 0.5
        hd = depth * 0.5
        if ridge_axis == "Y":
            verts = [
                (cx - hw, cy - hd, eave_z),
                (cx, cy - hd, ridge_z),
                (cx + hw, cy - hd, eave_z),
                (cx - hw, cy + hd, eave_z),
                (cx, cy + hd, ridge_z),
                (cx + hw, cy + hd, eave_z),
            ]
        else:
            verts = [
                (cx - hw, cy - hd, eave_z),
                (cx - hw, cy, ridge_z),
                (cx - hw, cy + hd, eave_z),
                (cx + hw, cy - hd, eave_z),
                (cx + hw, cy, ridge_z),
                (cx + hw, cy + hd, eave_z),
            ]
        faces = [(0, 1, 4, 3), (1, 2, 5, 4), (0, 3, 5, 2), (0, 2, 1), (3, 4, 5)]
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        return finalize_mesh(obj, mat_name, 2.4)

    def shed_roof(name: str, center: tuple[float, float, float], size: tuple[float, float, float], mat_name: str, high_side: str = "west"):
        cx, cy, cz = center
        sx, sy, sz = size
        x0, x1 = cx - sx * 0.5, cx + sx * 0.5
        y0, y1 = cy - sy * 0.5, cy + sy * 0.5
        low = cz - sz * 0.5
        high = cz + sz * 0.5
        if high_side == "west":
            verts = [(x0, y0, high), (x0, y1, high), (x1, y1, low), (x1, y0, low)]
        else:
            verts = [(x0, y0, low), (x0, y1, low), (x1, y1, high), (x1, y0, high)]
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        return finalize_mesh(obj, mat_name, 1.6)

    def ladder(prefix: str, x: float, y: float, z: float, height: float, mat_name: str, rung_count: int) -> None:
        box(f"{prefix}_Rail_L", (x - 8, y, z + height * 0.5), (4, 5, height), mat_name)
        box(f"{prefix}_Rail_R", (x + 8, y, z + height * 0.5), (4, 5, height), mat_name)
        for index in range(rung_count):
            rz = z + 22 + index * ((height - 44) / max(1, rung_count - 1))
            box(f"{prefix}_Rung_{index + 1:02d}", (x, y - 1, rz), (22, 4, 4), mat_name)

    def window_y(prefix: str, x: float, y: float, z: float, width: float, height: float, house_prefix: str) -> None:
        trim = f"M_{house_prefix}_Trim"
        glass = f"M_{house_prefix}_Glass"
        patch = f"M_{house_prefix}_TacticalPatch"
        box(f"{prefix}_Glass", (x, y, z), (width - 14, 3, height - 16), glass, bevel_width=0.35)
        box(f"{prefix}_Trim_Top", (x, y, z + height * 0.5), (width, 5, 7), trim)
        box(f"{prefix}_Trim_Bottom", (x, y, z - height * 0.5), (width, 5, 7), trim)
        box(f"{prefix}_Trim_Left", (x - width * 0.5, y, z), (7, 5, height), trim)
        box(f"{prefix}_Trim_Right", (x + width * 0.5, y, z), (7, 5, height), trim)
        box(f"{prefix}_Board_Diagonal_A", (x - width * 0.12, y + 1, z + 4), (width * 0.78, 5, 7), patch, rotation=(0.0, 0.0, math.radians(18)))
        box(f"{prefix}_Board_Diagonal_B", (x + width * 0.12, y + 1, z - 8), (width * 0.62, 5, 7), patch, rotation=(0.0, 0.0, math.radians(-14)))

    def window_x(prefix: str, x: float, y: float, z: float, width: float, height: float, house_prefix: str) -> None:
        trim = f"M_{house_prefix}_Trim"
        glass = f"M_{house_prefix}_Glass"
        patch = f"M_{house_prefix}_TacticalPatch"
        box(f"{prefix}_Glass", (x, y, z), (3, width - 14, height - 16), glass, bevel_width=0.35)
        box(f"{prefix}_Trim_Top", (x, y, z + height * 0.5), (5, width, 7), trim)
        box(f"{prefix}_Trim_Bottom", (x, y, z - height * 0.5), (5, width, 7), trim)
        box(f"{prefix}_Trim_Left", (x, y - width * 0.5, z), (5, 7, height), trim)
        box(f"{prefix}_Trim_Right", (x, y + width * 0.5, z), (5, 7, height), trim)
        box(f"{prefix}_Board_Diagonal_A", (x + 1, y - width * 0.12, z + 4), (5, width * 0.78, 7), patch, rotation=(0.0, 0.0, math.radians(-18)))
        box(f"{prefix}_Board_Diagonal_B", (x + 1, y + width * 0.12, z - 8), (5, width * 0.62, 7), patch, rotation=(0.0, 0.0, math.radians(14)))

    def save_current(path: Path) -> None:
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        print(f"Saved {path}")

    def make_large() -> None:
        reset_scene()
        create_root("HouseLarge_Root")
        hp = "HouseLarge"
        siding = "M_HouseLarge_Siding"
        roof = "M_HouseLarge_Roof"
        foundation = "M_HouseLarge_Foundation"
        trim = "M_HouseLarge_Trim"
        wood = "M_HouseLarge_InteriorWood"
        metal = "M_HouseLarge_Metal"
        patch = "M_HouseLarge_TacticalPatch"
        dirt = "M_HouseLarge_DirtMask"

        box("Large_Foundation_MainSlab", (0, 0, -18), (520, 396, 32), foundation)
        box("Large_Foundation_NorthBand", (0, -204, 26), (520, 16, 68), foundation)
        box("Large_Foundation_SouthBand", (0, 204, 26), (520, 16, 68), foundation)
        box("Large_Foundation_WestBand", (-260, 0, 26), (16, 396, 68), foundation)
        box("Large_Foundation_EastBand", (260, 0, 26), (16, 396, 68), foundation)
        box("Large_Cellar_Floor", (-92, 12, -118), (300, 245, 18), foundation)
        box("Large_Cellar_Wall_North", (-92, -116, -62), (300, 12, 112), foundation)
        box("Large_Cellar_Wall_West", (-248, 12, -62), (12, 245, 112), foundation)
        box("Large_Cellar_Wall_SouthLow", (-92, 136, -62), (210, 12, 112), foundation)
        box("Large_Cellar_Entry_HatchFrame", (190, 198, 42), (118, 18, 16), trim)
        for index in range(5):
            box(f"Large_Cellar_Stair_Tread_{index + 1:02d}", (180, 174 - index * 18, -90 + index * 25), (84, 22, 9), foundation)

        box("Large_GroundFloor_Floor", (0, 0, 6), (500, 388, 18), wood)
        for name, center, size in [
            ("Large_GroundFloor_Wall_North_Left", (-150, -198, 118), (190, 14, 224)),
            ("Large_GroundFloor_Wall_North_Right", (152, -198, 118), (184, 14, 224)),
            ("Large_GroundFloor_Wall_North_Header", (0, -198, 204), (110, 14, 52)),
            ("Large_GroundFloor_Wall_South_Left", (-176, 198, 118), (150, 14, 224)),
            ("Large_GroundFloor_Wall_South_Right", (168, 198, 118), (156, 14, 224)),
            ("Large_GroundFloor_Wall_South_DoorHeader", (0, 198, 214), (116, 14, 40)),
            ("Large_GroundFloor_Wall_West_Lower", (-264, -90, 118), (14, 158, 224)),
            ("Large_GroundFloor_Wall_West_Upper", (-264, 116, 118), (14, 176, 224)),
            ("Large_GroundFloor_Wall_East_Lower", (264, -116, 118), (14, 128, 224)),
            ("Large_GroundFloor_Wall_East_Upper", (264, 102, 118), (14, 180, 224)),
        ]:
            box(name, center, size, siding)
        box("Large_GroundFloor_InteriorWall_Kitchen", (74, 28, 112), (14, 220, 205), wood)
        box("Large_GroundFloor_InteriorWall_Living", (-96, -32, 112), (170, 14, 205), wood)
        box("Large_GroundFloor_DoorFrame_Front_L", (-46, 208, 78), (8, 12, 156), trim)
        box("Large_GroundFloor_DoorFrame_Front_R", (46, 208, 78), (8, 12, 156), trim)
        box("Large_GroundFloor_DoorFrame_Back_L", (-48, -208, 78), (8, 12, 156), trim)
        box("Large_GroundFloor_DoorFrame_Back_R", (48, -208, 78), (8, 12, 156), trim)
        for side, y in [("North", -209.5), ("South", 209.5)]:
            box(f"Large_GroundFloor_WallTie_{side}_SillBand", (0, y, 48), (500, 4, 18), siding, bevel_width=0.45)
            box(f"Large_GroundFloor_WallTie_{side}_MidBatten", (0, y, 142), (500, 4, 10), siding, bevel_width=0.35)
            box(f"Large_GroundFloor_WallTie_{side}_FasciaBand", (0, y, 232), (500, 4, 24), siding, bevel_width=0.45)
        for side, x in [("West", -275.5), ("East", 275.5)]:
            box(f"Large_GroundFloor_WallTie_{side}_SillBand", (x, 0, 48), (4, 388, 18), siding, bevel_width=0.45)
            box(f"Large_GroundFloor_WallTie_{side}_MidBatten", (x, 0, 142), (4, 388, 10), siding, bevel_width=0.35)
            box(f"Large_GroundFloor_WallTie_{side}_FasciaBand", (x, 0, 232), (4, 388, 24), siding, bevel_width=0.45)
        for name, x, y in [
            ("SW", -275.5, 209.5),
            ("SE", 275.5, 209.5),
            ("NW", -275.5, -209.5),
            ("NE", 275.5, -209.5),
        ]:
            box(f"Large_GroundFloor_CornerPost_{name}", (x, y, 124), (18, 18, 240), trim)

        box("Large_Porch_FrontDeck", (0, 240, 26), (460, 72, 20), wood)
        box("Large_Porch_SideDeck", (-276, 20, 26), (44, 210, 20), wood)
        for index, x in enumerate([-220, -80, 80, 220]):
            box(f"Large_Porch_FrontPost_{index + 1:02d}", (x, 266, 104), (12, 12, 168), trim)
        box("Large_Porch_FrontRail_West", (-162, 270, 88), (106, 10, 34), trim)
        box("Large_Porch_FrontRail_East", (162, 270, 88), (106, 10, 34), trim)
        for index in range(3):
            box(f"Large_Porch_Steps_{index + 1:02d}", (0, 258 + index * 12, 14 - index * 7), (118 + index * 14, 16, 8), foundation)
        box("Large_Porch_Roof_MetalAwning", (0, 236, 244), (500, 94, 14), roof, rotation=(math.radians(-6), 0.0, 0.0))

        window_y("Large_Window_Reinforced_North_Main", -72, -207, 126, 88, 92, hp)
        window_y("Large_Window_Reinforced_North_Kitchen", 142, -207, 124, 78, 86, hp)
        window_y("Large_Window_Reinforced_South_Left", -168, 207, 126, 76, 90, hp)
        window_y("Large_Window_Reinforced_South_Right", 166, 207, 126, 76, 90, hp)
        window_x("Large_Window_Reinforced_West_Main", -273, -22, 126, 92, 92, hp)
        window_x("Large_Window_Reinforced_East_Utility", 273, 16, 124, 86, 86, hp)

        box("Large_Loft_Floor_Partial", (-22, -20, 238), (360, 285, 18), wood)
        box("Large_Loft_Railing_Interior", (-20, 122, 270), (290, 8, 48), trim)
        box("Large_Loft_Wall_North_Left", (-118, -184, 304), (162, 12, 118), siding)
        box("Large_Loft_Wall_North_Right", (132, -184, 304), (144, 12, 118), siding)
        box("Large_Loft_Wall_West", (-206, -42, 304), (12, 214, 118), siding)
        box("Large_Loft_Wall_East", (206, -42, 304), (12, 214, 118), siding)
        box("Large_Loft_WallTie_North_SillBand", (0, -192, 264), (390, 4, 16), siding, bevel_width=0.45)
        box("Large_Loft_WallTie_North_FasciaBand", (0, -192, 354), (390, 4, 18), siding, bevel_width=0.45)
        box("Large_Loft_WallTie_West_FasciaBand", (-214, -42, 354), (4, 214, 18), siding, bevel_width=0.45)
        box("Large_Loft_WallTie_East_FasciaBand", (214, -42, 354), (4, 214, 18), siding, bevel_width=0.45)
        window_y("Large_Window_Reinforced_Loft_North", 0, -192, 316, 82, 58, hp)

        gable_roof("Large_Roof_MainGable", (0, 0, 0), 560, 418, 356, 458, roof, "Y")
        gable_roof("Large_Roof_CrossGable", (-30, 32, 0), 284, 470, 368, 442, roof, "X")
        box("Large_Roof_RidgeCap_Main", (0, 0, 463), (18, 392, 10), metal)
        box("Large_Roof_RidgeCap_Cross", (-30, 42, 447), (256, 16, 10), metal)
        box("Large_Roof_AccessHatch_Frame", (-112, -90, 386), (92, 66, 12), trim)
        box("Large_Roof_FightingPosition_Front", (108, -72, 420), (132, 16, 52), patch)
        box("Large_Roof_FightingPosition_Side", (180, -8, 420), (16, 112, 52), patch)
        box("Large_Roof_Gutter_North", (0, -214, 344), (540, 10, 12), metal)
        box("Large_Roof_Gutter_South", (0, 214, 344), (540, 10, 12), metal)
        box("Large_Roof_Downspout_SE", (246, 208, 166), (8, 8, 300), metal)

        ladder("Large_Ladder_To_Loft", (-170), -170, 26, 220, metal, 8)
        ladder("Large_Ladder_To_Roof", (-118), -104, 244, 146, metal, 5)
        for index, (x, y) in enumerate([(-138, 60), (-42, 76), (116, -44), (166, 92)]):
            box(f"Large_Cover_InteriorCrate_{index + 1:02d}", (x, y, 52), (62, 44, 64), wood)
        box("Large_Cover_RoofLowWall", (72, -154, 414), (152, 14, 42), patch)
        box("Large_Cover_CellarSupplyStack", (-156, 76, -72), (96, 52, 60), wood)
        box("Large_Tactical_TarpPatch_WestWall", (-275, 106, 156), (5, 116, 94), patch)
        box("Large_Tactical_WindowPlankBundle", (0, 215, 160), (118, 8, 24), patch)
        box("Large_Tactical_RoofSandbag_01", (34, -162, 445), (76, 20, 18), dirt)
        box("Large_Tactical_RoofSandbag_02", (106, -162, 448), (76, 20, 18), dirt)
        box("Large_Utility_Panel_EastWall", (274, 146, 118), (6, 42, 70), metal)
        box("Large_Utility_CableRun_East", (276, 86, 192), (5, 120, 5), metal)
        box("Large_Utility_Antenna_Mast", (28, -54, 512), (6, 6, 128), metal)
        box("Large_Utility_Antenna_Crossbar", (28, -54, 560), (70, 5, 5), metal)
        save_current(BLEND_DIR / "house_large.blend")

    def make_small() -> None:
        reset_scene()
        create_root("HouseSmall_Root")
        hp = "HouseSmall"
        siding = "M_HouseSmall_Siding"
        roof = "M_HouseSmall_Roof"
        foundation = "M_HouseSmall_Foundation"
        trim = "M_HouseSmall_Trim"
        wood = "M_HouseSmall_InteriorWood"
        metal = "M_HouseSmall_Metal"
        patch = "M_HouseSmall_TacticalPatch"
        dirt = "M_HouseSmall_DirtMask"

        box("Small_Foundation_MainSlab", (0, 0, -8), (320, 236, 22), foundation)
        for index, (x, y) in enumerate([(-135, -100), (135, -100), (-135, 100), (135, 100), (194, 20)]):
            box(f"Small_Foundation_Pier_{index + 1:02d}", (x, y, 24), (24, 24, 64), foundation)
        box("Small_MainRoom_Floor", (0, 0, 8), (304, 220, 16), wood)
        for name, center, size in [
            ("Small_MainRoom_Wall_North_Left", (-88, -114, 104), (116, 12, 192)),
            ("Small_MainRoom_Wall_North_Right", (94, -114, 104), (112, 12, 192)),
            ("Small_MainRoom_Wall_South_Left", (-108, 114, 104), (76, 12, 192)),
            ("Small_MainRoom_Wall_South_Right", (104, 114, 104), (88, 12, 192)),
            ("Small_MainRoom_Wall_West", (-154, 0, 104), (12, 220, 192)),
            ("Small_MainRoom_Wall_East_Back", (154, -54, 104), (12, 112, 192)),
            ("Small_MainRoom_Wall_East_Front", (154, 70, 104), (12, 76, 192)),
        ]:
            box(name, center, size, siding)
        box("Small_MainRoom_DoorFrame_Left", (-34, 122, 72), (8, 12, 144), trim)
        box("Small_MainRoom_DoorFrame_Right", (34, 122, 72), (8, 12, 144), trim)
        box("Small_MainRoom_InteriorHalfWall", (38, 18, 86), (12, 138, 140), wood)
        for side, y in [("North", -125.5), ("South", 125.5)]:
            box(f"Small_MainRoom_WallTie_{side}_SillBand", (0, y, 42), (304, 4, 16), siding, bevel_width=0.45)
            box(f"Small_MainRoom_WallTie_{side}_MidBatten", (0, y, 128), (304, 4, 9), siding, bevel_width=0.35)
            box(f"Small_MainRoom_WallTie_{side}_FasciaBand", (0, y, 206), (304, 4, 20), siding, bevel_width=0.45)
        for side, x in [("West", -165.5), ("East", 165.5)]:
            box(f"Small_MainRoom_WallTie_{side}_SillBand", (x, 0, 42), (4, 220, 16), siding, bevel_width=0.45)
            box(f"Small_MainRoom_WallTie_{side}_MidBatten", (x, 0, 128), (4, 220, 9), siding, bevel_width=0.35)
            box(f"Small_MainRoom_WallTie_{side}_FasciaBand", (x, 0, 206), (4, 220, 20), siding, bevel_width=0.45)
        for name, x, y in [
            ("SW", -165.5, 125.5),
            ("SE", 165.5, 125.5),
            ("NW", -165.5, -125.5),
            ("NE", 165.5, -125.5),
        ]:
            box(f"Small_MainRoom_CornerPost_{name}", (x, y, 106), (16, 16, 208), trim)

        box("Small_Porch_Deck", (-54, 148, 22), (188, 58, 18), wood)
        box("Small_Porch_Post_Left", (-134, 168, 88), (10, 10, 132), trim)
        box("Small_Porch_Post_Right", (20, 168, 88), (10, 10, 132), trim)
        box("Small_Porch_Rail_Left", (-98, 174, 72), (64, 9, 28), trim)
        box("Small_Porch_Steps_01", (-54, 188, 10), (92, 18, 8), foundation)
        box("Small_Porch_Steps_02", (-54, 204, 3), (108, 18, 8), foundation)
        box("Small_LeanTo_Floor", (170, 38, 12), (56, 126, 14), wood)
        box("Small_LeanTo_Wall_East", (204, 38, 76), (10, 126, 128), siding)
        box("Small_LeanTo_Wall_North", (170, -28, 76), (56, 10, 128), siding)
        box("Small_LeanTo_UtilityShelf", (174, 66, 70), (50, 22, 34), wood)
        shed_roof("Small_LeanTo_Roof_Shed", (172, 38, 170), (68, 148, 44), roof, "west")

        window_y("Small_Window_Reinforced_North_Main", -54, -122, 106, 72, 72, hp)
        window_x("Small_Window_Reinforced_West_Side", -162, -28, 106, 64, 72, hp)
        window_x("Small_Window_Reinforced_East_LeanTo", 208, 38, 92, 48, 58, hp)

        box("Small_Loft_Floor_Partial", (-28, -32, 206), (196, 136, 16), wood)
        box("Small_Loft_Railing", (-28, 36, 232), (170, 8, 38), trim)
        box("Small_Loft_Wall_North", (-28, -118, 258), (190, 10, 92), siding)
        box("Small_Loft_Wall_West", (-130, -32, 258), (10, 136, 92), siding)
        box("Small_Loft_WindowTrim", (-28, -125, 266), (72, 6, 46), trim)
        box("Small_Loft_WallTie_North_SillBand", (-28, -126, 224), (190, 4, 14), siding, bevel_width=0.45)
        box("Small_Loft_WallTie_North_FasciaBand", (-28, -126, 302), (190, 4, 16), siding, bevel_width=0.45)
        box("Small_Loft_WallTie_West_FasciaBand", (-136, -32, 302), (4, 136, 16), siding, bevel_width=0.45)

        gable_roof("Small_Roof_MainGable", (-12, 0, 0), 350, 260, 292, 366, roof, "Y")
        shed_roof("Small_Roof_PorchAwning", (-54, 148, 194), (210, 72, 28), roof, "west")
        box("Small_Roof_RidgeCap", (-12, 0, 370), (14, 228, 8), metal)
        box("Small_Roof_AccessHatch", (-72, -72, 308), (68, 54, 10), trim)
        box("Small_Roof_LowCover", (54, -84, 322), (92, 14, 38), patch)
        box("Small_Roof_Gutter_South", (-12, 134, 286), (340, 8, 10), metal)

        ladder("Small_Ladder_To_Loft", (-94), -78, 18, 188, metal, 6)
        ladder("Small_Ladder_To_Roof", (-72), -82, 212, 104, metal, 4)
        box("Small_Cover_MainRoom_Crate", (-78, 30, 48), (58, 42, 56), wood)
        box("Small_Cover_LeanTo_BarrelBlock", (202, 80, 50), (42, 42, 62), metal)
        box("Small_Cover_RoofBag", (12, -88, 342), (74, 18, 16), dirt)
        box("Small_Tactical_TarpPatch_South", (96, 132, 126), (76, 6, 70), patch)
        box("Small_Tactical_PlankBundle_North", (54, -133, 140), (92, 6, 18), patch)
        box("Small_Utility_Panel_LeanTo", (208, 100, 82), (6, 34, 58), metal)
        box("Small_Utility_CableRun", (170, 116, 174), (84, 5, 5), metal)
        box("Small_Utility_RoofVent", (96, 24, 350), (30, 30, 28), metal)
        save_current(BLEND_DIR / "house_small.blend")

    make_large()
    make_small()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate-blends", action="store_true")
    parser.add_argument("--write-materials", action="store_true")
    parser.add_argument("--write-configs", action="store_true")
    parser.add_argument("--write-prefabs", action="store_true")
    parser.add_argument("--update-scene", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    args = parse_args(argv)

    if args.generate_blends:
        generate_blends()
    if args.write_materials:
        write_materials()
    if args.write_configs:
        write_configs()
    if args.write_prefabs:
        write_prefabs()
    if args.update_scene:
        update_scene()

    if not any((args.generate_blends, args.write_materials, args.write_configs, args.write_prefabs, args.update_scene)):
        raise RuntimeError("No action specified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
