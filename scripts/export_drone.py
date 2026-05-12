import bpy
import os

os.makedirs("C:/Programming/S&Box/Assets/models", exist_ok=True)

drone = bpy.data.objects.get("Drone")
if drone:
    bpy.context.view_layer.objects.active = drone
    drone.select_set(True)

    export_path = "C:/Programming/S&Box/Assets/models/drone_high.fbx"
    bpy.ops.export_scene.fbx(filepath=export_path, use_selection=True)
    print(f"✅ SUCCESS: Exported to {export_path}")
else:
    print("ERROR: Drone not found")
