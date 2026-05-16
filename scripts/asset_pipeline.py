#!/usr/bin/env python3
"""
General Blender-to-S&Box asset pipeline.

This script exports a named object hierarchy from a .blend file to an FBX asset,
optionally verifies the exported FBX by importing it back into Blender, and can
wire a prefab's visual ModelRenderer to the exported asset path.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
DEFAULT_COLOR_TEXTURE = "materials/default/default_color.tga"
TEXTURE_COLOR_RE = re.compile(r'"TextureColor"\s*"([^"]+)"')
TEXTURE_RE = re.compile(r'"Texture[^"]*"\s*"([^"]+)"')


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def asset_name_from_blend(path: str) -> str:
    name = Path(path).name
    while name.lower().endswith(".blend"):
        name = name[:-len(".blend")]
    return Path(name).stem


def expand_config_variables(value: Any, variables: dict[str, str]) -> Any:
    if isinstance(value, str):
        for key, replacement in variables.items():
            value = value.replace("${" + key + "}", replacement)
        return value
    if isinstance(value, list):
        return [expand_config_variables(item, variables) for item in value]
    if isinstance(value, dict):
        return {key: expand_config_variables(item, variables) for key, item in value.items()}
    return value


def resolve_path(value: str | None, root: Path) -> Path | None:
    if not value:
        return None
    path = Path(value)
    return path if path.is_absolute() else root / path


def resolve_asset_resource_path(value: str, root: Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    if path.parts and path.parts[0].lower() == "assets":
        return root / path
    return root / "Assets" / path


def normalize_resource_path(value: str) -> str:
    return value.replace("\\", "/").lower()


def normalize_modeldoc_material_source_suffix(value: Any) -> str:
    if value is None or value is False:
        return ""
    if value is True:
        return ".vmat"
    suffix = str(value)
    if suffix.lower() in {"false", "none", "null"}:
        return ""
    return suffix


def modeldoc_material_source_name(name: str, suffix: Any = ".vmat") -> str:
    suffix = normalize_modeldoc_material_source_suffix(suffix)
    if not suffix:
        return name
    return name if name.lower().endswith(suffix.lower()) else f"{name}{suffix}"


def texture_color_from_vmat(path: Path) -> str | None:
    match = TEXTURE_COLOR_RE.search(path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def texture_paths_from_vmat(path: Path) -> list[str]:
    return TEXTURE_RE.findall(path.read_text(encoding="utf-8"))


def compiled_texture_glob(texture_path: Path) -> str:
    suffix = texture_path.suffix.lstrip(".")
    if not suffix:
        return texture_path.name + "_*.generated.vtex_c"
    return f"{texture_path.stem}_{suffix}_*.generated.vtex_c"


def validate_material_remaps(
    material_remaps: dict[str, str] | None,
    root: Path,
    allow_default_color_texture: bool = False,
) -> None:
    remaps = material_remaps or {}
    if not remaps:
        return

    for source, target in sorted(remaps.items()):
        material_path = resolve_asset_resource_path(target, root)
        if not material_path.exists():
            raise FileNotFoundError(
                f"Material remap for {source!r} points to missing material: {target}"
            )

        texture_color = texture_color_from_vmat(material_path)
        if not texture_color:
            print(f"Warning: {target} has no TextureColor entry")
            continue

        normalized_texture = normalize_resource_path(texture_color)
        if normalized_texture == DEFAULT_COLOR_TEXTURE and not allow_default_color_texture:
            raise ValueError(
                f"Material remap for {source!r} uses {DEFAULT_COLOR_TEXTURE}. "
                "Create an asset-specific color texture or set "
                "allow_default_color_texture only for intentional placeholders."
            )

        texture_path = resolve_asset_resource_path(texture_color, root)
        if not texture_path.exists():
            raise FileNotFoundError(
                f"Material {target} points to missing TextureColor image: {texture_color}"
            )

    print(f"Validated material remaps: {len(remaps)} material(s)")


def clear_material_compiled_caches(material_remaps: dict[str, str] | None, root: Path) -> int:
    remaps = material_remaps or {}
    removed = 0
    for target in sorted(set(remaps.values())):
        material_path = resolve_asset_resource_path(target, root)
        if not material_path.exists():
            continue

        compiled_material = Path(str(material_path) + "_c")
        if compiled_material.exists():
            compiled_material.unlink()
            removed += 1

        for texture in texture_paths_from_vmat(material_path):
            texture_path = resolve_asset_resource_path(texture, root)
            if not texture_path.exists():
                continue

            for compiled_texture in texture_path.parent.glob(compiled_texture_glob(texture_path)):
                compiled_texture.unlink()
                removed += 1

    if removed:
        print(f"Cleared material compiled cache: {removed} file(s)")
    return removed



def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def backup(path: Path, reason: str, root: Path) -> Path | None:
    if not path.exists():
        return None
    suffix = path.suffix
    try:
        relative_parent = path.resolve().parent.relative_to(root.resolve())
    except ValueError:
        relative_parent = Path("_external")

    backup_dir = root / ".tmpbuild" / "asset_backups" / relative_parent
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / f"{path.stem}.before-{reason}-{timestamp()}{suffix}"
    shutil.copy2(path, backup_path)
    print(f"Backup: {backup_path}")
    return backup_path


def resource_path_for(asset_path: Path, root: Path) -> str:
    assets_root = root / "Assets"
    try:
        return asset_path.resolve().relative_to(assets_root.resolve()).as_posix()
    except ValueError as exc:
        raise ValueError(f"Asset path must be inside {assets_root}: {asset_path}") from exc


def write_vmdl(
    path: Path,
    fbx_resource_path: str,
    material_remaps: dict[str, str] | None = None,
    material_source_suffix: Any = ".vmat",
    use_global_default: bool = True,
    global_default_material: str = "materials/default.vmat",
) -> None:
    remaps = material_remaps or {}
    remap_blocks = []
    for source, target in sorted(remaps.items()):
        source_name = modeldoc_material_source_name(source, material_source_suffix)
        remap_blocks.append(
            f"""
