#!/usr/bin/env python3
"""Audit Blender source assets for S&Box production readiness."""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


EXCLUDED_DIRS = {".git", ".tmpbuild", ".superpowers", "bin", "obj", "node_modules"}
JSON_BEGIN = "__BLENDER_ASSET_AUDIT_JSON_BEGIN__"
JSON_END = "__BLENDER_ASSET_AUDIT_JSON_END__"


INSPECTION_SCRIPT = r'''
import json
import math
import bpy
import mathutils

JSON_BEGIN = "__BLENDER_ASSET_AUDIT_JSON_BEGIN__"
JSON_END = "__BLENDER_ASSET_AUDIT_JSON_END__"


def rounded_tuple(values):
    return [round(float(value), 6) for value in values]


def get_basis_transform(obj):
    _location, rotation, scale = obj.matrix_basis.decompose()
    rotation.normalize()
    return rotation, scale


def rotation_angle_radians(rotation):
    clamped_w = max(-1.0, min(1.0, abs(float(rotation.w))))
    return 2.0 * math.acos(clamped_w)


def has_unapplied_transform(obj):
    rotation, scale = get_basis_transform(obj)
    scale_unapplied = any(abs(float(value) - 1.0) > 0.0001 for value in scale)
    rotation_unapplied = rotation_angle_radians(rotation) > 0.0001
    return scale_unapplied, rotation_unapplied


objects = list(bpy.data.objects)
mesh_objects = [obj for obj in objects if obj.type == "MESH"]
empty_objects = [obj for obj in objects if obj.type == "EMPTY"]

material_slots = sum(len(obj.material_slots) for obj in mesh_objects)
mesh_names = [obj.name for obj in mesh_objects]
empty_names = [obj.name for obj in empty_objects]

unapplied_transforms = []
for obj in objects:
    scale_unapplied, rotation_unapplied = has_unapplied_transform(obj)
    if scale_unapplied or rotation_unapplied:
        rotation, scale = get_basis_transform(obj)
        rotation_angle = rotation_angle_radians(rotation)
        unapplied_transforms.append({
            "name": obj.name,
            "type": obj.type,
            "scale": rounded_tuple(scale),
            "rotation_axis": rounded_tuple(rotation.axis),
            "rotation_angle_degrees": round(math.degrees(rotation_angle), 6),
            "rotation_degrees": rounded_tuple([math.degrees(value) for value in rotation.to_euler()]),
            "rotation_mode": obj.rotation_mode,
            "scale_unapplied": scale_unapplied,
            "rotation_unapplied": rotation_unapplied,
        })

uv_less_meshes = []
zero_vertex_meshes = []
for obj in mesh_objects:
    mesh = obj.data
    if len(mesh.vertices) == 0:
        zero_vertex_meshes.append(obj.name)
    if len(obj.material_slots) > 0 and len(mesh.uv_layers) == 0:
        uv_less_meshes.append(obj.name)

min_corner = [float("inf"), float("inf"), float("inf")]
max_corner = [float("-inf"), float("-inf"), float("-inf")]
has_bounds = False
for obj in mesh_objects:
    for corner in obj.bound_box:
        world_corner = obj.matrix_world @ mathutils.Vector(corner)
        for axis in range(3):
            value = float(world_corner[axis])
            min_corner[axis] = min(min_corner[axis], value)
            max_corner[axis] = max(max_corner[axis], value)
        has_bounds = True

if has_bounds:
    size = [max_corner[axis] - min_corner[axis] for axis in range(3)]
    dimensions = {
        "min": rounded_tuple(min_corner),
        "max": rounded_tuple(max_corner),
        "size": rounded_tuple(size),
        "x": round(float(size[0]), 6),
        "y": round(float(size[1]), 6),
        "z": round(float(size[2]), 6),
    }
else:
    dimensions = {
        "min": [0.0, 0.0, 0.0],
        "max": [0.0, 0.0, 0.0],
        "size": [0.0, 0.0, 0.0],
        "x": 0.0,
        "y": 0.0,
        "z": 0.0,
    }

root_empty_candidates = [obj.name for obj in empty_objects if obj.parent is None]
top_level_mesh_names = [obj.name for obj in mesh_objects if obj.parent is None]

payload = {
    "object_count": len(objects),
    "mesh_count": len(mesh_objects),
    "material_slots": material_slots,
    "mesh_names": mesh_names,
    "empty_names": empty_names,
    "dimensions": dimensions,
    "unapplied_transforms": unapplied_transforms,
    "uv_less_meshes": uv_less_meshes,
    "zero_vertex_meshes": zero_vertex_meshes,
    "root_empty_candidates": root_empty_candidates,
    "top_level_mesh_names": top_level_mesh_names,
    "name_hints_found": {},
}

print(JSON_BEGIN)
print(json.dumps(payload, sort_keys=True))
print(JSON_END)
'''


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit Blender source files.")
    parser.add_argument("--blend", action="append", default=[], help="Blend file to audit. May be repeated.")
    parser.add_argument("--profiles", default="scripts/asset_quality_profiles.json", help="Asset quality profile JSON.")
    parser.add_argument("--category", choices=("weapon", "drone", "character", "environment"), help="Profile category.")
    parser.add_argument(
        "--blender-exe",
        default=r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
        help="Path to Blender executable.",
    )
    parser.add_argument("--timeout-seconds", type=int, default=120, help="Maximum seconds to wait for each Blender inspection.")
    parser.add_argument("--root", default="", help="Project root. Defaults to current working directory.")
    return parser.parse_args()


