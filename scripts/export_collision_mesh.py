"""Export a collision-only FBX for an S&Box model, aligned 1:1 with its render mesh.

Most props should NOT need this -- set `"collision": {"mode": "render_mesh"}` in the
asset pipeline config and the whole render mesh becomes solid collision. Use THIS
tool only when some part of the model must be HOLLOW (e.g. a climb-through ladder,
a decorative antenna, foliage), then point the pipeline at the result:

    "collision": { "mode": "collision_mesh",
                   "filename": "models/watertower_collision.fbx",
                   "surface_prop": "metal" }

It reproduces the asset pipeline's combine+export EXACTLY (bake each mesh's
world transform into a copy, join, export with the same global_scale / axis), so
the collision FBX lines up perfectly with the render FBX in model space. Objects
whose name starts with any --exclude-prefix are dropped from the collision mesh.

Usage (the script re-launches Blender for you):

    python scripts/export_collision_mesh.py <blend> <output_fbx> [options]

    <blend>        Source .blend (relative to project root or absolute),
                   e.g. environment_model.blend/watertower.blend
    <output_fbx>   Target FBX (relative to project root or absolute),
                   e.g. Assets/models/watertower_collision.fbx

Options:
    --exclude-prefix PREFIX   Drop objects whose name starts with PREFIX
                              (repeatable). e.g. --exclude-prefix Ladder_
    --config PATH             Read global_scale/axis_forward/axis_up from a
                              matching *_asset_pipeline.json (recommended -- keeps
                              the collision export in lock-step with the render
                              export). Defaults are the project standard below.
    --global-scale FLOAT      Default 0.0254
    --axis-forward AXIS       Default -Y
    --axis-up AXIS            Default Z
    --blender-exe PATH        Override the Blender executable.

Example (water tower, ladder hollow):
    python scripts/export_collision_mesh.py \
        environment_model.blend/watertower.blend \
        Assets/models/watertower_collision.fbx --exclude-prefix Ladder_
"""

import sys

try:
    import bpy  # noqa: F401
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False


DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"


