#!/usr/bin/env python3
"""Generate procedural texture maps for the shotgun asset."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
MATERIAL_DIR = ROOT / "Assets" / "materials"
SIZE = 1024
RNG = random.Random(4127)


def clamp(value: int) -> int:
    return max(0, min(255, value))


def save_vmat(
    path: Path,
    color: str,
    normal: str,
    rough: str,
    ao: str,
    metalness: float,
    roughness: float,
) -> None:
    path.write_text(
        f'''"'"Layer0"
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


def noise_texture(base: tuple[int, int, int], spread: int) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), base)
    pix = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = RNG.randint(-spread, spread)
            pix[x, y] = tuple(clamp(c + n) for c in base)
    return img


def generate_metal() -> None:
    img = noise_texture((35, 39, 42), 12)
    draw = ImageDraw.Draw(img, "RGBA")

    for y in range(0, SIZE, 10):
        shade = RNG.randint(-10, 18)
        draw.line((0, y, SIZE, y), fill=(clamp(55 + shade), clamp(60 + shade), clamp(63 + shade), 42), width=1)

    for _ in range(340):
        x = RNG.randint(0, SIZE - 1)
        y = RNG.randint(0, SIZE - 1)
        length = RNG.randint(22, 180)
        alpha = RNG.randint(28, 90)
        angle = RNG.uniform(-0.08, 0.08)
        x2 = x + int(math.cos(angle) * length)
        y2 = y + int(math.sin(angle) * length)
        color = RNG.choice([(185, 190, 184, alpha), (12, 14, 15, alpha)])
        draw.line((x, y, x2, y2), fill=color, width=RNG.choice([1, 1, 1, 2]))

    for _ in range(32):
        x = RNG.randint(20, SIZE - 20)
        y = RNG.randint(20, SIZE - 20)
        r = RNG.randint(5, 18)
        draw.ellipse((x - r, y - r, x + r, y + r), outline=(150, 150, 140, 35), width=1)

    img = img.filter(ImageFilter.GaussianBlur(0.25))
    img.save(MATERIAL_DIR / "shotgun_metal_color.png")

    rough = Image.new("L", (SIZE, SIZE), 88)
    rd = ImageDraw.Draw(rough, "L")
    for y in range(0, SIZE, 8):
        rd.line((0, y, SIZE, y), fill=RNG.randint(70, 130), width=1)
    for _ in range(230):
        x = RNG.randint(0, SIZE)
        y = RNG.randint(0, SIZE)
        rd.line((x, y, x + RNG.randint(12, 120), y + RNG.randint(-5, 5)), fill=RNG.randint(130, 210), width=1)
    rough.save(MATERIAL_DIR / "shotgun_metal_rough.png")

    normal = Image.new("RGB", (SIZE, SIZE), (128, 128, 255))
    nd = ImageDraw.Draw(normal, "RGB")
    for _ in range(280):
        x = RNG.randint(0, SIZE)
        y = RNG.randint(0, SIZE)
        nd.line((x, y, x + RNG.randint(12, 160), y + RNG.randint(-3, 3)), fill=(118, 128, 246), width=1)
    normal = normal.filter(ImageFilter.GaussianBlur(0.35))
    normal.save(MATERIAL_DIR / "shotgun_metal_normal.png")

    ao = Image.new("L", (SIZE, SIZE), 220)
    ad = ImageDraw.Draw(ao, "L")
    for y in range(0, SIZE, 64):
        ad.rectangle((0, y, SIZE, y + 10), fill=185)
    ao.save(MATERIAL_DIR / "shotgun_metal_ao.png")


def generate_wood() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (96, 55, 27))
    draw = ImageDraw.Draw(img, "RGBA")
    pix = img.load()

    knots = [(RNG.randint(80, SIZE - 80), RNG.randint(80, SIZE - 80), RNG.randint(22, 58)) for _ in range(9)]
    for y in range(SIZE):
        wave = math.sin(y / 28.0) * 15 + math.sin(y / 93.0) * 30
        for x in range(SIZE):
            grain = int(24 * math.sin((x + wave) / 25.0) + 11 * math.sin((x + y * 0.35) / 9.0))
            r, g, b = 95 + grain, 55 + grain // 2, 25 + grain // 4
            pix[x, y] = (clamp(r + RNG.randint(-5, 5)), clamp(g + RNG.randint(-4, 4)), clamp(b + RNG.randint(-3, 3)))

    for kx, ky, kr in knots:
        for i in range(8):
            alpha = 90 - i * 8
            draw.ellipse((kx - kr - i * 7, ky - kr // 2 - i * 5, kx + kr + i * 7, ky + kr // 2 + i * 5), outline=(42, 24, 12, alpha), width=2)
        draw.ellipse((kx - kr // 2, ky - kr // 4, kx + kr // 2, ky + kr // 4), fill=(55, 30, 13, 80))

    for _ in range(120):
        y = RNG.randint(0, SIZE)
        draw.line((0, y, SIZE, y + RNG.randint(-35, 35)), fill=(165, 102, 52, RNG.randint(24, 70)), width=RNG.choice([1, 1, 2]))

    img = img.filter(ImageFilter.GaussianBlur(0.2))
    img.save(MATERIAL_DIR / "shotgun_wood_color.png")

    rough = noise_texture((150, 150, 150), 20).convert("L")
    rd = ImageDraw.Draw(rough, "L")
    for y in range(0, SIZE, 18):
        rd.line((0, y, SIZE, y + RNG.randint(-18, 18)), fill=RNG.randint(120, 190), width=1)
    rough.save(MATERIAL_DIR / "shotgun_wood_rough.png")

    normal = Image.new("RGB", (SIZE, SIZE), (128, 128, 255))
    nd = ImageDraw.Draw(normal, "RGB")
    for y in range(0, SIZE, 14):
        nd.line((0, y, SIZE, y + RNG.randint(-20, 20)), fill=(134, 126, 248), width=1)
    normal = normal.filter(ImageFilter.GaussianBlur(0.45))
    normal.save(MATERIAL_DIR / "shotgun_wood_normal.png")

    ao = Image.new("L", (SIZE, SIZE), 215)
    ImageDraw.Draw(ao, "L").rectangle((0, SIZE - 90, SIZE, SIZE), fill=175)
    ao.save(MATERIAL_DIR / "shotgun_wood_ao.png")


def generate_rubber() -> None:
    img = noise_texture((16, 17, 16), 10)
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(16, SIZE, 36):
        draw.line((0, y, SIZE, y), fill=(45, 47, 44, 80), width=2)
    for x in range(16, SIZE, 36):
        draw.line((x, 0, x, SIZE), fill=(4, 4, 4, 55), width=2)
    for _ in range(1400):
        x = RNG.randint(0, SIZE - 1)
        y = RNG.randint(0, SIZE - 1)
        r = RNG.choice([1, 1, 2])
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(70, 72, 68, RNG.randint(50, 110)))
    img.save(MATERIAL_DIR / "shotgun_rubber_color.png")

    rough = noise_texture((210, 210, 210), 18).convert("L")
    rough.save(MATERIAL_DIR / "shotgun_rubber_rough.png")
    Image.new("RGB", (SIZE, SIZE), (128, 128, 255)).save(MATERIAL_DIR / "shotgun_rubber_normal.png")
    Image.new("L", (SIZE, SIZE), 210).save(MATERIAL_DIR / "shotgun_rubber_ao.png")


def generate_shell() -> None:
    img = Image.new("RGB", (SIZE, SIZE), (132, 24, 22))
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(SIZE):
        shade = int(20 * math.sin(y / 37.0))
        draw.line((0, y, SIZE, y), fill=(clamp(132 + shade), clamp(24 + shade // 3), clamp(22 + shade // 3), 80))
    for _ in range(160):
        x = RNG.randint(0, SIZE)
        y = RNG.randint(0, SIZE)
        draw.line((x, y, x + RNG.randint(-8, 8), y + RNG.randint(20, 120)), fill=(210, 80, 65, RNG.randint(25, 70)), width=1)
    img.save(MATERIAL_DIR / "shotgun_shell_color.png")
    Image.new("L", (SIZE, SIZE), 145).save(MATERIAL_DIR / "shotgun_shell_rough.png")
    Image.new("RGB", (SIZE, SIZE), (128, 128, 255)).save(MATERIAL_DIR / "shotgun_shell_normal.png")
    Image.new("L", (SIZE, SIZE), 220).save(MATERIAL_DIR / "shotgun_shell_ao.png")


def main() -> None:
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)
    generate_metal()
    generate_wood()
    generate_rubber()
    generate_shell()

    save_vmat(
        MATERIAL_DIR / "shotgun_metal.vmat",
        "materials/shotgun_metal_color.png",
        "materials/shotgun_metal_normal.png",
        "materials/shotgun_metal_rough.png",
        "materials/shotgun_metal_ao.png",
        0.86,
        0.34,
    )
    save_vmat(
        MATERIAL_DIR / "shotgun_wood.vmat",
        "materials/shotgun_wood_color.png",
        "materials/shotgun_wood_normal.png",
        "materials/shotgun_wood_rough.png",
        "materials/shotgun_wood_ao.png",
        0.0,
        0.56,
    )
    save_vmat(
        MATERIAL_DIR / "shotgun_rubber.vmat",
        "materials/shotgun_rubber_color.png",
        "materials/shotgun_rubber_normal.png",
        "materials/shotgun_rubber_rough.png",
        "materials/shotgun_rubber_ao.png",
        0.0,
        0.82,
    )
    save_vmat(
        MATERIAL_DIR / "shotgun_shell.vmat",
        "materials/shotgun_shell_color.png",
        "materials/shotgun_shell_normal.png",
        "materials/shotgun_shell_rough.png",
        "materials/shotgun_shell_ao.png",
        0.04,
        0.46,
    )


if __name__ == "__main__":
    main()
