"""
Start the project-local Blender MCP bridge inside the current Blender session.

Usage:
1. In Blender, open the Scripting workspace.
2. Open this file in the text editor.
3. Run Script.

The Node MCP server in mcp/dist/blender.js connects to this bridge on
127.0.0.1:9876.
"""

from __future__ import annotations

import importlib
import importlib.util
import os
import socket
import sys
from pathlib import Path

import bpy  # type: ignore

PACKAGE_NAME = "_sbox_blender_mcp"
DEFAULT_PROJECT_ROOT = Path(r"C:\Programming\S&Box")


def _project_root() -> Path:
    if "__file__" in globals():
        return Path(__file__).resolve().parents[1]
    return DEFAULT_PROJECT_ROOT


def _load_bridge_package():
    existing = sys.modules.get(PACKAGE_NAME)
    if existing is not None:
        return existing

    addon_dir = Path(os.environ.get("SBOX_BLENDER_MCP_ADDON_DIR", _project_root() / "mcp-1.0.0"))
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


def start() -> None:
    host = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("BLENDER_MCP_PORT", "9876"))

    if _port_is_in_use(host, port):
        print(f"Blender MCP bridge is already reachable on {host}:{port}; leaving it running.")
        return

    _load_bridge_package()
    server = importlib.import_module(f"{PACKAGE_NAME}.mcp_to_blender_server")
    runner = importlib.import_module(f"{PACKAGE_NAME}.execute_interactive")

    server.timer_internal_vars_calc(active=0.05, idle=1.0, idle_delay=5.0)

    if not server.is_running():
        server.start(host, port)

    if not bpy.app.timers.is_registered(runner.run):
        bpy.app.timers.register(
            runner.run,
            first_interval=server.TIMER_INTERVAL_ACTIVE,
            persistent=True,
        )

    print(f"S&Box project Blender MCP bridge is running on {host}:{port}")


start()
