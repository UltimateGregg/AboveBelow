"""Proxy to the s&box editor MCP server (jtc.mcp-server, port 29015).

The editor's HTTP listener sets Access-Control-Allow-Origin but has no
OPTIONS/preflight handler, so the browser can't POST application/json to it
directly — the dashboard server proxies instead. Only a small allowlist of
tools is reachable: notably NOT editor_save_scene (project rule: never save
a pre-dirty scene) and NOT editor_take_screenshot (known broken).
"""

from __future__ import annotations

import json
import socket
import urllib.error
import urllib.request

MCP_URL = "http://127.0.0.1:29015/mcp"
DEFAULT_TIMEOUT = 5.0
STATUS_TIMEOUT = 2.5

ALLOWED_TOOLS = {
    "control_plane_status",
    "editor_scene_info",
    "editor_is_playing",
    "editor_play",
    "editor_stop",
}

_request_id = 0


def call_tool(tool: str, arguments: dict | None = None, timeout: float = DEFAULT_TIMEOUT) -> dict:
    """Call one MCP tool; returns {ok, editorOnline, result?|error?}."""
    global _request_id
    if tool not in ALLOWED_TOOLS:
        return {"ok": False, "editorOnline": None, "error": f"tool not allowed: {tool}"}

    _request_id += 1
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": _request_id,
            "method": "tools/call",
            "params": {"name": tool, "arguments": arguments or {}},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        MCP_URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
    except (urllib.error.URLError, socket.timeout, ConnectionError, OSError):
        return {"ok": False, "editorOnline": False, "error": "editor offline"}
    except json.JSONDecodeError:
        return {"ok": False, "editorOnline": True, "error": "invalid JSON from MCP server"}

    if "error" in payload and payload["error"]:
        message = payload["error"].get("message", "MCP error")
        return {"ok": False, "editorOnline": True, "error": message}
    return {"ok": True, "editorOnline": True, "result": unwrap_result(payload.get("result"))}


def unwrap_result(result):
    """MCP wraps tool output as {content:[{type:'text',text:...}]} — unwrap
    and json-parse the text when possible so the frontend gets objects."""
    if isinstance(result, dict):
        content = result.get("content")
        if isinstance(content, list) and content and isinstance(content[0], dict):
            text = content[0].get("text")
            if isinstance(text, str):
                try:
                    return json.loads(text)
                except json.JSONDecodeError:
                    return text
    return result


def _coerce_is_playing(value) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, dict):
        for key in ("isPlaying", "playing", "is_playing"):
            if key in value:
                return bool(value[key])
        return None
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("true", "yes", "playing"):
            return True
        if lowered in ("false", "no", "stopped"):
            return False
    return None


def editor_status_aggregate() -> dict:
    """One-shot status for the editor card; cheap offline short-circuit."""
    status = call_tool("control_plane_status", timeout=STATUS_TIMEOUT)
    if not status.get("editorOnline"):
        return {"editorOnline": False}

    playing = call_tool("editor_is_playing", timeout=STATUS_TIMEOUT)
    scene = call_tool("editor_scene_info", timeout=STATUS_TIMEOUT)
    return {
        "editorOnline": True,
        "status": status.get("result"),
        "isPlaying": _coerce_is_playing(playing.get("result")) if playing.get("ok") else None,
        "scene": scene.get("result") if scene.get("ok") else None,
    }


if __name__ == "__main__":
    print(json.dumps(editor_status_aggregate(), indent=1)[:2000])