# --------------------------------------------------------------------------- #
# Inside Blender: do the actual export.
# --------------------------------------------------------------------------- #
def run_in_blender(argv):
    import json
    from pathlib import Path

    import bpy
    from mathutils import Vector

    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("output_fbx")
    p.add_argument("--exclude-prefix", action="append", default=[])
    p.add_argument("--config", default=None)
    p.add_argument("--global-scale", type=float, default=0.0254)
    p.add_argument("--axis-forward", default="-Y")
    p.add_argument("--axis-up", default="Z")
    args = p.parse_args(argv)

    global_scale = args.global_scale
    axis_forward = args.axis_forward
    axis_up = args.axis_up
    if args.config:
        cfg = json.loads(Path(args.config).read_text(encoding="utf-8"))
        global_scale = float(cfg.get("global_scale", global_scale))
        axis_forward = cfg.get("axis_forward", axis_forward)
        axis_up = cfg.get("axis_up", axis_up)

    target = Path(args.output_fbx)
    target.parent.mkdir(parents=True, exist_ok=True)
    prefixes = tuple(args.exclude_prefix)

    def excluded(name):
        return bool(prefixes) and name.startswith(prefixes)

    sources = [o for o in bpy.context.scene.objects if o.type == "MESH" and not excluded(o.name)]
    dropped = sorted(o.name for o in bpy.context.scene.objects if o.type == "MESH" and excluded(o.name))
    if not sources:
        raise RuntimeError("No mesh objects left after exclusions -- check --exclude-prefix.")

    # Replicate asset_pipeline.py combine: bake world transform into copies, then join.
    combined = []
    for obj in sources:
        mesh = obj.data.copy()
        mesh.transform(obj.matrix_world)
        mesh.update()
        cp = bpy.data.objects.new(obj.name + "_Col", mesh)
        bpy.context.scene.collection.objects.link(cp)
        cp.location = (0.0, 0.0, 0.0)
        cp.rotation_euler = (0.0, 0.0, 0.0)
        cp.scale = (1.0, 1.0, 1.0)
        combined.append(cp)

    for o in bpy.data.objects:
        o.select_set(False)
    for o in combined:
        o.select_set(True)
    bpy.context.view_layer.objects.active = combined[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = target.stem
    joined.data.name = target.stem + "_mesh"

    corners = [joined.matrix_world @ Vector(c) for c in joined.bound_box]
    xs = [c.x for c in corners]; ys = [c.y for c in corners]; zs = [c.z for c in corners]

    for o in bpy.data.objects:
        o.select_set(False)
    joined.select_set(True)
    bpy.context.view_layer.objects.active = joined

    bpy.ops.export_scene.fbx(
        filepath=str(target),
        use_selection=True,
        object_types={"MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_space_transform=False,
        apply_unit_scale=True,
        global_scale=global_scale,
        axis_forward=axis_forward,
        axis_up=axis_up,
        path_mode="AUTO",
    )

    print("COLLISION_MESH_EXPORT_BEGIN")
    print("excluded_objects:", len(dropped), dropped[:10], "..." if len(dropped) > 10 else "")
    print("kept_mesh_objects:", len(sources))
    print("tris:", len(joined.data.polygons))
    print("bbox_min_blender: %.3f %.3f %.3f" % (min(xs), min(ys), min(zs)))
    print("bbox_max_blender: %.3f %.3f %.3f" % (max(xs), max(ys), max(zs)))
    print("exported_to:", str(target))
    print("bytes:", target.stat().st_size if target.exists() else 0)
    print("COLLISION_MESH_EXPORT_END")


# --------------------------------------------------------------------------- #
# Outside Blender: parse args, locate the .blend, re-launch Blender headless.
# --------------------------------------------------------------------------- #
def run_cli(argv):
    import argparse
    import os
    import subprocess
    from pathlib import Path

    p = argparse.ArgumentParser(description="Export a collision-only FBX aligned with a render mesh.")
    p.add_argument("blend")
    p.add_argument("output_fbx")
    p.add_argument("--exclude-prefix", action="append", default=[])
    p.add_argument("--config", default=None)
    p.add_argument("--global-scale", type=float, default=0.0254)
    p.add_argument("--axis-forward", default="-Y")
    p.add_argument("--axis-up", default="Z")
    p.add_argument("--blender-exe", default=os.environ.get("BLENDER_EXE", DEFAULT_BLENDER))
    args = p.parse_args(argv)

    root = Path(__file__).resolve().parent.parent
    blend = Path(args.blend)
    if not blend.is_absolute():
        blend = (root / args.blend).resolve()
    if not blend.exists():
        raise SystemExit(f"Blend file not found: {blend}")

    out = Path(args.output_fbx)
    if not out.is_absolute():
        out = (root / args.output_fbx).resolve()

    inner = [str(out)]
    for pre in args.exclude_prefix:
        inner += ["--exclude-prefix", pre]
    if args.config:
        cfg = Path(args.config)
        if not cfg.is_absolute():
            cfg = (root / args.config).resolve()
        inner += ["--config", str(cfg)]
    # Use '=' so axis values that start with '-' (e.g. -Y) aren't parsed as flags.
    inner += ["--global-scale=" + str(args.global_scale),
              "--axis-forward=" + args.axis_forward,
              "--axis-up=" + args.axis_up]

    cmd = [args.blender_exe, "--background", str(blend), "--python", str(Path(__file__).resolve()), "--"] + inner
    print("Running:", " ".join(f'"{c}"' if " " in c else c for c in cmd))
    rc = subprocess.call(cmd)
    raise SystemExit(rc)


if __name__ == "__main__":
    if IN_BLENDER:
        # Blender passes script args after a literal "--".
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        run_in_blender(argv)
    else:
        run_cli(sys.argv[1:])
