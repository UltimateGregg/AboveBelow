import bpy
from mathutils import Vector
import math

# Clear the scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Create materials
mat_body = bpy.data.materials.new(name="Grenade_Body")
mat_body.use_nodes = True
bsdf = mat_body.node_tree.nodes["Principled BSDF"]
bsdf.inputs['Base Color'].default_value = (0.2, 0.22, 0.13, 1.0)  # Dark olive green
bsdf.inputs['Roughness'].default_value = 0.8
bsdf.inputs['Metallic'].default_value = 0.0

mat_handle = bpy.data.materials.new(name="Grenade_Handle")
mat_handle.use_nodes = True
bsdf = mat_handle.node_tree.nodes["Principled BSDF"]
bsdf.inputs['Base Color'].default_value = (0.7, 0.7, 0.7, 1.0)  # Silver
bsdf.inputs['Roughness'].default_value = 0.3
bsdf.inputs['Metallic'].default_value = 0.9

mat_pin = bpy.data.materials.new(name="Grenade_Pin")
mat_pin.use_nodes = True
bsdf = mat_pin.node_tree.nodes["Principled BSDF"]
bsdf.inputs['Base Color'].default_value = (0.5, 0.5, 0.5, 1.0)  # Gray metal
bsdf.inputs['Roughness'].default_value = 0.4
bsdf.inputs['Metallic'].default_value = 0.85

# Create a parent empty
parent = bpy.data.objects.new("Frag_Grenade", None)
bpy.context.collection.objects.link(parent)

# Create the main body as a UV sphere
bpy.ops.mesh.primitive_uv_sphere_add(radius=1.2, location=(0, 0, 1.2))
body = bpy.context.active_object
body.name = "Body"
body.parent = parent
body.data.materials.append(mat_body)

# Scale it to be slightly egg-shaped (taller than wide)
body.scale = (0.95, 0.95, 1.1)

# Create horizontal groove rings (the cast ribs of M67)
groove_positions = [0.6, 1.2, 1.8]
for i, z_pos in enumerate(groove_positions):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=1.3,
        depth=0.15,
        location=(0, 0, z_pos)
    )
    groove = bpy.context.active_object
    groove.name = f"Groove_{i}"
    groove.parent = parent
    groove.data.materials.append(mat_body)
    groove.scale = (1.0, 1.0, 0.5)

# Create neck (transition to fuze)
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.55,
    depth=0.2,
    location=(0, 0, 2.46)
)
neck = bpy.context.active_object
neck.name = "Neck"
neck.parent = parent
neck.data.materials.append(mat_body)

# Create fuze assembly
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.45,
    location=(0, 0, 2.75)
)
fuze = bpy.context.active_object
fuze.name = "Fuze"
fuze.parent = parent
fuze.scale = (0.95, 0.95, 0.5)
fuze.data.materials.append(mat_body)

# Create safety lever/handle - silver colored
# Top part of lever
bpy.ops.mesh.primitive_cube_add(
    size=1,
    location=(0.85, 0, 3.0)
)
lever_top = bpy.context.active_object
lever_top.name = "Lever_Top"
lever_top.parent = parent
lever_top.scale = (0.4, 0.15, 0.04)
lever_top.data.materials.append(mat_handle)

# Side/vertical part of lever
bpy.ops.mesh.primitive_cube_add(
    size=1,
    location=(1.25, 0, 2.7)
)
lever_side = bpy.context.active_object
lever_side.name = "Lever_Side"
lever_side.parent = parent
lever_side.scale = (0.18, 0.15, 0.45)
lever_side.data.materials.append(mat_handle)

# Create safety pin (thin cylindrical rod)
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.048,
    depth=0.55,
    location=(-0.1575, 0, 2.925)
)
pin = bpy.context.active_object
pin.name = "Pin"
pin.parent = parent
pin.rotation_euler = (math.radians(90), 0, 0)
pin.data.materials.append(mat_pin)

# Create pin ring (circular part)
bpy.ops.mesh.primitive_torus_add(
    major_radius=0.26,
    minor_radius=0.04,
    location=(-0.1575, 0, 3.24)
)
pin_ring = bpy.context.active_object
pin_ring.name = "PinRing"
pin_ring.parent = parent
pin_ring.rotation_euler = (math.radians(90), 0, 0)
pin_ring.data.materials.append(mat_pin)

# Save the file
bpy.ops.wm.save_as_mainfile(filepath="weapons_model.blend/frag_grenade.blend")
