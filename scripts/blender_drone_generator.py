"""
Blender Drone Generator Script (Fixed - Context Independent)
Generates a stylized quadcopter drone model for S&Box integration
Run in Blender: Open Blender > Scripting workspace > load this file > Run Script

Specifications:
- Collision bounds: 60×60×20 units
- Propeller positions: ±82, ±82 (XY), Z=10
- Material: Dark gray-blue (0.2, 0.2, 0.25)
- Target: 1.5k-2k triangles (high LOD)
"""

import bpy
import bmesh
import math
from mathutils import Vector, Euler

# === CLEAN UP ===
# Delete all mesh objects
for obj in bpy.data.objects:
    if obj.type in ('MESH', 'EMPTY'):
        bpy.data.objects.remove(obj, do_unlink=True)

# === MATERIALS ===
def create_drone_material():
    """Create dark gray-blue material for drone"""
    # Remove existing material if present
    if "DroneMaterial" in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials["DroneMaterial"])

    mat = bpy.data.materials.new(name="DroneMaterial")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    # Dark gray-blue: (0.2, 0.2, 0.25, 1.0)
    bsdf.inputs['Base Color'].default_value = (0.2, 0.2, 0.25, 1.0)
    bsdf.inputs['Metallic'].default_value = 0.3
    bsdf.inputs['Roughness'].default_value = 0.7
    return mat

# === GEOMETRY HELPERS ===
def create_box(name, size, location=(0, 0, 0)):
    """Create a simple box mesh"""
    # Create mesh
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)

    # Link to scene
    bpy.context.collection.objects.link(obj)

    # Create box geometry
    bm = bmesh.new()
    bm.verts.new((-size[0]/2, -size[1]/2, -size[2]/2))
    bm.verts.new((size[0]/2, -size[1]/2, -size[2]/2))
    bm.verts.new((size[0]/2, size[1]/2, -size[2]/2))
    bm.verts.new((-size[0]/2, size[1]/2, -size[2]/2))
    bm.verts.new((-size[0]/2, -size[1]/2, size[2]/2))
    bm.verts.new((size[0]/2, -size[1]/2, size[2]/2))
    bm.verts.new((size[0]/2, size[1]/2, size[2]/2))
    bm.verts.new((-size[0]/2, size[1]/2, size[2]/2))

    # Create faces
    verts = bm.verts[:]
    bm.faces.new([verts[0], verts[1], verts[2], verts[3]])
    bm.faces.new([verts[4], verts[7], verts[6], verts[5]])
    bm.faces.new([verts[0], verts[4], verts[5], verts[1]])
    bm.faces.new([verts[2], verts[6], verts[7], verts[3]])
    bm.faces.new([verts[0], verts[3], verts[7], verts[4]])
    bm.faces.new([verts[1], verts[5], verts[6], verts[2]])

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    return obj

def create_cylinder(name, radius, height, location=(0, 0, 0), vertices=8):
    """Create a cylinder"""
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()

    # Top and bottom circles
    top_verts = []
    bottom_verts = []

    for i in range(vertices):
        angle = (i / vertices) * 2 * math.pi
        x = radius * math.cos(angle)
        y = radius * math.sin(angle)

        top_verts.append(bm.verts.new((x, y, height/2)))
        bottom_verts.append(bm.verts.new((x, y, -height/2)))

    # Side faces
    for i in range(vertices):
        next_i = (i + 1) % vertices
        bm.faces.new([bottom_verts[i], bottom_verts[next_i], top_verts[next_i], top_verts[i]])

    # Top and bottom caps
    bm.faces.new(top_verts)
    bm.faces.new(list(reversed(bottom_verts)))

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    return obj

