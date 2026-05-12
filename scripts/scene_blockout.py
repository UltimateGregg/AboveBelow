#!/usr/bin/env python3
"""
Small helpers for repeatable S&Box blockout scene edits.

The script intentionally uses the same JSON shape already present in
Assets/scenes/main.scene so map blockouts can be regenerated without hand
copying renderer/collider boilerplate.
"""

from __future__ import annotations

import argparse
import json
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any


PROJECT_GUID_NAMESPACE = uuid.UUID("f5c891a0-b163-4cb2-bf4c-21c9854b26cf")


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def backup(path: Path, root: Path) -> Path:
    backup_dir = root / ".tmpbuild" / "scene_backups" / path.parent.relative_to(root)
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / f"{path.stem}.before-scene-blockout-{timestamp()}{path.suffix}"
    shutil.copy2(path, backup_path)
    return backup_path


def stable_guid(name: str, suffix: str = "object") -> str:
    return str(uuid.uuid5(PROJECT_GUID_NAMESPACE, f"{name}:{suffix}"))


def render_options() -> dict[str, bool]:
    return {
        "GameLayer": True,
        "OverlayLayer": False,
        "BloomLayer": False,
        "AfterUILayer": False,
    }


def model_renderer(name: str, material: str, tint: str = "1,1,1,1", model: str = "models/dev/box.vmdl") -> dict[str, Any]:
    return {
        "__type": "Sandbox.ModelRenderer",
        "__guid": stable_guid(name, "renderer"),
        "__enabled": True,
        "Flags": 0,
        "BodyGroups": 18446744073709551615,
        "CreateAttachments": False,
        "LodOverride": None,
        "MaterialGroup": None,
        "MaterialOverride": material,
        "Materials": None,
        "Model": model,
        "OnComponentDestroy": None,
        "OnComponentDisabled": None,
        "OnComponentEnabled": None,
        "OnComponentFixedUpdate": None,
        "OnComponentStart": None,
        "OnComponentUpdate": None,
        "RenderOptions": render_options(),
        "RenderType": "On",
        "Tint": tint,
    }


def box_collider(name: str, scale: str, static: bool = True) -> dict[str, Any]:
    return {
        "__type": "Sandbox.BoxCollider",
        "__guid": stable_guid(name, "collider"),
        "__enabled": True,
        "Flags": 0,
        "Center": "0,0,0",
        "ColliderFlags": 0,
        "Elasticity": None,
        "Friction": None,
        "IsTrigger": False,
        "OnComponentDestroy": None,
        "OnComponentDisabled": None,
        "OnComponentEnabled": None,
        "OnComponentFixedUpdate": None,
        "OnComponentStart": None,
        "OnComponentUpdate": None,
        "OnObjectTriggerEnter": None,
        "OnObjectTriggerExit": None,
        "OnTriggerEnter": None,
        "OnTriggerExit": None,
        "RollingResistance": None,
        "Scale": scale,
        "Static": static,
        "Surface": None,
        "SurfaceVelocity": "0,0,0",
    }


