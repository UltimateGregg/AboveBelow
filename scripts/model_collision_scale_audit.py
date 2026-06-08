#!/usr/bin/env python3
"""Audit generated ModelDoc collision scale against render mesh bounds."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
EXCLUDED_DIRS = {".git", ".tmpbuild", "bin", "obj", "node_modules"}
JSON_BEGIN = "__MODEL_COLLISION_SCALE_AUDIT_JSON_BEGIN__"
JSON_END = "__MODEL_COLLISION_SCALE_AUDIT_JSON_END__"

CLASS_ASSIGNMENT_RE = re.compile(r"_class\s*=\s*\"(?P<class>[^\"]+)\"")
STRING_FIELD_RE = r"\b{field}\s*=\s*\"([^\"]*)\""
NUMBER_FIELD_RE = r"\b{field}\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
VECTOR_FIELD_RE = r"\b{field}\s*=\s*\[\s*([^\]]+)\]"
NUMBER_RE = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")

BLENDER_BOUNDS_SCRIPT = r'''
import json
import math
import bpy

JSON_BEGIN = "__MODEL_COLLISION_SCALE_AUDIT_JSON_BEGIN__"
JSON_END = "__MODEL_COLLISION_SCALE_AUDIT_JSON_END__"

with open(r"{input_path}", "r", encoding="utf-8") as handle:
    payload = json.load(handle)

results = []
for item in payload["items"]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)

    entry = {
        "key": item["key"],
        "fbx": item["fbx"],
        "ok": True,
        "error": "",
        "mins": [0.0, 0.0, 0.0],
        "maxs": [0.0, 0.0, 0.0],
        "size": [0.0, 0.0, 0.0],
        "mesh_count": 0,
    }

    try:
        bpy.ops.import_scene.fbx(filepath=item["fbx"])
        mins = [math.inf, math.inf, math.inf]
        maxs = [-math.inf, -math.inf, -math.inf]
        mesh_count = 0
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            mesh_count += 1
            matrix = obj.matrix_world
            for vertex in obj.data.vertices:
                world = matrix @ vertex.co
                for axis in range(3):
                    value = float(world[axis])
                    mins[axis] = min(mins[axis], value)
                    maxs[axis] = max(maxs[axis], value)
        if mesh_count == 0:
            raise RuntimeError("FBX imported no mesh objects")
        entry["mins"] = mins
        entry["maxs"] = maxs
        entry["size"] = [maxs[axis] - mins[axis] for axis in range(3)]
        entry["mesh_count"] = mesh_count
    except Exception as exc:
        entry["ok"] = False
        entry["error"] = str(exc)

    results.append(entry)

print(JSON_BEGIN)
print(json.dumps(results, sort_keys=True))
print(JSON_END)
'''


@dataclass
class Issue:
    severity: str
    area: str
    path: str
    message: str
    recommendation: str = ""


@dataclass
class ModelDocShape:
    shape_class: str
    filename: str = ""
    import_scale: float = 1.0
    origin: tuple[float, float, float] | None = None
    dimensions: tuple[float, float, float] | None = None
    point0: tuple[float, float, float] | None = None
    point1: tuple[float, float, float] | None = None
    radius: float | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit ModelDoc collision bounds against render mesh bounds.")
    parser.add_argument("--root", default="", help="Project root. Defaults to current working directory.")
    parser.add_argument("--config", action="append", default=[], help="Asset pipeline config to inspect. May be repeated.")
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER, help="Path to Blender executable.")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Maximum Blender inspection time.")
    parser.add_argument("--axis-tolerance", type=float, default=0.25, help="Allowed per-axis render/collision size deviation.")
    parser.add_argument("--max-overall-scale-ratio", type=float, default=2.0, help="Allowed diagonal scale ratio before failure.")
    parser.add_argument("--show-info", action="store_true", help="Emit informational audit lines.")
    parser.add_argument("--fail-on-warning", action="store_true", help="Exit non-zero on warnings as well as errors.")
    return parser.parse_args()


def relative_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix().replace("\\", "/")


def print_issue(issue: Issue, show_info: bool) -> None:
    if issue.severity == "Info" and not show_info:
        return
    location = f" [{issue.path}]" if issue.path else ""
    print(f"[{issue.severity}] {issue.area}{location} - {' '.join(str(issue.message).split())}")
    if issue.recommendation:
        print(f"  Recommendation: {' '.join(str(issue.recommendation).split())}")


def load_json(path: Path, issues: list[Issue], root: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(path, root), f"Failed to parse config: {exc}"))
        return None
    if not isinstance(data, dict):
        issues.append(Issue("Error", "Model Collision Scale", relative_path(path, root), "Config must contain a JSON object."))
        return None
    return data


def resolve_root(root_arg: str) -> Path:
    if root_arg.strip():
        return Path(root_arg).resolve()
    return Path.cwd().resolve()


def resolve_project_path(root: Path, value: str | None) -> Path | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or "${" in text:
        return None
    path = Path(text)
    if path.is_absolute():
        return path
    return root / path


def resolve_resource_path(root: Path, value: str | None) -> Path | None:
    if value is None:
        return None
    text = str(value).strip().replace("\\", "/").lstrip("/")
    if not text or "${" in text or re.match(r"^(https?:|file:|asset:)", text, re.I):
        return None
    if text.lower().startswith("assets/"):
        return root / text
    if text.lower().startswith(("models/", "materials/", "prefabs/", "sounds/", "scenes/", "ui/")):
        return root / "Assets" / text
    return None


def discover_configs(root: Path, explicit: list[str]) -> list[Path]:
    if explicit:
        paths: list[Path] = []
        for value in explicit:
            path = resolve_project_path(root, value) or Path(value)
            paths.append(path)
        return paths

    scripts_dir = root / "scripts"
    configs: list[Path] = []
    if not scripts_dir.exists():
        return configs
    for current_root, dirs, files in os.walk(scripts_dir):
        dirs[:] = [name for name in dirs if name not in EXCLUDED_DIRS]
        for file_name in files:
            if file_name.endswith("_asset_pipeline.json"):
                configs.append(Path(current_root) / file_name)
    return sorted(configs, key=lambda path: path.as_posix().lower())


def field_string(body: str, field: str) -> str:
    match = re.search(STRING_FIELD_RE.format(field=re.escape(field)), body)
    return match.group(1) if match else ""


def field_number(body: str, field: str, default: float = 1.0) -> float:
    match = re.search(NUMBER_FIELD_RE.format(field=re.escape(field)), body)
    if not match:
        return default
    return float(match.group(1))


def field_vector(body: str, field: str) -> tuple[float, float, float] | None:
    match = re.search(VECTOR_FIELD_RE.format(field=re.escape(field)), body)
    if not match:
        return None
    numbers = [float(item.group(0)) for item in NUMBER_RE.finditer(match.group(1))]
    if len(numbers) != 3:
        return None
    return (numbers[0], numbers[1], numbers[2])


def read_modeldoc(path: Path, issues: list[Issue], root: Path) -> tuple[list[ModelDocShape], list[ModelDocShape]]:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(path, root), f"Failed to read VMDL: {exc}"))
        return [], []

    render_meshes: list[ModelDocShape] = []
    collision_shapes: list[ModelDocShape] = []

    for match in CLASS_ASSIGNMENT_RE.finditer(raw):
        shape_class = match.group("class")
        block_start = raw.rfind("{", 0, match.start())
        if block_start < 0:
            continue
        depth = 0
        block_end = -1
        for index in range(block_start, len(raw)):
            char = raw[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    block_end = index + 1
                    break
        if block_end < 0:
            continue
        body = raw[block_start:block_end]
        if shape_class == "RenderMeshFile":
            render_meshes.append(
                ModelDocShape(
                    shape_class=shape_class,
                    filename=field_string(body, "filename"),
                    import_scale=field_number(body, "import_scale", 1.0),
                )
            )
        elif shape_class == "PhysicsMeshFile":
            collision_shapes.append(
                ModelDocShape(
                    shape_class=shape_class,
                    filename=field_string(body, "filename"),
                    import_scale=field_number(body, "import_scale", 1.0),
                )
            )
        elif shape_class == "PhysicsShapeBox":
            collision_shapes.append(
                ModelDocShape(
                    shape_class=shape_class,
                    origin=field_vector(body, "origin") or (0.0, 0.0, 0.0),
                    dimensions=field_vector(body, "dimensions"),
                )
            )
        elif shape_class in {"PhysicsShapeCapsule", "PhysicsShapeCylinder"}:
            collision_shapes.append(
                ModelDocShape(
                    shape_class=shape_class,
                    point0=field_vector(body, "point0"),
                    point1=field_vector(body, "point1"),
                    radius=field_number(body, "radius", math.nan),
                )
            )

    return render_meshes, collision_shapes


def bounds_size_from_config(config: dict[str, Any]) -> tuple[float, float, float] | None:
    raw = config.get("audit_render_bounds")
    if not isinstance(raw, dict):
        return None
    if isinstance(raw.get("size"), list) and len(raw["size"]) == 3:
        return tuple(float(value) for value in raw["size"])
    mins = raw.get("mins")
    maxs = raw.get("maxs")
    if isinstance(mins, list) and isinstance(maxs, list) and len(mins) == 3 and len(maxs) == 3:
        return tuple(float(maxs[index]) - float(mins[index]) for index in range(3))
    return None


def collision_mode(config: dict[str, Any]) -> str | None:
    raw_collision = config.get("collision")
    if isinstance(raw_collision, dict):
        return str(raw_collision.get("mode", "render_mesh")).strip().lower()
    if config.get("physics_shapes") is not None:
        return "primitives"
    return None


def collision_is_enabled(mode: str | None) -> bool:
    if mode is None:
        return False
    return mode not in {"", "none", "off", "false"}


def primitive_reason(config: dict[str, Any]) -> str:
    for key in ("primitive_collision_reason", "collision_reason"):
        value = config.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    raw_collision = config.get("collision")
    if isinstance(raw_collision, dict):
        for key in ("reason", "primitive_reason"):
            value = raw_collision.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return ""


def primitive_union_size(shapes: list[ModelDocShape], config_path: str, issues: list[Issue]) -> tuple[float, float, float] | None:
    mins = [math.inf, math.inf, math.inf]
    maxs = [-math.inf, -math.inf, -math.inf]
    found = False

    for shape in shapes:
        if shape.shape_class == "PhysicsShapeBox":
            if shape.dimensions is None:
                issues.append(Issue("Error", "Model Collision Scale", config_path, "PhysicsShapeBox is missing dimensions.", "Regenerate the VMDL from a valid collision config."))
                continue
            origin = shape.origin or (0.0, 0.0, 0.0)
            for axis in range(3):
                half = abs(float(shape.dimensions[axis])) * 0.5
                mins[axis] = min(mins[axis], float(origin[axis]) - half)
                maxs[axis] = max(maxs[axis], float(origin[axis]) + half)
            found = True
        elif shape.shape_class in {"PhysicsShapeCapsule", "PhysicsShapeCylinder"}:
            if shape.point0 is None or shape.point1 is None or shape.radius is None or math.isnan(shape.radius):
                issues.append(Issue("Error", "Model Collision Scale", config_path, f"{shape.shape_class} is missing point0, point1, or radius.", "Regenerate the VMDL from a valid collision config."))
                continue
            radius = abs(float(shape.radius))
            for axis in range(3):
                mins[axis] = min(mins[axis], min(float(shape.point0[axis]), float(shape.point1[axis])) - radius)
                maxs[axis] = max(maxs[axis], max(float(shape.point0[axis]), float(shape.point1[axis])) + radius)
            found = True

    if not found:
        return None
    return tuple(maxs[axis] - mins[axis] for axis in range(3))


def scaled_size(size: tuple[float, float, float], import_scale: float) -> tuple[float, float, float]:
    scale = abs(float(import_scale))
    return tuple(float(value) * scale for value in size)


def vector_text(values: tuple[float, float, float]) -> str:
    return "[" + ", ".join(f"{value:.3f}".rstrip("0").rstrip(".") for value in values) + "]"


def diagonal(values: tuple[float, float, float]) -> float:
    return math.sqrt(sum(float(value) * float(value) for value in values))


def has_zero_axis(values: tuple[float, float, float], epsilon: float = 1e-4) -> bool:
    return any(abs(float(value)) <= epsilon for value in values)


def compare_bounds(
    render_size: tuple[float, float, float],
    collision_size: tuple[float, float, float],
    config_path: str,
    issues: list[Issue],
    axis_tolerance: float,
    max_overall_scale_ratio: float,
) -> None:
    if has_zero_axis(render_size):
        issues.append(Issue("Error", "Model Collision Scale", config_path, f"Render bounds are zero or degenerate: {vector_text(render_size)}.", "Fix the exported render mesh before relying on collision proof."))
        return
    if has_zero_axis(collision_size):
        issues.append(Issue("Error", "Model Collision Scale", config_path, f"Collision bounds are zero or degenerate: {vector_text(collision_size)}.", "Regenerate model collision so ModelCollider.LocalBounds will not compile as zero."))
        return

    axis_errors: list[str] = []
    ratios: list[float] = []
    for axis, axis_name in enumerate(("X", "Y", "Z")):
        render_axis = float(render_size[axis])
        collision_axis = float(collision_size[axis])
        ratio = collision_axis / render_axis
        ratios.append(ratio)
        deviation = abs(collision_axis - render_axis) / abs(render_axis)
        if deviation > axis_tolerance:
            axis_errors.append(f"{axis_name} {ratio:.3g}x")

    render_diag = diagonal(render_size)
    collision_diag = diagonal(collision_size)
    if render_diag <= 1e-4 or collision_diag <= 1e-4:
        overall_ratio = math.inf
    else:
        diag_ratio = collision_diag / render_diag
        overall_ratio = max(diag_ratio, 1.0 / diag_ratio)

    ratio_spread = math.inf
    positive_ratios = [ratio for ratio in ratios if ratio > 1e-6]
    if positive_ratios:
        ratio_spread = max(positive_ratios) / min(positive_ratios)

    if axis_errors or overall_ratio > max_overall_scale_ratio or ratio_spread > max_overall_scale_ratio:
        issues.append(
            Issue(
                "Error",
                "Model Collision Scale",
                config_path,
                f"Collision bounds {vector_text(collision_size)} do not match render bounds {vector_text(render_size)}. Axis ratios: {', '.join(axis_errors) if axis_errors else 'within per-axis tolerance'}; diagonal ratio {overall_ratio:.3g}x; axis spread {ratio_spread:.3g}x.",
                "Use collision.mode render_mesh for solid props, or derive primitive dimensions from exported source-unit mesh bounds and document why primitives are required.",
            )
        )


def collect_bounds_requests(
    root: Path,
    configs: list[tuple[Path, dict[str, Any], list[ModelDocShape], list[ModelDocShape]]],
) -> dict[str, Path]:
    requests: dict[str, Path] = {}
    for _, config, render_meshes, collision_shapes in configs:
        if bounds_size_from_config(config) is not None:
            continue
        for render in render_meshes:
            path = resolve_resource_path(root, render.filename)
            if path is not None:
                requests[path.resolve().as_posix()] = path
        for shape in collision_shapes:
            if shape.shape_class != "PhysicsMeshFile":
                continue
            path = resolve_resource_path(root, shape.filename)
            if path is not None:
                requests[path.resolve().as_posix()] = path
    return requests


def run_blender_bounds(blender: Path, requests: dict[str, Path], timeout_seconds: int, root: Path, issues: list[Issue]) -> dict[str, tuple[float, float, float]]:
    if not requests:
        return {}
    if not blender.exists():
        issues.append(Issue("Error", "Model Collision Scale", relative_path(blender, root), "Blender executable was not found for FBX bounds inspection.", "Install Blender or pass -BlenderExe to model_collision_scale_audit.ps1."))
        return {}

    missing = [path for path in requests.values() if not path.exists()]
    for path in missing:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(path, root), "Referenced FBX does not exist.", "Re-export the asset pipeline or fix the ModelDoc filename."))

    items = [{"key": key, "fbx": str(path)} for key, path in sorted(requests.items()) if path.exists()]
    if not items:
        return {}

    with tempfile.TemporaryDirectory(prefix="sbox-model-collision-bounds-") as temp_dir:
        temp = Path(temp_dir)
        input_path = temp / "input.json"
        script_path = temp / "inspect_fbx_bounds.py"
        input_path.write_text(json.dumps({"items": items}, indent=2), encoding="utf-8")
        script_path.write_text(BLENDER_BOUNDS_SCRIPT.replace("{input_path}", str(input_path).replace("\\", "\\\\")), encoding="utf-8")
        try:
            result = subprocess.run(
                [str(blender), "--background", "--factory-startup", "--python", str(script_path)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired:
            issues.append(Issue("Error", "Model Collision Scale", relative_path(blender, root), f"Blender bounds inspection timed out after {timeout_seconds} seconds.", "Inspect fewer configs with -Config or increase -TimeoutSeconds."))
            return {}

    output = result.stdout or ""
    if result.returncode != 0:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(blender, root), f"Blender bounds inspection exited {result.returncode}.", output[-1000:]))
        return {}

    match = re.search(re.escape(JSON_BEGIN) + r"\s*(?P<payload>.*?)\s*" + re.escape(JSON_END), output, re.S)
    if not match:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(blender, root), "Blender bounds inspection did not emit JSON payload.", output[-1000:]))
        return {}

    try:
        results = json.loads(match.group("payload"))
    except json.JSONDecodeError as exc:
        issues.append(Issue("Error", "Model Collision Scale", relative_path(blender, root), f"Failed to parse Blender bounds JSON: {exc}"))
        return {}

    bounds: dict[str, tuple[float, float, float]] = {}
    for entry in results:
        key = str(entry.get("key", ""))
        if not entry.get("ok", False):
            issues.append(Issue("Error", "Model Collision Scale", relative_path(Path(entry.get("fbx", "")), root), f"Failed to inspect FBX bounds: {entry.get('error', '')}", "Re-export the FBX or inspect it in Blender."))
            continue
        size = entry.get("size")
        if not isinstance(size, list) or len(size) != 3:
            issues.append(Issue("Error", "Model Collision Scale", relative_path(Path(entry.get("fbx", "")), root), "Blender returned invalid bounds size.", "Re-run the audit after checking the FBX import."))
            continue
        bounds[key] = (float(size[0]), float(size[1]), float(size[2]))
    return bounds


def render_size_for(
    root: Path,
    config: dict[str, Any],
    render_meshes: list[ModelDocShape],
    bounds_by_path: dict[str, tuple[float, float, float]],
    config_path: str,
    issues: list[Issue],
) -> tuple[float, float, float] | None:
    config_bounds = bounds_size_from_config(config)
    if config_bounds is not None:
        render_scale = render_meshes[0].import_scale if render_meshes else 1.0
        return scaled_size(config_bounds, render_scale)

    if not render_meshes:
        issues.append(Issue("Error", "Model Collision Scale", config_path, "VMDL has no RenderMeshFile to compare against.", "Regenerate the model document from the asset pipeline."))
        return None

    render = render_meshes[0]
    path = resolve_resource_path(root, render.filename)
    if path is None:
        issues.append(Issue("Error", "Model Collision Scale", config_path, f"RenderMeshFile has an unresolved filename '{render.filename}'.", "Use a project-local render mesh path."))
        return None
    key = path.resolve().as_posix()
    size = bounds_by_path.get(key)
    if size is None:
        issues.append(Issue("Error", "Model Collision Scale", config_path, f"Render mesh bounds were not available for '{render.filename}'.", "Run the audit with Blender available so render bounds can be measured."))
        return None
    return scaled_size(size, render.import_scale)


def collision_size_for(
    root: Path,
    collision_shapes: list[ModelDocShape],
    render_meshes: list[ModelDocShape],
    render_size: tuple[float, float, float] | None,
    bounds_by_path: dict[str, tuple[float, float, float]],
    config_path: str,
    issues: list[Issue],
) -> tuple[float, float, float] | None:
    mesh_shapes = [shape for shape in collision_shapes if shape.shape_class == "PhysicsMeshFile"]
    primitive_shapes = [shape for shape in collision_shapes if shape.shape_class != "PhysicsMeshFile"]

    if mesh_shapes:
        if len(mesh_shapes) > 1:
            issues.append(Issue("Warning", "Model Collision Scale", config_path, f"VMDL has {len(mesh_shapes)} PhysicsMeshFile nodes; comparing the first one.", "Keep generated solid-prop collision to one render_mesh PhysicsMeshFile unless there is a documented split-collision reason."))
        shape = mesh_shapes[0]
        if render_meshes and render_size is not None:
            render = render_meshes[0]
            if shape.filename.replace("\\", "/").lower() == render.filename.replace("\\", "/").lower():
                render_scale = abs(float(render.import_scale))
                if render_scale <= 1e-6:
                    issues.append(Issue("Error", "Model Collision Scale", config_path, "RenderMeshFile import_scale is zero.", "Use a non-zero render import_scale before comparing collision bounds."))
                    return None
                scale_ratio = abs(float(shape.import_scale)) / render_scale
                return tuple(float(value) * scale_ratio for value in render_size)
        path = resolve_resource_path(root, shape.filename)
        if path is None:
            issues.append(Issue("Error", "Model Collision Scale", config_path, f"PhysicsMeshFile has an unresolved filename '{shape.filename}'.", "Use a project-local collision mesh path."))
            return None
        size = bounds_by_path.get(path.resolve().as_posix())
        if size is None:
            issues.append(Issue("Error", "Model Collision Scale", config_path, f"Collision mesh bounds were not available for '{shape.filename}'.", "Run the audit with Blender available so collision bounds can be measured."))
            return None
        return scaled_size(size, shape.import_scale)

    if primitive_shapes:
        return primitive_union_size(primitive_shapes, config_path, issues)

    return None


def audit_config(
    root: Path,
    config_path: Path,
    config: dict[str, Any],
    render_meshes: list[ModelDocShape],
    collision_shapes: list[ModelDocShape],
    bounds_by_path: dict[str, tuple[float, float, float]],
    args: argparse.Namespace,
    issues: list[Issue],
) -> None:
    config_rel = relative_path(config_path, root)
    mode = collision_mode(config)

    if not collision_is_enabled(mode):
        if args.show_info:
            issues.append(Issue("Info", "Model Collision Scale", config_rel, "No generated model collision declared; skipped bounds comparison."))
        return

    if mode in {"primitives", "shapes"} or config.get("physics_shapes") is not None:
        reason = primitive_reason(config)
        if not reason:
            issues.append(
                Issue(
                    "Error",
                    "Model Collision Scale",
                    config_rel,
                    "Primitive/legacy physics_shapes collision is declared without a documented exception reason.",
                    "Default solid props to collision.mode render_mesh. Use primitives only for a documented hollow/climb-through/blocker reason, with dimensions derived from exported source-unit bounds.",
                )
            )

    if not collision_shapes:
        issues.append(
            Issue(
                "Error",
                "Model Collision Scale",
                config_rel,
                "Collision is declared but the generated VMDL has no PhysicsShapeList child shapes; ModelCollider.LocalBounds would compile as zero.",
                "Re-export the VMDL from the asset pipeline and keep PhysicsMeshFile under PhysicsShapeList.",
            )
        )
        return

    render_size = render_size_for(root, config, render_meshes, bounds_by_path, config_rel, issues)
    collision_size = collision_size_for(root, collision_shapes, render_meshes, render_size, bounds_by_path, config_rel, issues)
    if render_size is None or collision_size is None:
        return

    compare_bounds(render_size, collision_size, config_rel, issues, args.axis_tolerance, args.max_overall_scale_ratio)

    if args.show_info:
        mesh_kinds = ", ".join(sorted({shape.shape_class for shape in collision_shapes}))
        issues.append(Issue("Info", "Model Collision Scale", config_rel, f"Compared render bounds {vector_text(render_size)} with collision bounds {vector_text(collision_size)} ({mesh_kinds})."))


def main() -> int:
    args = parse_args()
    root = resolve_root(args.root)
    issues: list[Issue] = []

    configs: list[tuple[Path, dict[str, Any], list[ModelDocShape], list[ModelDocShape]]] = []
    for config_path in discover_configs(root, args.config):
        config = load_json(config_path, issues, root)
        if config is None:
            continue
        if "target_vmdl" not in config:
            continue
        target_vmdl = resolve_project_path(root, str(config.get("target_vmdl", "")))
        if target_vmdl is None:
            issues.append(Issue("Error", "Model Collision Scale", relative_path(config_path, root), "Config target_vmdl is blank or unresolved.", "Set target_vmdl to the generated model document path."))
            continue
        if not target_vmdl.exists():
            issues.append(Issue("Error", "Model Collision Scale", relative_path(config_path, root), f"target_vmdl does not exist: {relative_path(target_vmdl, root)}", "Run the asset pipeline before collision-scale audit."))
            continue
        render_meshes, collision_shapes = read_modeldoc(target_vmdl, issues, root)
        configs.append((config_path, config, render_meshes, collision_shapes))

    bounds_requests = collect_bounds_requests(root, configs)
    bounds_by_path = run_blender_bounds(Path(args.blender_exe), bounds_requests, args.timeout_seconds, root, issues)

    for config_path, config, render_meshes, collision_shapes in configs:
        audit_config(root, config_path, config, render_meshes, collision_shapes, bounds_by_path, args, issues)

    if not issues:
        print("No blocking issues found.")
    else:
        for issue in issues:
            print_issue(issue, args.show_info)

    if any(issue.severity == "Error" for issue in issues):
        return 1
    if args.fail_on_warning and any(issue.severity == "Warning" for issue in issues):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