\t\t\t\t\t\t\t{{
\t\t\t\t\t\t\t\tfrom = "{source_name}"
\t\t\t\t\t\t\t\tto = "{target}"
\t\t\t\t\t\t\t}},
""".rstrip()
        )
    remap_text = "\n".join(remap_blocks)

    path.write_text(
        f"""<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:modeldoc29:version{{3cec427c-1b0e-4d48-a90a-0436f33a6041}} -->
{{
\trootNode = 
\t{{
\t\t_class = "RootNode"
\t\tchildren = 
\t\t[
\t\t\t{{
\t\t\t\t_class = "MaterialGroupList"
\t\t\t\tchildren = 
\t\t\t\t[
\t\t\t\t\t{{
\t\t\t\t\t\t_class = "DefaultMaterialGroup"
\t\t\t\t\t\tremaps = 
\t\t\t\t\t\t[
{remap_text}
\t\t\t\t\t\t]
\t\t\t\t\t\tuse_global_default = {str(bool(use_global_default)).lower()}
\t\t\t\t\t\tglobal_default_material = "{global_default_material}"
\t\t\t\t\t}},
\t\t\t\t]
\t\t\t}},
\t\t\t{{
\t\t\t\t_class = "RenderMeshList"
\t\t\t\tchildren = 
\t\t\t\t[
\t\t\t\t\t{{
\t\t\t\t\t\t_class = "RenderMeshFile"
\t\t\t\t\t\tname = "LOD0"
\t\t\t\t\t\tfilename = "{fbx_resource_path}"
\t\t\t\t\t\timport_translation = [ 0.0, 0.0, 0.0 ]
\t\t\t\t\t\timport_rotation = [ 0.0, 0.0, 0.0 ]
\t\t\t\t\t\timport_scale = 1.0
\t\t\t\t\t\talign_origin_x_type = "None"
\t\t\t\t\t\talign_origin_y_type = "None"
\t\t\t\t\t\talign_origin_z_type = "None"
\t\t\t\t\t\tparent_bone = ""
\t\t\t\t\t\timport_filter = 
\t\t\t\t\t\t{{
\t\t\t\t\t\t\texclude_by_default = false
\t\t\t\t\t\t\texception_list = [  ]
\t\t\t\t\t\t}}
\t\t\t\t\t}},
\t\t\t\t]
\t\t\t}},
\t\t]
\t\tmodel_archetype = ""
\t\tprimary_associated_entity = ""
\t\tanim_graph_name = ""
\t}}
}}
""",
        encoding="utf-8",
    )


def write_blender_export_script(script_path: Path, config_path: Path) -> None:
    script_path.write_text(
        f"""