# === BUILD DRONE ===
def build_drone():
    """Construct the complete drone model"""

    print("Creating materials...")
    drone_mat = create_drone_material()

    # Create blade material
    blade_mat = bpy.data.materials.new(name="BladeMaterial")
    blade_mat.use_nodes = True
    bsdf = blade_mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs['Base Color'].default_value = (0.1, 0.1, 0.15, 1.0)
    bsdf.inputs['Metallic'].default_value = 0.5

    print("Creating main body...")

    # === MAIN BODY ===
    body = create_box("Body", (14, 14, 8), (0, 0, 0))
    body.data.materials.append(drone_mat)

    hub_top = create_box("HubTop", (7, 7, 2), (0, 0, 4.5))
    hub_top.data.materials.append(drone_mat)

    # === PROPELLER ARMS ===
    arm_positions = [
        (1, 1),      # Front-left
        (1, -1),     # Front-right
        (-1, 1),     # Back-left
        (-1, -1),    # Back-right
    ]

    print("Creating propeller arms...")
    arms = []
    for idx, (x_dir, y_dir) in enumerate(arm_positions):
        arm_name = f"Arm_{idx+1}"
        arm_length = 28
        arm_x = x_dir * arm_length * 0.5
        arm_y = y_dir * arm_length * 0.5

        arm = create_box(arm_name, (2, 28, 1.5), (arm_x, arm_y, 1))
        arm.data.materials.append(drone_mat)
        arms.append(arm)

    # === MOTORS ===
    print("Creating motors...")
    motors = []
    for idx, (x_dir, y_dir) in enumerate(arm_positions):
        motor_name = f"Motor_{idx+1}"
        motor_x = x_dir * 27.5
        motor_y = y_dir * 27.5
        motor_z = 1

        motor = create_cylinder(motor_name, 2, 3, (motor_x, motor_y, motor_z), vertices=8)
        motor.data.materials.append(drone_mat)
        motors.append(motor)

    # === PROPELLER BLADES ===
    print("Creating propeller blades...")
    propellers = []
    for idx, (x_dir, y_dir) in enumerate(arm_positions):
        prop_name = f"Propeller_{idx+1}"
        prop_x = x_dir * 27.5
        prop_y = y_dir * 27.5
        prop_z = 3

        prop = create_box(prop_name, (18, 3, 0.4), (prop_x, prop_y, prop_z))
        prop.data.materials.append(blade_mat)
        propellers.append(prop)

    # === CAMERA MOUNT ===
    print("Creating camera mount...")
    camera_mount = create_box("CameraMount", (2, 2, 2), (0, 0, 5))
    camera_mount.data.materials.append(drone_mat)

    # === CREATE ROOT EMPTY ===
    print("Organizing hierarchy...")
    root = bpy.data.objects.new("Drone", None)
    bpy.context.collection.objects.link(root)

    # Parent all components
    all_objects = [body, hub_top] + arms + motors + propellers + [camera_mount]
    for obj in all_objects:
        obj.parent = root

    return root, all_objects

# === MAIN EXECUTION ===
print("\n" + "="*60)
print("🚁 Building S&Box Drone Model...")
print("="*60)

drone_root, components = build_drone()
print(f"✓ Created drone with {len(components)} components")

print("\n✅ Drone model created successfully!")
print("\n" + "="*60)
print("NEXT STEPS:")
print("="*60)
print("1. Click on 'Drone' in the Outliner to select it")
print("2. Press 'S' then '0.3' then Enter to scale to 0.3")
print("3. Export as FBX:")
print("   - File > Export As > Assets/models/drone_high.fbx")
print("   - Format: FBX (.fbx)")
print("4. Create LOD versions:")
print("   - Select Drone > Shift+D (duplicate)")
print("   - Add Decimate modifier: ratio=0.5 (medium)")
print("   - Apply modifier > Export as drone_med.fbx")
print("   - Repeat with ratio=0.25 for drone_low.fbx")
print("\nDrone specifications:")
print("- Central body: 14×14×8 units")
print("- 4 propeller arms with motors and blades")
print("- Camera mount at (0, 0, 5)")
print("- Material: Dark gray-blue (0.2, 0.2, 0.25)")
print("="*60)
