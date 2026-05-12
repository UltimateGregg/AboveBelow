import bpy
import os

os.makedirs("C:/Programming/S&Box/Assets/models", exist_ok=True)

# Find and scale the Drone root object
drone = bpy.data.objects.get("Drone")
if drone:
    drone.scale = (0.3, 0.3, 0.3)
    print(f"✓ Scaled Drone to 0.3x")
else:
    print("Warning: Drone root not found, scaling all objects")
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            obj.scale = (0.3, 0.3, 0.3)

# Export the whole scene
export_path = "C:/Programming/S&Box/Assets/models/drone_high.fbx"
try:
    bpy.ops.export_scene.fbx(filepath=export_path, use_selection=False)
    print(f"✅ SUCCESS: Exported scaled drone to {export_path}")
except Exception as e:
    print(f"ERROR: {e}")
