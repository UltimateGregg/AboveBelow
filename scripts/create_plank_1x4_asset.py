from __future__ import annotations

import argparse
import math
import random
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = ROOT / "Assets" / "materials" / "environment"
BLEND_DIR = ROOT / "environment_model.blend"
BLEND_FILE = BLEND_DIR / "plank_1x4.blend"
DEFAULT_BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")


def clamp(value: float, low: int = 0, high: int = 255) -> int:
    return max(low, min(high, int(round(value))))


def hash_noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393 + y * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFF
    value ^= value >> 13
    value = (value * 1274126177) & 0xFFFFFFFF
    value ^= value >> 16
    return value / 0xFFFFFFFF


def smooth_noise(x: float, y: float, seed: int) -> float:
    x0 = math.floor(x)
    y0 = math.floor(y)
    tx = x - x0
    ty = y - y0
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    a = hash_noise(x0, y0, seed)
    b = hash_noise(x0 + 1, y0, seed)
    c = hash_noise(x0, y0 + 1, seed)
    d = hash_noise(x0 + 1, y0 + 1, seed)
    return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty


def draw_rounded_rect_outline(draw: ImageDraw.ImageDraw, size: tuple[int, int]) -> None:
    width, height = size
    edge = (118, 88, 45, 80)
    draw.rounded_rectangle((8, 8, width - 9, height - 9), radius=18, outline=edge, width=2)


def generate_face_textures(seed: int = 146) -> None:
    width, height = 2048, 512
    rng = random.Random(seed)
    knots = [
        (rng.randint(220, width - 280), rng.randint(90, height - 90), rng.uniform(28, 58), rng.uniform(0.65, 1.25))
        for _ in range(7)
    ]
    color = Image.new("RGBA", (width, height))
    roughness = Image.new("RGBA", (width, height))
    ao = Image.new("RGBA", (width, height))
    heights: list[float] = []

    for y in range(height):
        v = y / height
        for x in range(width):
            u = x / width
            long_wave = math.sin((u * 58.0 + smooth_noise(u * 11.0, v * 2.0, seed) * 2.1) * math.tau)
            fine_wave = math.sin((u * 265.0 + smooth_noise(u * 46.0, v * 5.0, seed + 4) * 2.4) * math.tau)
            board_band = math.sin((v * 5.8 + smooth_noise(u * 3.0, v * 6.0, seed + 7) * 0.65) * math.tau)
            pore = hash_noise(x, y, seed + 13) - 0.5
            knot_shade = 0.0
            knot_ridge = 0.0
            for cx, cy, radius, squish in knots:
                dx = (x - cx) / radius
                dy = (y - cy) / (radius * 0.62 * squish)
                distance = math.sqrt(dx * dx + dy * dy)
                if distance < 1.35:
                    ring = math.sin(distance * 36.0 - u * 28.0)
                    falloff = max(0.0, 1.35 - distance) / 1.35
                    knot_shade += falloff * 54.0 + max(0.0, ring) * falloff * 22.0
                    knot_ridge += falloff * 0.17 + ring * falloff * 0.045

            sun_bleach = 10.0 * smooth_noise(u * 2.5, v * 2.0, seed + 19)
            grain = long_wave * 12.0 + fine_wave * 5.5 + board_band * 8.0 + pore * 7.0
            base = 188.0 + grain + sun_bleach - knot_shade * 0.55
            r = clamp(base + 28.0)
            g = clamp(base + 9.0 - knot_shade * 0.22)
            b = clamp(base - 43.0 - knot_shade * 0.42)
            color.putpixel((x, y), (r, g, b, 255))

            height_value = 0.48 + long_wave * 0.038 + fine_wave * 0.018 + knot_ridge + pore * 0.020
            heights.append(height_value)
            rough = clamp(204 + knot_shade * 0.42 + abs(fine_wave) * 12.0 - max(0.0, long_wave) * 8.0)
            roughness.putpixel((x, y), (rough, rough, rough, 255))
            ao_value = clamp(239 - knot_shade * 0.52 - abs(fine_wave) * 2.0)
            ao.putpixel((x, y), (ao_value, ao_value, ao_value, 255))

    draw = ImageDraw.Draw(color, "RGBA")
    stamp_font = ImageFont.load_default()
    stamp = "SPF 1x4 KD HT - SELECT"
    stamp_box = (1420, 334, 1838, 402)
    draw.rounded_rectangle(stamp_box, radius=5, outline=(30, 24, 18, 105), width=3)
    draw.text((stamp_box[0] + 16, stamp_box[1] + 20), stamp, fill=(25, 20, 14, 120), font=stamp_font)
    draw_rounded_rect_outline(draw, (width, height))

    normal = Image.new("RGBA", (width, height))
    strength_x = 7.0
    strength_y = 3.2
    for y in range(height):
        for x in range(width):
            left = heights[y * width + ((x - 1) % width)]
            right = heights[y * width + ((x + 1) % width)]
            down = heights[max(0, y - 1) * width + x]
            up = heights[min(height - 1, y + 1) * width + x]
            dx = (right - left) * strength_x
            dy = (up - down) * strength_y
            length = math.sqrt(dx * dx + dy * dy + 1.0)
            normal.putpixel(
                (x, y),
                (
                    clamp((-dx / length) * 127.5 + 127.5),
                    clamp((-dy / length) * 127.5 + 127.5),
                    clamp((1.0 / length) * 127.5 + 127.5),
                    255,
                ),
            )

    color.save(MATERIALS / "plank_1x4_face_color.png")
    normal.save(MATERIALS / "plank_1x4_face_normal.png")
    roughness.save(MATERIALS / "plank_1x4_face_rough.png")
    ao.save(MATERIALS / "plank_1x4_face_ao.png")


