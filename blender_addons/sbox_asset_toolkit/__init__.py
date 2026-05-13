bl_info = {
    "name": "S&Box Asset Toolkit",
    "author": "Above/Below tooling",
    "version": (0, 1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > S&Box",
    "description": "Visible Blender control surface for S&Box asset production and MCP bridge work.",
    "category": "3D View",
}

import importlib
import importlib.util
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

import bpy
from bpy.props import BoolProperty, EnumProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup


PACKAGE_NAME = "_sbox_blender_mcp"
DEFAULT_PROJECT_ROOT = Path(os.environ.get("SBOX_PROJECT_ROOT", r"C:\Programming\S&Box"))

CATEGORY_ITEMS = (
    ("weapon", "Weapon", "Weapon or held equipment"),
    ("drone", "Drone", "Drone or drone component"),
    ("character", "Character", "Soldier, pilot, arms, or character gear"),
    ("environment", "Environment", "Environment prop or scene asset"),
)

SOCKET_PRESETS = {
    "weapon": (
        ("socket_muzzle", (0.0, 1.2, 0.15), (90.0, 0.0, 0.0)),
        ("socket_grip", (0.0, -0.35, -0.22), (0.0, 0.0, 0.0)),
        ("socket_attachment", (0.0, 0.15, 0.32), (0.0, 0.0, 0.0)),
    ),
    "drone": (
        ("socket_camera", (0.0, -0.45, -0.12), (75.0, 0.0, 0.0)),
        ("socket_muzzle", (0.0, -0.65, -0.08), (90.0, 0.0, 0.0)),
        ("socket_prop_front_left", (-0.55, 0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_front_right", (0.55, 0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_rear_left", (-0.55, -0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_rear_right", (0.55, -0.55, 0.08), (0.0, 0.0, 0.0)),
    ),
    "character": (
        ("socket_head", (0.0, 0.0, 1.72), (0.0, 0.0, 0.0)),
        ("socket_weapon_r", (0.34, -0.08, 1.15), (0.0, 0.0, 0.0)),
        ("socket_pack", (0.0, 0.16, 1.25), (0.0, 0.0, 0.0)),
    ),
    "environment": (
        ("socket_origin", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        ("socket_collision_note", (0.0, 0.0, 1.0), (0.0, 0.0, 0.0)),
    ),
}

MATERIAL_PRESETS = {
    "weapon": (
        ("SBox_Metal", (0.45, 0.46, 0.44, 1.0), 0.85, 0.34),
        ("SBox_Polymer", (0.045, 0.052, 0.058, 1.0), 0.0, 0.62),
        ("SBox_Marking", (0.9, 0.84, 0.54, 1.0), 0.0, 0.4),
    ),
    "drone": (
        ("SBox_Frame", (0.08, 0.095, 0.11, 1.0), 0.45, 0.42),
        ("SBox_Motor", (0.18, 0.19, 0.2, 1.0), 0.75, 0.28),
        ("SBox_Lens", (0.02, 0.025, 0.035, 1.0), 0.0, 0.16),
    ),
    "character": (
        ("SBox_Fabric", (0.14, 0.18, 0.15, 1.0), 0.0, 0.72),
        ("SBox_Gear", (0.09, 0.085, 0.075, 1.0), 0.1, 0.55),
        ("SBox_TeamAccent", (0.85, 0.14, 0.09, 1.0), 0.0, 0.4),
    ),
    "environment": (
        ("SBox_Surface", (0.32, 0.35, 0.31, 1.0), 0.0, 0.68),
        ("SBox_EdgeWear", (0.66, 0.62, 0.52, 1.0), 0.0, 0.5),
    ),
}


def project_root(context) -> Path:
    raw = context.scene.sbox_asset_toolkit.project_root
    return Path(raw or str(DEFAULT_PROJECT_ROOT)).expanduser()


def safe_asset_name(value: str) -> str:
    name = re.sub(r"[^A-Za-z0-9_]+", "_", value.strip()).strip("_")
    return name or "sbox_asset"


def current_blend_path() -> Path:
    if not bpy.data.filepath:
        raise RuntimeError("Save the Blender file before running this action.")
    return Path(bpy.data.filepath)


def relative_to_root(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def report_dir(root: Path) -> Path:
    path = root / ".tmpbuild" / "blender_live_toolkit"
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_report(root: Path, stem: str, text: str) -> Path:
    path = report_dir(root) / f"{stem}.txt"
    path.write_text(text, encoding="utf-8")
    return path


def set_status(context, message: str, report_path: Path | None = None, preview_path: Path | None = None) -> None:
    props = context.scene.sbox_asset_toolkit
    props.last_status = message[:1200]
    if report_path is not None:
        props.last_report = str(report_path)
    if preview_path is not None:
        props.last_preview = str(preview_path)


def run_powershell(root: Path, script_rel: str, args: list[str], report_stem: str, timeout_seconds: int = 300) -> tuple[str, Path]:
    script = root / script_rel
    if not script.exists():
        raise FileNotFoundError(f"Missing script: {script}")

    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        *args,
    ]
    completed = subprocess.run(
        command,
        cwd=str(root),
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    output += f"\nExitCode: {completed.returncode}\n"
    report = write_report(root, report_stem, output)
    if completed.returncode != 0:
        raise RuntimeError(f"{script.name} failed with exit code {completed.returncode}. Report: {report}")
    return output, report


def _load_bridge_package(root: Path):
    existing = sys.modules.get(PACKAGE_NAME)
    if existing is not None:
        return existing

    addon_dir = Path(os.environ.get("SBOX_BLENDER_MCP_ADDON_DIR", root / "mcp-1.0.0"))
    init_path = addon_dir / "__init__.py"
    if not init_path.exists():
        raise FileNotFoundError(f"Cannot find Blender MCP package at {init_path}")

    spec = importlib.util.spec_from_file_location(
        PACKAGE_NAME,
        init_path,
        submodule_search_locations=[str(addon_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load Blender MCP package from {init_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[PACKAGE_NAME] = module
    spec.loader.exec_module(module)
    return module


def _port_is_in_use(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.25):
            return True
    except OSError:
        return False


def ensure_bridge_running(root: Path, host: str = "127.0.0.1", port: int = 9876) -> str:
    if _port_is_in_use(host, port):
        return f"Blender MCP bridge already reachable on {host}:{port}."

    os.environ["SBOX_BLENDER_MCP_ADDON_DIR"] = str(root / "mcp-1.0.0")
    os.environ["BLENDER_MCP_HOST"] = host
    os.environ["BLENDER_MCP_PORT"] = str(port)

    _load_bridge_package(root)
    server = importlib.import_module(f"{PACKAGE_NAME}.mcp_to_blender_server")
    runner = importlib.import_module(f"{PACKAGE_NAME}.execute_interactive")

    server.timer_internal_vars_calc(active=0.05, idle=1.0, idle_delay=5.0)
    if not server.is_running():
        server.start(host, port)
    if not bpy.app.timers.is_registered(runner.run):
        bpy.app.timers.register(runner.run, first_interval=server.TIMER_INTERVAL_ACTIVE, persistent=True)
    return f"Blender MCP bridge running on {host}:{port}."


def create_material(name: str, color: tuple[float, float, float, float], metallic: float, roughness: float):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat


def ensure_empty(name: str, location, rotation_degrees, parent=None):
    obj = bpy.data.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(obj)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 0.18
    obj.location = location
    obj.rotation_euler = tuple(value * 0.017453292519943295 for value in rotation_degrees)
    obj.parent = parent
    obj["sbox_socket"] = True
    return obj


def setup_asset_scene(asset_name: str, category: str, clear_scene: bool) -> dict[str, object]:
    asset = safe_asset_name(asset_name)
    if clear_scene:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()

    root_name = f"{asset}_Root"
    root = bpy.data.objects.get(root_name)
    if root is None:
        root = bpy.data.objects.new(root_name, None)
        bpy.context.scene.collection.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.5
    root.location = (0.0, 0.0, 0.0)
    root["sbox_asset_root"] = True
    root["sbox_asset_category"] = category

    materials = []
    for mat_name, color, metallic, roughness in MATERIAL_PRESETS.get(category, MATERIAL_PRESETS["environment"]):
        materials.append(create_material(mat_name, color, metallic, roughness).name)

    sockets = []
    for name, location, rotation in SOCKET_PRESETS.get(category, SOCKET_PRESETS["environment"]):
        sockets.append(ensure_empty(name, location, rotation, root).name)

    if bpy.data.objects.get("SBox_Key_Area") is None:
        bpy.ops.object.light_add(type="AREA", location=(2.5, -4.0, 4.0))
        light = bpy.context.object
        light.name = "SBox_Key_Area"
        light.data.energy = 450
        light.data.size = 5

    if bpy.data.objects.get("SBox_PreviewCamera") is None:
        bpy.ops.object.camera_add(location=(3.0, -5.5, 2.4), rotation=(1.2, 0.0, 0.48))
        camera = bpy.context.object
        camera.name = "SBox_PreviewCamera"
        bpy.context.scene.camera = camera

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    bpy.context.view_layer.objects.active = root

    return {
        "asset_name": asset,
        "category": category,
        "root": root.name,
        "materials": materials,
        "sockets": sockets,
    }


class SBOXAssetToolkitProperties(PropertyGroup):
    project_root: StringProperty(name="Project Root", subtype="DIR_PATH", default=str(DEFAULT_PROJECT_ROOT))
    asset_name: StringProperty(name="Asset Name", default="new_sbox_asset")
    category: EnumProperty(name="Category", items=CATEGORY_ITEMS, default="weapon")
    target_prefab: StringProperty(name="Target Prefab", default="")
    target_model: StringProperty(name="Target Model", default="")
    clear_scene_on_setup: BoolProperty(name="Clear Scene On Setup", default=False)
    last_status: StringProperty(name="Last Status", default="Ready.")
    last_report: StringProperty(name="Latest Report", subtype="FILE_PATH", default="")
    last_preview: StringProperty(name="Latest Preview", subtype="FILE_PATH", default="")


class SBOX_OT_start_bridge(Operator):
    bl_idname = "sbox.start_bridge"
    bl_label = "Start MCP Bridge"
    bl_description = "Start the project-local Blender MCP bridge in this visible Blender session"

    def execute(self, context):
        try:
            message = ensure_bridge_running(project_root(context))
            set_status(context, message)
            self.report({"INFO"}, message)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_setup_asset_scene(Operator):
    bl_idname = "sbox.setup_asset_scene"
    bl_label = "Setup Production Scene"
    bl_description = "Create S&Box root, sockets, materials, lighting, and preview camera in the visible scene"

    def execute(self, context):
        props = context.scene.sbox_asset_toolkit
        result = setup_asset_scene(props.asset_name, props.category, props.clear_scene_on_setup)
        set_status(context, f"Prepared {result['asset_name']} scene with {len(result['sockets'])} sockets.")
        return {"FINISHED"}


class SBOX_OT_create_asset_brief(Operator):
    bl_idname = "sbox.create_asset_brief"
    bl_label = "Create Asset Brief"
    bl_description = "Create or update the production asset brief for this asset"

    def execute(self, context):
        props = context.scene.sbox_asset_toolkit
        root = project_root(context)
        asset = safe_asset_name(props.asset_name)
        out_file = root / "docs" / "assets" / "briefs" / f"{asset}.md"
        args = ["-Name", asset, "-Category", props.category, "-OutFile", str(out_file)]
        if props.target_prefab:
            args += ["-Prefab", props.target_prefab]
        if props.target_model:
            args += ["-Model", props.target_model]
        try:
            _, report = run_powershell(root, "scripts/agents/new_asset_brief.ps1", args, f"{asset}_brief")
            set_status(context, f"Asset brief written: {out_file}", report)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_run_quality_audit(Operator):
    bl_idname = "sbox.run_quality_audit"
    bl_label = "Run Quality Audit"
    bl_description = "Run the Blender source quality audit on the saved current file"

    def execute(self, context):
        props = context.scene.sbox_asset_toolkit
        root = project_root(context)
        try:
            blend = current_blend_path()
            args = ["-Blend", str(blend), "-Category", props.category, "-ShowInfo"]
            _, report = run_powershell(root, "scripts/agents/blender_quality_audit.ps1", args, "current_blender_quality", 180)
            set_status(context, "Quality audit completed. Review latest report for warnings.", report)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_render_preview(Operator):
    bl_idname = "sbox.render_preview"
    bl_label = "Render Preview"
    bl_description = "Render a local production preview PNG for the saved current file"

    def execute(self, context):
        root = project_root(context)
        try:
            blend = current_blend_path()
            output, report = run_powershell(root, "scripts/agents/asset_visual_review.ps1", ["-Blend", str(blend), "-ShowInfo"], "current_asset_preview", 240)
            preview = None
            for line in output.splitlines():
                if line.strip().lower().endswith(".png"):
                    candidate = root / line.strip()
                    if candidate.exists():
                        preview = candidate
            set_status(context, "Preview rendered." if preview else "Preview command completed.", report, preview)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_export_to_sbox(Operator):
    bl_idname = "sbox.export_to_sbox"
    bl_label = "Export To S&Box"
    bl_description = "Run the smart Blender to S&Box asset export for the saved current file"

    def execute(self, context):
        root = project_root(context)
        try:
            blend = current_blend_path()
            _, report = run_powershell(root, "scripts/smart_asset_export.ps1", ["-BlendFilePath", str(blend)], "current_asset_export", 600)
            set_status(context, "S&Box export completed. Check S&Box asset browser reload.", report)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_run_production_checks(Operator):
    bl_idname = "sbox.run_production_checks"
    bl_label = "Run Production Checks"
    bl_description = "Run the full asset-production agent suite"

    def execute(self, context):
        root = project_root(context)
        try:
            _, report = run_powershell(root, "scripts/agents/run_agent_checks.ps1", ["-Suite", "asset-production", "-ShowInfo"], "asset_production_suite", 600)
            set_status(context, "Asset-production suite completed. Review latest report for warnings.", report)
            return {"FINISHED"}
        except Exception as exc:
            set_status(context, str(exc))
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}


class SBOX_OT_open_latest_report(Operator):
    bl_idname = "sbox.open_latest_report"
    bl_label = "Open Latest Report"

    def execute(self, context):
        path = context.scene.sbox_asset_toolkit.last_report
        if not path or not Path(path).exists():
            self.report({"ERROR"}, "No latest report exists.")
            return {"CANCELLED"}
        os.startfile(path)
        return {"FINISHED"}


class SBOX_OT_open_latest_preview(Operator):
    bl_idname = "sbox.open_latest_preview"
    bl_label = "Open Latest Preview"

    def execute(self, context):
        path = context.scene.sbox_asset_toolkit.last_preview
        if not path or not Path(path).exists():
            self.report({"ERROR"}, "No latest preview exists.")
            return {"CANCELLED"}
        os.startfile(path)
        return {"FINISHED"}


class SBOX_PT_asset_toolkit(Panel):
    bl_label = "S&Box Asset Toolkit"
    bl_idname = "SBOX_PT_asset_toolkit"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "S&Box"

    def draw(self, context):
        layout = self.layout
        props = context.scene.sbox_asset_toolkit

        layout.prop(props, "project_root")
        layout.prop(props, "asset_name")
        layout.prop(props, "category")
        layout.prop(props, "target_prefab")
        layout.prop(props, "target_model")
        layout.prop(props, "clear_scene_on_setup")

        layout.separator()
        layout.operator("sbox.start_bridge", icon="LINKED")
        layout.operator("sbox.setup_asset_scene", icon="EMPTY_AXIS")

        layout.separator()
        row = layout.row(align=True)
        row.operator("sbox.create_asset_brief", icon="TEXT")
        row.operator("sbox.run_quality_audit", icon="CHECKMARK")
        row = layout.row(align=True)
        row.operator("sbox.render_preview", icon="RENDER_STILL")
        row.operator("sbox.export_to_sbox", icon="EXPORT")
        layout.operator("sbox.run_production_checks", icon="FILE_TICK")

        layout.separator()
        row = layout.row(align=True)
        row.operator("sbox.open_latest_report", icon="FILE_TEXT")
        row.operator("sbox.open_latest_preview", icon="IMAGE_DATA")

        layout.separator()
        box = layout.box()
        box.label(text="Status")
        for line in props.last_status.splitlines()[:6]:
            box.label(text=line[:96])


CLASSES = (
    SBOXAssetToolkitProperties,
    SBOX_OT_start_bridge,
    SBOX_OT_setup_asset_scene,
    SBOX_OT_create_asset_brief,
    SBOX_OT_run_quality_audit,
    SBOX_OT_render_preview,
    SBOX_OT_export_to_sbox,
    SBOX_OT_run_production_checks,
    SBOX_OT_open_latest_report,
    SBOX_OT_open_latest_preview,
    SBOX_PT_asset_toolkit,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.sbox_asset_toolkit = bpy.props.PointerProperty(type=SBOXAssetToolkitProperties)


def unregister():
    if hasattr(bpy.types.Scene, "sbox_asset_toolkit"):
        del bpy.types.Scene.sbox_asset_toolkit
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
