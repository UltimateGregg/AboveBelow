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


def road_curb(name: str, position: str, scale: str) -> dict[str, Any]:
    return game_object(
        name,
        position,
        scale=scale,
        material="materials/arena/concrete_wall.vmat",
        tint="0.72,0.72,0.68,1",
        model="models/dev/box.vmdl",
    )


def build_road_corridor() -> dict[str, Any]:
    yellow = "1,0.78,0.16,1"
    white = "0.86,0.84,0.74,1"
    dirt = "0.50,0.43,0.28,1"
    concrete = "materials/arena/concrete_wall.vmat"
    grass = "materials/arena/grass_ground.vmat"

    cx = ROAD_CENTER_X
    west_curb_x = cx - 205
    east_curb_x = cx + 205
    west_shoulder_x = cx - 275
    east_shoulder_x = cx + 275

    children: list[dict[str, Any]] = [
        road_plane("RoadShoulder_West", f"{west_shoulder_x},0,0.16", "2.2,88,1", grass, dirt),
        road_plane("RoadShoulder_East", f"{east_shoulder_x},0,0.16", "2.2,88,1", grass, dirt),
        road_surface("RoadSurface_Main", f"{cx},0,0.2", "7.2,86,1"),
        road_curb("RoadCurb_West", f"{west_curb_x},0,5", "0.32,86,0.2"),
        road_curb("RoadCurb_East", f"{east_curb_x},0,5", "0.32,86,0.2"),
    ]

    for index, y in enumerate((-1820, -1560, -1300, -1040, -780, -520, -260, 260, 520, 780, 1040, 1300, 1560, 1820), start=1):
        children.append(road_marking(f"RoadDash_{index:02}", f"{cx},{y},2", "0.16,2.4,0.04", yellow))

    for index, y in enumerate((-1740, -920, -180, 640, 1460), start=1):
        children.append(road_marking(f"RoadEdgeWear_West_{index:02}", f"{cx - 154},{y},1.4", "0.42,5.4,0.025", white))
        children.append(road_marking(f"RoadEdgeWear_East_{index:02}", f"{cx + 154},{y + 120},1.4", "0.34,4.8,0.025", white))

    children.extend(
        [
            solid_box("RoadCover_Northwest_Barrier", f"{cx - 305},1185,42", "3.4,0.52,1.7", concrete, "0.62,0.64,0.58,1"),
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


def build_center_lane() -> dict[str, Any]:
    concrete = "materials/arena/concrete_wall.vmat"
    metal = "materials/arena/metal_pad.vmat"
    children = [
        solid_box("CenterLane_GPSBreak_WestTall", "-780,150,145", "0.78,4.8,5.8", concrete, "0.52,0.55,0.57,1"),
        solid_box("CenterLane_GPSBreak_EastTall", "520,-160,145", "0.78,4.8,5.8", concrete, "0.52,0.55,0.57,1"),
        solid_box("CenterLane_MedianLowCover_North", "-220,455,44", "5.4,0.58,1.75", concrete, "0.74,0.75,0.70,1"),
        solid_box("CenterLane_MedianLowCover_South", "235,-455,44", "5.4,0.58,1.75", concrete, "0.74,0.75,0.70,1"),
        solid_box("CenterLane_BurntVehicleBlock_North", "365,690,62", "2.8,1.35,2.45", metal, "0.32,0.36,0.37,1"),
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
    concrete = "materials/arena/concrete_wall.vmat"
    children = [
        solid_box("AssetPlaceholder_SignalMast_East", "2380,0,210", "0.22,0.22,8.4", metal, "0.36,0.42,0.46,1"),
        solid_box("AssetPlaceholder_SignalMast_Mid", "2240,690,205", "0.2,0.2,7.8", metal, "0.36,0.42,0.46,1"),
        solid_box("AssetPlaceholder_RooftopHVAC_North", "1250,1630,285", "1.9,1.1,0.72", metal, "0.38,0.43,0.45,1"),
        solid_box("AssetPlaceholder_RooftopHVAC_South", "1460,-1605,285", "1.9,1.1,0.72", metal, "0.38,0.43,0.45,1"),
        solid_box("AssetPlaceholder_Barricade_NorthLane", "540,1700,42", "3.4,0.52,1.7", concrete, "0.63,0.66,0.62,1"),
        solid_box("AssetPlaceholder_Barricade_SouthLane", "1040,-1460,42", "3.4,0.52,1.7", concrete, "0.63,0.66,0.62,1"),
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