def game_object(
    name: str,
    position: str,
    scale: str = "1,1,1",
    rotation: str = "0,0,0,1",
    material: str | None = None,
    tint: str = "1,1,1,1",
    model: str = "models/dev/box.vmdl",
    collider_scale: str | None = None,
    children: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    components: list[dict[str, Any]] = []
    if material:
        components.append(model_renderer(name, material, tint, model))
    if collider_scale:
        components.append(box_collider(name, collider_scale))

    return {
        "__guid": stable_guid(name),
        "__version": 2,
        "Flags": 0,
        "Name": name,
        "Position": position,
        "Rotation": rotation,
        "Scale": scale,
        "Tags": "",
        "Enabled": True,
        "NetworkMode": 2,
        "NetworkFlags": 0,
        "NetworkOrphaned": 0,
        "NetworkTransmit": True,
        "OwnerTransfer": 1,
        "Components": components,
        "Children": children or [],
    }


def iter_objects(node: dict[str, Any]):
    yield node
    for child in node.get("Children", []) or []:
        yield from iter_objects(child)


def find_object(scene: dict[str, Any], name: str) -> dict[str, Any] | None:
    for root_object in scene.get("GameObjects", []) or []:
        for game_object_node in iter_objects(root_object):
            if game_object_node.get("Name") == name:
                return game_object_node
    return None


def road_surface(name: str, position: str, scale: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material="materials/arena/asphalt_cover.vmat",
        model="models/dev/plane.vmdl",
    )


def road_marking(name: str, position: str, scale: str, tint: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material="materials/arena/concrete_wall.vmat",
        tint=tint,
        model="models/dev/box.vmdl",
    )


def road_curb(name: str, position: str, scale: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material="materials/arena/concrete_wall.vmat",
        tint="0.72,0.72,0.68,1",
        model="models/dev/box.vmdl",
    )


def build_road_intersection() -> dict[str, Any]:
    yellow = "1,0.78,0.16,1"
    white = "0.92,0.92,0.86,1"
    children: list[dict[str, Any]] = [
        road_surface("RoadIntersection_Core", "0,0,0.25", "12,12,1"),
        road_surface("RoadIntersection_NorthApproach", "0,1050,0.2", "7.2,30,1"),
        road_surface("RoadIntersection_SouthApproach", "0,-1050,0.2", "7.2,30,1"),
        road_surface("RoadIntersection_EastApproach", "1050,0,0.2", "30,7.2,1"),
        road_surface("RoadIntersection_WestApproach", "-1050,0,0.2", "30,7.2,1"),
    ]

    for side, x in (("West", -205), ("East", 205)):
        children.append(road_curb(f"RoadCurb_NorthApproach_{side}", f"{x},1050,5", "0.32,30,0.2"))
        children.append(road_curb(f"RoadCurb_SouthApproach_{side}", f"{x},-1050,5", "0.32,30,0.2"))

    for side, y in (("North", 205), ("South", -205)):
        children.append(road_curb(f"RoadCurb_EastApproach_{side}", f"1050,{y},5", "30,0.32,0.2"))
        children.append(road_curb(f"RoadCurb_WestApproach_{side}", f"-1050,{y},5", "30,0.32,0.2"))

    for index, y in enumerate((500, 760, 1020, 1280, 1540), start=1):
        children.append(road_marking(f"RoadDash_North_{index:02}", f"0,{y},2", "0.16,2.4,0.04", yellow))
        children.append(road_marking(f"RoadDash_South_{index:02}", f"0,{-y},2", "0.16,2.4,0.04", yellow))

    for index, x in enumerate((500, 760, 1020, 1280, 1540), start=1):
        children.append(road_marking(f"RoadDash_East_{index:02}", f"{x},0,2", "2.4,0.16,0.04", yellow))
        children.append(road_marking(f"RoadDash_West_{index:02}", f"{-x},0,2", "2.4,0.16,0.04", yellow))

    children.extend(
        [
            road_marking("RoadStopLine_North", "0,360,2", "6.4,0.24,0.04", white),
            road_marking("RoadStopLine_South", "0,-360,2", "6.4,0.24,0.04", white),
            road_marking("RoadStopLine_East", "360,0,2", "0.24,6.4,0.04", white),
            road_marking("RoadStopLine_West", "-360,0,2", "0.24,6.4,0.04", white),
        ]
    )

    for index, y in enumerate((410, 445, 480, 515), start=1):
        children.append(road_marking(f"Crosswalk_North_{index:02}", f"0,{y},2.2", "5.2,0.18,0.04", white))
        children.append(road_marking(f"Crosswalk_South_{index:02}", f"0,{-y},2.2", "5.2,0.18,0.04", white))

    for index, x in enumerate((410, 445, 480, 515), start=1):
        children.append(road_marking(f"Crosswalk_East_{index:02}", f"{x},0,2.2", "0.18,5.2,0.04", white))
        children.append(road_marking(f"Crosswalk_West_{index:02}", f"{-x},0,2.2", "0.18,5.2,0.04", white))

    return game_object("RoadIntersection_Center", "0,0,0", children=children)


def install_group(parent: dict[str, Any], group: dict[str, Any]) -> tuple[int, int]:
    children = parent.setdefault("Children", [])
    before = len(children)
    children[:] = [child for child in children if child.get("Name") != group["Name"]]
    removed = before - len(children)
    insert_at = 1 if children and children[0].get("Name") == "ArenaFloor" else len(children)
    children.insert(insert_at, group)
    return len(group.get("Children", []) or []), removed


def add_road_intersection(scene_path: Path, dry_run: bool) -> None:
    root = project_root()
    data = json.loads(scene_path.read_text(encoding="utf-8"))
    blockout_map = find_object(data, "BlockoutMap")
    if blockout_map is None:
        raise RuntimeError("BlockoutMap was not found in the scene")

    group = build_road_intersection()
    count, removed = install_group(blockout_map, group)

    scene_info = find_object(data, "Scene Information")
    if scene_info:
        for component in scene_info.get("Components", []) or []:
            if component.get("__type") == "Sandbox.SceneInformation":
                component["Description"] = (
                    "Drone vs Players playable blockout: expanded 3600-unit arena with textured grass, "
                    "a central road intersection, concrete, asphalt, metal launch pad, west soldier base, "
                    "east drone pad, central cover, GameManager, HUD, and role-specific spawn points."
                )

    if dry_run:
        print(f"Dry run: would install {count} RoadIntersection_Center children; replaced groups: {removed}")
        return

    backup_path = backup(scene_path, root)
    scene_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Backup: {backup_path}")
    print(f"Installed RoadIntersection_Center with {count} child objects")


def main() -> int:
    parser = argparse.ArgumentParser(description="Repeatable S&Box scene blockout edits.")
    parser.add_argument("command", choices=["add-road-intersection"])
    parser.add_argument("--scene", default="Assets/scenes/main.scene")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    scene_path = Path(args.scene)
    if not scene_path.is_absolute():
        scene_path = project_root() / scene_path
    if not scene_path.exists():
        raise FileNotFoundError(scene_path)

    if args.command == "add-road-intersection":
        add_road_intersection(scene_path, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