def generate_end_textures(seed: int = 912) -> None:
    width = height = 512
    color = Image.new("RGBA", (width, height))
    roughness = Image.new("RGBA", (width, height))
    ao = Image.new("RGBA", (width, height))
    heights: list[float] = []
    center_x = width * 0.53
    center_y = height * 0.47

    for y in range(height):
        for x in range(width):
            dx = (x - center_x) / width
            dy = (y - center_y) / height
            radius = math.sqrt(dx * dx + dy * dy)
            angle = math.atan2(dy, dx)
            ring = math.sin((radius * 92.0 + smooth_noise(x * 0.025, y * 0.025, seed) * 1.6) * math.tau)
            ray = math.sin(angle * 18.0 + radius * 12.0)
            pore = hash_noise(x, y, seed + 9) - 0.5
            shade = ring * 20.0 + ray * 7.0 + pore * 10.0
            edge_dark = max(0.0, radius - 0.34) * 110.0
            base = 182.0 + shade - edge_dark
            r = clamp(base + 26.0)
            g = clamp(base + 8.0)
            b = clamp(base - 42.0)
            color.putpixel((x, y), (r, g, b, 255))
            height_value = 0.48 + ring * 0.05 + ray * 0.018 + pore * 0.02
            heights.append(height_value)
            rough = clamp(214 + abs(ring) * 20.0)
            roughness.putpixel((x, y), (rough, rough, rough, 255))
            ao_value = clamp(238 - edge_dark * 0.6 - abs(ring) * 7.0)
            ao.putpixel((x, y), (ao_value, ao_value, ao_value, 255))

    draw = ImageDraw.Draw(color, "RGBA")
    draw_rounded_rect_outline(draw, (width, height))
    normal = Image.new("RGBA", (width, height))
    for y in range(height):
        for x in range(width):
            left = heights[y * width + max(0, x - 1)]
            right = heights[y * width + min(width - 1, x + 1)]
            down = heights[max(0, y - 1) * width + x]
            up = heights[min(height - 1, y + 1) * width + x]
            dx = (right - left) * 5.5
            dy = (up - down) * 5.5
            length = math.sqrt(dx * dx + dy * dy + 1.0)
            normal.putpixel(
                (x, y),
                (
                    clamp((-dx / length) * 127.5 + 127.5),
                    clamp((-dy / length) * 127.5 + 127.5),
                    clamp((1.0 / length) * 127.5 + 127.5),
                    255,
                ),
            )

    color.save(MATERIALS / "plank_1x4_end_color.png")
    normal.save(MATERIALS / "plank_1x4_end_normal.png")
    roughness.save(MATERIALS / "plank_1x4_end_rough.png")
    ao.save(MATERIALS / "plank_1x4_end_ao.png")


