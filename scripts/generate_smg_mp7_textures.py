#!/usr/bin/env python3
"""Generate production texture maps for the SMG MP7 asset."""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
MATERIAL_DIR = ROOT / "Assets" / "materials" / "weapons"
SIZE = 512


def add_noise(image: Image.Image, amount: int, seed: int) -> Image.Image:
    rng = random.Random(seed)
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b = pixels[x, y]
            delta = rng.randint(-amount, amount)
            pixels[x, y] = (
                max(0, min(255, r + delta)),
                max(0, min(255, g + delta)),
                max(0, min(255, b + delta)),
            )
    return image


def save_color(name: str, base: tuple[int, int, int], accent: tuple[int, int, int], seed: int, kind: str) -> None:
    rng = random.Random(seed)
    image = Image.new("RGB", (SIZE, SIZE), base)
    draw = ImageDraw.Draw(image)

    if kind == "polymer":
        for y in range(22, SIZE, 38):
            draw.rectangle((0, y, SIZE, y + 7), fill=tuple(max(0, c - 22) for c in base))
        for x in range(-SIZE, SIZE, 32):
            draw.line((x, SIZE, x + SIZE, 0), fill=tuple(min(255, c + 13) for c in base), width=2)
    elif kind == "metal":
        for _ in range(90):
            y = rng.randrange(SIZE)
            x0 = rng.randrange(-64, SIZE)
            length = rng.randrange(60, 210)
            shade = rng.randrange(-22, 36)
            color = tuple(max(0, min(255, c + shade)) for c in base)
            draw.line((x0, y, x0 + length, y + rng.randrange(-4, 5)), fill=color, width=1)
        for x in range(42, SIZE, 96):
            draw.rectangle((x, 0, x + 3, SIZE), fill=tuple(max(0, c - 18) for c in base))
    elif kind == "accent":
        for y in range(0, SIZE, 64):
            draw.rectangle((0, y, SIZE, y + 20), fill=base)
            draw.rectangle((0, y + 20, SIZE, y + 28), fill=accent)
        for x in range(28, SIZE, 118):
            draw.rectangle((x, 0, x + 12, SIZE), fill=tuple(max(0, c - 20) for c in accent))
    elif kind == "sights":
        draw.rectangle((0, 0, SIZE, SIZE), fill=base)
        for y in range(36, SIZE, 96):
            draw.line((0, y, SIZE, y + 18), fill=accent, width=5)
        for _ in range(36):
            cx = rng.randrange(0, SIZE)
            cy = rng.randrange(0, SIZE)
            draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=(92, 210, 164))

    image = add_noise(image, 9, seed + 100).filter(ImageFilter.GaussianBlur(0.15))
    image.save(MATERIAL_DIR / name)


def save_scalar(name: str, base: int, seed: int, scratches: bool = False) -> None:
    rng = random.Random(seed)
    image = Image.new("L", (SIZE, SIZE), base)
    draw = ImageDraw.Draw(image)
    for _ in range(180):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        value = max(0, min(255, base + rng.randint(-18, 18)))
        draw.point((x, y), fill=value)
    if scratches:
        for _ in range(52):
            y = rng.randrange(SIZE)
            x0 = rng.randrange(-80, SIZE)
            draw.line((x0, y, x0 + rng.randrange(40, 170), y + rng.randrange(-3, 4)), fill=max(0, base - 34), width=1)
    image.filter(ImageFilter.GaussianBlur(0.35)).save(MATERIAL_DIR / name)


def write_vmat(
    name: str,
    color: str,
    rough: str,
    ao: str,
    metalness: float,
    roughness: float,
    tint: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> None:
    (MATERIAL_DIR / name).write_text(
        f'''"Layer0"
{{
\t"shader"\t\t"shaders/complex.shader"
\t"TextureColor"\t\t"materials/weapons/{color}"
\t"TextureNormal"\t\t"materials/default/default_normal.tga"
\t"TextureRoughness"\t\t"materials/weapons/{rough}"
\t"TextureAmbientOcclusion"\t\t"materials/weapons/{ao}"
\t"g_flModelTintAmount"\t\t"1.000000"
\t"g_vColorTint"\t\t"[{tint[0]:.6f} {tint[1]:.6f} {tint[2]:.6f} 0.000000]"
\t"g_flMetalness"\t\t"{metalness:.6f}"
\t"g_flRoughness"\t\t"{roughness:.6f}"
\t"g_flAmbientOcclusionDirectDiffuse"\t\t"0.280000"
\t"g_flAmbientOcclusionDirectSpecular"\t\t"0.180000"
\t"g_bFogEnabled"\t\t"1"
\t"g_vTexCoordScale"\t\t"[1.000 1.000]"
\t"g_vTexCoordOffset"\t\t"[0.000 0.000]"
\t"g_vTexCoordScrollSpeed"\t\t"[0.000 0.000]"
}}
''',
        encoding="utf-8",
    )


def main() -> int:
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)

    save_color("smg_polymer_color.png", (28, 31, 34), (55, 60, 64), 2101, "polymer")
    save_color("smg_metal_color.png", (52, 57, 61), (78, 86, 91), 2102, "metal")
    save_color("smg_accent_color.png", (122, 142, 138), (178, 136, 64), 2103, "accent")
    save_color("smg_sights_color.png", (20, 23, 23), (60, 154, 128), 2104, "sights")

    save_scalar("smg_polymer_rough.png", 184, 2201)
    save_scalar("smg_metal_rough.png", 118, 2202, scratches=True)
    save_scalar("smg_accent_rough.png", 144, 2203)
    save_scalar("smg_sights_rough.png", 82, 2204)

    save_scalar("smg_polymer_ao.png", 214, 2301)
    save_scalar("smg_metal_ao.png", 196, 2302)
    save_scalar("smg_accent_ao.png", 205, 2303)
    save_scalar("smg_sights_ao.png", 226, 2304)

    write_vmat("smg_polymer.vmat", "smg_polymer_color.png", "smg_polymer_rough.png", "smg_polymer_ao.png", 0.03, 0.72)
    write_vmat("smg_metal.vmat", "smg_metal_color.png", "smg_metal_rough.png", "smg_metal_ao.png", 0.78, 0.42)
    write_vmat("smg_accent.vmat", "smg_accent_color.png", "smg_accent_rough.png", "smg_accent_ao.png", 0.16, 0.48)
    write_vmat("smg_sights.vmat", "smg_sights_color.png", "smg_sights_rough.png", "smg_sights_ao.png", 0.08, 0.24)

    print(f"Generated SMG MP7 textures in {MATERIAL_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
