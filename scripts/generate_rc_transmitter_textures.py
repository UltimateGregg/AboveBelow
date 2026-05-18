"""Generate simple TX16-style texture maps for the RC transmitter asset."""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
MATERIAL_DIR = PROJECT_ROOT / "Assets" / "materials" / "weapons"


def font(size: int, bold: bool = False):
    names = [
        "arialbd.ttf" if bold else "arial.ttf",
        "segoeuib.ttf" if bold else "segoeui.ttf",
    ]
    for name in names:
        try:
            return ImageFont.truetype(name, size=size)
        except OSError:
            pass
    return ImageFont.load_default()


def save_polymer() -> None:
    random.seed(16)
    image = Image.new("RGB", (512, 512), (31, 33, 34))
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            base = 28 + int(10 * (y / image.height))
            speckle = random.randint(-8, 8)
            stripe = 4 if (x + y * 2) % 37 < 2 else 0
            v = max(14, min(58, base + speckle + stripe))
            pixels[x, y] = (v, v + 1, v + 2)

    draw = ImageDraw.Draw(image, "RGBA")
    for x in range(0, 512, 32):
        draw.line((x, 0, x + 80, 512), fill=(255, 255, 255, 7), width=1)
    image.save(MATERIAL_DIR / "rc_polymer_color.png")


def save_screen() -> None:
    image = Image.new("RGB", (512, 320), (12, 23, 35))
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rectangle((0, 0, 511, 319), fill=(8, 18, 31, 255))
    draw.rectangle((10, 10, 501, 310), outline=(40, 190, 230, 255), width=3)
    draw.rectangle((20, 20, 492, 56), fill=(12, 80, 118, 255))
    draw.text((30, 25), "EDGETX", font=font(24, True), fill=(235, 255, 255, 255))
    draw.text((350, 25), "DVP QUAD", font=font(20, True), fill=(180, 240, 255, 255))

    draw.text((30, 78), "MODEL: FPV DRONE", font=font(18, True), fill=(88, 220, 255, 255))
    draw.text((30, 108), "ARM  SAFE", font=font(16), fill=(130, 255, 154, 255))
    draw.text((30, 136), "RSSI  98%", font=font(16), fill=(220, 245, 255, 255))
    draw.text((30, 164), "BAT   15.8V", font=font(16), fill=(255, 226, 110, 255))
    draw.text((30, 192), "ALT   42m", font=font(16), fill=(220, 245, 255, 255))

    cx, cy = 345, 165
    draw.ellipse((cx - 78, cy - 78, cx + 78, cy + 78), outline=(38, 150, 190, 255), width=3)
    draw.line((cx - 68, cy, cx + 68, cy), fill=(74, 200, 235, 255), width=3)
    draw.line((cx, cy - 68, cx, cy + 68), fill=(74, 200, 235, 160), width=1)
    draw.polygon([(cx - 52, cy + 18), (cx, cy - 18), (cx + 52, cy + 18)], outline=(255, 226, 90, 255), fill=(255, 226, 90, 40))

    for i, height in enumerate([42, 70, 104, 132]):
        x0 = 440 + i * 14
        draw.rectangle((x0, 250 - height, x0 + 9, 250), fill=(74, 220, 120, 220))
    draw.text((405, 260), "TELEM", font=font(14), fill=(180, 240, 255, 255))

    for y in range(64, 300, 32):
        draw.line((250, y, 492, y), fill=(80, 120, 150, 60), width=1)
    image.save(MATERIAL_DIR / "rc_screen_color.png")


def save_flat(name: str, color: tuple[int, int, int], noise: int = 4) -> None:
    random.seed(hash(name) & 0xFFFF)
    image = Image.new("RGB", (256, 256), color)
    pixels = image.load()
    for y in range(256):
        for x in range(256):
            n = random.randint(-noise, noise)
            pixels[x, y] = tuple(max(0, min(255, c + n)) for c in color)
    image.save(MATERIAL_DIR / name)


def main() -> None:
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)
    save_polymer()
    save_screen()
    save_flat("rc_antenna_color.png", (20, 21, 21), 5)
    save_flat("rc_rubber_color.png", (8, 8, 9), 3)
    save_flat("rc_metal_color.png", (150, 152, 148), 9)
    save_flat("rc_label_color.png", (220, 226, 220), 4)
    save_flat("rc_accent_blue_color.png", (34, 130, 215), 5)
    print("Generated RC transmitter texture set.")


if __name__ == "__main__":
    main()
