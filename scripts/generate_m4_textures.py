#!/usr/bin/env python3
"""Generate image-backed material maps for the M4 asset."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
MATERIAL_DIR = ROOT / "Assets" / "materials" / "weapons"
SIZE = 1024
RNG = random.Random(5561)


def clamp(value: int) -> int:
    return max(0, min(255, value))


def noise_texture(base: tuple[int, int, int], spread: int) -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE), base)
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = RNG.randint(-spread, spread)
            pixels[x, y] = tuple(clamp(channel + n) for channel in base)
    return image


def save_vmat(
    name: str,
    color: str,
    normal: str,
    rough: str,
    ao: str,
    metalness: float,
    roughness: float,
) -> None:
    (MATERIAL_DIR / f"{name}.vmat").write_text(
        f'''"Layer0"
{{
\t"shader"\t\t"shaders/complex.shader"
\t"TextureColor"\t\t"{color}"
\t"TextureNormal"\t\t"{normal}"
\t"TextureRoughness"\t\t"{rough}"
\t"TextureAmbientOcclusion"\t\t"{ao}"
\t"g_flModelTintAmount"\t\t"1.000000"
\t"g_vColorTint"\t\t"[1.000000 1.000000 1.000000 0.000000]"
\t"g_flMetalness"\t\t"{metalness:.6f}"
\t"g_flRoughness"\t\t"{roughness:.6f}"
\t"g_flAmbientOcclusionDirectDiffuse"\t\t"0.350000"
\t"g_flAmbientOcclusionDirectSpecular"\t\t"0.250000"
\t"g_bFogEnabled"\t\t"1"
\t"g_vTexCoordScale"\t\t"[1.000 1.000]"
\t"g_vTexCoordOffset"\t\t"[0.000 0.000]"
\t"g_vTexCoordScrollSpeed"\t\t"[0.000 0.000]"
}}
''',
        encoding="utf-8",
    )


def scratch_lines(draw: ImageDraw.ImageDraw, count: int, bright: tuple[int, int, int], dark: tuple[int, int, int]) -> None:
    for _ in range(count):
        x = RNG.randint(0, SIZE - 1)
        y = RNG.randint(0, SIZE - 1)
        length = RNG.randint(18, 170)
        angle = RNG.uniform(-0.14, 0.14)
        color = RNG.choice((*[bright] * 2, dark))
        alpha = RNG.randint(24, 90)
        x2 = x + int(math.cos(angle) * length)
        y2 = y + int(math.sin(angle) * length)
        draw.line((x, y, x2, y2), fill=(*color, alpha), width=RNG.choice([1, 1, 1, 2]))


def make_surface(prefix: str, base: tuple[int, int, int], spread: int, metal: bool, rough_base: int) -> None:
    color = noise_texture(base, spread)
    draw = ImageDraw.Draw(color, "RGBA")
    if metal:
        for y in range(0, SIZE, 9):
            shade = RNG.randint(-12, 22)
            draw.line((0, y, SIZE, y), fill=(clamp(base[0] + shade), clamp(base[1] + shade), clamp(base[2] + shade), 42), width=1)
        scratch_lines(draw, 420, (185, 186, 178), (10, 11, 12))
    else:
        for y in range(0, SIZE, 36):
            draw.line((0, y, SIZE, y + RNG.randint(-8, 8)), fill=(clamp(base[0] + 26), clamp(base[1] + 26), clamp(base[2] + 24), 38), width=1)
        for _ in range(1200):
            x = RNG.randint(0, SIZE - 1)
            y = RNG.randint(0, SIZE - 1)
            r = RNG.choice([1, 1, 2])
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(clamp(base[0] + 45), clamp(base[1] + 45), clamp(base[2] + 42), RNG.randint(26, 80)))
    color = color.filter(ImageFilter.GaussianBlur(0.22))
    color.save(MATERIAL_DIR / f"{prefix}_color.png")

    rough = Image.new("L", (SIZE, SIZE), rough_base)
    rd = ImageDraw.Draw(rough, "L")
    for _ in range(260):
        x = RNG.randint(0, SIZE)
        y = RNG.randint(0, SIZE)
        rd.line((x, y, x + RNG.randint(12, 140), y + RNG.randint(-6, 6)), fill=RNG.randint(max(0, rough_base - 50), min(255, rough_base + 55)), width=1)
    rough.save(MATERIAL_DIR / f"{prefix}_rough.png")

    normal = Image.new("RGB", (SIZE, SIZE), (128, 128, 255))
    nd = ImageDraw.Draw(normal, "RGB")
    for _ in range(320):
        x = RNG.randint(0, SIZE)
        y = RNG.randint(0, SIZE)
        nd.line((x, y, x + RNG.randint(12, 150), y + RNG.randint(-3, 3)), fill=(120, 128, 247), width=1)
    normal = normal.filter(ImageFilter.GaussianBlur(0.35))
    normal.save(MATERIAL_DIR / f"{prefix}_normal.png")

    ao = Image.new("L", (SIZE, SIZE), 218)
    ad = ImageDraw.Draw(ao, "L")
    for y in range(0, SIZE, 96):
        ad.rectangle((0, y, SIZE, y + 12), fill=188)
    ao.save(MATERIAL_DIR / f"{prefix}_ao.png")


def main() -> None:
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)

    specs = {
        "m4_receiver": ((29, 31, 31), 12, True, 118, 0.55, 0.48),
        "m4_bare_metal": ((96, 96, 88), 16, True, 84, 0.90, 0.31),
        "m4_accent": ((42, 43, 41), 11, True, 132, 0.35, 0.60),
        "m4_polymer": ((16, 17, 16), 9, False, 198, 0.02, 0.82),
        "m4_rubber": ((9, 9, 9), 7, False, 224, 0.0, 0.93),
        "m4_markings": ((180, 176, 154), 8, False, 172, 0.05, 0.72),
    }

    for prefix, (base, spread, metal, rough_base, metalness, roughness) in specs.items():
        make_surface(prefix, base, spread, metal, rough_base)
        save_vmat(
            prefix,
            f"materials/weapons/{prefix}_color.png",
            f"materials/weapons/{prefix}_normal.png",
            f"materials/weapons/{prefix}_rough.png",
            f"materials/weapons/{prefix}_ao.png",
            metalness,
            roughness,
        )


if __name__ == "__main__":
    main()
