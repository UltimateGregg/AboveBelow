#!/usr/bin/env python3
"""Render named proof views for S&Box environment Blender assets."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
JSON_BEGIN = "__ENV_ASSET_VIEW_JSON_BEGIN__"
JSON_END = "__ENV_ASSET_VIEW_JSON_END__"


BLENDER_SCRIPT = r'''
import json
import sys
from pathlib import Path

import bpy
import mathutils

JSON_BEGIN = "__ENV_ASSET_VIEW_JSON_BEGIN__"
JSON_END = "__ENV_ASSET_VIEW_JSON_END__"


def parse_args():
    argv = sys.argv
    if "--" not in argv:
        raise RuntimeError("Missing script argument separator.")
    raw = argv[argv.index("--") + 1:]
    values = {}
    index = 0
    while index < len(raw):
        key = raw[index]
        if not key.startswith("--"):
            raise RuntimeError(f"Unexpected argument '{key}'.")
        if index + 1 >= len(raw):
            raise RuntimeError(f"Missing value for '{key}'.")
        values[key[2:].replace("-", "_")] = raw[index + 1]
        index += 2
    return values


def mesh_bounds(mesh_objects):
    min_corner = mathutils.Vector((float("inf"), float("inf"), float("inf")))
    max_corner = mathutils.Vector((float("-inf"), float("-inf"), float("-inf")))
    for obj in mesh_objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ mathutils.Vector(corner)
            min_corner.x = min(min_corner.x, world.x)
            min_corner.y = min(min_corner.y, world.y)
            min_corner.z = min(min_corner.z, world.z)
            max_corner.x = max(max_corner.x, world.x)
            max_corner.y = max(max_corner.y, world.y)
            max_corner.z = max(max_corner.z, world.z)
    center = (min_corner + max_corner) * 0.5
    size = max_corner - min_corner
    return min_corner, max_corner, center, size


def make_light(name, location, energy, size):
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return obj


def look_at(camera, target):
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_view(scene, name, output_path, center, size, direction, target_z_factor, ortho_factor):
    max_dimension = max(float(size.x), float(size.y), float(size.z), 1.0)
    target = mathutils.Vector((center.x, center.y, center.z - size.z * 0.15 + size.z * target_z_factor))
    camera_data = bpy.data.cameras.new(f"{name}_camera")
    camera = bpy.data.objects.new(f"{name}_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    camera.data.type = "ORTHO"
    camera.location = target + mathutils.Vector(direction).normalized() * (max_dimension * 2.4)
    look_at(camera, target)
    camera.data.ortho_scale = max_dimension * ortho_factor
    camera.data.clip_end = max(2000.0, max_dimension * 8.0)

    scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    return str(output_path)


def main():
    values = parse_args()
    asset_name = values["asset_name"]
    out_dir = Path(values["out_dir"])
    out_dir.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = int(values.get("resolution_x", "1400"))
    scene.render.resolution_y = int(values.get("resolution_y", "900"))
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"

    mesh_objects = [obj for obj in scene.objects if obj.type == "MESH" and not obj.hide_render and obj.visible_get()]
    if not mesh_objects:
        raise RuntimeError("No render-visible mesh objects were found.")

    material_names = sorted({
        slot.material.name
        for obj in mesh_objects
        for slot in obj.material_slots
        if slot.material is not None
    })
    min_corner, max_corner, center, size = mesh_bounds(mesh_objects)
    max_dimension = max(float(size.x), float(size.y), float(size.z), 1.0)

    created = [
        make_light("env_preview_key_light", center + mathutils.Vector((-max_dimension * 1.5, -max_dimension * 1.7, max_dimension * 2.1)), 700.0, 6.0),
        make_light("env_preview_fill_light", center + mathutils.Vector((max_dimension * 1.6, max_dimension * 1.0, max_dimension * 1.2)), 220.0, 8.0),
    ]

    views = {
        "ground": ((1.9, -2.4, 0.55), 0.30, 1.18),
        "drone": ((1.1, -1.2, 2.1), 0.55, 1.42),
        "three_quarter": ((1.7, -2.0, 1.2), 0.45, 1.34),
    }
    outputs = {}
    try:
        for view_name, (direction, target_z_factor, ortho_factor) in views.items():
            output = out_dir / f"{asset_name}_{view_name}.png"
            outputs[view_name] = render_view(scene, view_name, output, center, size, direction, target_z_factor, ortho_factor)
    finally:
        for obj in created:
            bpy.data.objects.remove(obj, do_unlink=True)

    metadata = {
        "asset_name": asset_name,
        "mesh_count": len(mesh_objects),
        "material_count": len(material_names),
        "materials": material_names,
        "bounds": {
            "min": [round(float(v), 6) for v in min_corner],
            "max": [round(float(v), 6) for v in max_corner],
            "size": [round(float(v), 6) for v in size],
        },
        "camera_names": list(views.keys()),
        "output_paths": outputs,
    }
    sidecar = out_dir / f"{asset_name}_views.json"
    sidecar.write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")
    metadata["sidecar"] = str(sidecar)

    print(JSON_BEGIN)
    print(json.dumps(metadata, sort_keys=True))
    print(JSON_END)


main()
'''


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render ground, drone, and three-quarter environment asset views.")
    parser.add_argument("--blend", required=True, help="Blend file to render.")
    parser.add_argument("--asset-name", required=True, help="Output asset slug, such as house_large.")
    parser.add_argument("--out-dir", default="screenshots/asset_previews", help="Preview output directory.")
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER, help="Path to Blender executable.")
    parser.add_argument("--resolution-x", type=int, default=1400)
    parser.add_argument("--resolution-y", type=int, default=900)
    parser.add_argument("--timeout-seconds", type=int, default=240)
    return parser.parse_args()


def parse_metadata(output: str) -> dict[str, Any] | None:
    start = output.find(JSON_BEGIN)
    end = output.find(JSON_END)
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        return json.loads(output[start + len(JSON_BEGIN):end].strip())
    except json.JSONDecodeError:
        return None


def main() -> int:
    root = project_root()
    args = parse_args()
    blend = (root / args.blend).resolve()
    out_dir = (root / args.out_dir).resolve()
    blender = Path(args.blender_exe)

    if not blend.exists():
        raise SystemExit(f"Blend file does not exist: {blend}")
    if not blender.exists():
        raise SystemExit(f"Blender executable does not exist: {blender}")

    with tempfile.TemporaryDirectory(prefix="sbox-env-views-") as temp_dir:
        script_path = Path(temp_dir) / "render_environment_asset_views_blender.py"
        script_path.write_text(BLENDER_SCRIPT, encoding="utf-8")
        result = subprocess.run(
            [
                str(blender),
                "--background",
                str(blend),
                "--python",
                str(script_path),
                "--",
                "--asset-name",
                args.asset_name,
                "--out-dir",
                str(out_dir),
                "--resolution-x",
                str(args.resolution_x),
                "--resolution-y",
                str(args.resolution_y),
            ],
            text=True,
            capture_output=True,
            timeout=args.timeout_seconds,
        )

    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0:
        sys.stderr.write(output)
        return result.returncode

    metadata = parse_metadata(output)
    if metadata is None:
        sys.stderr.write(output)
        raise SystemExit("Blender render did not return parseable metadata.")

    print(f"Rendered {args.asset_name}:")
    for name, path in metadata["output_paths"].items():
        print(f"  {name}: {path}")
    print(f"  sidecar: {metadata['sidecar']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
