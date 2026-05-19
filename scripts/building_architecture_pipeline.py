#!/usr/bin/env python3
"""
Generate the authored building meshes and keep the S&Box prefab/scene graphs in
sync with those meshes.

Run blend generation inside Blender:
  blender --background --python scripts/building_architecture_pipeline.py -- --generate-blends

Run JSON wiring with normal Python:
  python scripts/building_architecture_pipeline.py --write-configs --write-prefabs --update-scene
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BLEND_DIR = ROOT / "environment_model.blend"
MODEL_DIR = ROOT / "Assets" / "models"
PREFAB_DIR = ROOT / "Assets" / "prefabs" / "environment"
SCENE_PATH = ROOT / "Assets" / "scenes" / "main.scene"
SCRIPTS_DIR = ROOT / "scripts"

MATERIAL_REMAP = {
    "Material_Brick": "materials/arena/concrete_wall.vmat",
    "Material_Concrete": "materials/arena/concrete_wall.vmat",
    "Material_Glass": "materials/arena/asphalt_cover.vmat",
    "Material_Metal": "materials/arena/metal_pad.vmat",
    "Material_Wood": "materials/arena/asphalt_cover.vmat",
}

MATERIAL_COLORS = {
    "Material_Brick": (0.47, 0.40, 0.35, 1.0),
    "Material_Concrete": (0.55, 0.55, 0.52, 1.0),
    "Material_Glass": (0.20, 0.35, 0.42, 0.55),
    "Material_Metal": (0.38, 0.39, 0.40, 1.0),
    "Material_Wood": (0.37, 0.25, 0.15, 1.0),
}


def stable_guid(*parts: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "/".join(parts)))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def base_gameobject(name: str, position: str = "0,0,0") -> dict[str, Any]:
    return {
        "__guid": stable_guid("building-template", name, "go"),
        "Flags": 0,
        "Name": name,
        "Position": position,
        "Rotation": "0,0,0,1",
        "Scale": "1,1,1",
        "Enabled": True,
        "Components": [],
        "Children": [],
    }


def model_renderer(model: str, name: str) -> dict[str, Any]:
    return {
        "__type": "Sandbox.ModelRenderer",
        "__guid": stable_guid("building-template", name, "renderer"),
        "BodyGroups": 18446744073709551615,
        "CreateAttachments": False,
        "Model": model,
        "RenderType": "On",
        "Tint": "1,1,1,1",
    }


def box_collider(name: str, scale: str, center: str = "0,0,0", trigger: bool = False) -> dict[str, Any]:
    return {
        "__type": "Sandbox.BoxCollider",
        "__guid": stable_guid("building-template", name, "box"),
        "Center": center,
        "Scale": scale,
        "Static": True,
        "IsTrigger": trigger,
    }


def ladder_volume(name: str, top_exit: str) -> dict[str, Any]:
    return {
        "__type": "DroneVsPlayers.LadderVolume",
        "__guid": stable_guid("building-template", name, "ladder-volume"),
        "AutoConfigureCollider": True,
        "GrabPadding": 18,
        "UseTopExit": True,
        "TopExitLocalOffset": top_exit,
        "TopExitTriggerDistance": 32,
        "BottomExitTriggerDistance": 8,
    }


def visual_child(name: str, model: str) -> dict[str, Any]:
    child = base_gameobject("Model_Visual")
    child["__guid"] = stable_guid(name, "Model_Visual", "go")
    child["Components"] = [model_renderer(model, name)]
    return child


def collision_child(name: str, position: str, scale: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [box_collider(name, scale)]
    return child


def trigger_child(name: str, position: str, scale: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [box_collider(name, scale, trigger=True)]
    return child


def ladder_child(name: str, position: str, collider_center: str, collider_scale: str, top_exit: str) -> dict[str, Any]:
    child = base_gameobject(name, position)
    child["Components"] = [
        ladder_volume(name, top_exit),
        box_collider(name, collider_scale, center=collider_center, trigger=True),
    ]
    return child


def large_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Large", "models/house_large.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Basement", "0,0,-170", "240,240,20"),
            collision_child("Collision_Floor_Ground", "0,0,-2.211", "240,240,20"),
            collision_child("Collision_Floor_Loft", "0,0,273.482", "220,220,20"),
            collision_child("Collision_Roof", "0,0,489.571", "313.786,308.094,62.179"),
            collision_child("Collision_Basement_North", "0,-125,-76.105", "240,10,167.789"),
            collision_child("Collision_Basement_South", "0,125,-76.105", "240,10,167.789"),
            collision_child("Collision_Basement_West", "-125,0,-76.105", "10,240,167.789"),
            collision_child("Collision_Basement_East_A", "125,-70,-76.105", "10,100,167.789"),
            collision_child("Collision_Basement_East_B", "125,70,-76.105", "10,100,167.789"),
            collision_child("Collision_Wall_South_Left", "-76,125,135.635", "88,10,255.692"),
            collision_child("Collision_Wall_South_Right", "76,125,135.635", "88,10,255.692"),
            collision_child("Collision_Wall_South_Lintel", "0,125,211.741", "64,10,103.482"),
            collision_child("Collision_Wall_North_Left", "-80,-125,135.635", "80,10,255.692"),
            collision_child("Collision_Wall_North_Right", "80,-125,135.635", "80,10,255.692"),
            collision_child("Collision_Wall_North_Sill", "0,-125,47.895", "80,10,80.211"),
            collision_child("Collision_Wall_North_Header", "0,-125,211.741", "80,10,103.482"),
            collision_child("Collision_Wall_West_Lower", "-125,-80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_West_Upper", "-125,80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_West_Sill", "-125,0,47.895", "10,80,80.211"),
            collision_child("Collision_Wall_West_Header", "-125,0,211.741", "10,80,103.482"),
            collision_child("Collision_Wall_East_Lower", "125,-80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_East_Upper", "125,80,135.635", "10,80,255.692"),
            collision_child("Collision_Wall_East_Sill", "125,0,47.895", "10,80,80.211"),
            collision_child("Collision_Wall_East_Header", "125,0,211.741", "10,80,103.482"),
            collision_child("Collision_UpperWall_South_Left", "-73,115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_South_Right", "73,115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_South_Header", "0,115,429.241", "72,10,58.482"),
            collision_child("Collision_UpperWall_North_Left", "-73,-115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_North_Right", "73,-115,370.982", "74,10,175"),
            collision_child("Collision_UpperWall_North_Sill", "0,-115,311.741", "72,10,56.518"),
            collision_child("Collision_UpperWall_North_Header", "0,-115,429.241", "72,10,58.482"),
            collision_child("Collision_UpperWall_West_Lower", "-115,-73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_West_Upper", "-115,73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_West_Sill", "-115,0,311.741", "10,72,56.518"),
            collision_child("Collision_UpperWall_West_Header", "-115,0,429.241", "10,72,58.482"),
            collision_child("Collision_UpperWall_East_Lower", "115,-73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_East_Upper", "115,73,370.982", "10,74,175"),
            collision_child("Collision_UpperWall_East_Sill", "115,0,311.741", "10,72,56.518"),
            collision_child("Collision_UpperWall_East_Header", "115,0,429.241", "10,72,58.482"),
            collision_child("Collision_Interior_Wall_Left", "-65,25,135.635", "110,10,255.692"),
            collision_child("Collision_Interior_Wall_Right", "85,25,135.635", "70,10,255.692"),
            collision_child("Collision_Stairs_Down", "80,80,-76.105", "42,58,167.789"),
            collision_child("Collision_Parapet_North", "0,-135,535", "270,10,45"),
            collision_child("Collision_Parapet_South", "0,135,535", "270,10,45"),
            collision_child("Collision_Parapet_East", "135,0,535", "10,270,45"),
            collision_child("Collision_Parapet_West", "-135,0,535", "10,270,45"),
            ladder_child("Ladder_To_Loft", "-50,-104,7.789", "0,0,137.846", "30,30,275.692", "0,54,275.692"),
            ladder_child("Ladder_To_Roof", "-50,-54,283.482", "0,0,87.5", "30,30,175", "0,54,175"),
            trigger_child("Zone_Foyer", "0,105,70", "110,50,100"),
            trigger_child("Zone_LivingArea", "-55,-25,90", "150,100,140"),
            trigger_child("Zone_Kitchen", "70,60,90", "90,100,140"),
            trigger_child("Zone_Basement", "0,0,-76.105", "220,220,167.789"),
            trigger_child("Zone_Loft", "0,0,323.482", "220,220,80"),
            trigger_child("Zone_Roof", "0,0,489.571", "313.786,308.094,70"),
        ]
    )
    return children


def small_house_children() -> list[dict[str, Any]]:
    children = [visual_child("House_Small", "models/house_small.vmdl")]
    children.extend(
        [
            collision_child("Collision_Floor_Ground", "0,0,10", "180,180,20"),
            collision_child("Collision_Floor_Loft", "0,-38,240", "110,95,18"),
            collision_child("Collision_Roof", "0,0,365", "195,195,26"),
            collision_child("Collision_Wall_South_Left", "-60,90,110", "60,10,220"),
            collision_child("Collision_Wall_South_Right", "60,90,110", "60,10,220"),
            collision_child("Collision_Wall_South_Lintel", "0,90,185", "60,10,70"),
            collision_child("Collision_Wall_North_Left", "-62,-90,110", "56,10,220"),
            collision_child("Collision_Wall_North_Right", "62,-90,110", "56,10,220"),
            collision_child("Collision_Wall_North_Sill", "0,-90,42", "68,10,84"),
            collision_child("Collision_Wall_North_Header", "0,-90,185", "68,10,70"),
            collision_child("Collision_Wall_West_Lower", "-90,-55,110", "10,70,220"),
            collision_child("Collision_Wall_West_Upper", "-90,55,110", "10,70,220"),
            collision_child("Collision_Wall_West_Sill", "-90,0,42", "10,70,84"),
            collision_child("Collision_Wall_West_Header", "-90,0,185", "10,70,70"),
            collision_child("Collision_Wall_East", "90,0,110", "10,180,220"),
            collision_child("Collision_UpperWall_South_Left", "-48,74,295", "42,10,110"),
            collision_child("Collision_UpperWall_South_Right", "48,74,295", "42,10,110"),
            collision_child("Collision_UpperWall_South_Header", "0,74,328", "54,10,44"),
            collision_child("Collision_UpperWall_North_Left", "-48,-74,295", "42,10,110"),
            collision_child("Collision_UpperWall_North_Right", "48,-74,295", "42,10,110"),
            collision_child("Collision_UpperWall_North_Sill", "0,-74,260", "54,10,38"),
            collision_child("Collision_UpperWall_North_Header", "0,-74,328", "54,10,44"),
            collision_child("Collision_UpperWall_West_Lower", "-74,-46,295", "10,46,110"),
            collision_child("Collision_UpperWall_West_Upper", "-74,46,295", "10,46,110"),
            collision_child("Collision_UpperWall_West_Sill", "-74,0,260", "10,50,38"),
            collision_child("Collision_UpperWall_West_Header", "-74,0,328", "10,50,44"),
            collision_child("Collision_UpperWall_East", "74,0,295", "10,145,110"),
            collision_child("Collision_Interior_Wall", "25,12,110", "85,10,200"),
            collision_child("Collision_Parapet_North", "0,-98,392", "195,10,42"),
            collision_child("Collision_Parapet_South", "0,98,392", "195,10,42"),
            collision_child("Collision_Parapet_East", "98,0,392", "10,195,42"),
            collision_child("Collision_Parapet_West", "-98,0,392", "10,195,42"),
            ladder_child("Ladder_To_Loft", "0,-82,0", "0,0,121", "24,26,242", "0,52,252"),
            ladder_child("Ladder_To_Roof", "0,-35,240", "0,0,70", "24,26,140", "0,50,140"),
            trigger_child("Zone_Entry", "0,70,70", "95,50,100"),
            trigger_child("Zone_MainRoom", "-35,-15,90", "110,110,130"),
            trigger_child("Zone_SideRoom", "55,20,90", "70,110,130"),
            trigger_child("Zone_Loft", "0,-38,265", "110,95,70"),
            trigger_child("Zone_Roof", "0,0,392", "195,195,60"),
        ]
    )
    return children


def prefab_payload(name: str, children: list[dict[str, Any]], existing_path: Path) -> dict[str, Any]:
    existing = load_json(existing_path) if existing_path.exists() else {}
    root = (existing.get("RootObject") or {}).copy()
    root_guid = root.get("__guid", stable_guid(name, "root"))
    root = {
        "__guid": root_guid,
        "Flags": root.get("Flags", 0),
        "Name": name,
        "Enabled": True,
        "NetworkMode": root.get("NetworkMode", 2),
        "Components": root.get("Components", []),
        "Children": children,
    }
    payload = {"RootObject": root}
    for key in ("ShowInMenu", "MenuPath", "MenuIcon", "DontBreakAsTemplate", "ResourceVersion", "__references", "__version", "Meta"):
        if key in existing:
            payload[key] = existing[key]
    if "Meta" not in payload and name == "House_Large":
        payload["Meta"] = {"Version": 2}
    return payload


def write_prefabs() -> None:
    write_json(PREFAB_DIR / "House_Large.prefab", prefab_payload("House_Large", large_house_children(), PREFAB_DIR / "House_Large.prefab"))
    write_json(PREFAB_DIR / "House_Small.prefab", prefab_payload("House_Small", small_house_children(), PREFAB_DIR / "House_Small.prefab"))


def config_payload(asset_name: str, combined_name: str, root_object: str) -> dict[str, Any]:
    return {
        "source_blend": f"environment_model.blend/{asset_name}.blend",
        "root_object": root_object,
        "target_fbx": f"Assets/models/{asset_name}.fbx",
        "target_vmdl": f"Assets/models/{asset_name}.vmdl",
        "model_resource_path": f"models/{asset_name}.vmdl",
        "combine_meshes": True,
        "combined_object_name": combined_name,
        "material_remap": MATERIAL_REMAP,
        "vmdl_use_global_default": False,
        "strict_vmdl_material_sources": True,
        "verify_fbx": True,
        "required_object": [combined_name],
        "object_type": ["EMPTY", "MESH"],
        "global_scale": 0.0254,
        "axis_forward": "-Y",
        "axis_up": "Z",
    }


def write_configs() -> None:
    write_json(SCRIPTS_DIR / "house_large_asset_pipeline.json", config_payload("house_large", "HouseLargeMesh", "HouseLarge_Root"))
    write_json(SCRIPTS_DIR / "house_small_asset_pipeline.json", config_payload("house_small", "HouseSmallMesh", "HouseSmall_Root"))


def freshen_guids(node: dict[str, Any], prefix: str, path: str = "") -> dict[str, Any]:
    clone = copy.deepcopy(node)
    name = clone.get("Name", "node")
    current_path = f"{path}/{name}"
    if "__guid" in clone:
        clone["__guid"] = stable_guid(prefix, current_path, "go")
    for index, component in enumerate(clone.get("Components", []) or []):
        if "__guid" in component:
            component["__guid"] = stable_guid(prefix, current_path, f"component-{index}", component.get("__type", "component"))
    clone["Children"] = [freshen_guids(child, prefix, current_path) for child in clone.get("Children", []) or []]
    return clone


def update_scene() -> None:
    scene = load_json(SCENE_PATH)
    replacements = {
        "House_Large": large_house_children(),
        "House_Small": small_house_children(),
    }
    changed = 0

    def visit(node: dict[str, Any]) -> None:
        nonlocal changed
        name = str(node.get("Name", ""))
        for building, children in replacements.items():
            if name.startswith(f"{building}_"):
                prefix = f"scene:{node.get('__guid', name)}:{building}"
                node["Children"] = [freshen_guids(child, prefix) for child in children]
                changed += 1
                return
        for child in node.get("Children", []) or []:
            if isinstance(child, dict):
                visit(child)

    for child in scene.get("GameObjects", []) or []:
        if isinstance(child, dict):
            visit(child)
    if "RootObject" in scene and isinstance(scene["RootObject"], dict):
        visit(scene["RootObject"])

    if changed == 0:
        raise RuntimeError("No House_Large_* or House_Small_* scene instances were found.")
    write_json(SCENE_PATH, scene)
    print(f"Updated {changed} scene building instance(s).")


def generate_blends() -> None:
    try:
        import bpy
        from mathutils import Vector
    except ImportError as exc:
        raise RuntimeError("--generate-blends must run inside Blender") from exc

    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    def reset_scene() -> None:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()

    active_root = {"object": None}

    def create_root(name: str):
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 42.0
        root["sbox_asset_root"] = True
        root["sbox_asset_category"] = "environment"
        bpy.context.scene.collection.objects.link(root)
        active_root["object"] = root
        return root

    def material(name: str):
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = MATERIAL_COLORS[name]
        return mat

    def assign_uvs(obj) -> None:
        mesh = obj.data
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        uv_layer = mesh.uv_layers.active.data
        for poly in mesh.polygons:
            normal = poly.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                if axis == 0:
                    uv_layer[loop_index].uv = (co.y * 0.03, co.z * 0.03)
                elif axis == 1:
                    uv_layer[loop_index].uv = (co.x * 0.03, co.z * 0.03)
                else:
                    uv_layer[loop_index].uv = (co.x * 0.03, co.y * 0.03)

    def box(name: str, center: tuple[float, float, float], size: tuple[float, float, float], mat_name: str):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
        obj = bpy.context.view_layer.objects.active
        obj.name = name
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        obj.dimensions = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.data.materials.append(material(mat_name))
        assign_uvs(obj)
        if min(size) >= 4:
            bevel_width = min(3.0, min(size) * 0.18)
            bevel = obj.modifiers.new("Small bevels for readable edges", "BEVEL")
            bevel.width = bevel_width
            bevel.segments = 1
            bevel.affect = "EDGES"
            obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        return obj

    def roof(name: str, width: float, depth: float, eave_z: float, ridge_z: float, mat_name: str):
        hw = width * 0.5
        hd = depth * 0.5
        verts = [
            (-hw, -hd, eave_z),
            (0, -hd, ridge_z),
            (hw, -hd, eave_z),
            (-hw, hd, eave_z),
            (0, hd, ridge_z),
            (hw, hd, eave_z),
        ]
        faces = [(0, 1, 4, 3), (1, 2, 5, 4), (0, 3, 5, 2), (0, 2, 1), (3, 4, 5)]
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if active_root["object"] is not None:
            obj.parent = active_root["object"]
        obj.data.materials.append(material(mat_name))
        assign_uvs(obj)
        bevel = obj.modifiers.new("Small bevels for readable roof edges", "BEVEL")
        bevel.width = 2.0
        bevel.segments = 1
        bevel.affect = "EDGES"
        obj.modifiers.new("Weighted roof normals", "WEIGHTED_NORMAL")
        return obj

    def ladder(name: str, x: float, y: float, z: float, height: float, mat_name: str):
        objs = [
            box(f"{name}_Rail_L", (x - 7, y, z + height * 0.5), (3, 4, height), mat_name),
            box(f"{name}_Rail_R", (x + 7, y, z + height * 0.5), (3, 4, height), mat_name),
        ]
        rung_count = max(4, int(height / 32))
        for index in range(rung_count):
            rz = z + 24 + index * ((height - 48) / max(1, rung_count - 1))
            objs.append(box(f"{name}_Rung_{index + 1:02d}", (x, y - 1, rz), (18, 3, 3), mat_name))
        return objs

    def save_current(path: Path) -> None:
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        print(f"Saved {path}")

    def make_large() -> None:
        reset_scene()
        create_root("HouseLarge_Root")
        box("Floor_Basement", (0, 0, -170), (240, 240, 20), "Material_Concrete")
        box("Floor_Ground", (0, 0, -2.211), (240, 240, 20), "Material_Concrete")
        box("Basement_Wall_North", (0, -125, -76.105), (240, 10, 167.789), "Material_Concrete")
        box("Basement_Wall_South", (0, 125, -76.105), (240, 10, 167.789), "Material_Concrete")
        box("Basement_Wall_West", (-125, 0, -76.105), (10, 240, 167.789), "Material_Concrete")
        box("Basement_Wall_East_A", (125, -70, -76.105), (10, 100, 167.789), "Material_Concrete")
        box("Basement_Wall_East_B", (125, 70, -76.105), (10, 100, 167.789), "Material_Concrete")
        for name, center, size in [
            ("Wall_South_Left", (-76, 125, 135.635), (88, 10, 255.692)),
            ("Wall_South_Right", (76, 125, 135.635), (88, 10, 255.692)),
            ("Wall_South_Lintel", (0, 125, 211.741), (64, 10, 103.482)),
            ("Wall_North_Left", (-80, -125, 135.635), (80, 10, 255.692)),
            ("Wall_North_Right", (80, -125, 135.635), (80, 10, 255.692)),
            ("Wall_North_Sill", (0, -125, 47.895), (80, 10, 80.211)),
            ("Wall_North_Header", (0, -125, 211.741), (80, 10, 103.482)),
            ("Wall_West_Lower", (-125, -80, 135.635), (10, 80, 255.692)),
            ("Wall_West_Upper", (-125, 80, 135.635), (10, 80, 255.692)),
            ("Wall_West_Sill", (-125, 0, 47.895), (10, 80, 80.211)),
            ("Wall_West_Header", (-125, 0, 211.741), (10, 80, 103.482)),
            ("Wall_East_Lower", (125, -80, 135.635), (10, 80, 255.692)),
            ("Wall_East_Upper", (125, 80, 135.635), (10, 80, 255.692)),
            ("Wall_East_Sill", (125, 0, 47.895), (10, 80, 80.211)),
            ("Wall_East_Header", (125, 0, 211.741), (10, 80, 103.482)),
        ]:
            box(name, center, size, "Material_Brick")
        for name, center, size in [
            ("Upper_Wall_South_Left", (-73, 115, 370.982), (74, 10, 175)),
            ("Upper_Wall_South_Right", (73, 115, 370.982), (74, 10, 175)),
            ("Upper_Wall_South_Header", (0, 115, 429.241), (72, 10, 58.482)),
            ("Upper_Wall_North_Left", (-73, -115, 370.982), (74, 10, 175)),
            ("Upper_Wall_North_Right", (73, -115, 370.982), (74, 10, 175)),
            ("Upper_Wall_North_Sill", (0, -115, 311.741), (72, 10, 56.518)),
            ("Upper_Wall_North_Header", (0, -115, 429.241), (72, 10, 58.482)),
            ("Upper_Wall_West_Lower", (-115, -73, 370.982), (10, 74, 175)),
            ("Upper_Wall_West_Upper", (-115, 73, 370.982), (10, 74, 175)),
            ("Upper_Wall_West_Sill", (-115, 0, 311.741), (10, 72, 56.518)),
            ("Upper_Wall_West_Header", (-115, 0, 429.241), (10, 72, 58.482)),
            ("Upper_Wall_East_Lower", (115, -73, 370.982), (10, 74, 175)),
            ("Upper_Wall_East_Upper", (115, 73, 370.982), (10, 74, 175)),
            ("Upper_Wall_East_Sill", (115, 0, 311.741), (10, 72, 56.518)),
            ("Upper_Wall_East_Header", (115, 0, 429.241), (10, 72, 58.482)),
            ("Upper_Window_North_TopTrim", (0, -122, 392), (84, 4, 8)),
            ("Upper_Window_North_BottomTrim", (0, -122, 354), (84, 4, 8)),
            ("Upper_Window_East_TopTrim", (122, 0, 392), (4, 84, 8)),
            ("Upper_Window_East_BottomTrim", (122, 0, 354), (4, 84, 8)),
        ]:
            box(name, center, size, "Material_Brick" if "Window" not in name else "Material_Glass")
        box("Wall_Interior_Left", (-65, 25, 135.635), (110, 10, 255.692), "Material_Wood")
        box("Wall_Interior_Right", (85, 25, 135.635), (70, 10, 255.692), "Material_Wood")
        for name, center, size in [
            ("Door_Frame_Front_L", (-32.747, 116.887, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Front_R", (31.759, 116.887, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Back_L", (47.424, 20.731, 62.789), (5.529, 7.326, 150)),
            ("Door_Frame_Back_R", (91.656, 20.731, 62.789), (5.529, 7.326, 150)),
            ("Window_Frame_North_Top", (0, -132, 150), (92, 4, 8)),
            ("Window_Frame_North_Bottom", (0, -132, 100), (92, 4, 8)),
            ("Window_Frame_West_Top", (-132, 0, 150), (4, 92, 8)),
            ("Window_Frame_West_Bottom", (-132, 0, 100), (4, 92, 8)),
            ("Window_Frame_East_Top", (132, 0, 150), (4, 92, 8)),
            ("Window_Frame_East_Bottom", (132, 0, 100), (4, 92, 8)),
            ("Corner_Post_SW", (-132, 132, 150), (12, 12, 300)),
            ("Corner_Post_SE", (132, 132, 150), (12, 12, 300)),
            ("Corner_Post_NW", (-132, -132, 150), (12, 12, 300)),
            ("Corner_Post_NE", (132, -132, 150), (12, 12, 300)),
            ("Upper_Corner_Post_SW", (-106, 106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_SE", (106, 106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_NW", (-106, -106, 392), (10, 10, 190)),
            ("Upper_Corner_Post_NE", (106, -106, 392), (10, 10, 190)),
        ]:
            box(name, center, size, "Material_Glass" if "Window" in name else "Material_Wood")
        box("Stairs_Down", (80, 80, -76.105), (42, 58, 167.789), "Material_Concrete")
        box("Floor_Loft", (0, 0, 273.482), (220, 220, 20), "Material_Wood")
        box("Loft_Safety_Rail", (0, -112, 303.482), (220, 6, 36), "Material_Wood")
        ladder("Ladder_To_Loft", -50, -104, 7.789, 275.692, "Material_Metal")
        ladder("Ladder_To_Roof", -50, -54, 283.482, 175, "Material_Metal")
        roof("Roof_Sloped", 313.786, 308.094, 458.482, 520.661, "Material_Metal")
        for name, center, size in [
            ("Parapet_North", (0, -135, 535), (270, 10, 45)),
            ("Parapet_South", (0, 135, 535), (270, 10, 45)),
            ("Parapet_East", (135, 0, 535), (10, 270, 45)),
            ("Parapet_West", (-135, 0, 535), (10, 270, 45)),
            ("Roof_Ridge", (0, 0, 524.661), (16, 260, 8)),
        ]:
            box(name, center, size, "Material_Metal")
        save_current(BLEND_DIR / "house_large.blend")

    def make_small() -> None:
        reset_scene()
        create_root("HouseSmall_Root")
        box("Floor_Ground", (0, 0, 10), (180, 180, 20), "Material_Concrete")
        for name, center, size in [
            ("Wall_South_Left", (-60, 90, 110), (60, 10, 220)),
            ("Wall_South_Right", (60, 90, 110), (60, 10, 220)),
            ("Wall_South_Lintel", (0, 90, 185), (60, 10, 70)),
            ("Wall_North_Left", (-62, -90, 110), (56, 10, 220)),
            ("Wall_North_Right", (62, -90, 110), (56, 10, 220)),
            ("Wall_North_Sill", (0, -90, 42), (68, 10, 84)),
            ("Wall_North_Header", (0, -90, 185), (68, 10, 70)),
            ("Wall_West_Lower", (-90, -55, 110), (10, 70, 220)),
            ("Wall_West_Upper", (-90, 55, 110), (10, 70, 220)),
            ("Wall_West_Sill", (-90, 0, 42), (10, 70, 84)),
            ("Wall_West_Header", (-90, 0, 185), (10, 70, 70)),
            ("Wall_East", (90, 0, 110), (10, 180, 220)),
        ]:
            box(name, center, size, "Material_Brick")
        for name, center, size in [
            ("Upper_Wall_South_Left", (-48, 74, 295), (42, 10, 110)),
            ("Upper_Wall_South_Right", (48, 74, 295), (42, 10, 110)),
            ("Upper_Wall_South_Header", (0, 74, 328), (54, 10, 44)),
            ("Upper_Wall_North_Left", (-48, -74, 295), (42, 10, 110)),
            ("Upper_Wall_North_Right", (48, -74, 295), (42, 10, 110)),
            ("Upper_Wall_North_Sill", (0, -74, 260), (54, 10, 38)),
            ("Upper_Wall_North_Header", (0, -74, 328), (54, 10, 44)),
            ("Upper_Wall_West_Lower", (-74, -46, 295), (10, 46, 110)),
            ("Upper_Wall_West_Upper", (-74, 46, 295), (10, 46, 110)),
            ("Upper_Wall_West_Sill", (-74, 0, 260), (10, 50, 38)),
            ("Upper_Wall_West_Header", (-74, 0, 328), (10, 50, 44)),
            ("Upper_Wall_East", (74, 0, 295), (10, 145, 110)),
            ("Upper_Corner_Post_SW", (-76, 76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_SE", (76, 76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_NW", (-76, -76, 300), (10, 10, 120)),
            ("Upper_Corner_Post_NE", (76, -76, 300), (10, 10, 120)),
        ]:
            box(name, center, size, "Material_Brick")
        box("Wall_Interior", (25, 12, 110), (85, 10, 200), "Material_Wood")
        for name, center, size in [
            ("Door_Frame_Front_L", (-32, 90, 72), (6, 8, 144)),
            ("Door_Frame_Front_R", (32, 90, 72), (6, 8, 144)),
            ("Window_Frame_North_Top", (0, -94, 158), (68, 4, 8)),
            ("Window_Frame_North_Bottom", (0, -94, 78), (68, 4, 8)),
            ("Window_Frame_West_Top", (-94, 0, 158), (4, 68, 8)),
            ("Window_Frame_West_Bottom", (-94, 0, 78), (4, 68, 8)),
            ("Corner_Post_SW", (-92, 92, 112), (10, 10, 224)),
            ("Corner_Post_SE", (92, 92, 112), (10, 10, 224)),
            ("Corner_Post_NW", (-92, -92, 112), (10, 10, 224)),
            ("Corner_Post_NE", (92, -92, 112), (10, 10, 224)),
        ]:
            box(name, center, size, "Material_Glass" if "Window" in name else "Material_Wood")
        box("Floor_Loft", (0, -38, 240), (110, 95, 18), "Material_Wood")
        box("Loft_Safety_Rail", (0, -88, 270), (110, 6, 36), "Material_Wood")
        ladder("Ladder_To_Loft", 0, -82, 0, 242, "Material_Metal")
        ladder("Ladder_To_Roof", 0, -35, 240, 140, "Material_Metal")
        roof("Roof_Sloped", 205, 205, 350, 408, "Material_Metal")
        for name, center, size in [
            ("Parapet_North", (0, -98, 392), (195, 10, 42)),
            ("Parapet_South", (0, 98, 392), (195, 10, 42)),
            ("Parapet_East", (98, 0, 392), (10, 195, 42)),
            ("Parapet_West", (-98, 0, 392), (10, 195, 42)),
            ("Roof_Ridge", (0, 0, 410), (14, 205, 8)),
        ]:
            box(name, center, size, "Material_Metal")
        save_current(BLEND_DIR / "house_small.blend")

    make_large()
    make_small()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate-blends", action="store_true")
    parser.add_argument("--write-configs", action="store_true")
    parser.add_argument("--write-prefabs", action="store_true")
    parser.add_argument("--update-scene", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    args = parse_args(argv)

    if args.generate_blends:
        generate_blends()
    if args.write_configs:
        write_configs()
    if args.write_prefabs:
        write_prefabs()
    if args.update_scene:
        update_scene()

    if not any((args.generate_blends, args.write_configs, args.write_prefabs, args.update_scene)):
        raise RuntimeError("No action specified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
