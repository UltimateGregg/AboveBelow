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
import math
import random
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


def model_renderer(name: str, material: str | None, tint: str = "1,1,1,1", model: str = "models/dev/box.vmdl") -> dict[str, Any]:
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


def model_collider(name: str, model: str, static: bool = True) -> dict[str, Any]:
    return {
        "__type": "Sandbox.ModelCollider",
        "__guid": stable_guid(name, "model_collider"),
        "__enabled": True,
        "Flags": 0,
        "IsTrigger": False,
        "Model": model,
        "Static": static,
        "Surface": None,
        "SurfaceVelocity": "0,0,0",
    }


def trigger_box_collider(name: str, scale: str, static: bool = True) -> dict[str, Any]:
    collider = box_collider(name, scale, static)
    collider["IsTrigger"] = True
    return collider


def ladder_volume(name: str, top_exit: str) -> dict[str, Any]:
    return {
        "__type": "DroneVsPlayers.LadderVolume",
        "__guid": stable_guid(name, "ladder_volume"),
        "__enabled": True,
        "Flags": 0,
        "AutoConfigureCollider": True,
        "GrabPadding": 18,
        "UseTopExit": True,
        "TopExitLocalOffset": top_exit,
        "TopExitTriggerDistance": 28,
        "BottomExitTriggerDistance": 8,
    }


def point_light(name: str, color: str, radius: float) -> dict[str, Any]:
    return {
        "__type": "Sandbox.PointLight",
        "__guid": stable_guid(name, "point_light"),
        "__enabled": True,
        "Flags": 0,
        "LightColor": color,
        "Radius": radius,
        "OnComponentDestroy": None,
        "OnComponentDisabled": None,
        "OnComponentEnabled": None,
        "OnComponentFixedUpdate": None,
        "OnComponentStart": None,
        "OnComponentUpdate": None,
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


def solid_box(
    name: str,
    position: str,
    scale: str,
    material: str = "materials/arena/concrete_wall.vmat",
    tint: str = "0.78,0.78,0.72,1",
    rotation: str = "0,0,0,1",
) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        rotation=rotation,
        material=material,
        tint=tint,
        model="models/dev/box.vmdl",
        collider_scale="50,50,50",
    )


def visual_box(
    name: str,
    position: str,
    scale: str,
    material: str = "materials/arena/concrete_wall.vmat",
    tint: str = "1,1,1,1",
    rotation: str = "0,0,0,1",
) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        rotation=rotation,
        material=material,
        tint=tint,
        model="models/dev/box.vmdl",
    )


def solid_primitive(
    name: str,
    position: str,
    scale: str,
    material: str,
    tint: str,
    model: str = "models/dev/box.vmdl",
) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material=material,
        tint=tint,
        model=model,
        collider_scale="50,50,50",
    )


def model_prop(
    name: str,
    position: str,
    model: str,
    rotation: str = "0,0,0,1",
    scale: str = "1,1,1",
    tint: str = "1,1,1,1",
) -> dict[str, Any]:
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
        "Components": [
            model_renderer(name, None, tint=tint, model=model),
            model_collider(name, model),
        ],
        "Children": [],
    }


def light_marker(
    name: str,
    position: str,
    color: str,
    radius: float,
    marker_scale: str = "0.28,0.28,0.18",
    material: str = "materials/emp_glow.vmat",
) -> dict[str, Any]:
    marker = visual_box(
        f"{name}_GlowMarker",
        "0,0,0",
        marker_scale,
        material=material,
        tint=color,
    )
    return game_object(
        name,
        position,
        children=[marker],
    ) | {"Components": [point_light(name, color, radius)]}


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


ROAD_CENTER_X = 416.190948
ROAD_LENGTH_SCALE = 218.529922
ROAD_DASH_SPACING = 260
ROAD_DASH_EDGE_MARGIN = 260
ROAD_EDGE_WEAR_COUNT_PER_SIDE = 12
ROAD_EDGE_WEAR_EDGE_MARGIN = 620
ROAD_EDGE_WEAR_SEED = 416190948
DEV_BOX_UNIT = 50


def scene_float(value: float) -> str:
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return text if text else "0"


def vector_text(*values: float) -> str:
    return ",".join(scene_float(value) for value in values)


def z_rotation(degrees: float) -> str:
    radians = math.radians(degrees)
    half_angle = radians / 2
    return vector_text(0, 0, math.sin(half_angle), math.cos(half_angle))


def road_surface(name: str, position: str, scale: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material="materials/arena/asphalt_cover.vmat",
        model="models/dev/plane.vmdl",
    )


def road_plane(name: str, position: str, scale: str, material: str, tint: str = "1,1,1,1") -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material=material,
        tint=tint,
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