def blender_script() -> str:
    blend_path = BLEND_FILE.as_posix()
    face_texture = (MATERIALS / "plank_1x4_face_color.png").as_posix()
    end_texture = (MATERIALS / "plank_1x4_end_color.png").as_posix()
    return f"""
from pathlib import Path
import bpy

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

root = bpy.data.objects.new("Plank1x4Root", None)
bpy.context.scene.collection.objects.link(root)

def make_material(name, texture_path):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (0.82, 0.63, 0.36, 1.0)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new(type="ShaderNodeOutputMaterial")
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    tex = nodes.new(type="ShaderNodeTexImage")
    tex.image = bpy.data.images.load(texture_path, check_existing=True)
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material

face_mat = make_material("Plank1x4Face", r"{face_texture}")
end_mat = make_material("Plank1x4End", r"{end_texture}")

length = 2.4384
width = 0.0889
thickness = 0.01905
lx = length * 0.5
wy = width * 0.5
tz = thickness * 0.5
verts = [
    (-lx, -wy, -tz), (lx, -wy, -tz), (lx, wy, -tz), (-lx, wy, -tz),
    (-lx, -wy, tz), (lx, -wy, tz), (lx, wy, tz), (-lx, wy, tz),
]
faces = [
    (3, 2, 1, 0),
    (4, 5, 6, 7),
    (0, 1, 5, 4),
    (1, 2, 6, 5),
    (2, 3, 7, 6),
    (3, 0, 4, 7),
]
mesh = bpy.data.meshes.new("Plank1x4_mesh")
mesh.from_pydata(verts, [], faces)
mesh.update()
mesh.materials.append(face_mat)
mesh.materials.append(end_mat)

for index, poly in enumerate(mesh.polygons):
    poly.material_index = 1 if index in (3, 5) else 0
    poly.use_smooth = False

uv_layer = mesh.uv_layers.new(name="UVMap")
face_uvs = [
    [(0.0, 0.08), (1.0, 0.08), (1.0, 0.28), (0.0, 0.28)],
    [(0.0, 0.38), (0.0, 0.98), (1.0, 0.98), (1.0, 0.38)],
    [(0.0, 0.02), (0.0, 0.16), (1.0, 0.16), (1.0, 0.02)],
    [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)],
    [(0.0, 0.20), (0.0, 0.34), (1.0, 0.34), (1.0, 0.20)],
    [(1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)],
]
for poly, uvs in zip(mesh.polygons, face_uvs):
    for loop_index, uv in zip(poly.loop_indices, uvs):
        uv_layer.data[loop_index].uv = uv

plank = bpy.data.objects.new("Plank1x4", mesh)
bpy.context.scene.collection.objects.link(plank)
plank.parent = root
bevel = plank.modifiers.new("Soft store-board eased edges", "BEVEL")
bevel.width = 0.0035
bevel.segments = 2
bevel.affect = "EDGES"
weighted = plank.modifiers.new("Weighted board normals", "WEIGHTED_NORMAL")
weighted.keep_sharp = True

bpy.context.view_layer.objects.active = plank
plank.select_set(True)
bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

bpy.ops.wm.save_as_mainfile(filepath=r"{blend_path}")
"""


def run_blender(blender_exe: Path) -> None:
    if not blender_exe.exists():
        raise FileNotFoundError(f"Blender executable not found: {blender_exe}")

    with tempfile.NamedTemporaryFile("w", suffix="_plank_1x4_blender.py", delete=False, encoding="utf-8") as script:
        script.write(blender_script())
        script_path = Path(script.name)

    try:
        completed = subprocess.run(
            [str(blender_exe), "--background", "--python", str(script_path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        if completed.returncode != 0:
            raise RuntimeError(f"Blender failed with exit code {completed.returncode}")
    finally:
        script_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create the 1x4 plank Blender source and texture maps.")
    parser.add_argument("--blender-exe", type=Path, default=DEFAULT_BLENDER)
    args = parser.parse_args()

    MATERIALS.mkdir(parents=True, exist_ok=True)
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    generate_face_textures()
    generate_end_textures()
    run_blender(args.blender_exe)
    print(f"Created {BLEND_FILE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