import json
from pathlib import Path

import bpy

config = json.loads(Path(r"{config_path}").read_text(encoding="utf-8"))
target = Path(config["target_fbx"])
target.parent.mkdir(parents=True, exist_ok=True)
result_path = Path(config["result_path"])
material_remaps = config.get("material_remap", {{}})

root_name = config.get("root_object")
root = bpy.data.objects.get(root_name) if root_name else None
if root_name and root is None:
    raise RuntimeError(f"Root object not found: {{root_name}}")

if root is not None:
    export_objects = [root] + list(root.children_recursive)
else:
    export_objects = [
        obj for obj in bpy.context.scene.objects
        if obj.type in config.get("object_types", ["EMPTY", "MESH"])
    ]

if not export_objects:
    raise RuntimeError("No objects matched the export selection")

source_object_names = [obj.name for obj in export_objects]

if config.get("combine_meshes", False):
    mesh_sources = [obj for obj in export_objects if obj.type == "MESH"]
    if not mesh_sources:
        raise RuntimeError("combine_meshes is enabled, but no mesh objects were selected")

    combined_objects = []
    for obj in mesh_sources:
        mesh = obj.data.copy()
        mesh.transform(obj.matrix_world)
        mesh.update()
        copy = bpy.data.objects.new(obj.name + "_ExportMesh", mesh)
        bpy.context.scene.collection.objects.link(copy)
        copy.location = (0.0, 0.0, 0.0)
        copy.rotation_euler = (0.0, 0.0, 0.0)
        copy.scale = (1.0, 1.0, 1.0)
        combined_objects.append(copy)

    for obj in bpy.data.objects:
        obj.select_set(False)
    for obj in combined_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = combined_objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = config.get("combined_object_name", root_name or "CombinedModel")
    joined.data.name = joined.name + "_mesh"
    export_objects = [joined]

for obj in bpy.data.objects:
    obj.select_set(False)

for obj in export_objects:
    obj.select_set(True)

bpy.context.view_layer.objects.active = root or export_objects[0]

bpy.ops.export_scene.fbx(
    filepath=str(target),
    use_selection=True,
    object_types=set(config.get("object_types", ["EMPTY", "MESH"])),
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    add_leaf_bones=False,
    bake_space_transform=False,
    apply_unit_scale=True,
    global_scale=float(config.get("global_scale", 1.0)),
    axis_forward=config.get("axis_forward", "-Z"),
    axis_up=config.get("axis_up", "Y"),
    path_mode="AUTO",
)

result = {{
    "exported_to": str(target),
    "source_objects": source_object_names,
    "selected_objects": [obj.name for obj in export_objects],
    "bytes": target.stat().st_size if target.exists() else 0,
}}