def road_edge_wear_decal(name: str, position: str, scale: str, rotation: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        rotation=rotation,
        material="materials/arena/road_edge_wear.vmat",
        model="models/dev/plane.vmdl",
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


def road_cover_northwest_barrier(position: str) -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    amber = "materials/emp_glow.vmat"

    children = [
        solid_box("NWBarrier_Base_Foot", "0,0,4.5", "3.42,0.62,0.18", concrete, "0.50,0.52,0.48,1"),
        solid_box("NWBarrier_Lower_Block", "0,0,25", "3.28,0.48,0.72", concrete, "0.58,0.60,0.55,1"),
        solid_box("NWBarrier_Upper_Core", "0,0,52", "3.05,0.32,0.72", concrete, "0.64,0.66,0.60,1"),
        solid_box("NWBarrier_Top_Cap", "0,0,75", "2.88,0.22,0.32", concrete, "0.70,0.71,0.66,1"),
        solid_box("NWBarrier_North_Sloped_Face", "0,11,44", "3.25,0.10,0.88", concrete, "0.55,0.57,0.52,1", rotation="0.0871557,0,0,0.9961947"),
        solid_box("NWBarrier_South_Sloped_Face", "0,-11,44", "3.25,0.10,0.88", concrete, "0.60,0.62,0.57,1", rotation="-0.0871557,0,0,0.9961947"),
        solid_box("NWBarrier_Left_End_Cap", "-84,0,42", "0.14,0.52,1.44", concrete, "0.48,0.50,0.47,1"),
        solid_box("NWBarrier_Right_End_Cap", "84,0,42", "0.14,0.52,1.44", concrete, "0.48,0.50,0.47,1"),
        solid_box("NWBarrier_North_Toe", "0,16,12", "3.26,0.12,0.22", concrete, "0.46,0.48,0.44,1"),
        solid_box("NWBarrier_South_Toe", "0,-16,12", "3.26,0.12,0.22", concrete, "0.46,0.48,0.44,1"),
        visual_box("NWBarrier_Reflector_Left", "-64,-16.4,54", "0.26,0.025,0.16", amber, "1,0.62,0.15,1"),
        visual_box("NWBarrier_Reflector_Right", "64,-16.4,54", "0.26,0.025,0.16", amber, "1,0.62,0.15,1"),
        visual_box("NWBarrier_HazardStripe_Left", "-44,-16.8,53", "0.18,0.026,0.72", metal, "0.96,0.74,0.12,1", rotation="0,0.173648,0,0.984807"),
        visual_box("NWBarrier_HazardStripe_Mid", "0,-16.8,53", "0.18,0.026,0.72", metal, "0.08,0.08,0.07,1", rotation="0,0.173648,0,0.984807"),
        visual_box("NWBarrier_HazardStripe_Right", "44,-16.8,53", "0.18,0.026,0.72", metal, "0.96,0.74,0.12,1", rotation="0,0.173648,0,0.984807"),
        visual_box("NWBarrier_ConcreteChip_Left", "-74,-16.7,30", "0.34,0.024,0.18", concrete, "0.34,0.35,0.32,1"),
        visual_box("NWBarrier_ConcreteChip_Right", "72,16.7,36", "0.28,0.024,0.22", concrete, "0.38,0.39,0.36,1"),
        visual_box("NWBarrier_DirtScuff_Lower", "-12,-16.9,18", "1.15,0.022,0.12", concrete, "0.28,0.25,0.20,1"),
        visual_box("NWBarrier_DirtScuff_Top", "28,16.9,66", "0.74,0.022,0.09", concrete, "0.42,0.40,0.34,1"),
    ]

    return game_object("RoadCover_Northwest_Barrier", position, children=children)


def build_road_edge_wear_decals(cx: float) -> list[dict[str, Any]]:
    rng = random.Random(ROAD_EDGE_WEAR_SEED)
    road_half_length = (ROAD_LENGTH_SCALE * DEV_BOX_UNIT) / 2
    min_y = -road_half_length + ROAD_EDGE_WEAR_EDGE_MARGIN
    max_y = road_half_length - ROAD_EDGE_WEAR_EDGE_MARGIN
    bucket_span = (max_y - min_y) / ROAD_EDGE_WEAR_COUNT_PER_SIDE
    decals: list[dict[str, Any]] = []

    for side_name, direction in (("West", -1), ("East", 1)):
        side_values: list[tuple[float, float, float, float, float, float]] = []
        for index in range(ROAD_EDGE_WEAR_COUNT_PER_SIDE):
            base_y = min_y + bucket_span * (index + 0.5)
            y = base_y + rng.uniform(-bucket_span * 0.36, bucket_span * 0.36)
            x = cx + direction * rng.uniform(132, 174)
            z = rng.uniform(0.39, 0.45)
            scale_x = rng.uniform(0.74, 1.48)
            scale_y = rng.uniform(3.0, 6.9)
            yaw = rng.uniform(-4.2, 4.2)
            side_values.append((y, x, z, scale_x, scale_y, yaw))

        side_values.sort(key=lambda values: values[0])
        for index, (y, x, z, scale_x, scale_y, yaw) in enumerate(side_values, start=1):
            decals.append(
                road_edge_wear_decal(
                    f"RoadEdgeWear_{side_name}_{index:02}",
                    vector_text(x, y, z),
                    vector_text(scale_x, scale_y, 1),
                    z_rotation(yaw),
                )
            )

    return decals


def build_road_corridor() -> dict[str, Any]:
    yellow = "1,0.78,0.16,1"
    dirt = "0.50,0.43,0.28,1"
    concrete = "materials/arena/concrete_wall.vmat"
    grass = "materials/arena/grass_ground.vmat"

    cx = ROAD_CENTER_X
    west_curb_x = cx - 205
    east_curb_x = cx + 205
    west_shoulder_x = cx - 275
    east_shoulder_x = cx + 275

    children: list[dict[str, Any]] = [
        road_plane("RoadShoulder_West", f"{west_shoulder_x},0,0.16", f"2.2,{ROAD_LENGTH_SCALE},1", grass, dirt),
        road_plane("RoadShoulder_East", f"{east_shoulder_x},0,0.16", f"2.2,{ROAD_LENGTH_SCALE},1", grass, dirt),
        road_surface("RoadSurface_Main", f"{cx},0,0.2", f"7.2,{ROAD_LENGTH_SCALE},1"),
        road_curb("RoadCurb_West", f"{west_curb_x},0,5", f"0.32,{ROAD_LENGTH_SCALE},0.2"),
        road_curb("RoadCurb_East", f"{east_curb_x},0,5", f"0.32,{ROAD_LENGTH_SCALE},0.2"),
    ]

    road_half_length = (ROAD_LENGTH_SCALE * DEV_BOX_UNIT) / 2
    dash_extent = int((road_half_length - ROAD_DASH_EDGE_MARGIN) // ROAD_DASH_SPACING) * ROAD_DASH_SPACING
    for index, y in enumerate(range(-dash_extent, dash_extent + 1, ROAD_DASH_SPACING), start=1):
        children.append(road_marking(f"RoadDash_{index:02}", f"{cx},{y},2", "0.16,2.4,0.04", yellow))

    children.extend(build_road_edge_wear_decals(cx))

    children.extend(
        [
            road_cover_northwest_barrier(f"{cx - 305},1185,0"),
            solid_box("RoadCover_Northeast_Barrier", f"{cx + 335},1510,42", "0.56,3.1,1.7", concrete, "0.62,0.64,0.58,1"),
            solid_box("RoadCover_Southwest_Barrier", f"{cx - 335},-1335,42", "0.56,3.2,1.7", concrete, "0.62,0.64,0.58,1"),
            solid_box("RoadCover_Southeast_Barrier", f"{cx + 305},-980,42", "3.2,0.52,1.7", concrete, "0.62,0.64,0.58,1"),
            road_marking("RoadShoulderDirt_West_North", f"{cx - 238},1680,1.2", "0.5,7.0,0.025", dirt),
            road_marking("RoadShoulderDirt_West_South", f"{cx - 246},-1510,1.2", "0.58,6.2,0.025", dirt),
            road_marking("RoadShoulderDirt_East_North", f"{cx + 245},1080,1.2", "0.54,5.8,0.025", dirt),
            road_marking("RoadShoulderDirt_East_South", f"{cx + 238},-1720,1.2", "0.5,6.8,0.025", dirt),
        ]
    )

    return game_object("RoadCorridor_Main", "0,0,0", children=children)


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


def lane_marker(name: str, position: str, scale: str, tint: str) -> dict[str, Any]:
    return visual_box(
        name,
        position,
        scale,
        material="materials/emp_glow.vmat",
        tint=tint,
    )


def build_north_lane() -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    children = [
        solid_box("NorthLane_WestPorchCover_A", "-1420,1235,42", "3.8,0.55,1.7", concrete, "0.72,0.74,0.70,1"),
        solid_box("NorthLane_WestPorchCover_B", "-1180,1085,48", "0.7,4.2,1.9", concrete, "0.70,0.72,0.68,1"),
        solid_box("NorthLane_WaterTower_Berm_West", "-690,1265,50", "4.6,0.7,2.0", concrete, "0.62,0.69,0.60,1"),
        solid_box("NorthLane_WaterTower_Berm_East", "-315,1660,48", "4.2,0.65,1.9", concrete, "0.62,0.69,0.60,1"),
        solid_box("NorthLane_RoadSightBreaker_Left", "210,1275,110", "0.75,3.6,4.4", concrete, "0.58,0.62,0.62,1"),
        solid_box("NorthLane_RoadSightBreaker_Right", "645,1510,88", "3.4,0.72,3.5", concrete, "0.58,0.62,0.62,1"),
        solid_box("NorthLane_EastHouse_ApproachCover", "945,1325,46", "4.8,0.62,1.85", concrete, "0.70,0.72,0.68,1"),
        solid_box("NorthLane_GullyRockCover_A", "-95,1110,38", "2.1,1.35,1.55", metal, "0.44,0.50,0.52,1"),
        lane_marker("NorthLane_PaintedRoute_01", "-1470,1160,7", "2.4,0.08,0.04", "0.2,0.85,1,0.85"),
        lane_marker("NorthLane_PaintedRoute_02", "-670,1195,7", "2.4,0.08,0.04", "0.2,0.85,1,0.85"),
        lane_marker("NorthLane_PaintedRoute_03", "760,1390,7", "2.4,0.08,0.04", "0.2,0.85,1,0.85"),
    ]
    return game_object("Lane_North_Infiltration", "0,0,0", children=children)


def center_lane_burnt_vehicle_block_north() -> dict[str, Any]:
    metal = "materials/arena/metal_pad.vmat"
    asphalt = "materials/arena/asphalt_cover.vmat"
    glow = "materials/emp_glow.vmat"
    box = "models/dev/box.vmdl"
    sphere = "models/dev/sphere.vmdl"

    children = [
        solid_primitive("BurntVehicle_CrushedLowerShell", "0,0,33", "4.85,2.04,0.56", metal, "0.10,0.11,0.11,1", box),
        solid_primitive("BurntVehicle_LeftRocker_RustedSplit", "0,-57,29", "4.55,0.18,0.34", metal, "0.42,0.18,0.08,1", box),
        solid_primitive("BurntVehicle_RightRocker_RustedSplit", "0,57,29", "4.55,0.18,0.34", metal, "0.38,0.16,0.07,1", box),
        solid_primitive("BurntVehicle_Hood_WarpedBlackPlate", "75,0,58", "1.82,1.78,0.16", metal, "0.07,0.075,0.07,1", box),
        solid_primitive("BurntVehicle_Trunk_CavedRustPlate", "-86,0,54", "1.55,1.74,0.18", metal, "0.34,0.17,0.08,1", box),
        solid_primitive("BurntVehicle_Cabin_SootVoid", "-5,0,66", "1.72,1.48,0.72", metal, "0.025,0.025,0.025,1", box),
        solid_primitive("BurntVehicle_Roof_CollapsedSootPlate", "-10,0,96", "1.96,1.42,0.18", metal, "0.055,0.052,0.048,1", box),
        solid_primitive("BurntVehicle_Engine_ExposedBlock", "110,0,41", "0.62,0.90,0.46", metal, "0.03,0.03,0.028,1", box),
        solid_primitive("BurntVehicle_FrontBumper_HangingSteel", "137,0,25", "0.18,2.14,0.22", metal, "0.26,0.20,0.17,1", box),
        solid_primitive("BurntVehicle_RearBumper_SaggedRust", "-137,0,25", "0.18,2.04,0.22", metal, "0.39,0.17,0.08,1", box),
        solid_primitive("BurntVehicle_Wheel_FL_CharredTire", "82,-62,24", "0.74,0.28,0.74", metal, "0.018,0.018,0.016,1", sphere),
        solid_primitive("BurntVehicle_Wheel_FR_CharredTire", "82,62,24", "0.74,0.28,0.74", metal, "0.018,0.018,0.016,1", sphere),
        solid_primitive("BurntVehicle_Wheel_RL_ExposedRim", "-82,-62,24", "0.68,0.24,0.68", metal, "0.20,0.18,0.15,1", sphere),
        solid_primitive("BurntVehicle_Wheel_RR_BurnedHub", "-82,62,24", "0.68,0.24,0.68", metal, "0.24,0.12,0.06,1", sphere),
        visual_box("BurntVehicle_AshBed_GroundScorch", "0,0,2", "5.80,2.75,0.04", asphalt, "0.055,0.052,0.047,1"),
        visual_box("BurntVehicle_AshDrift_Front", "128,-28,8", "0.75,0.38,0.12", asphalt, "0.16,0.15,0.13,1"),
        visual_box("BurntVehicle_AshDrift_Rear", "-122,34,8", "0.82,0.42,0.12", asphalt, "0.13,0.12,0.105,1"),
        visual_box("BurntVehicle_BrokenGlass_WindshieldShard", "42,-39,83", "0.60,0.035,0.24", metal, "0.06,0.10,0.12,0.58"),
        visual_box("BurntVehicle_BrokenGlass_SideShard", "-43,39,75", "0.50,0.035,0.22", metal, "0.05,0.09,0.105,0.56"),
        visual_box("BurntVehicle_RustStripe_LeftPanel", "16,-59,50", "1.45,0.035,0.13", metal, "0.52,0.20,0.07,1"),
        visual_box("BurntVehicle_RustStripe_RightPanel", "-18,59,49", "1.30,0.035,0.13", metal, "0.49,0.18,0.06,1"),
        visual_box("BurntVehicle_SootScale_Hood", "78,-46,65", "0.72,0.035,0.18", asphalt, "0.015,0.015,0.013,1"),
        visual_box("BurntVehicle_SootScale_Roof", "-18,42,105", "0.65,0.035,0.14", asphalt, "0.012,0.012,0.011,1"),
        visual_box("BurntVehicle_HotWarning_Reflector", "136,-55,37", "0.18,0.026,0.18", glow, "1,0.42,0.12,0.85"),
    ]

    return game_object("CenterLane_BurntVehicleBlock_North", "923.058044,690,0", children=children)


def build_center_lane() -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    children = [
        solid_box("CenterLane_GPSBreak_WestTall", "-780,150,145", "0.78,4.8,5.8", concrete, "0.52,0.55,0.57,1"),
        solid_box("CenterLane_GPSBreak_EastTall", "520,-160,145", "0.78,4.8,5.8", concrete, "0.52,0.55,0.57,1"),
        solid_box("CenterLane_MedianLowCover_North", "-220,455,44", "5.4,0.58,1.75", concrete, "0.74,0.75,0.70,1"),
        solid_box("CenterLane_MedianLowCover_South", "235,-455,44", "5.4,0.58,1.75", concrete, "0.74,0.75,0.70,1"),
        center_lane_burnt_vehicle_block_north(),
        solid_box("CenterLane_BurntVehicleBlock_South", "-415,-710,62", "2.8,1.35,2.45", metal, "0.32,0.36,0.37,1"),
        solid_box("CenterLane_ServiceBarricade_West", "-1090,-205,54", "0.68,3.8,2.15", concrete, "0.62,0.64,0.62,1"),
        solid_box("CenterLane_ServiceBarricade_East", "1120,245,54", "0.68,3.8,2.15", concrete, "0.62,0.64,0.62,1"),
        lane_marker("CenterLane_DangerStripe_North", "-40,515,8", "4.8,0.08,0.04", "1,0.72,0.18,0.9"),
        lane_marker("CenterLane_DangerStripe_South", "35,-515,8", "4.8,0.08,0.04", "1,0.72,0.18,0.9"),
    ]
    return game_object("Lane_Center_Killbox", "0,0,0", children=children)


def build_south_lane() -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    children = [
        solid_box("SouthLane_HouseExitCover_A", "-1370,-1180,44", "4.1,0.62,1.75", concrete, "0.70,0.72,0.68,1"),
        solid_box("SouthLane_HouseExitCover_B", "-1060,-1510,48", "0.68,4.4,1.9", concrete, "0.70,0.72,0.68,1"),
        solid_box("SouthLane_TrenchConnector_West", "-610,-1090,42", "4.8,0.6,1.7", concrete, "0.61,0.68,0.58,1"),
        solid_box("SouthLane_TrenchConnector_Mid", "120,-945,44", "0.68,4.2,1.75", concrete, "0.61,0.68,0.58,1"),
        solid_box("SouthLane_SprintGap_RoadCover", "780,-1260,52", "4.6,0.62,2.05", concrete, "0.74,0.72,0.66,1"),
        solid_box("SouthLane_EastHouse_BreachCover", "1510,-1265,48", "0.72,4.2,1.9", concrete, "0.70,0.72,0.68,1"),
        solid_box("SouthLane_DroneDive_Baffle", "1110,-760,116", "0.7,3.4,4.65", metal, "0.42,0.47,0.50,1"),
        lane_marker("SouthLane_PaintedRoute_01", "-1280,-1080,7", "2.2,0.08,0.04", "0.2,0.85,1,0.85"),
        lane_marker("SouthLane_PaintedRoute_02", "-240,-1010,7", "2.2,0.08,0.04", "0.2,0.85,1,0.85"),
        lane_marker("SouthLane_PaintedRoute_03", "930,-1180,7", "2.2,0.08,0.04", "0.2,0.85,1,0.85"),
    ]
    return game_object("Lane_South_Flank", "0,0,0", children=children)


def build_operator_nests() -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    children = [
        game_object(
            "OperatorNest_EastLaunch",
            "0,0,0",
            children=[
                solid_box("EastLaunch_NorthBlastWall", "2210,365,58", "3.8,0.52,2.3", concrete, "0.58,0.61,0.62,1"),
                solid_box("EastLaunch_SouthBlastWall", "2210,-365,58", "3.8,0.52,2.3", concrete, "0.58,0.61,0.62,1"),
                solid_box("EastLaunch_BackConsoleBlock", "2455,0,48", "0.72,3.6,1.9", metal, "0.38,0.44,0.47,1"),
                visual_box("EastLaunch_ApproachPaint_North", "2015,520,9", "2.1,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.8"),
                visual_box("EastLaunch_ApproachPaint_South", "2015,-520,9", "2.1,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.8"),
                visual_box("EastLaunch_EscapeRead_East", "2570,0,9", "0.08,2.2,0.05", material="materials/emp_glow.vmat", tint="1,0.68,0.22,0.75"),
                light_marker("EastLaunch_SignalLight", "2310,0,175", "0.2,0.9,1,1", 520),
            ],
        ),
        game_object(
            "OperatorNest_MidService",
            "0,0,0",
            children=[
                solid_box("MidService_LowWall_West", "1780,510,46", "0.62,3.6,1.85", concrete, "0.64,0.66,0.62,1"),
                solid_box("MidService_LowWall_North", "2020,820,46", "3.8,0.56,1.85", concrete, "0.64,0.66,0.62,1"),
                solid_box("MidService_AntennaBase", "2240,690,74", "0.62,0.62,2.95", metal, "0.42,0.48,0.52,1"),
                visual_box("MidService_ApproachPaint_West", "1665,520,9", "0.08,2.1,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("MidService_ApproachPaint_South", "2045,405,9", "2.1,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("MidService_EscapeRead_East", "2380,690,9", "0.08,1.8,0.05", material="materials/emp_glow.vmat", tint="1,0.68,0.22,0.75"),
                light_marker("MidService_SignalLight", "2240,690,245", "1,0.68,0.22,1", 420),
            ],
        ),
        game_object(
            "OperatorNest_NorthHouse",
            "0,0,0",
            children=[
                solid_box("NorthHouse_OperatorCover_West", "1250,1885,46", "0.62,3.6,1.85", concrete, "0.64,0.66,0.62,1"),
                solid_box("NorthHouse_OperatorCover_South", "1465,1555,46", "3.5,0.56,1.85", concrete, "0.64,0.66,0.62,1"),
                visual_box("NorthHouse_ApproachPaint_West", "1125,1810,9", "0.08,2.0,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("NorthHouse_ApproachPaint_South", "1465,1440,9", "2.0,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("NorthHouse_EscapeRead_Roof", "1610,1810,9", "0.08,1.8,0.05", material="materials/emp_glow.vmat", tint="1,0.68,0.22,0.75"),
                light_marker("NorthHouse_SignalLight", "1500,1810,205", "0.2,0.9,1,1", 360),
            ],
        ),
        game_object(
            "OperatorNest_SouthHouse",
            "0,0,0",
            children=[
                solid_box("SouthHouse_OperatorCover_West", "1510,-1885,46", "0.62,3.6,1.85", concrete, "0.64,0.66,0.62,1"),
                solid_box("SouthHouse_OperatorCover_North", "1705,-1545,46", "3.5,0.56,1.85", concrete, "0.64,0.66,0.62,1"),
                visual_box("SouthHouse_ApproachPaint_West", "1385,-1810,9", "0.08,2.0,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("SouthHouse_ApproachPaint_North", "1705,-1430,9", "2.0,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
                visual_box("SouthHouse_EscapeRead_Roof", "1850,-1810,9", "0.08,1.8,0.05", material="materials/emp_glow.vmat", tint="1,0.68,0.22,0.75"),
                light_marker("SouthHouse_SignalLight", "1740,-1810,205", "0.2,0.9,1,1", 360),
            ],
        ),
    ]
    return game_object("OperatorNestPatterns", "0,0,0", children=children)


def build_readability_vfx() -> dict[str, Any]:
    children = [
        light_marker("LaunchPad_Glow_North", "2140,310,70", "0.2,0.9,1,1", 420, marker_scale="1.6,0.08,0.06"),
        light_marker("LaunchPad_Glow_South", "2140,-310,70", "0.2,0.9,1,1", 420, marker_scale="1.6,0.08,0.06"),
        light_marker("WaterTower_PerchMarker", "-940,1497,360", "1,0.68,0.22,1", 360, marker_scale="0.7,0.7,0.08"),
        light_marker("NorthRoof_PerchMarker", "1120,1680,286", "1,0.68,0.22,1", 320, marker_scale="0.65,0.65,0.08"),
        light_marker("SouthRoof_PerchMarker", "1340,-1660,286", "1,0.68,0.22,1", 320, marker_scale="0.65,0.65,0.08"),
        visual_box("BreachMarker_NorthHouse_West", "910,1680,8", "0.08,2.6,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
        visual_box("BreachMarker_NorthHouse_South", "1185,1370,8", "2.6,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
        visual_box("BreachMarker_SouthHouse_West", "1130,-1660,8", "0.08,2.6,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
        visual_box("BreachMarker_SouthHouse_North", "1395,-1370,8", "2.6,0.08,0.05", material="materials/emp_glow.vmat", tint="0.2,0.9,1,0.75"),
    ]
    return game_object("ReadabilityVFX_Blockout", "0,0,0", children=children)


def build_asset_replacement_placeholders() -> dict[str, Any]:
    metal = "materials/arena/metal_pad.vmat"
    children = [
        solid_box("AssetPlaceholder_SignalMast_East", "2380,0,210", "0.22,0.22,8.4", metal, "0.36,0.42,0.46,1"),
        solid_box("AssetPlaceholder_SignalMast_Mid", "2240,690,205", "0.2,0.2,7.8", metal, "0.36,0.42,0.46,1"),
        solid_box("AssetPlaceholder_RooftopHVAC_North", "1250,1630,285", "1.9,1.1,0.72", metal, "0.38,0.43,0.45,1"),
        solid_box("AssetPlaceholder_RooftopHVAC_South", "1460,-1605,285", "1.9,1.1,0.72", metal, "0.38,0.43,0.45,1"),
        model_prop("BurntCarWreck_NorthLane", "891.141296,2359.74512,0.2", "models/burnt_car_wreck.vmdl", rotation="0,0,0.0436193869,0.999048233"),
        model_prop("BurntCarWreck_SouthLane", "1040,-1460,0.2", "models/burnt_car_wreck.vmdl", rotation="0,0,-0.0610485412,0.998134792"),
    ]
    return game_object("AssetProductionPlaceholders", "0,0,0", children=children)


def build_above_below_level_pass() -> dict[str, Any]:
    return game_object(
        "LevelDesignPass_AboveBelow",
        "0,0,0",
        children=[
            build_north_lane(),
            build_center_lane(),
            build_south_lane(),
            build_operator_nests(),
            build_readability_vfx(),
            build_asset_replacement_placeholders(),
        ],
    )


def ladder_visual_box(name: str, position: str, scale: str, tint: str = "0.64,0.70,0.72,1") -> dict[str, Any]:
    return visual_box(
        name,
        position,
        scale,
        material="materials/arena/metal_pad.vmat",
        tint=tint,
    )


def ladder_trigger_child(name: str, position: str, scale: str, top_exit: str) -> dict[str, Any]:
    return {
        "__guid": stable_guid(name),
        "__version": 2,
        "Flags": 0,
        "Name": name,
        "Position": position,
        "Rotation": "0,0,0,1",
        "Scale": "1,1,1",
        "Tags": "",
        "Enabled": True,
        "NetworkMode": 2,
        "NetworkFlags": 0,
        "NetworkOrphaned": 0,
        "NetworkTransmit": True,
        "OwnerTransfer": 1,
        "Components": [
            trigger_box_collider(name, scale),
            ladder_volume(name, top_exit),
        ],
        "Children": [],
    }


def build_floating_center_ladder() -> dict[str, Any]:
    children: list[dict[str, Any]] = [
        solid_box(
            "TopLanding",
            "0,92,470",
            "2.6,2.0,0.28",
            material="materials/arena/metal_pad.vmat",
            tint="0.38,0.46,0.48,1",
        ),
        solid_box(
            "TopLanding_BackStop",
            "0,152,515",
            "2.6,0.18,1.8",
            material="materials/arena/concrete_wall.vmat",
            tint="0.58,0.62,0.62,1",
        ),
        ladder_trigger_child(
            "Collision_Ladder",
            "0,0,245",
            "82,58,450",
            "0,92,486",
        ),
        ladder_visual_box("Visual_Rail_Left", "-32,0,245", "0.12,0.12,8.9"),
        ladder_visual_box("Visual_Rail_Right", "32,0,245", "0.12,0.12,8.9"),
    ]

    for index, z in enumerate(range(58, 431, 34), start=1):
        children.append(
            ladder_visual_box(
                f"Visual_Rung_{index:02}",
                f"0,0,{z}",
                "1.42,0.12,0.10",
                tint="0.74,0.78,0.76,1",
            )
        )

    children.extend(
        [
            ladder_visual_box("Visual_TopCue", "0,74,492", "1.9,0.12,0.12", tint="0.9,0.74,0.22,1"),
            light_marker("FloatingCenterLadder_ReadLight", "0,62,535", "1,0.68,0.22,1", 360, marker_scale="0.44,0.44,0.08"),
        ]
    )

    return game_object(
        "FloatingCenterLadder",
        f"{ROAD_CENTER_X},0,0",
        children=children,
    )


def install_group(parent: dict[str, Any], group: dict[str, Any], aliases: set[str] | None = None) -> tuple[int, int]:
    children = parent.setdefault("Children", [])
    before = len(children)
    removable_names = aliases or {group["Name"]}
    removable_names.add(group["Name"])
    children[:] = [child for child in children if child.get("Name") not in removable_names]
    removed = before - len(children)
    insert_at = 1 if children and children[0].get("Name") == "ArenaFloor" else len(children)
    children.insert(insert_at, group)
    return len(group.get("Children", []) or []), removed


def install_group_after(parent: dict[str, Any], group: dict[str, Any], after_name: str, aliases: set[str] | None = None) -> tuple[int, int]:
    children = parent.setdefault("Children", [])
    before = len(children)
    removable_names = aliases or {group["Name"]}
    removable_names.add(group["Name"])
    children[:] = [child for child in children if child.get("Name") not in removable_names]
    removed = before - len(children)

    insert_at = len(children)
    for index, child in enumerate(children):
        if child.get("Name") == after_name:
            insert_at = index + 1
            break

    children.insert(insert_at, group)
    return len(group.get("Children", []) or []), removed


def add_road_corridor(scene_path: Path, dry_run: bool) -> None:
    root = project_root()
    data = json.loads(scene_path.read_text(encoding="utf-8"))
    blockout_map = find_object(data, "BlockoutMap")
    if blockout_map is None:
        raise RuntimeError("BlockoutMap was not found in the scene")

    group = build_road_corridor()
    count, removed = install_group(blockout_map, group, aliases={"RoadIntersection_Center", "RoadCorridor_Main"})

    scene_info = find_object(data, "Scene Information")
    if scene_info:
        for component in scene_info.get("Components", []) or []:
            if component.get("__type") == "Sandbox.SceneInformation":
                component["Description"] = (
                    "ABOVE / BELOW playable map: expanded arena with textured grass, "
                    "a finished north-south tactical service road corridor, concrete cover, "
                    "metal launch pad, west soldier base, east drone pad, central cover, "
                    "GameManager, HUD, and role-specific spawn points."
                )

    if dry_run:
        print(f"Dry run: would install {count} RoadCorridor_Main children; replaced road groups: {removed}")
        return

    backup_path = backup(scene_path, root)
    scene_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Backup: {backup_path}")
    print(f"Installed RoadCorridor_Main with {count} child objects")


def add_road_intersection(scene_path: Path, dry_run: bool) -> None:
    add_road_corridor(scene_path, dry_run)


def add_legacy_road_intersection(scene_path: Path, dry_run: bool) -> None:
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


def apply_above_below_level_pass(scene_path: Path, dry_run: bool) -> None:
    root = project_root()
    data = json.loads(scene_path.read_text(encoding="utf-8"))
    blockout_map = find_object(data, "BlockoutMap")
    if blockout_map is None:
        raise RuntimeError("BlockoutMap was not found in the scene")

    group = build_above_below_level_pass()
    count, removed = install_group(blockout_map, group)

    scene_info = find_object(data, "Scene Information")
    if scene_info:
        for component in scene_info.get("Components", []) or []:
            if component.get("__type") == "Sandbox.SceneInformation":
                component["Description"] = (
                    "ABOVE / BELOW playable map pass: three readable west-to-east soldier lanes, "
                    "defensible but breachable pilot/operator nests, broken drone sightlines, "
                    "authored collision-bearing cover, launch/readability lights, and asset-replacement placeholders."
                )

    if dry_run:
        print(f"Dry run: would install {count} LevelDesignPass_AboveBelow child groups; replaced groups: {removed}")
        return

    backup_path = backup(scene_path, root)
    scene_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Backup: {backup_path}")
    print(f"Installed LevelDesignPass_AboveBelow with {count} child groups")


def add_floating_center_ladder(scene_path: Path, dry_run: bool) -> None:
    root = project_root()
    data = json.loads(scene_path.read_text(encoding="utf-8"))
    blockout_map = find_object(data, "BlockoutMap")
    if blockout_map is None:
        raise RuntimeError("BlockoutMap was not found in the scene")

    group = build_floating_center_ladder()
    count, removed = install_group_after(blockout_map, group, after_name="RoadCorridor_Main")

    if dry_run:
        print(f"Dry run: would install {count} FloatingCenterLadder child objects; replaced groups: {removed}")
        return

    backup_path = backup(scene_path, root)
    scene_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Backup: {backup_path}")
    print(f"Installed FloatingCenterLadder with {count} child objects")


def main() -> int:
    parser = argparse.ArgumentParser(description="Repeatable S&Box scene blockout edits.")
    parser.add_argument("command", choices=["add-road-corridor", "add-road-intersection", "apply-above-below-level-pass", "add-floating-center-ladder"])
    parser.add_argument("--scene", default="Assets/scenes/main.scene")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    scene_path = Path(args.scene)
    if not scene_path.is_absolute():
        scene_path = project_root() / scene_path
    if not scene_path.exists():
        raise FileNotFoundError(scene_path)

    if args.command == "add-road-corridor":
        add_road_corridor(scene_path, args.dry_run)
    elif args.command == "add-road-intersection":
        add_road_intersection(scene_path, args.dry_run)
    elif args.command == "apply-above-below-level-pass":
        apply_above_below_level_pass(scene_path, args.dry_run)
    elif args.command == "add-floating-center-ladder":
        add_floating_center_ladder(scene_path, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
