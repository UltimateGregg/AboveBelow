"""Generate cleaner tactical textures for the drone jammer asset."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

PROJECT_ROOT = Path(r"C:\Programming\S&Box")
MATERIAL_DIR = PROJECT_ROOT / "Assets" / "materials"


def clamp(value: int) -> int:
    return max(0, min(255, value))


def save_body() -> None:
    random.seed(74)
    size = 768
    image = Image.new("RGB", (size, size), (31, 34, 35))
    pixels = image.load()

    for y in range(size):
        for x in range(size):
            grain = random.randint(-9, 9)
            brushed = int(math.sin((x + y * 0.45) * 0.055) * 5)
            panel = 7 if (x % 192 < 4 or y % 192 < 4) else 0
            v = clamp(33 + grain + brushed - panel)
            pixels[x, y] = (v, clamp(v + 2), clamp(v + 3))

    draw = ImageDraw.Draw(image, "RGBA")
    for x in [96, 288, 480, 672]:
        draw.line((x, 28, x, size - 28), fill=(12, 14, 15, 95), width=3)
    for y in [128, 384, 640]:
        draw.line((28, y, size - 28, y), fill=(12, 14, 15, 80), width=3)

    for _ in range(120):
        x = random.randint(36, size - 80)
        y = random.randint(36, size - 36)
        length = random.randint(16, 82)
        alpha = random.randint(20, 55)
        draw.line((x, y, x + length, y + random.randint(-4, 4)), fill=(190, 200, 190, alpha), width=1)

    for _ in range(28):
        x = random.randint(30, size - 30)
        y = random.randint(30, size - 30)
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(8, 9, 10, 150))

    image.save(MATERIAL_DIR / "jammer_body_color.png")


def save_antenna() -> None:
    random.seed(88)
    image = Image.new("RGB", (512, 512), (92, 94, 91))
    pixels = image.load()
    for y in range(512):
        for x in range(512):
            line = int(math.sin(x * 0.14) * 10)
            grain = random.randint(-10, 10)
            v = clamp(104 + line + grain)
            pixels[x, y] = (v, clamp(v + 1), clamp(v - 3))

    draw = ImageDraw.Draw(image, "RGBA")
    for y in range(0, 512, 38):
        draw.line((0, y, 512, y), fill=(220, 220, 210, 28), width=1)
    for _ in range(45):
        x = random.randint(20, 490)
        y = random.randint(20, 490)
        draw.line((x, y, x + random.randint(12, 70), y), fill=(35, 35, 34, 55), width=1)
    image.save(MATERIAL_DIR / "jammer_antenna_color.png")


def save_led() -> None:
    image = Image.new("RGB", (256, 256), (4, 22, 28))
    draw = ImageDraw.Draw(image, "RGBA")
    for r in range(120, 0, -6):
        alpha = int(180 * (1 - r / 128))
        draw.ellipse((128 - r, 128 - r, 128 + r, 128 + r), fill=(15, 210, 255, alpha))
    draw.ellipse((82, 82, 174, 174), fill=(105, 245, 255, 255))
    draw.ellipse((104, 98, 136, 130), fill=(230, 255, 255, 210))
    image.save(MATERIAL_DIR / "jammer_led_color.png")


def save_flat(name: str, value: int, channels: tuple[int, int, int] | None = None) -> None:
    color = channels if channels else (value, value, value)
    Image.new("RGB", (64, 64), color).save(MATERIAL_DIR / name)


def main() -> None:
    MATERIAL_DIR.mkdir(parents=True, exist_ok=True)
    save_body()
    save_antenna()
    save_led()
    save_flat("jammer_body_rough.png", 206)
    save_flat("jammer_antenna_rough.png", 112)
    save_flat("jammer_led_rough.png", 42)
    save_flat("jammer_ao.png", 224)
    save_flat("jammer_flat_normal.png", 128, (128, 128, 255))
    print("Generated jammer texture set.")


if __name__ == "__main__":
    main()