def resolve_root(root_arg: str) -> Path:
    if root_arg.strip():
        return Path(root_arg).resolve()
    return Path.cwd().resolve()


def relative_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def discover_blends(root: Path) -> list[Path]:
    blends: list[Path] = []
    for current_root, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name not in EXCLUDED_DIRS]
        for file_name in files:
            if file_name.lower().endswith(".blend"):
                blends.append(Path(current_root) / file_name)
    return sorted(blends, key=lambda item: item.as_posix().lower())


def load_profile_hints(profile_path: Path, category: str | None) -> list[str]:
    if not category:
        return []
    try:
        profiles = json.loads(profile_path.read_text(encoding="utf-8"))
    except OSError:
        return []
    except json.JSONDecodeError:
        return []

    category_profile = profiles.get(category, {})
    hints = category_profile.get("required_name_hints", [])
    return [str(hint).lower() for hint in hints if str(hint).strip()]


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


def run_blender_inspection(blender_exe: Path, blend_path: Path, timeout_seconds: int) -> tuple[dict[str, Any] | None, str]:
    with tempfile.NamedTemporaryFile("w", suffix="_blender_asset_audit.py", delete=False, encoding="utf-8") as handle:
        handle.write(INSPECTION_SCRIPT)
        script_path = Path(handle.name)

    try:
        try:
            result = subprocess.run(
                [str(blender_exe), "--background", str(blend_path), "--python", str(script_path)],
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as exc:
            output = (subprocess_text(exc.stdout) + subprocess_text(exc.stderr)).strip()
            detail = f" Partial output: {output}" if output else ""
            return None, f"Blender inspection timed out after {timeout_seconds} seconds.{detail}"
    finally:
        try:
            script_path.unlink()
        except OSError:
            pass

    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0:
        return None, f"Blender exited with code {result.returncode}: {output.strip()}"

    start = output.find(JSON_BEGIN)
    end = output.find(JSON_END)
    if start == -1 or end == -1 or end <= start:
        return None, f"Blender inspection did not emit JSON payload: {output.strip()}"

    json_text = output[start + len(JSON_BEGIN):end].strip()
    try:
        return json.loads(json_text), ""
    except json.JSONDecodeError as exc:
        return None, f"Blender inspection emitted invalid JSON: {exc}"


def collect_name_hints(inspection: dict[str, Any], required_hints: list[str]) -> dict[str, list[str]]:
    names = []
    names.extend(str(name) for name in inspection.get("mesh_names", []))
    names.extend(str(name) for name in inspection.get("empty_names", []))

    found: dict[str, list[str]] = {}
    for hint in required_hints:
        matches = [name for name in names if hint in name.lower()]
        if matches:
            found[hint] = matches
    return found


def has_suspicious_dimensions(inspection: dict[str, Any]) -> list[float]:
    dimensions = inspection.get("dimensions", {})
    sizes = dimensions.get("size", [dimensions.get("x", 0), dimensions.get("y", 0), dimensions.get("z", 0)])
    suspicious = []
    for size in sizes:
        value = abs(float(size))
        if value < 0.01 or value > 10000:
            suspicious.append(float(size))
    return suspicious


def audit_blend(
    blender_exe: Path,
    blend_path: Path,
    root: Path,
    required_hints: list[str],
    timeout_seconds: int,
) -> tuple[int, int]:
    relative = relative_path(blend_path, root)
    errors = 0
    warnings = 0

    if not blend_path.exists():
        print_issue("Error", "Blender Quality", relative, "Blend file is missing.")
        return 1, 0

    inspection, failure = run_blender_inspection(blender_exe, blend_path, timeout_seconds)
    if inspection is None:
        print_issue("Error", "Blender Quality", relative, failure)
        return 1, 0

    found_hints = collect_name_hints(inspection, required_hints)
    inspection["name_hints_found"] = found_hints

    print_issue("Info", "Blender Quality", relative, json.dumps(inspection, sort_keys=True))

    if int(inspection.get("mesh_count", 0)) == 0:
        print_issue("Error", "Blender Quality", relative, "No mesh objects were found.")
        errors += 1

    for mesh_name in inspection.get("zero_vertex_meshes", []):
        print_issue("Error", "Blender Quality", relative, f"Mesh '{mesh_name}' has zero vertices.")
        errors += 1

    for transform in inspection.get("unapplied_transforms", []):
        issues = []
        if transform.get("scale_unapplied"):
            issues.append("scale")
        if transform.get("rotation_unapplied"):
            issues.append("rotation")
        print_issue(
            "Warning",
            "Blender Quality",
            relative,
            f"Object '{transform.get('name')}' has unapplied {' and '.join(issues)}.",
        )
        warnings += 1

    if int(inspection.get("material_slots", 0)) > 0:
        for mesh_name in inspection.get("uv_less_meshes", []):
            print_issue("Warning", "Blender Quality", relative, f"Mesh '{mesh_name}' has material slots but no UV layers.")
            warnings += 1

    top_level_meshes = inspection.get("top_level_mesh_names", [])
    if len(top_level_meshes) > 1 and len(inspection.get("root_empty_candidates", [])) == 0:
        print_issue("Warning", "Blender Quality", relative, "Multiple mesh objects were found with no root empty candidate.")
        warnings += 1

    for hint in required_hints:
        if hint not in found_hints:
            print_issue("Warning", "Blender Quality", relative, f"Missing required '{hint}' name hint.")
            warnings += 1

    suspicious_dimensions = has_suspicious_dimensions(inspection)
    if suspicious_dimensions:
        print_issue(
            "Warning",
            "Blender Quality",
            relative,
            f"Suspicious dimensions: {', '.join(str(round(value, 6)) for value in suspicious_dimensions)}.",
        )
        warnings += 1

    return errors, warnings


def main() -> int:
    args = parse_args()
    root = resolve_root(args.root)
    blender_exe = Path(args.blender_exe)
    profiles = Path(args.profiles)
    if not profiles.is_absolute():
        profiles = root / profiles

    if args.timeout_seconds <= 0:
        print_issue("Error", "Blender Quality", "", "--timeout-seconds must be greater than zero.")
        return 1

    if not blender_exe.exists():
        print_issue("Error", "Blender Quality", str(blender_exe), "Blender executable is missing.")
        return 1

    if args.blend:
        blend_paths = [Path(item) if Path(item).is_absolute() else root / item for item in args.blend]
    else:
        blend_paths = discover_blends(root)

    if not blend_paths:
        print_issue("Info", "Blender Quality", "", "No .blend files were found to audit.")
        return 0

    required_hints = load_profile_hints(profiles, args.category)
    errors = 0
    for blend_path in blend_paths:
        blend_errors, _ = audit_blend(blender_exe, blend_path, root, required_hints, args.timeout_seconds)
        errors += blend_errors

    return 1 if errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
