#!/usr/bin/env python3
"""Generate project-owned texture maps for the FPV drone body and propellers."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
MATERIAL_DIR = ROOT / "Assets" / "materials"
SIZE = 512


def clamp(value: int) -> int:
    return max(0, min(255, value))


def add_noise(image: Image.Image, amount: int, seed: int) -> Image.Image:
    rng = random.Random(seed)
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b = pixels[x, y]
            delta = rng.randint(-amount, amount)
            pixels[x, y] = (
                clamp(r + delta),
                clamp(g + delta),
                clamp(b + delta),
            )
    return image


def save_carbon() -> None:
    rng = random.Random(4101)
    image = Image.new("RGB", (SIZE, SIZE), (17, 18, 21))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            weave_a = 22 if ((x + y) // 12) % 2 == 0 else -2
            weave_b = 16 if ((x - y) // 12) % 2 == 0 else -4
            strand = int(math.sin((x + y) * 0.22) * 7)
            v = clamp(24 + weave_a + weave_b + strand + rng.randint(-6, 6))
            pixels[x, y] = (v, v, clamp(v + 4))

    draw = ImageDraw.Draw(image, "RGBA")
    for offset in range(-SIZE, SIZE * 2, 48):
        draw.line((offset, 0, offset - SIZE, SIZE), fill=(180, 190, 205, 22), width=2)
        draw.line((offset, 0, offset + SIZE, SIZE), fill=(4, 5, 7, 80), width=2)
    image.filter(ImageFilter.GaussianBlur(0.15)).save(MATERIAL_DIR / "drone_fpv_frame_color.png")


def save_motor() -> None:
    rng = random.Random(4102)
    image = Image.new("RGB", (SIZE, SIZE), (125, 26, 34))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            radial = int(math.sin(x * 0.08) * 17 + math.sin((x + y) * 0.03) * 8)
            groove = -22 if x % 64 < 4 else 0
            scratch = rng.randint(-10, 16)
            pixels[x, y] = (
                clamp(145 + radial + groove + scratch),
                clamp(32 + radial // 3 + scratch // 3),
                clamp(43 + radial // 4 + scratch // 4),
            )

    draw = ImageDraw.Draw(image, "RGBA")
    for x in range(34, SIZE, 96):
        draw.rectangle((x, 0, x + 6, SIZE), fill=(235, 120, 120, 42))
    for _ in range(90):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        draw.line((x, y, x + rng.randrange(20, 110), y + rng.randrange(-5, 6)), fill=(245, 180, 170, 36), width=1)
    image.filter(ImageFilter.GaussianBlur(0.12)).save(MATERIAL_DIR / "drone_fpv_motor_color.png")


def save_propeller() -> None:
    rng = random.Random(4103)
    image = Image.new("RGB", (SIZE, SIZE), (224, 226, 232))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            leading = 28 if (x + y * 2) % 96 < 13 else 0
            stripe = -48 if 225 < y < 270 else 0
            scuff = rng.randint(-12, 12)
            v = clamp(226 + leading + stripe + scuff)
            pixels[x, y] = (v, v, clamp(v + 7))

    draw = ImageDraw.Draw(image, "RGBA")
    for x in range(20, SIZE, 82):
        draw.line((x, 0, x + 140, SIZE), fill=(35, 40, 52, 55), width=3)
    image.filter(ImageFilter.GaussianBlur(0.2)).save(MATERIAL_DIR / "drone_fpv_propeller_color.png")


def save_battery() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (34, 37, 42))
    draw = ImageDraw.Draw(image, "RGBA")
    add_noise(image, 8, 4104)
    draw.rectangle((28, 86, 484, 426), fill=(31, 34, 39, 245), outline=(8, 9, 12, 180), width=8)
    draw.rectangle((62, 122, 450, 206), fill=(21, 88, 140, 235))
    draw.rectangle((62, 220, 450, 296), fill=(218, 224, 70, 235))
    draw.text((84, 140), "4S 1500", fill=(230, 245, 255, 255))
    draw.text((84, 238), "FPV PACK", fill=(20, 26, 20, 255))
    for x in range(0, SIZE, 36):
        draw.line((x, 0, x + 70, SIZE), fill=(255, 255, 255, 10), width=1)
    image.save(MATERIAL_DIR / "drone_fpv_battery_color.png")


def save_camera_body() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (42, 45, 49))
    draw = ImageDraw.Draw(image, "RGBA")
    add_noise(image, 9, 4105)
    for y in range(48, SIZE, 96):
        draw.rectangle((0, y, SIZE, y + 8), fill=(18, 20, 23, 90))
    for x in range(70, SIZE, 150):
        draw.rectangle((x, 0, x + 5, SIZE), fill=(80, 86, 92, 45))
    image.filter(ImageFilter.GaussianBlur(0.1)).save(MATERIAL_DIR / "drone_fpv_camera_body_color.png")


def save_lens() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (4, 8, 12))
    draw = ImageDraw.Draw(image, "RGBA")
    for r in range(250, 10, -10):
        t = 1.0 - r / 250
        color = (clamp(8 + int(35 * t)), clamp(18 + int(80 * t)), clamp(26 + int(120 * t)), 255)
        draw.ellipse((256 - r, 256 - r, 256 + r, 256 + r), fill=color)
    draw.ellipse((108, 92, 235, 210), fill=(210, 245, 255, 112))
    draw.ellipse((184, 150, 292, 258), fill=(86, 176, 255, 82))
    image.save(MATERIAL_DIR / "drone_fpv_lens_color.png")


def save_strap() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (13, 14, 15))
    draw = ImageDraw.Draw(image, "RGBA")
    add_noise(image, 6, 4106)
    for y in range(0, SIZE, 26):
        draw.line((0, y, SIZE, y + 10), fill=(70, 75, 76, 45), width=2)
    draw.rectangle((0, 205, SIZE, 308), fill=(28, 30, 30, 190))
    image.save(MATERIAL_DIR / "drone_fpv_strap_color.png")


def save_antenna() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (18, 18, 18))
    draw = ImageDraw.Draw(image, "RGBA")
    add_noise(image, 7, 4107)
    for x in range(0, SIZE, 40):
        draw.line((x, 0, x + 26, SIZE), fill=(95, 95, 90, 35), width=2)
    image.save(MATERIAL_DIR / "drone_fpv_antenna_color.png")


def save_electronics() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (12, 58, 48))
    draw = ImageDraw.Draw(image, "RGBA")
    add_noise(image, 7, 4108)
    for x in range(40, SIZE, 96):
        draw.rectangle((x, 52, x + 42, 160), fill=(20, 24, 24, 220))
        draw.rectangle((x + 8, 184, x + 54, 292), fill=(32, 35, 33, 210))
    for y in range(34, SIZE, 64):
        draw.line((0, y, SIZE, y + 18), fill=(210, 166, 52, 80), width=3)
    for _ in range(34):
        cx = random.Random(4110 + _).randrange(30, SIZE - 30)
        cy = random.Random(4210 + _).randrange(30, SIZE - 30)
        draw.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=(220, 170, 60, 190))
    image.save(MATERIAL_DIR / "drone_fpv_electronics_color.png")


def save_scalar(name: str, value: int) -> None:
    Image.new("RGB", (64, 64), (value, value, value)).save(MATERIAL_DIR / name)


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
\t"TextureColor"\t\t"materials/{color}"
\t"TextureNormal"\t\t"materials/default/default_normal.tga"
\t"TextureRoughness"\t\t"materials/{rough}"
\t"TextureAmbientOcclusion"\t\t"materials/{ao}"
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

    save_carbon()
    save_motor()
    save_propeller()
    save_battery()
    save_camera_body()
    save_lens()
    save_strap()
    save_antenna()
    save_electronics()

    save_scalar("drone_fpv_frame_rough.png", 188)
    save_scalar("drone_fpv_motor_rough.png", 82)
    save_scalar("drone_fpv_propeller_rough.png", 128)
    save_scalar("drone_fpv_battery_rough.png", 156)
    save_scalar("drone_fpv_camera_body_rough.png", 112)
    save_scalar("drone_fpv_lens_rough.png", 32)
    save_scalar("drone_fpv_strap_rough.png", 210)
    save_scalar("drone_fpv_antenna_rough.png", 190)
    save_scalar("drone_fpv_electronics_rough.png", 96)
    save_scalar("drone_fpv_ao.png", 220)

    write_vmat("drone_fpv_frame.vmat", "drone_fpv_frame_color.png", "drone_fpv_frame_rough.png", "drone_fpv_ao.png", 0.08, 0.68)
    write_vmat("drone_fpv_motor.vmat", "drone_fpv_motor_color.png", "drone_fpv_motor_rough.png", "drone_fpv_ao.png", 0.86, 0.26)
    write_vmat("drone_fpv_propeller.vmat", "drone_fpv_propeller_color.png", "drone_fpv_propeller_rough.png", "drone_fpv_ao.png", 0.0, 0.36)
    write_vmat("drone_fpv_battery.vmat", "drone_fpv_battery_color.png", "drone_fpv_battery_rough.png", "drone_fpv_ao.png", 0.02, 0.55)
    write_vmat("drone_fpv_camera_body.vmat", "drone_fpv_camera_body_color.png", "drone_fpv_camera_body_rough.png", "drone_fpv_ao.png", 0.45, 0.42)
    write_vmat("drone_fpv_lens.vmat", "drone_fpv_lens_color.png", "drone_fpv_lens_rough.png", "drone_fpv_ao.png", 0.0, 0.08)
    write_vmat("drone_fpv_strap.vmat", "drone_fpv_strap_color.png", "drone_fpv_strap_rough.png", "drone_fpv_ao.png", 0.0, 0.74)
    write_vmat("drone_fpv_antenna.vmat", "drone_fpv_antenna_color.png", "drone_fpv_antenna_rough.png", "drone_fpv_ao.png", 0.0, 0.66)
    write_vmat("drone_fpv_electronics.vmat", "drone_fpv_electronics_color.png", "drone_fpv_electronics_rough.png", "drone_fpv_ao.png", 0.34, 0.31)

    print(f"Generated FPV drone textures in {MATERIAL_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