if config.get("verify_fbx", False):
    temp_collection = bpy.data.collections.new("AssetPipeline_Verify_Temp")
    bpy.context.scene.collection.children.link(temp_collection)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(target))
    new_objects = [obj for obj in bpy.data.objects if obj not in before]
    for obj in new_objects:
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        temp_collection.objects.link(obj)

    names = sorted(obj.name for obj in new_objects)
    required = config.get("required_objects", [])
    missing = [
        name for name in required
        if not any(obj.name == name or obj.name.startswith(name + ".") for obj in new_objects)
    ]
    result["verify"] = {{
        "object_count": len(names),
        "mesh_count": sum(1 for obj in new_objects if obj.type == "MESH"),
        "empty_count": sum(1 for obj in new_objects if obj.type == "EMPTY"),
        "names": names,
        "missing_required": missing,
    }}

    if material_remaps:
        material_names = sorted({{
            slot.material.name
            for obj in new_objects
            if obj.type == "MESH"
            for slot in obj.material_slots
            if slot.material is not None
        }})
        missing_materials = [
            name for name in sorted(material_remaps)
            if not any(slot == name or slot.startswith(name + ".") for slot in material_names)
        ]
        result["verify"]["material_names"] = material_names
        result["verify"]["missing_materials"] = missing_materials

    for obj in list(new_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(temp_collection)

result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
""".lstrip(),
        encoding="utf-8",
    )


def run_blender_export(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    blender = Path(args.blender_exe)
    source_blend = resolve_path(args.source_blend, root)
    target_fbx = resolve_path(args.target_fbx, root)
    if source_blend is None or target_fbx is None:
        raise ValueError("--source-blend and --target-fbx are required for export")
    if not blender.exists():
        raise FileNotFoundError(f"Blender executable not found: {blender}")
    if not source_blend.exists():
        raise FileNotFoundError(f"Source .blend file not found: {source_blend}")

    backup(target_fbx, "asset-pipeline-export", root)

    work_dir = root / ".tmpbuild" / "asset_pipeline"
    work_dir.mkdir(parents=True, exist_ok=True)
    config_path = work_dir / "blender_export_config.json"
    result_path = work_dir / "blender_export_result.json"
    script_path = work_dir / "blender_export_asset.py"

    config = {
        "root_object": args.root_object,
        "target_fbx": str(target_fbx),
        "result_path": str(result_path),
        "verify_fbx": args.verify_fbx,
        "required_objects": args.required_object or [],
        "object_types": args.object_type or ["EMPTY", "MESH"],
        "combine_meshes": args.combine_meshes,
        "combined_object_name": args.combined_object_name,
        "global_scale": args.global_scale,
        "axis_forward": args.axis_forward,
        "axis_up": args.axis_up,
        "material_remap": args.material_remap or {},
    }
    config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    write_blender_export_script(script_path, config_path)

    command = [
        str(blender),
        "--background",
        str(source_blend),
        "--python",
        str(script_path),
        "--python-exit-code",
        "1",
    ]
    completed = subprocess.run(command, cwd=root, text=True, capture_output=True)
    if completed.stdout:
        print(completed.stdout.strip())
    if completed.stderr:
        print(completed.stderr.strip(), file=sys.stderr)
    if completed.returncode != 0:
        raise RuntimeError(f"Blender export failed with exit code {completed.returncode}")

    result = load_json(result_path)
    verify = result.get("verify")
    if isinstance(verify, dict) and verify.get("missing_required"):
        missing = ", ".join(verify["missing_required"])
        raise RuntimeError(f"FBX verification failed; missing required objects: {missing}")
    if isinstance(verify, dict) and verify.get("missing_materials"):
        missing = ", ".join(verify["missing_materials"])
        names = ", ".join(verify.get("material_names", [])) or "<none>"
        raise RuntimeError(
            f"FBX verification failed; missing remapped material slots: {missing}. "
            f"Exported material slots: {names}"
        )

    print(f"Exported: {result['exported_to']} ({result['bytes']} bytes)")
    return result


def iter_gameobjects(node: dict[str, Any]):
    yield node
    for child in node.get("Children", []) or []:
        yield from iter_gameobjects(child)


def update_prefab(args: argparse.Namespace, root: Path, model_resource_path: str) -> None:
    prefab = resolve_path(args.prefab, root)
    if prefab is None:
        return
    if not prefab.exists():
        raise FileNotFoundError(f"Prefab not found: {prefab}")

    data = load_json(prefab)
    root_object = data.get("RootObject")
    if not isinstance(root_object, dict):
        raise ValueError(f"{prefab} does not look like an S&Box prefab")

    target = None
    for gameobject in iter_gameobjects(root_object):
        if gameobject.get("Name") == args.visual_object:
            target = gameobject
            break
    if target is None:
        raise ValueError(f"GameObject named {args.visual_object!r} was not found in {prefab}")

    renderer = None
    for component in target.get("Components", []) or []:
        if component.get("__type") == "Sandbox.ModelRenderer":
            renderer = component
            break
    if renderer is None:
        raise ValueError(f"{args.visual_object!r} does not have a Sandbox.ModelRenderer")

    renderer["Model"] = model_resource_path
    if args.material_override:
        renderer["MaterialOverride"] = args.material_override
    if args.visual_tint:
        renderer["Tint"] = args.visual_tint
    if args.visual_scale:
        target["Scale"] = args.visual_scale
    if args.clear_visual_children:
        target.pop("Children", None)

    if args.dry_run:
        print(f"Dry run: would update {prefab} ModelRenderer to {model_resource_path}")
        return

    backup(prefab, "asset-pipeline-prefab", root)
    prefab.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Updated prefab: {prefab}")

    if args.remove_compiled_cache:
        compiled = Path(str(prefab) + "_c")
        if compiled.exists():
            backup(compiled, "asset-pipeline-compiled-cache", root)
            compiled.unlink()
            print(f"Removed compiled cache: {compiled}")


def update_vmdl(args: argparse.Namespace, root: Path, fbx_resource_path: str) -> Path | None:
    target_vmdl = resolve_path(args.target_vmdl, root)
    if target_vmdl is None:
        return None

    if args.dry_run:
        print(f"Dry run: would update {target_vmdl} to import {fbx_resource_path}")
        return target_vmdl

    backup(target_vmdl, "asset-pipeline-vmdl", root)
    write_vmdl(
        target_vmdl,
        fbx_resource_path,
        args.material_remap or {},
        args.vmdl_material_source_suffix,
        args.vmdl_use_global_default,
        args.vmdl_global_default_material,
    )
    print(f"Updated model document: {target_vmdl}")
    return target_vmdl


def build_parser(defaults: dict[str, Any]) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export Blender assets and wire S&Box prefabs.")
    parser.set_defaults(**defaults)
    parser.add_argument("--config", help="Optional JSON config file with these same option names.")
    parser.add_argument("--blender-exe", default=defaults.get("blender_exe", DEFAULT_BLENDER))
    parser.add_argument("--source-blend", default=defaults.get("source_blend"), help="Source .blend file to open for export.")
    parser.add_argument("--blend-file", dest="source_blend", help=argparse.SUPPRESS)
    parser.add_argument("--root-object", default=defaults.get("root_object"), help="Root object to export. If omitted, exports all scene EMPTY/MESH objects.")
    parser.add_argument("--target-fbx", default=defaults.get("target_fbx"), help="Target FBX path under the project Assets folder.")
    parser.add_argument("--target-vmdl", default=defaults.get("target_vmdl"), help="Optional .vmdl wrapper to generate for the exported FBX.")
    parser.add_argument("--model-resource-path", default=defaults.get("model_resource_path"), help="S&Box resource path to put in the prefab. Defaults from target FBX.")
    parser.add_argument("--prefab", default=defaults.get("prefab"), help="Optional prefab JSON file to update.")
    parser.add_argument("--visual-object", default=defaults.get("visual_object", "Visual"))
    parser.add_argument("--visual-scale", default=defaults.get("visual_scale"), help="Optional scale string for the visual GameObject, e.g. 1,1,1.")
    parser.add_argument("--visual-tint", default=defaults.get("visual_tint"), help="Optional renderer tint string, e.g. 1,1,1,1.")
    parser.add_argument("--material-remap", dest="material_remap", default=defaults.get("material_remap", {}), help="Material remap dictionary. Prefer setting this in JSON config.")
    parser.add_argument(
        "--vmdl-material-source-suffix",
        default=defaults.get("vmdl_material_source_suffix", ".vmat"),
        help=(
            "Suffix appended to material_remap source names when writing .vmdl "
            "from values. Set to an empty string in JSON config when S&Box "
            "must match the raw FBX material names."
        ),
    )
    parser.add_argument(
        "--vmdl-use-global-default",
        action=argparse.BooleanOptionalAction,
        default=defaults.get("vmdl_use_global_default", True),
        help=(
            "Write ModelDoc use_global_default. Disable per config for multi-material "
            "assets where S&Box should preserve source material assignments instead "
            "of falling back to materials/default.vmat."
        ),
    )
    parser.add_argument(
        "--vmdl-global-default-material",
        default=defaults.get("vmdl_global_default_material", "materials/default.vmat"),
        help="ModelDoc global_default_material resource used when vmdl_use_global_default is enabled.",
    )
    parser.add_argument("--material-override", default=defaults.get("material_override"), help="Optional renderer-wide material override for the updated prefab ModelRenderer.")
    parser.add_argument("--clear-visual-children", action="store_true", default=defaults.get("clear_visual_children", False))
    parser.add_argument("--remove-compiled-cache", action="store_true", default=defaults.get("remove_compiled_cache", False))
    parser.add_argument(
        "--allow-default-color-texture",
        action="store_true",
        default=defaults.get("allow_default_color_texture", False),
        help="Allow remapped materials to keep materials/default/default_color.tga as TextureColor.",
    )
    parser.add_argument("--verify-fbx", action="store_true", default=defaults.get("verify_fbx", False))
    parser.add_argument("--required-object", action="append", default=defaults.get("required_object", []))
    parser.add_argument("--object-type", action="append", default=defaults.get("object_type", ["EMPTY", "MESH"]))
    parser.add_argument("--combine-meshes", action="store_true", default=defaults.get("combine_meshes", False))
    parser.add_argument("--combined-object-name", default=defaults.get("combined_object_name", "CombinedModel"))
    parser.add_argument("--global-scale", type=float, default=defaults.get("global_scale", 1.0))
    parser.add_argument("--axis-forward", default=defaults.get("axis_forward", "-Z"))
    parser.add_argument("--axis-up", default=defaults.get("axis_up", "Y"))
    parser.add_argument("--skip-export", action="store_true", default=defaults.get("skip_export", False))
    parser.add_argument("--skip-vmdl", action="store_true", default=defaults.get("skip_vmdl", False))
    parser.add_argument("--skip-prefab", action="store_true", default=defaults.get("skip_prefab", False))
    parser.add_argument("--dry-run", action="store_true", default=defaults.get("dry_run", False))
    return parser


def parse_args(argv: list[str]) -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config")
    pre_parser.add_argument("--source-blend")
    pre_parser.add_argument("--blend-file", dest="source_blend")
    known, _ = pre_parser.parse_known_args(argv)
    defaults: dict[str, Any] = {}
    if known.config:
        defaults = load_json(Path(known.config))
        blend_file = known.source_blend or defaults.get("source_blend")
        if isinstance(blend_file, str):
            defaults = expand_config_variables(
                defaults,
                {
                    "BLEND_FILE": blend_file,
                    "ASSET_NAME": asset_name_from_blend(blend_file),
                },
            )
    parser = build_parser(defaults)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    root = project_root()
    args = parse_args(argv)

    target_fbx = resolve_path(args.target_fbx, root)
    if target_fbx is None:
        raise ValueError("--target-fbx is required")

    if args.model_resource_path:
        model_resource_path = args.model_resource_path
    else:
        target_vmdl = resolve_path(args.target_vmdl, root)
        model_resource_path = resource_path_for(target_vmdl or target_fbx, root)

    fbx_resource_path = resource_path_for(target_fbx, root)
    validate_material_remaps(
        args.material_remap,
        root,
        bool(args.allow_default_color_texture),
    )
    if not args.dry_run:
        clear_material_compiled_caches(args.material_remap, root)

    if not args.skip_export and not args.dry_run:
        run_blender_export(args, root)
    elif args.dry_run:
        print("Dry run: skipping Blender export")

    if not args.skip_vmdl:
        update_vmdl(args, root, fbx_resource_path)

    if not args.skip_prefab and args.prefab:
        update_prefab(args, root, model_resource_path)

    print("Asset pipeline complete.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
