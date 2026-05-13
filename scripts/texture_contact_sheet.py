#!/usr/bin/env python3
"""Create a contact sheet for S&Box material textures and cutout masks."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw


TEXTURE_RE = re.compile(r'"(?P<key>Texture[^"]*)"\s*"(?P<value>[^"]+)"')


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_resource_path(root: Path, resource_path: str) -> Path:
    normalized = resource_path.replace("\\", "/").lstrip("/")
    if normalized.lower().startswith("assets/"):
        return root / normalized
    return root / "Assets" / normalized


def parse_vmat(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return {match.group("key"): match.group("value") for match in TEXTURE_RE.finditer(text)}


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (224, 224, 224, 255))
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            if ((x // cell) + (y // cell)) % 2:
                pixels[x, y] = (174, 174, 174, 255)
    return image


def fit_image(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = image.copy()
    fitted.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (28, 28, 28, 255))
    x = (size[0] - fitted.width) // 2
    y = (size[1] - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def load_texture(root: Path, resource_path: str | None) -> Image.Image | None:
    if not resource_path:
        return None
    path = resolve_resource_path(root, resource_path)
    if not path.exists():
        return None
    return Image.open(path).convert("RGBA")


def material_preview(root: Path, textures: dict[str, str], tile_size: tuple[int, int]) -> Image.Image:
    color = load_texture(root, textures.get("TextureColor"))
    mask = load_texture(root, textures.get("TextureTranslucency"))
    if color is None:
        return checkerboard(tile_size)

    color = color.convert("RGBA")
    if mask is not None:
        mask_luma = mask.convert("L")
        color.putalpha(mask_luma)

    preview = checkerboard(color.size)
    preview.alpha_composite(color)
    return fit_image(preview, tile_size)


def mask_preview(root: Path, textures: dict[str, str], tile_size: tuple[int, int]) -> Image.Image:
    mask = load_texture(root, textures.get("TextureTranslucency"))
    if mask is None:
        return Image.new("RGBA", tile_size, (48, 48, 48, 255))
    return fit_image(mask.convert("RGBA"), tile_size)


def color_preview(root: Path, textures: dict[str, str], tile_size: tuple[int, int]) -> Image.Image:
    color = load_texture(root, textures.get("TextureColor"))
    if color is None:
        return Image.new("RGBA", tile_size, (48, 48, 48, 255))
    return fit_image(color.convert("RGBA"), tile_size)


def material_paths_from_args(root: Path, args: argparse.Namespace) -> list[Path]:
    materials: list[str] = []
    if args.config:
        config = json.loads((root / args.config).read_text(encoding="utf-8"))
        remaps = config.get("material_remap") or {}
        if not isinstance(remaps, dict):
            raise ValueError(f"{args.config} material_remap must be a JSON object")
        materials.extend(str(value) for value in remaps.values())
    materials.extend(args.material or [])

    paths: list[Path] = []
    seen: set[Path] = set()
    for material in materials:
        path = resolve_resource_path(root, material)
        if path not in seen:
            paths.append(path)
            seen.add(path)
    return paths


def make_sheet(root: Path, material_paths: list[Path], out_path: Path) -> None:
    tile_size = (300, 150)
    label_height = 28
    gap = 12
    padding = 14
    columns = 3
    width = padding * 2 + columns * tile_size[0] + (columns - 1) * gap
    row_height = label_height + tile_size[1] + padding
    height = padding + max(1, len(material_paths)) * row_height
    sheet = Image.new("RGBA", (width, height), (24, 24, 24, 255))
    draw = ImageDraw.Draw(sheet)

    headers = ["cutout preview", "color texture", "mask texture"]
    for index, material_path in enumerate(material_paths):
        y = padding + index * row_height
        label = material_path.relative_to(root).as_posix() if material_path.exists() else str(material_path)
        draw.text((padding, y), label, fill=(236, 236, 236, 255))
        y += label_height

        textures = parse_vmat(material_path) if material_path.exists() else {}
        tiles = [
            material_preview(root, textures, tile_size),
            color_preview(root, textures, tile_size),
            mask_preview(root, textures, tile_size),
        ]
        for column, tile in enumerate(tiles):
            x = padding + column * (tile_size[0] + gap)
            sheet.alpha_composite(tile, (x, y))
            draw.text((x + 6, y + 6), headers[column], fill=(255, 255, 255, 255))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render a texture contact sheet for S&Box materials.")
    parser.add_argument("--config", help="Asset pipeline config whose material_remap targets should be shown.")
    parser.add_argument("--material", action="append", help="Additional material resource path to include.")
    parser.add_argument("--out", help="Output PNG path.")
    return parser


def main() -> int:
    root = project_root()
    args = build_parser().parse_args()
    material_paths = material_paths_from_args(root, args)
    if not material_paths:
        raise SystemExit("No materials were provided. Use --config or --material.")
    out_path = root / (args.out or "screenshots/asset_previews/texture_contact_sheet.png")
    make_sheet(root, material_paths, out_path)
    print(f"Texture contact sheet: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
