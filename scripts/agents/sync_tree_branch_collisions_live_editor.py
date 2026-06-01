#!/usr/bin/env python3
"""Mirror saved pine collision helpers into the currently open S&Box editor scene.

This is intentionally editor-live glue: it reads the already-authored
Collision_Trunk/Collision_Branch_* children from Assets/scenes/main.scene and
recreates them through the native MCP scene/component tools when the editor has
a stale in-memory graph.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


TREE_MODELS = {
    "models/terrain_assets.vmdl",
    "models/terrain_pine.vmdl",
    "models/terrain_pine_broad.vmdl",
    "models/terrain_pine_windswept.vmdl",
}
VIEWER_TYPES = (
    "DroneVsPlayers.SelectedHierarchyColliderViewer",
    "SelectedHierarchyColliderViewer",
)


def parse_vec(text: str | None, default: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> tuple[float, float, float]:
    if not text:
        return default
    parts = [part.strip() for part in text.split(",")]
    if len(parts) != 3:
        return default
    return (float(parts[0]), float(parts[1]), float(parts[2]))


def parse_quat(text: str | None) -> tuple[float, float, float, float]:
    if not text:
        return (0.0, 0.0, 0.0, 1.0)
    parts = [part.strip() for part in text.split(",")]
    if len(parts) != 4:
        return (0.0, 0.0, 0.0, 1.0)
    return (float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


def fmt(value: float) -> str:
    if abs(value) < 0.0000005:
        value = 0.0
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def vec_text(vector: tuple[float, float, float]) -> str:
    return ",".join(fmt(part) for part in vector)


def add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul_components(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] * b[0], a[1] * b[1], a[2] * b[2])


def quat_mul(
    a: tuple[float, float, float, float],
    b: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def quat_rotate(q: tuple[float, float, float, float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z, w = q
    vx, vy, vz = v
    # q * v * conjugate(q), expanded.
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (
        vx + w * tx + (y * tz - z * ty),
        vy + w * ty + (z * tx - x * tz),
        vz + w * tz + (x * ty - y * tx),
    )


def quat_normalize(q: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    length = math.sqrt(sum(part * part for part in q))
    if length <= 0.0000001:
        return (0.0, 0.0, 0.0, 1.0)
    return tuple(part / length for part in q)  # type: ignore[return-value]


def quat_to_sbox_euler(q: tuple[float, float, float, float]) -> tuple[float, float, float]:
    x, y, z, w = quat_normalize(q)
    sinr_cosp = 2.0 * (w * x + y * z)
    cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
    roll_x = math.degrees(math.atan2(sinr_cosp, cosr_cosp))

    sinp = 2.0 * (w * y - z * x)
    pitch_y = math.degrees(math.copysign(math.pi / 2.0, sinp) if abs(sinp) >= 1.0 else math.asin(sinp))

    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    yaw_z = math.degrees(math.atan2(siny_cosp, cosy_cosp))

    return (pitch_y, yaw_z, roll_x)


class McpClient:
    def __init__(self, url: str) -> None:
        self.url = url
        self.next_id = 1000

    def call(self, name: str, arguments: dict[str, Any], timeout: int = 30) -> Any:
        self.next_id += 1
        body = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        }
        data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            self.url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
        if "error" in payload:
            raise RuntimeError(payload["error"])
        text = payload["result"]["content"][0]["text"]
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


def iter_objects(objects: list[dict[str, Any]], path: str = ""):
    for obj in objects:
        name = str(obj.get("Name", ""))
        current = f"{path}/{name}" if path else name
        yield obj, current
        children = obj.get("Children")
        if isinstance(children, list):
            yield from iter_objects(children, current)


def get_tree_model(obj: dict[str, Any]) -> str | None:
    for component in obj.get("Components", []) or []:
        model = component.get("Model")
        if model and component.get("RenderType") is not None:
            normalized = str(model).replace("\\", "/")
            if normalized in TREE_MODELS:
                return normalized
    return None


def collision_children(obj: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        child
        for child in (obj.get("Children", []) or [])
        if str(child.get("Name", "")).startswith(("Collision_Trunk", "Collision_Branch_"))
    ]


def box_scale(child: dict[str, Any]) -> str | None:
    for component in child.get("Components", []) or []:
        if component.get("__type") == "Sandbox.BoxCollider" or (
            component.get("Center") is not None and component.get("Scale") is not None
        ):
            return str(component.get("Scale"))
    return None


def live_find_all(client: McpClient, pattern: str) -> list[dict[str, Any]]:
    result = client.call("scene_find_objects", {"pattern": pattern}, timeout=60)
    if isinstance(result, list):
        return result
    return []


def delete_existing_collision_children(client: McpClient, pine_ids: set[str]) -> int:
    deleted = 0
    for pattern in ("Collision_Trunk", "Collision_Branch_*"):
        for entry in live_find_all(client, pattern):
            if entry.get("parentId") not in pine_ids:
                continue
            client.call("scene_delete_object", {"id": entry["id"]}, timeout=30)
            deleted += 1
    return deleted


def remove_root_colliders(client: McpClient, tree_id: str) -> int:
    removed = 0
    while True:
        components = client.call("component_list", {"id": tree_id}, timeout=30)
        collider_types = [
            component["type"]
            for component in components
            if str(component.get("type", "")).endswith("Collider")
        ]
        if not collider_types:
            return removed
        client.call("component_remove", {"id": tree_id, "type": collider_types[0]}, timeout=30)
        removed += 1


def is_hierarchy_collider_viewer_type(type_name: str) -> bool:
    return type_name in VIEWER_TYPES or type_name.endswith(".SelectedHierarchyColliderViewer")


def find_hierarchy_collider_viewer_type(components: list[dict[str, Any]]) -> str | None:
    for component in components:
        type_name = str(component.get("type", ""))
        if is_hierarchy_collider_viewer_type(type_name):
            return type_name
    return None


def ensure_hierarchy_collider_viewer(client: McpClient, tree_id: str) -> bool:
    components = client.call("component_list", {"id": tree_id}, timeout=30)
    viewer_type = find_hierarchy_collider_viewer_type(components)
    if viewer_type is not None:
        return False

    last_error: Exception | None = None
    for type_name in VIEWER_TYPES:
        try:
            client.call("component_add", {"id": tree_id, "type": type_name}, timeout=30)
        except Exception as error:  # Try the short name when the full type is not registered.
            last_error = error
            continue

        components = client.call("component_list", {"id": tree_id}, timeout=30)
        viewer_type = find_hierarchy_collider_viewer_type(components)
        if viewer_type is None:
            continue

        for property_name, value in (("AlwaysDraw", "false"), ("IncludeTriggers", "true")):
            try:
                client.call(
                    "component_set",
                    {"id": tree_id, "type": viewer_type, "property": property_name, "value": value},
                    timeout=30,
                )
            except Exception:
                pass

        return True

    raise RuntimeError(f"Could not add SelectedHierarchyColliderViewer to {tree_id}: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Project root")
    parser.add_argument("--scene", default="Assets/scenes/main.scene", help="Authored scene JSON")
    parser.add_argument("--mcp", default="http://localhost:29015/mcp", help="Native editor MCP endpoint")
    parser.add_argument("--limit", type=int, default=0, help="Optional tree limit for smoke testing")
    parser.add_argument("--viewer-only", action="store_true", help="Only add the root hierarchy collider viewer")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    scene_path = root / args.scene
    scene = json.loads(scene_path.read_text(encoding="utf-8"))
    tree_entries: list[tuple[dict[str, Any], str]] = []
    for obj, path in iter_objects(scene.get("GameObjects", [])):
        if get_tree_model(obj) is None:
            continue
        children = collision_children(obj)
        if len(children) < 38:
            raise RuntimeError(f"{path} does not have the authored collision children in {scene_path}")
        tree_entries.append((obj, path))

    if args.limit > 0:
        tree_entries = tree_entries[: args.limit]

    client = McpClient(args.mcp)
    status = client.call("control_plane_status", {}, timeout=10)
    scene_info = status.get("scene", {}) if isinstance(status, dict) else {}
    print(
        f"Live editor scene: {scene_info.get('name')} source={scene_info.get('sourcePath')} "
        f"dirty={scene_info.get('hasUnsavedChanges')} playing={scene_info.get('isPlaying')}"
    )
    source_path = str(scene_info.get("sourcePath") or "").replace("\\", "/")
    if scene_info.get("isPlaying"):
        raise RuntimeError("Refusing to sync pine collision while the editor is in play mode.")
    if source_path.lower() != "scenes/main.scene":
        raise RuntimeError(f"Refusing to sync pine collision into sourcePath='{source_path}', expected scenes/main.scene.")

    viewer_added = 0
    if args.viewer_only:
        started = time.time()
        for index, (tree, _) in enumerate(tree_entries, start=1):
            if ensure_hierarchy_collider_viewer(client, str(tree["__guid"])):
                viewer_added += 1
            if index == 1 or index % 25 == 0 or index == len(tree_entries):
                elapsed = time.time() - started
                print(f"Checked root viewer on {index}/{len(tree_entries)} pine trees ({viewer_added} added, {elapsed:.1f}s).")
                sys.stdout.flush()

        print(f"Live pine collision viewer sync complete: {len(tree_entries)} pine tree root(s), {viewer_added} viewer component(s) added.")
        return 0

    pine_ids = {str(obj["__guid"]) for obj, _ in tree_entries}
    deleted = delete_existing_collision_children(client, pine_ids)
    print(f"Deleted {deleted} pre-existing live pine collision helper(s).")

    total_children = 0
    total_removed_colliders = 0
    started = time.time()
    for index, (tree, path) in enumerate(tree_entries, start=1):
        tree_id = str(tree["__guid"])
        parent_position = parse_vec(tree.get("Position"))
        parent_rotation = parse_quat(tree.get("Rotation"))
        parent_scale = parse_vec(tree.get("Scale"), (1.0, 1.0, 1.0))

        if ensure_hierarchy_collider_viewer(client, tree_id):
            viewer_added += 1
        total_removed_colliders += remove_root_colliders(client, tree_id)

        for child in collision_children(tree):
            local_position = parse_vec(child.get("Position"))
            local_rotation = parse_quat(child.get("Rotation"))
            scaled_local_position = mul_components(local_position, parent_scale)
            world_position = add(parent_position, quat_rotate(parent_rotation, scaled_local_position))
            world_rotation = quat_mul(parent_rotation, local_rotation)
            euler = quat_to_sbox_euler(world_rotation)
            scale = box_scale(child)
            if scale is None:
                raise RuntimeError(f"{path}/{child.get('Name')} is missing a BoxCollider scale")

            created = client.call(
                "scene_create_object",
                {
                    "name": child["Name"],
                    "parentId": tree_id,
                    "position": vec_text(world_position),
                },
                timeout=30,
            )
            child_id = created["id"]
            client.call(
                "scene_set_transform",
                {
                    "id": child_id,
                    "position": vec_text(world_position),
                    "rotation": vec_text(euler),
                    "scale": vec_text(parent_scale),
                },
                timeout=30,
            )
            client.call("component_add", {"id": child_id, "type": "BoxCollider"}, timeout=30)
            client.call("component_set", {"id": child_id, "type": "BoxCollider", "property": "Scale", "value": scale}, timeout=30)
            client.call("component_set", {"id": child_id, "type": "BoxCollider", "property": "Static", "value": "true"}, timeout=30)
            total_children += 1

        if index == 1 or index % 10 == 0 or index == len(tree_entries):
            elapsed = time.time() - started
            print(f"Synced {index}/{len(tree_entries)} pine trees ({total_children} helper children, {elapsed:.1f}s).")
            sys.stdout.flush()

    print(
        f"Live pine collision sync complete: {len(tree_entries)} pine tree(s), "
        f"{total_children} helper child object(s), removed {total_removed_colliders} root collider(s), "
        f"added {viewer_added} root viewer component(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
