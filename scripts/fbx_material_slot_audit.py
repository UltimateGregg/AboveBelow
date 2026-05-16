#!/usr/bin/env python3
"""Compare generated ModelDoc material sources with exported FBX material slots."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
EXCLUDED_DIRS = {".git", ".tmpbuild", "bin", "obj", "node_modules"}
JSON_BEGIN = "__FBX_MATERIAL_SLOT_AUDIT_JSON_BEGIN__"
JSON_END = "__FBX_MATERIAL_SLOT_AUDIT_JSON_END__"

VMDL_FROM_RE = re.compile(r'\bfrom\s*=\s*"([^"]+)"')

BLENDER_SCRIPT = r'''
import json
import bpy

JSON_BEGIN = "__FBX_MATERIAL_SLOT_AUDIT_JSON_BEGIN__"
JSON_END = "__FBX_MATERIAL_SLOT_AUDIT_JSON_END__"

with open(r"{input_path}", "r", encoding="utf-8") as handle:
    payload = json.load(handle)

results = []
for item in payload["items"]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    entry = {
        "key": item["key"],
        "fbx": item["fbx"],
        "ok": True,
        "error": "",
        "objects": [],
        "material_names": [],
    }

    try:
        bpy.ops.import_scene.fbx(filepath=item["fbx"])
        material_names = set()
        objects = []
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            slot_names = []
            index_counts = {}
            for slot in obj.material_slots:
                if slot.material is not None:
                    slot_names.append(slot.material.name)
                    material_names.add(slot.material.name)
                else:
                    slot_names.append(None)
            for poly in obj.data.polygons:
                key = str(poly.material_index)
                index_counts[key] = index_counts.get(key, 0) + 1
            objects.append({
                "name": obj.name,
                "mesh": obj.data.name,
                "materials": slot_names,
                "index_counts": index_counts,
            })
        entry["objects"] = objects
        entry["material_names"] = sorted(material_names)
    except Exception as exc:
        entry["ok"] = False
        entry["error"] = str(exc)

    results.append(entry)

print(JSON_BEGIN)
print(json.dumps(results, sort_keys=True))
print(JSON_END)
'''


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit FBX material slots against ModelDoc remaps.")
    parser.add_argument("--root", default="", help="Project root. Defaults to current working directory.")
    parser.add_argument("--config", action="append", default=[], help="Asset pipeline config to inspect. May be repeated.")
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER, help="Path to Blender executable.")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Maximum Blender inspection time.")
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


def print_issue(severity: str, area: str, path: str, message: str, recommendation: str = "") -> None:
    location = f" [{path}]" if path else ""
    print(f"[{severity}] {area}{location} - {' '.join(str(message).split())}")
    if recommendation:
        print(f"  Recommendation: {' '.join(str(recommendation).split())}")


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        print_issue("Error", "FBX Material Slots", path.as_posix(), f"Failed to parse config: {exc}")
        return None
    if not isinstance(data, dict):
        print_issue("Error", "FBX Material Slots", path.as_posix(), "Config must contain a JSON object.")
        return None
    return data


def resolve_project_path(root: Path, value: str | None) -> Path | None:
    if value is None or not str(value).strip() or "${" in str(value):
        return None
    path = Path(str(value))
    if path.is_absolute():
        return path
    return root / path


def bool_option(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "on"}:
        return True
    if text in {"false", "0", "no", "off", "none", "null"}:
        return False
    return bool(value)


def discover_configs(root: Path, explicit: list[str]) -> list[Path]:
    if explicit:
        return [resolve_project_path(root, value) or Path(value) for value in explicit]

    scripts_dir = root / "scripts"
    configs: list[Path] = []
    for current_root, dirs, files in os.walk(scripts_dir):
        dirs[:] = [name for name in dirs if name not in EXCLUDED_DIRS]
        for file_name in files:
            if file_name.endswith("_asset_pipeline.json"):
                configs.append(Path(current_root) / file_name)
    return sorted(configs, key=lambda path: path.as_posix().lower())


def read_vmdl_sources(path: Path) -> list[str]:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError:
        return []
    return VMDL_FROM_RE.findall(raw)


def should_inspect(config: dict[str, Any]) -> bool:
    if not isinstance(config.get("material_remap"), dict) or not config["material_remap"]:
        return False
    if bool_option(config.get("verify_vmdl_sources_against_fbx"), False):
        return True
    if bool_option(config.get("strict_vmdl_material_sources"), False):
        return True
    if "vmdl_use_global_default" in config and not bool_option(config.get("vmdl_use_global_default"), True):
        return True
    return False


def run_blender(blender: Path, items: list[dict[str, str]], timeout_seconds: int) -> dict[str, dict[str, Any]] | None:
    with tempfile.TemporaryDirectory(prefix="sbox-fbx-material-audit-") as temp_dir:
        temp = Path(temp_dir)
        input_path = temp / "input.json"
        script_path = temp / "inspect_fbx_materials.py"
        input_path.write_text(json.dumps({"items": items}, indent=2), encoding="utf-8")
        script_path.write_text(BLENDER_SCRIPT.replace("{input_path}", str(input_path).replace("\\", "\\\\")), encoding="utf-8")

        try:
            result = subprocess.run(
                [str(blender), "--background", "--python", str(script_path)],
                text=True,
                capture_output=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired:
            print_issue("Error", "FBX Material Slots", "", f"Blender inspection timed out after {timeout_seconds}s.")
            return None

    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0:
        print_issue("Error", "FBX Material Slots", "", f"Blender exited with {result.returncode}: {output.strip()}")
        return None

    begin = output.find(JSON_BEGIN)
    end = output.find(JSON_END)
    if begin == -1 or end == -1 or end <= begin:
        print_issue("Error", "FBX Material Slots", "", "Blender inspection did not return parseable JSON.")
        return None

    json_text = output[begin + len(JSON_BEGIN):end].strip()
    try:
        rows = json.loads(json_text)
    except json.JSONDecodeError as exc:
        print_issue("Error", "FBX Material Slots", "", f"Failed to parse Blender inspection JSON: {exc}")
        return None

    return {str(row["key"]): row for row in rows if isinstance(row, dict) and "key" in row}


def main() -> int:
    args = parse_args()
    root = resolve_root(args.root)
    blender = Path(args.blender_exe)
    errors = 0

    config_paths = discover_configs(root, args.config)
    selected: list[dict[str, Any]] = []
    blender_items: list[dict[str, str]] = []

    for config_path in config_paths:
        if config_path is None:
            continue
        config_path = config_path.resolve()
        config = load_json(config_path)
        if config is None:
            errors += 1
            continue
        if not should_inspect(config):
            continue

        fbx = resolve_project_path(root, config.get("target_fbx"))
        vmdl = resolve_project_path(root, config.get("target_vmdl"))
        rel_config = relative_path(config_path, root)
        if fbx is None or vmdl is None:
            print_issue("Error", "FBX Material Slots", rel_config, "Strict material config needs target_fbx and target_vmdl paths.")
            errors += 1
            continue
        if not fbx.exists():
            print_issue("Error", "FBX Material Slots", rel_config, f"target_fbx does not exist: {relative_path(fbx, root)}")
            errors += 1
            continue
        if not vmdl.exists():
            print_issue("Error", "FBX Material Slots", rel_config, f"target_vmdl does not exist: {relative_path(vmdl, root)}")
            errors += 1
            continue

        key = str(len(selected))
        selected.append(
            {
                "key": key,
                "config_path": config_path,
                "config": config,
                "fbx": fbx,
                "vmdl": vmdl,
                "vmdl_sources": read_vmdl_sources(vmdl),
            }
        )
        blender_items.append({"key": key, "fbx": str(fbx)})

    if not selected:
        print_issue("Info", "FBX Material Slots", "", "No strict FBX material-slot configs found.")
        return 0

    if not blender.exists():
        print_issue("Warning", "FBX Material Slots", "", f"Blender executable not found: {blender}")
        return 0

    inspected = run_blender(blender, blender_items, args.timeout_seconds)
    if inspected is None:
        return 1

    for item in selected:
        config = item["config"]
        rel_config = relative_path(item["config_path"], root)
        row = inspected.get(item["key"])
        strict = bool_option(config.get("strict_vmdl_material_sources"), False)
        global_default = bool_option(config.get("vmdl_use_global_default"), True)
        severity = "Error" if strict or not global_default else "Warning"

        if row is None or not row.get("ok", False):
            message = "FBX import failed"
            if row and row.get("error"):
                message += f": {row['error']}"
            print_issue(severity, "FBX Material Slots", rel_config, message, "Open/export the source blend and inspect the FBX before handoff.")
            if severity == "Error":
                errors += 1
            continue

        material_names = set(str(name) for name in row.get("material_names", []))
        expected_raw = set(str(name) for name in config.get("material_remap", {}).keys())
        missing_raw = sorted(name for name in expected_raw if name not in material_names and not any(slot.startswith(name + ".") for slot in material_names))
        if missing_raw:
            print_issue(
                severity,
                "FBX Material Slots",
                rel_config,
                f"FBX is missing material slot(s) from material_remap: {', '.join(missing_raw)}.",
                "Fix Blender material names or update material_remap before exporting.",
            )
            if severity == "Error":
                errors += 1

        vmdl_sources = set(str(source) for source in item["vmdl_sources"])
        missing_vmdl_sources = sorted(
            source for source in vmdl_sources
            if source not in material_names and not any(slot.startswith(source + ".") for slot in material_names)
        )
        if missing_vmdl_sources:
            suffix_hints = [
                source for source in missing_vmdl_sources
                if source.endswith(".vmat") and source[:-5] in material_names
            ]
            detail = f"VMDL remap source(s) do not match exported FBX material slots: {', '.join(missing_vmdl_sources)}."
            if suffix_hints:
                detail += " These look like .vmat suffix mismatches against raw FBX material names."
            print_issue(
                severity,
                "FBX Material Slots",
                relative_path(item["vmdl"], root),
                detail,
                "Set vmdl_material_source_suffix to the FBX slot style and re-export with asset_pipeline.py.",
            )
            if severity == "Error":
                errors += 1
        else:
            print_issue("Info", "FBX Material Slots", rel_config, f"Checked {len(material_names)} FBX material slot(s).")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
