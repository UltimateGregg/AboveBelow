from __future__ import annotations

import os
from pathlib import Path

import bpy  # type: ignore


project_root = Path(os.environ.get("SBOX_PROJECT_ROOT", r"C:\Programming\S&Box"))

try:
    bpy.ops.preferences.addon_enable(module="sbox_asset_toolkit")
except Exception as exc:
    print(f"S&Box Asset Toolkit add-on enable failed: {exc}")

scene = bpy.context.scene
if scene and hasattr(scene, "sbox_asset_toolkit"):
    scene.sbox_asset_toolkit.project_root = str(project_root)
    try:
        bpy.ops.sbox.start_bridge()
    except Exception as exc:
        scene.sbox_asset_toolkit.last_status = f"Bridge startup failed: {exc}"
        print(scene.sbox_asset_toolkit.last_status)

print("S&Box visible Blender asset toolkit startup complete.")
