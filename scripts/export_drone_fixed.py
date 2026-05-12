import bpy
import os

os.makedirs("C:/Programming/S&Box/Assets/models", exist_ok=True)

# Collect all mesh data
meshes = []
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        meshes.append(obj)

print(f"Found {len(meshes)} mesh objects")

# Export the whole scene (all objects)
export_path = "C:/Programming/S&Box/Assets/models/drone_high.fbx"
try:
    bpy.ops.export_scene.fbx(filepath=export_path, use_selection=False)
    print(f"✅ SUCCESS: Exported {len(meshes)} objects to {export_path}")
except Exception as e:
    print(f"ERROR: {e}")
