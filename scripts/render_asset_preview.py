#!/usr/bin/env python3
"""Render local PNG previews for Blender asset source files."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


JSON_BEGIN = "__ASSET_PREVIEW_JSON_BEGIN__"
JSON_END = "__ASSET_PREVIEW_JSON_END__"


BLENDER_RENDER_SCRIPT = r'''
import json
import sys
from pathlib import Path

import bpy
import mathutils

JSON_BEGIN = "__ASSET_PREVIEW_JSON_BEGIN__"
JSON_END = "__ASSET_PREVIEW_JSON_END__"


def parse_script_args():
    argv = sys.argv
    if "--" not in argv:
        raise RuntimeError("Missing script argument separator.")

    args = argv[argv.index("--") + 1:]
    values = {}
    index = 0
    while index < len(args):
        key = args[index]
        if not key.startswith("--"):
            raise RuntimeError(f"Unexpected argument '{key}'.")
        if index + 1 >= len(args):
            raise RuntimeError(f"Missing value for '{key}'.")
        values[key[2:].replace("-", "_")] = args[index + 1]
        index += 2
    return values


def rounded_tuple(values):
    return [round(float(value), 6) for value in values]


def combined_mesh_bounds(mesh_objects):
    min_corner = mathutils.Vector((float("inf"), float("inf"), float("inf")))
    max_corner = mathutils.Vector((float("-inf"), float("-inf"), float("-inf")))
    has_bounds = False

    for obj in mesh_objects:
        for corner in obj.bound_box:
            world_corner = obj.matrix_world @ mathutils.Vector(corner)
            min_corner.x = min(min_corner.x, world_corner.x)
            min_corner.y = min(min_corner.y, world_corner.y)
            min_corner.z = min(min_corner.z, world_corner.z)
            max_corner.x = max(max_corner.x, world_corner.x)
            max_corner.y = max(max_corner.y, world_corner.y)
            max_corner.z = max(max_corner.z, world_corner.z)
            has_bounds = True

    if not has_bounds:
        raise RuntimeError("No render-visible mesh objects were found.")

    center = (min_corner + max_corner) * 0.5
    size = max_corner - min_corner
    max_dimension = max(float(size.x), float(size.y), float(size.z), 1.0)
    return center, size, max_dimension


def make_light(name, location, energy):
    light_data = bpy.data.lights.new(name, type="AREA")
    light_data.energy = energy
    light_data.size = 5.0
    light_obj = bpy.data.objects.new(name, light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.location = location
    return light_obj


def frame_camera(scene, center, size, max_dimension):
    created_objects = []
    camera_obj = scene.camera

    if camera_obj is None:
        camera_data = bpy.data.cameras.new("asset_preview_camera")
        camera_obj = bpy.data.objects.new("asset_preview_camera", camera_data)
        bpy.context.collection.objects.link(camera_obj)
        scene.camera = camera_obj
        created_objects.append(camera_obj)

        created_objects.append(make_light(
            "asset_preview_key_light",
            center + mathutils.Vector((-max_dimension * 1.8, -max_dimension * 2.0, max_dimension * 2.4)),
            650.0,
        ))
        created_objects.append(make_light(
            "asset_preview_fill_light",
            center + mathutils.Vector((max_dimension * 1.8, max_dimension * 1.3, max_dimension * 1.5)),
            180.0,
        ))

    camera_obj.data.type = "ORTHO"
    camera_direction = mathutils.Vector((1.6, -2.2, 1.25)).normalized()
    camera_obj.location = center + camera_direction * (max_dimension * 3.0)
    camera_obj.rotation_euler = (center - camera_obj.location).to_track_quat("-Z", "Y").to_euler()

    aspect = scene.render.resolution_x / max(1, scene.render.resolution_y)
    vertical_need = max(float(size.z), float(size.y) * 0.75, 1.0)
    horizontal_need = max(float(size.x), float(size.y) * 0.75, 1.0) / max(aspect, 0.1)
    camera_obj.data.ortho_scale = max(vertical_need, horizontal_need, max_dimension * 0.55, 1.0) * 1.35

    return created_objects


def render_preview():
    values = parse_script_args()
    output_path = Path(values["output_path"])
    sidecar_path = Path(values["sidecar_path"])
    resolution_x = int(values["resolution_x"])
    resolution_y = int(values["resolution_y"])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sidecar_path.parent.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    scene.render.resolution_x = resolution_x
    scene.render.resolution_y = resolution_y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output_path)

    all_mesh_objects = [obj for obj in scene.objects if obj.type == "MESH"]
    mesh_objects = []
    skipped_hidden_mesh_names = []
    forced_render_hidden = []
    for obj in all_mesh_objects:
        if obj.hide_render or not obj.visible_get():
            skipped_hidden_mesh_names.append(obj.name)
            if not obj.hide_render:
                forced_render_hidden.append(obj)
                obj.hide_render = True
            continue
        mesh_objects.append(obj)

    if len(mesh_objects) == 0:
        raise RuntimeError("No render-visible mesh objects were found.")

    material_names = {
        slot.material.name
        for obj in mesh_objects
        for slot in obj.material_slots
        if slot.material is not None
    }

    center, size, max_dimension = combined_mesh_bounds(mesh_objects)
    created_objects = frame_camera(scene, center, size, max_dimension)

    try:
        bpy.ops.render.render(write_still=True)
    finally:
        for obj in forced_render_hidden:
            obj.hide_render = False

    metadata = {
        "mesh_count": len(mesh_objects),
        "material_count": len(material_names),
        "output_path": str(output_path),
        "render_resolution": {
            "x": resolution_x,
            "y": resolution_y,
        },
        "skipped_hidden_mesh_names": skipped_hidden_mesh_names,
        "total_mesh_count": len(all_mesh_objects),
    }
    sidecar_path.write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")

    for obj in created_objects:
        bpy.data.objects.remove(obj, do_unlink=True)

    print(JSON_BEGIN)
    print(json.dumps(metadata, sort_keys=True))
    print(JSON_END)


render_preview()
'''


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render PNG previews for Blender asset source files.")
    parser.add_argument("--blend", action="append", required=True, help="Blend file to preview. May be repeated.")
    parser.add_argument("--out-dir", default="screenshots/asset_previews", help="Directory for preview PNG and JSON files.")
    parser.add_argument(
        "--blender-exe",
        default=r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
        help="Path to Blender executable.",
    )
    parser.add_argument("--resolution-x", type=int, default=1400, help="Preview render width.")
    parser.add_argument("--resolution-y", type=int, default=900, help="Preview render height.")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Maximum seconds to wait for each Blender render.")
    return parser.parse_args()


def print_issue(severity: str, area: str, path: str, message: str) -> None:
    location = f" [{path}]" if path else ""
    single_line_message = " ".join(str(message).split())
    print(f"[{severity}] {area}{location} - {single_line_message}")


def subprocess_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def relative_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def preview_slug_for_blend(blend_path: Path, root: Path) -> str:
    name = blend_path.name
    while name.lower().endswith(".blend"):
        name = name[:-len(".blend")]
    slug = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower()
    return slug or "asset"


def build_preview_paths(blend_path: Path, root: Path, out_dir: Path) -> tuple[Path, Path]:
    preview_base = preview_slug_for_blend(blend_path, root)
    return out_dir / f"{preview_base}_preview.png", out_dir / f"{preview_base}_preview.json"


def parse_render_metadata(output: str) -> dict[str, Any] | None:
    start = output.find(JSON_BEGIN)
    end = output.find(JSON_END)
    if start == -1 or end == -1 or end <= start:
        return None

    json_text = output[start + len(JSON_BEGIN):end].strip()
    try:
        return json.loads(json_text)
    except json.JSONDecodeError:
        return None


def render_blend(
    blender_exe: Path,
    blend_path: Path,
    out_dir: Path,
    root: Path,
    resolution_x: int,
    resolution_y: int,
    timeout_seconds: int,
) -> bool:
    relative = relative_path(blend_path, root)
    if not blend_path.exists():
        print_issue("Error", "Asset Preview", relative, "Blend file is missing.")
        return False

    output_path, sidecar_path = build_preview_paths(blend_path, root, out_dir)

    with tempfile.NamedTemporaryFile("w", suffix="_asset_preview.py", delete=False, encoding="utf-8") as handle:
        handle.write(BLENDER_RENDER_SCRIPT)
        script_path = Path(handle.name)

    try:
        try:
            result = subprocess.run(
                [
                    str(blender_exe),
                    "--background",
                    str(blend_path),
                    "--python",
                    str(script_path),
                    "--",
                    "--output-path",
                    str(output_path),
                    "--sidecar-path",
                    str(sidecar_path),
                    "--resolution-x",
                    str(resolution_x),
                    "--resolution-y",
                    str(resolution_y),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as exc:
            output = (subprocess_text(exc.stdout) + subprocess_text(exc.stderr)).strip()
            detail = f" Partial output: {output}" if output else ""
            print_issue("Error", "Asset Preview", relative, f"Blender render timed out after {timeout_seconds} seconds.{detail}")
            return False
    finally:
        try:
            script_path.unlink()
        except OSError:
            pass

    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0:
        print_issue("Error", "Asset Preview", relative, f"Blender exited with code {result.returncode}: {output.strip()}")
        return False

    metadata = parse_render_metadata(output)
    if metadata is None:
        print_issue("Warning", "Asset Preview", relative, "Blender completed but did not emit preview metadata.")
    else:
        print_issue("Info", "Asset Preview", relative, json.dumps(metadata, sort_keys=True))

    if not output_path.exists():
        print_issue("Error", "Asset Preview", relative, f"Expected preview was not written: {relative_path(output_path, root)}")
        return False

    if not sidecar_path.exists():
        print_issue("Error", "Asset Preview", relative, f"Expected JSON sidecar was not written: {relative_path(sidecar_path, root)}")
        return False

    print_issue("Info", "Asset Preview", relative_path(output_path, root), "Preview rendered.")
    return True


def main() -> int:
    args = parse_args()
    root = Path.cwd().resolve()
    blender_exe = Path(args.blender_exe)
    out_dir = Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = root / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.resolution_x <= 0 or args.resolution_y <= 0:
        print_issue("Error", "Asset Preview", "", "Render resolution must be greater than zero.")
        return 1

    if args.timeout_seconds <= 0:
        print_issue("Error", "Asset Preview", "", "--timeout-seconds must be greater than zero.")
        return 1

    blend_paths = []
    preview_targets: dict[Path, list[Path]] = {}
    duplicate_targets = False
    for blend_arg in args.blend:
        blend_path = Path(blend_arg)
        if not blend_path.is_absolute():
            blend_path = root / blend_path
        blend_paths.append(blend_path)
        output_path, _ = build_preview_paths(blend_path, root, out_dir)
        target_key = output_path.resolve()
        preview_targets.setdefault(target_key, []).append(blend_path)

    for output_path, source_paths in preview_targets.items():
        if len(source_paths) <= 1:
            continue
        duplicate_targets = True
        source_list = ", ".join(relative_path(path, root) for path in source_paths)
        print_issue("Error", "Asset Preview", relative_path(output_path, root), f"Duplicate preview output target for blends: {source_list}.")

    if duplicate_targets:
        return 1

    if not blender_exe.exists():
        print_issue("Error", "Asset Preview", str(blender_exe), "Blender executable is missing.")
        return 1

    success = True
    for blend_path in blend_paths:
        success = render_blend(
            blender_exe=blender_exe,
            blend_path=blend_path,
            out_dir=out_dir,
            root=root,
            resolution_x=args.resolution_x,
            resolution_y=args.resolution_y,
            timeout_seconds=args.timeout_seconds,
        ) and success

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
