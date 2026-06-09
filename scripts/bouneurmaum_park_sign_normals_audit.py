#!/usr/bin/env python3
"""Audit Bouneurmaum park sign prism side normals for S&Box backface culling."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
JSON_BEGIN = "__PARK_SIGN_NORMALS_AUDIT_JSON_BEGIN__"
JSON_END = "__PARK_SIGN_NORMALS_AUDIT_JSON_END__"

PRISM_OBJECTS = [
    "OuterDarkBrownBoard",
    "InsetWoodFace",
    "DarkLowerDivider",
    "SmallLeftPine_LowerBoughs",
    "SmallLeftPine_MiddleBoughs",
    "SmallLeftPine_TopBoughs",
    "CenterPine_LowerBoughs",
    "CenterPine_MiddleBoughs",
    "CenterPine_TopBoughs",
    "SmallRightPine_LowerBoughs",
    "SmallRightPine_MiddleBoughs",
    "SmallRightPine_TopBoughs",
]

BLENDER_SCRIPT = r'''
import json
import math

import bpy

JSON_BEGIN = "__PARK_SIGN_NORMALS_AUDIT_JSON_BEGIN__"
JSON_END = "__PARK_SIGN_NORMALS_AUDIT_JSON_END__"

blend_path = __BLEND_PATH_JSON__
object_names = __OBJECT_NAMES_JSON__

bpy.ops.wm.open_mainfile(filepath=blend_path)

result = {
    "blend": blend_path,
    "objects": [],
    "errors": [],
}

for object_name in object_names:
    obj = bpy.data.objects.get(object_name)
    if obj is None:
        result["errors"].append({
            "object": object_name,
            "message": "object not found",
        })
        continue
    if obj.type != "MESH":
        result["errors"].append({
            "object": object_name,
            "message": "object is not a mesh",
        })
        continue

    mesh = obj.data
    if not mesh.vertices or not mesh.polygons:
        result["errors"].append({
            "object": object_name,
            "message": "mesh has no geometry",
        })
        continue

    xs = [vertex.co.x for vertex in mesh.vertices]
    zs = [vertex.co.z for vertex in mesh.vertices]
    center_x = (min(xs) + max(xs)) * 0.5
    center_z = (min(zs) + max(zs)) * 0.5

    side_count = 0
    inward = []
    for polygon in mesh.polygons:
        normal = polygon.normal
        side_normal_len = math.sqrt((normal.x * normal.x) + (normal.z * normal.z))
        if abs(normal.y) > 0.65 or side_normal_len < 0.20:
            continue

        cx = 0.0
        cz = 0.0
        for vertex_index in polygon.vertices:
            vertex = mesh.vertices[vertex_index]
            cx += vertex.co.x
            cz += vertex.co.z
        cx /= len(polygon.vertices)
        cz /= len(polygon.vertices)

        radial_x = cx - center_x
        radial_z = cz - center_z
        radial_len = math.sqrt((radial_x * radial_x) + (radial_z * radial_z))
        if radial_len < 0.02:
            continue

        side_count += 1
        dot = (normal.x * radial_x) + (normal.z * radial_z)
        if dot < -0.001:
            inward.append({
                "index": polygon.index,
                "dot": dot,
                "center": [cx, cz],
                "normal": [normal.x, normal.y, normal.z],
            })

    entry = {
        "object": object_name,
        "side_faces": side_count,
        "inward_faces": len(inward),
        "sample_inward": inward[:5],
    }
    result["objects"].append(entry)

    if side_count == 0:
        result["errors"].append({
            "object": object_name,
            "message": "no side-facing polygons were inspectable",
        })
    elif inward:
        result["errors"].append({
            "object": object_name,
            "message": f"{len(inward)} side-facing polygon(s) point inward",
            "sample": inward[:3],
        })

print(JSON_BEGIN)
print(json.dumps(result, sort_keys=True))
print(JSON_END)
'''


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit park sign side-face normals.")
    parser.add_argument("--root", default="", help="Project root. Defaults to current working directory.")
    parser.add_argument(
        "--blend",
        default="environment_model.blend/bouneurmaum_park_sign.blend",
        help="Blend file to inspect, relative to root unless absolute.",
    )
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER, help="Path to Blender executable.")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Maximum Blender inspection time.")
    return parser.parse_args()


def resolve_root(root_arg: str) -> Path:
    if root_arg.strip():
        return Path(root_arg).resolve()
    return Path.cwd().resolve()


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return root / path


def relative_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def print_issue(severity: str, area: str, path: str, message: str, recommendation: str = "") -> None:
    location = f" [{path}]" if path else ""
    print(f"[{severity}] {area}{location} - {' '.join(str(message).split())}")
    if recommendation:
        print(f"  Recommendation: {' '.join(str(recommendation).split())}")


def run_blender(blender: Path, blend: Path, timeout_seconds: int) -> dict[str, Any] | None:
    script_text = BLENDER_SCRIPT
    script_text = script_text.replace("__BLEND_PATH_JSON__", json.dumps(str(blend)))
    script_text = script_text.replace("__OBJECT_NAMES_JSON__", json.dumps(PRISM_OBJECTS))

    with tempfile.TemporaryDirectory(prefix="sbox-park-sign-normals-") as temp_dir:
        script_path = Path(temp_dir) / "inspect_park_sign_normals.py"
        script_path.write_text(script_text, encoding="utf-8")

        try:
            result = subprocess.run(
                [str(blender), "--background", "--python", str(script_path)],
                text=True,
                capture_output=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired:
            print_issue("Error", "Park Sign Normals", "", f"Blender inspection timed out after {timeout_seconds}s.")
            return None

    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0:
        print_issue("Error", "Park Sign Normals", "", f"Blender exited with {result.returncode}: {output.strip()}")
        return None

    begin = output.find(JSON_BEGIN)
    end = output.find(JSON_END)
    if begin == -1 or end == -1 or end <= begin:
        print_issue("Error", "Park Sign Normals", "", "Blender inspection did not return parseable JSON.")
        return None

    json_text = output[begin + len(JSON_BEGIN):end].strip()
    try:
        data = json.loads(json_text)
    except json.JSONDecodeError as exc:
        print_issue("Error", "Park Sign Normals", "", f"Failed to parse Blender inspection JSON: {exc}")
        return None
    if not isinstance(data, dict):
        print_issue("Error", "Park Sign Normals", "", "Blender inspection JSON was not an object.")
        return None
    return data


def main() -> int:
    args = parse_args()
    root = resolve_root(args.root)
    blend = resolve_path(root, args.blend).resolve()
    blender = Path(args.blender_exe)

    if not blend.exists():
        print_issue("Error", "Park Sign Normals", relative_path(blend, root), "Blend file does not exist.")
        return 1
    if not blender.exists():
        print_issue("Error", "Park Sign Normals", str(blender), "Blender executable does not exist.")
        return 1

    data = run_blender(blender, blend, args.timeout_seconds)
    if data is None:
        return 1

    rel_blend = relative_path(blend, root)
    errors = data.get("errors", [])
    if errors:
        for error in errors:
            object_name = str(error.get("object", ""))
            message = str(error.get("message", "normal audit failed"))
            print_issue(
                "Error",
                "Park Sign Normals",
                rel_blend,
                f"{object_name}: {message}.",
                "Reverse the prism side-face winding so normals point outward before exporting to S&Box.",
            )
        return 1

    objects = data.get("objects", [])
    side_faces = sum(int(row.get("side_faces", 0)) for row in objects if isinstance(row, dict))
    print_issue("Info", "Park Sign Normals", rel_blend, f"Checked {len(objects)} prism object(s) and {side_faces} side-facing polygon(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
