"""
Start the project-local Blender MCP bridge in background mode.

This script blocks until Blender is closed. It is intended to be launched by
scripts/start_blender_mcp_background.ps1.
"""

from __future__ import annotations

import importlib
import importlib.util
import os
import socket
import sys
from pathlib import Path

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


def main() -> None:
    host = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("BLENDER_MCP_PORT", "9876"))

    if _port_is_in_use(host, port):
        raise RuntimeError(f"Port {host}:{port} is already in use; leaving the existing bridge untouched.")

    _load_bridge_package()
    server = importlib.import_module(f"{PACKAGE_NAME}.mcp_to_blender_server")
    runner = importlib.import_module(f"{PACKAGE_NAME}.execute_blocking")

    server.start(host, port)
    print(f"S&Box project Blender MCP bridge is running on {host}:{port}")
    try:
        runner.run()
    finally:
        server.stop()


main()
