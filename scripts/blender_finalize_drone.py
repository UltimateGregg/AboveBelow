"""
Blender Drone Finalization Script
Parent propellers to arms and export FBX
Paste this into Blender's Python console and run
"""

import bpy

# Parent propellers to arms
propeller_arm_pairs = [
    ("Propeller_1", "Arm_1"),
    ("Propeller_2", "Arm_2"),
    ("Propeller_3", "Arm_3"),
    ("Propeller_4", "Arm_4"),
]

print("🔧 Parenting propellers to arms...")
for prop_name, arm_name in propeller_arm_pairs:
    prop = bpy.data.objects.get(prop_name)
    arm = bpy.data.objects.get(arm_name)
    if prop and arm:
        prop.parent = arm
        print(f"  ✓ {prop_name} → {arm_name}")
    else:
        print(f"  ✗ Missing: {prop_name} or {arm_name}")

# Select Drone root
drone = bpy.data.objects.get("Drone")
if not drone:
    print("✗ ERROR: Drone object not found!")
else:
    bpy.context.view_layer.objects.active = drone
    drone.select_set(True)
    print(f"\n✓ Selected Drone")

    # Export FBX
    export_path = r"C:\Programming\S&Box\Assets\models\drone_high.fbx"
    bpy.ops.export_scene.fbx(
        filepath=export_path,
        use_selection=True,
        global_scale=1.0,
        axis_forward='-Y',
        axis_up='Z'
    )
    print(f"\n✅ Exported to: {export_path}")
    print("\nNext: Import FBX into S&Box via Asset Browser")
