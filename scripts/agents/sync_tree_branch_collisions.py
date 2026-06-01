#!/usr/bin/env python3
"""Rebuild authored pine tree collision helpers for scene instances and prefabs.

The pine mesh is generated in scripts/create_environment_proxy_assets.py. This
script mirrors its trunk/root-flare/dead-stub/whorl branch layout and writes
explicit child BoxCollider helpers so placed pines have trunk coverage plus
separate branch collision without touching stock oak ModelCollider setups.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import uuid
from collections import OrderedDict
from pathlib import Path
from typing import Iterable


TREE_MODELS = {
    "models/terrain_assets.vmdl": "pine",
    "models/terrain_pine.vmdl": "pine",
    "models/terrain_pine_broad.vmdl": "broad",
    "models/terrain_pine_windswept.vmdl": "windswept",
}

PREFABS = (
    "Assets/prefabs/environment/terrain_assets.prefab",
    "Assets/prefabs/environment/terrain_pine.prefab",
    "Assets/prefabs/environment/terrain_pine_broad.prefab",
    "Assets/prefabs/environment/terrain_pine_windswept.prefab",
)

GUID_NAMESPACE = uuid.UUID("88b0198f-afd8-451e-a965-9c8ef6e6af7b")


def fmt(value: float) -> str:
    if abs(value) < 0.0000005:
        value = 0.0
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def vec_text(vector: tuple[float, float, float]) -> str:
    return ",".join(fmt(part) for part in vector)


def quat_text(quat: tuple[float, float, float, float]) -> str:
    return ",".join(fmt(part) for part in quat)


def add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: tuple[float, float, float], scalar: float) -> tuple[float, float, float]:
    return (a[0] * scalar, a[1] * scalar, a[2] * scalar)


def length(vector: tuple[float, float, float]) -> float:
    return math.sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2])


def normalize(vector: tuple[float, float, float]) -> tuple[float, float, float]:
    magnitude = length(vector)
    if magnitude <= 0.000001:
        return (1.0, 0.0, 0.0)
    return (vector[0] / magnitude, vector[1] / magnitude, vector[2] / magnitude)


def quaternion_from_x_axis(direction: tuple[float, float, float]) -> tuple[float, float, float, float]:
    target = normalize(direction)
    dot = max(-1.0, min(1.0, target[0]))
    if dot > 0.999999:
        return (0.0, 0.0, 0.0, 1.0)
    if dot < -0.999999:
        return (0.0, 0.0, 1.0, 0.0)

    # cross((1, 0, 0), target)
    quat = (0.0, -target[2], target[1], 1.0 + dot)
    magnitude = math.sqrt(sum(part * part for part in quat))
    return tuple(part / magnitude for part in quat)  # type: ignore[return-value]


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def deform_point(point: tuple[float, float, float], variant: str) -> tuple[float, float, float]:
    x, y, z = point
    height_factor = clamp01((z - 8.2) / 6.8)

    if variant == "windswept":
        lean = height_factor**1.35
        return (
            x * (0.82 + height_factor * 0.08) + lean * 0.82,
            y * (0.78 + height_factor * 0.12),
            z * 1.08,
        )
    if variant == "broad":
        crown = height_factor**0.75
        return (
            x * (1.05 + crown * 0.32),
            y * (1.08 + crown * 0.24),
            z * (0.90 + height_factor * 0.03),
        )

    return point


def to_sbox_units(point: tuple[float, float, float], variant: str) -> tuple[float, float, float]:
    deformed = deform_point(point, variant)
    return (deformed[0] * 100.0, deformed[1] * 100.0, deformed[2] * 100.0)


def branch_record(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    branch_kind: str,
) -> dict[str, object]:
    return {
        "name": name,
        "start": start,
        "end": end,
        "radius": radius,
        "kind": branch_kind,
    }


def consume_whorl_decoration_rng(rng: random.Random, length_value: float, twig_count: int, pad_count: int) -> None:
    for _ in range(twig_count):
        rng.uniform(-0.05, 0.08)
        rng.uniform(-0.04, 0.08)
        rng.uniform(-0.05, 0.07)

    for pad in range(pad_count):
        rng.uniform(-0.02, 0.16)
        rng.uniform(-10.0, 10.0)
        rng.uniform(0.86, 1.14)
        rng.uniform(0.85, 1.18)
        rng.uniform(-10.0, 12.0)

        if length_value > 1.45:
            rng.uniform(-0.04, 0.05)
            rng.uniform(-8.0, 8.0)
            rng.uniform(0.62, 0.88)
            rng.uniform(0.75, 1.05)
            rng.uniform(-28.0, 28.0)

        if length_value > 2.4 and pad == 1:
            rng.uniform(-0.08, 0.08)
            rng.uniform(-12.0, 12.0)
            rng.uniform(0.52, 0.72)
            rng.uniform(0.70, 0.92)
            rng.uniform(36.0, 58.0)


def pine_branch_records() -> list[dict[str, object]]:
    records: list[dict[str, object]] = []

    for index, angle_degrees in enumerate((18, 93, 161, 232, 306), start=1):
        angle = math.radians(angle_degrees)
        start = (math.cos(angle) * 0.11, math.sin(angle) * 0.11, 0.24)
        end = (math.cos(angle) * 0.72, math.sin(angle) * 0.72, 0.08)
        records.append(branch_record(f"Collision_Branch_RootFlare_{index:02d}", start, end, 0.085, "root_flare"))

    dead_stub_specs = (
        (3.1, 72, 0.34),
        (4.15, 25, 0.55),
        (5.4, 205, 0.72),
        (6.55, 325, 0.62),
        (7.8, 145, 0.82),
        (8.75, 268, 0.58),
    )
    for index, (z, angle_degrees, branch_length) in enumerate(dead_stub_specs, start=1):
        angle = math.radians(angle_degrees)
        start = (math.cos(angle) * 0.10, math.sin(angle) * 0.10, z)
        end = (math.cos(angle) * branch_length, math.sin(angle) * branch_length, z + 0.08)
        records.append(branch_record(f"Collision_Branch_DeadStub_{index:02d}", start, end, 0.045, "dead_stub"))

    whorl_specs = (
        (9.35, 3.30, (8, 96, 188, 282), 0.066),
        (10.05, 3.05, (48, 138, 226, 316), 0.060),
        (10.82, 2.72, (14, 108, 198, 292), 0.054),
        (11.60, 2.34, (58, 178, 300), 0.048),
        (12.38, 1.96, (24, 142, 260), 0.042),
        (13.12, 1.56, (84, 205, 330), 0.036),
        (13.86, 1.12, (36, 166, 286), 0.031),
        (14.55, 0.72, (112, 246), 0.026),
    )

    branch_index = 1
    rng = random.Random(19)
    for z, branch_length, angles, base_radius in whorl_specs:
        for angle_degrees in angles:
            angle = math.radians(angle_degrees + rng.uniform(-7.0, 7.0))
            direction = (math.cos(angle), math.sin(angle), 0.0)
            start = (direction[0] * 0.12, direction[1] * 0.12, z)
            end = (
                direction[0] * branch_length,
                direction[1] * branch_length,
                z + rng.uniform(0.12, 0.34),
            )

            records.append(
                branch_record(
                    f"Collision_Branch_Whorl_{branch_index:02d}",
                    start,
                    end,
                    base_radius,
                    "whorl",
                )
            )

            twig_count = 3 if branch_length > 2.2 else (2 if branch_length > 1.1 else 1)
            pad_count = 3 if branch_length > 2.2 else (2 if branch_length > 1.25 else 1)
            consume_whorl_decoration_rng(rng, branch_length, twig_count, pad_count)
            branch_index += 1

    return records


BRANCH_RECORDS = pine_branch_records()


def make_guid(seed: str) -> str:
    return str(uuid.uuid5(GUID_NAMESPACE, seed))


def box_component(seed: str, scale: tuple[float, float, float]) -> OrderedDict[str, object]:
    return OrderedDict(
        [
            ("__type", "Sandbox.BoxCollider"),
            ("__guid", make_guid(f"{seed}:component")),
            ("__enabled", True),
            ("Flags", 0),
            ("Center", "0,0,0"),
            ("ColliderFlags", 0),
            ("Elasticity", None),
            ("Friction", None),
            ("IsTrigger", False),
            ("OnComponentDestroy", None),
            ("OnComponentDisabled", None),
            ("OnComponentEnabled", None),
            ("OnComponentFixedUpdate", None),
            ("OnComponentStart", None),
            ("OnComponentUpdate", None),
            ("OnObjectTriggerEnter", None),
            ("OnObjectTriggerExit", None),
            ("OnTriggerEnter", None),
            ("OnTriggerExit", None),
            ("RollingResistance", None),
            ("Scale", vec_text(scale)),
            ("Static", True),
            ("Surface", None),
            ("SurfaceVelocity", "0,0,0"),
        ]
    )


def hierarchy_collider_viewer_component(seed: str) -> OrderedDict[str, object]:
    return OrderedDict(
        [
            ("__type", "DroneVsPlayers.SelectedHierarchyColliderViewer"),
            ("__guid", make_guid(f"{seed}:viewer")),
            ("__enabled", True),
            ("Flags", 0),
            ("AlwaysDraw", False),
            ("IncludeTriggers", True),
            ("OnComponentDestroy", None),
            ("OnComponentDisabled", None),
            ("OnComponentEnabled", None),
            ("OnComponentFixedUpdate", None),
            ("OnComponentStart", None),
            ("OnComponentUpdate", None),
            ("SolidColliderColor", "1,0.55,0.12,1"),
            ("TriggerColliderColor", "0.25,0.75,1,1"),
        ]
    )


def collision_child(
    owner_seed: str,
    name: str,
    position: tuple[float, float, float],
    rotation: tuple[float, float, float, float],
    scale: tuple[float, float, float],
) -> OrderedDict[str, object]:
    seed = f"{owner_seed}:{name}"
    return OrderedDict(
        [
            ("__guid", make_guid(seed)),
            ("__version", 2),
            ("Flags", 0),
            ("Name", name),
            ("Position", vec_text(position)),
            ("Rotation", quat_text(rotation)),
            ("Scale", "1,1,1"),
            ("Tags", ""),
            ("Enabled", True),
            ("NetworkMode", 2),
            ("NetworkFlags", 0),
            ("NetworkOrphaned", 0),
            ("NetworkTransmit", True),
            ("OwnerTransfer", 1),
            ("Components", [box_component(seed, scale)]),
            ("Children", []),
        ]
    )


def trunk_child(owner_seed: str, variant: str) -> OrderedDict[str, object]:
    start = to_sbox_units((0.0, 0.0, 0.0), variant)
    end = to_sbox_units((0.0, 0.0, 15.2), variant)
    delta = sub(end, start)
    trunk_length = length(delta)
    position = mul(add(start, end), 0.5)
    rotation = quaternion_from_x_axis(delta)
    width = 90.0 if variant == "broad" else 82.0
    return collision_child(owner_seed, "Collision_Trunk", position, rotation, (trunk_length + 10.0, width, width))


def branch_thickness(record: dict[str, object], variant: str) -> float:
    kind = str(record["kind"])
    radius = float(record["radius"])
    base = radius * 200.0

    if kind == "whorl":
        thickness = max(56.0, base + 32.0)
    elif kind == "root_flare":
        thickness = max(32.0, base + 18.0)
    else:
        thickness = max(24.0, base + 16.0)

    if variant == "broad":
        thickness *= 1.12
    elif variant == "windswept":
        thickness *= 0.94

    return thickness


def branch_child(owner_seed: str, variant: str, record: dict[str, object]) -> OrderedDict[str, object]:
    start = to_sbox_units(record["start"], variant)  # type: ignore[arg-type]
    end = to_sbox_units(record["end"], variant)  # type: ignore[arg-type]
    delta = sub(end, start)
    branch_length = length(delta)
    thickness = branch_thickness(record, variant)
    position = mul(add(start, end), 0.5)
    rotation = quaternion_from_x_axis(delta)
    return collision_child(
        owner_seed,
        str(record["name"]),
        position,
        rotation,
        (branch_length + max(10.0, thickness * 0.25), thickness, thickness),
    )


def get_components(obj: dict[str, object]) -> list[dict[str, object]]:
    components = obj.get("Components")
    if isinstance(components, list):
        return components  # type: ignore[return-value]
    return []


def get_children(obj: dict[str, object]) -> list[dict[str, object]]:
    children = obj.get("Children")
    if isinstance(children, list):
        return children  # type: ignore[return-value]
    obj["Children"] = []
    return obj["Children"]  # type: ignore[return-value]


def component_type(component: dict[str, object]) -> str:
    return str(component.get("__type", ""))


def is_collider_component(component: dict[str, object]) -> bool:
    type_name = component_type(component)
    if type_name.endswith("Collider"):
        return True
    return "IsTrigger" in component and any(key in component for key in ("Radius", "Height", "Start", "End", "Scale", "BoxSize"))


def is_hierarchy_collider_viewer_component(component: dict[str, object]) -> bool:
    type_name = component_type(component)
    if type_name in ("DroneVsPlayers.SelectedHierarchyColliderViewer", "SelectedHierarchyColliderViewer"):
        return True
    return all(
        key in component
        for key in (
            "AlwaysDraw",
            "IncludeTriggers",
            "SolidColliderColor",
            "TriggerColliderColor",
        )
    )


def tree_model(obj: dict[str, object]) -> str | None:
    for component in get_components(obj):
        model = component.get("Model")
        if model is None or "RenderType" not in component:
            continue
        normalized = str(model).replace("\\", "/")
        if normalized in TREE_MODELS:
            return normalized
    return None


def collision_children(owner_seed: str, variant: str) -> list[OrderedDict[str, object]]:
    children: list[OrderedDict[str, object]] = [trunk_child(owner_seed, variant)]
    children.extend(branch_child(owner_seed, variant, record) for record in BRANCH_RECORDS)
    return children


def rewrite_tree_object(obj: dict[str, object], owner_seed: str, model: str) -> bool:
    variant = TREE_MODELS[model]
    original_components = get_components(obj)
    filtered_components = [component for component in original_components if not is_collider_component(component)]
    changed = len(filtered_components) != len(original_components)
    if not any(is_hierarchy_collider_viewer_component(component) for component in filtered_components):
        filtered_components.append(hierarchy_collider_viewer_component(owner_seed))
        changed = True
    if changed:
        obj["Components"] = filtered_components

    children = get_children(obj)
    preserved_children = [
        child
        for child in children
        if not str(child.get("Name", "")).lower().startswith(("collision_trunk", "collision_branch_"))
    ]
    generated_children = collision_children(owner_seed, variant)
    if len(preserved_children) != len(children) or children[-len(generated_children) :] != generated_children:
        obj["Children"] = preserved_children + generated_children
        changed = True

    return changed


def walk_scene_objects(objects: Iterable[dict[str, object]], path: str = "") -> Iterable[tuple[dict[str, object], str]]:
    for obj in objects:
        name = str(obj.get("Name", ""))
        current_path = f"{path}/{name}" if path else name
        yield obj, current_path
        children = obj.get("Children")
        if isinstance(children, list):
            yield from walk_scene_objects(children, current_path)  # type: ignore[arg-type]


def process_json_file(path: Path) -> tuple[int, bool]:
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    changed = False
    tree_count = 0

    root_object = data.get("RootObject")
    if isinstance(root_object, dict):
        for obj, obj_path in walk_scene_objects([root_object]):
            model = tree_model(obj)
            if model is None:
                continue
            tree_count += 1
            seed = f"{path.as_posix()}:{obj.get('__guid', obj_path)}"
            changed = rewrite_tree_object(obj, seed, model) or changed
    else:
        game_objects = data.get("GameObjects")
        if isinstance(game_objects, list):
            for obj, obj_path in walk_scene_objects(game_objects):
                model = tree_model(obj)
                if model is None:
                    continue
                tree_count += 1
                seed = f"{path.as_posix()}:{obj.get('__guid', obj_path)}"
                changed = rewrite_tree_object(obj, seed, model) or changed

    if changed:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    return tree_count, changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Project root")
    parser.add_argument("--scene", default="Assets/scenes/main.scene", help="Scene JSON path")
    parser.add_argument("--dry-run", action="store_true", help="Report matching files without writing")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    targets = [root / args.scene, *(root / prefab for prefab in PREFABS)]

    if args.dry_run:
        for target in targets:
            count, _ = process_json_file_dry(target)
            print(f"{target.relative_to(root).as_posix()}: {count} pine tree object(s)")
        return 0

    total = 0
    changed_files: list[str] = []
    for target in targets:
        count, changed = process_json_file(target)
        total += count
        if changed:
            changed_files.append(target.relative_to(root).as_posix())

    print(f"Rebuilt pine trunk/branch collision for {total} pine tree object(s).")
    if changed_files:
        print("Changed files:")
        for file_path in changed_files:
            print(f"  {file_path}")
    else:
        print("No files changed.")
    print(f"Collision set: 1 trunk box + {len(BRANCH_RECORDS)} branch boxes per pine tree.")
    return 0


def process_json_file_dry(path: Path) -> tuple[int, bool]:
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    tree_count = 0
    root_object = data.get("RootObject")
    if isinstance(root_object, dict):
        for obj, _ in walk_scene_objects([root_object]):
            if tree_model(obj) is not None:
                tree_count += 1
    else:
        game_objects = data.get("GameObjects")
        if isinstance(game_objects, list):
            for obj, _ in walk_scene_objects(game_objects):
                if tree_model(obj) is not None:
                    tree_count += 1
    return tree_count, False


if __name__ == "__main__":
    raise SystemExit(main())
