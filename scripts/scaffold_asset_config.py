#!/usr/bin/env python3
"""
scaffold_asset_config.py

Generate a starter asset_pipeline config from a .blend file by running
Blender headless to introspect objects and material slots. Writes to
scripts/<assetname>_asset_pipeline.json by default.

Defaults reflect this project's conventions:
  axis_forward = -Y, axis_up = Z, global_scale = 0.0254,
  combine_meshes = true, target_* under Assets/models/<assetname>.{fbx,vmdl},
  material slots mapped to materials/<lowercased_slot>.vmat (with a leading
  "M_" stripped, since that's how this project names slot blocks).

Refuses to overwrite an existing config without --force, so it is safe to
call from the auto-export hook on every save.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def asset_name_from_blend(blend_path: Path) -> str:
    name = blend_path.name
    while name.lower().endswith(".blend"):
        name = name[: -len(".blend")]
    return name


# Runs inside Blender --background. Writes a JSON summary to the path passed
# after the lone "--" separator on the command line.
INTROSPECT_SCRIPT = textwrap.dedent(
    """
    import json
    import sys
    from pathlib import Path

    import bpy

    sep = sys.argv.index("--")
    result_path = Path(sys.argv[sep + 1])

    mesh_objects = []
    material_slot_names = []
    seen_materials = set()

    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            mesh_objects.append({
                "name": obj.name,
                "parent": obj.parent.name if obj.parent else None,
                "vertex_count": len(obj.data.vertices) if obj.data else 0,
            })
            for slot in obj.material_slots:
                if slot.material and slot.material.name not in seen_materials:
                    seen_materials.add(slot.material.name)
                    material_slot_names.append(slot.material.name)

    root = None
    for obj in bpy.context.scene.objects:
        if (
            obj.type == "EMPTY"
            and obj.parent is None
            and any(c.type == "MESH" for c in obj.children_recursive)
        ):
            root = obj.name
            break

    top_collection = None
    for child in bpy.context.scene.collection.children:
        top_collection = child.name
        break

    data = {
        "root_object": root,
        "mesh_objects": mesh_objects,
        "material_slot_names": material_slot_names,
        "top_collection": top_collection,
    }
    result_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    """
).lstrip()


def introspect_blend(blend_path: Path, blender_exe: Path) -> dict:
    script_file = tempfile.NamedTemporaryFile(
        mode="w", suffix=".py", delete=False, encoding="utf-8"
    )
    script_file.write(INTROSPECT_SCRIPT)
    script_file.close()

    result_file = tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8"
    )
    result_file.close()

    try:
        cmd = [
            str(blender_exe),
            "--background",
            str(blend_path),
            "--python",
            script_file.name,
            "--",
            result_file.name,
        ]
        completed = subprocess.run(cmd, capture_output=True, text=True)
        if completed.returncode != 0:
            sys.stderr.write(completed.stdout or "")
            sys.stderr.write(completed.stderr or "")
            raise RuntimeError(
                f"Blender headless introspection failed (exit {completed.returncode})"
            )
        return json.loads(Path(result_file.name).read_text(encoding="utf-8"))
    finally:
        for p in (script_file.name, result_file.name):
            try:
                Path(p).unlink()
            except OSError:
                pass


def material_to_vmat(slot_name: str) -> str:
    name = slot_name
    if len(name) >= 2 and name[0] in ("M", "m") and name[1] == "_":
        name = name[2:]
    name = name.lower()
    return f"materials/{name}.vmat"


def combined_name_for(asset_name: str) -> str:
    pascal = "".join(part.capitalize() for part in asset_name.replace("-", "_").split("_") if part)
    return f"{pascal or 'Combined'}Mesh"


def build_config(blend_path: Path, info: dict, root: Path) -> dict:
    asset_name = asset_name_from_blend(blend_path)
    try:
        rel_blend = blend_path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        rel_blend = blend_path.as_posix()

    material_slots = info.get("material_slot_names") or []
    material_remap = {slot: material_to_vmat(slot) for slot in material_slots}

    combined_name = combined_name_for(asset_name)

    config: dict = {
        "source_blend": rel_blend,
        "target_fbx": f"Assets/models/{asset_name}.fbx",
        "target_vmdl": f"Assets/models/{asset_name}.vmdl",
        "model_resource_path": f"models/{asset_name}.vmdl",
        "combine_meshes": True,
        "combined_object_name": combined_name,
        "material_remap": material_remap,
        "verify_fbx": True,
        "required_object": [combined_name],
        "object_type": ["EMPTY", "MESH"],
        "global_scale": 0.0254,
        "axis_forward": "-Y",
        "axis_up": "Z",
    }

    # Only set root_object when there is a clear top-level Empty container.
    # Otherwise asset_pipeline.py exports every EMPTY/MESH at scene root, which
    # is what we want for collections of unparented parts (most procedurally
    # built models — water tower, weapons, etc.).
    if info.get("root_object"):
        config["root_object"] = info["root_object"]

    return config


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blend", help="Path to the .blend file to scaffold")
    parser.add_argument(
        "--out", help="Output config path. Default: scripts/<assetname>_asset_pipeline.json"
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing config")
    parser.add_argument("--blender-exe", default=DEFAULT_BLENDER, help="Path to Blender executable")
    args = parser.parse_args(argv)

    blend = Path(args.blend).resolve()
    if not blend.exists():
        sys.exit(f"Blend file not found: {blend}")

    asset_name = asset_name_from_blend(blend)
    root = project_root()
    out_path = (
        Path(args.out).resolve()
        if args.out
        else root / "scripts" / f"{asset_name}_asset_pipeline.json"
    )

    if out_path.exists() and not args.force:
        print(f"Config already exists: {out_path}")
        print("Use --force to overwrite, or edit the file manually.")
        return 0

    blender_exe = Path(args.blender_exe)
    if not blender_exe.exists():
        sys.exit(f"Blender executable not found: {blender_exe}")

    print(f"Introspecting {blend.name} ...")
    info = introspect_blend(blend, blender_exe)

    config = build_config(blend, info, root)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {out_path}")
    print(f"  root_object       : {config.get('root_object', '<all top-level objects>')}")
    print(f"  combined name     : {config['combined_object_name']}")
    print(f"  material slots    : {len(config['material_remap'])}")
    print(f"  target_fbx        : {config['target_fbx']}")
    print(f"  target_vmdl       : {config['target_vmdl']}")
    print()
    print("Review the material_remap paths if they don't match your .vmat names,")
    print("then save the .blend again (or rerun the pipeline) to export.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
