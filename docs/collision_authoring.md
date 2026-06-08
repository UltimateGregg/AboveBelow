# Collision Authoring (mesh-based)

How to give any S&Box model **exact, 1:1 collision that matches the visible
geometry** — and have it survive re-exports and non-uniform instance scaling.

This is the methodology that fixed the water tower after several failed attempts
with hand-placed primitive colliders. Use it as the default for props, buildings,
and any model where the collision should match what the player sees.

> TL;DR — Two parts. **Model:** the `.vmdl` gets a `PhysicsMeshFile` node (the
> pipeline writes it from a `collision` config block). **Prefab:** a
> `ModelCollider` on the same GameObject as the `ModelRenderer`. That's it.

---

## Why the old approach failed

Hand-placed `BoxCollider`/`CapsuleCollider` children under a prop root drift out
of alignment because:

1. **They're authored in the wrong space.** The visible mesh is usually under a
   scaled `Visual` child; the colliders are siblings at a different scale, so they
   land at a fraction (or multiple) of the right size/position.
2. **Instance transforms distort them.** A scene instance often has a non-uniform
   scale and a rotation. Primitives (sphere/capsule especially) can't represent
   that cleanly, and a box under non-uniform-scale + rotation shears.
3. **They're approximate.** A real prop (legs, bracing, a railing, a ladder) needs
   dozens of primitives to hug — nobody tunes them perfectly by hand.

## Why mesh + ModelCollider wins

- A **`ModelCollider` on the same object as the `ModelRenderer`** transforms with
  the *exact same matrix as the visual mesh*. Whatever the instance does
  (non-uniform scale, yaw, parenting), collision follows. Alignment is automatic
  and permanent.
- A **`PhysicsMeshFile`** is the actual triangle mesh — every leg, strut, rung,
  and railing is solid, with zero per-part tuning.

---

## Part 1 — Model: bake mesh collision into the `.vmdl`

The asset pipeline writes the physics node for you. Add a `collision` block to the
asset's `scripts/<name>_asset_pipeline.json`:

```json
"collision": {
  "mode": "render_mesh",
  "surface_prop": "metal",
  "collision_tags": "solid"
}
```

`mode` options:

| mode             | meaning                                                                 | when |
|------------------|-------------------------------------------------------------------------|------|
| `render_mesh`    | collision = the model's own render FBX (everything solid)               | **default**, almost everything |
| `collision_mesh` | collision = a separate FBX (set `"filename"`) — to make a part *hollow* | climb-through ladders, antennas, foliage |
| `primitives`     | hand-authored `PhysicsShape*` boxes/capsules/cylinders (`"shapes"` here)| documented exceptions only; dimensions must come from exported source-unit mesh bounds |
| `none`           | no baked collision                                                       | pure decoration |

On the next `.blend` save (or `python scripts/asset_pipeline.py --config
scripts/<name>_asset_pipeline.json`) the pipeline regenerates the `.vmdl` with:

```kv3
{
    _class = "PhysicsShapeList"
    children =
    [
        {
            _class = "PhysicsMeshFile"
            name = "collision"
            surface_prop = "metal"
            collision_tags = "solid"
            filename = "models/<name>.fbx"
            import_scale = 1.0
        },
    ]
}
```

### ⚠️ The gotcha that eats hours

`PhysicsMeshFile` (and `PhysicsHullFile`) **MUST be a child of `PhysicsShapeList`**.
Placed directly under `RootNode` the model compiler **silently ignores it** — no
error, no warning, just zero collision. The pipeline always nests it correctly;
if the generated `.vmdl` differs, fix the asset-pipeline config and re-export.

## Part 2 — Prefab/scene: ModelCollider on the Visual

The model having physics shapes does nothing until something references them. Put
a `ModelCollider` on the **same GameObject as the `ModelRenderer`** (the `Visual`
child):

```json
{
  "__type": "Sandbox.ModelCollider",
  "Model": "models/<name>.vmdl",
  "IsTrigger": false,
  "Static": true
}
```

Do **not** add `Collision_*` box children for the body. The single `ModelCollider`
replaces all of them and stays aligned forever.

Place solid props through their prefab, not by dragging the raw `.vmdl` into the
scene. Raw model placement can create a dynamic Prop that falls on play; the
prefab owns the static `ModelCollider` contract.

---

## Hollow parts (e.g. a climb-through ladder)

A climbable ladder is driven by a `LadderVolume` trigger that pulls the player to
the climb-box centre, so the ladder can be either:

- **Solid** (default): include it in `render_mesh`. The player climbs *against* the
  rails. This is what the water tower uses.
- **Hollow**: exclude it from collision so nothing can block the climb. Generate a
  collision FBX that drops the ladder objects, and point the pipeline at it:

```powershell
python scripts/export_collision_mesh.py `
    environment_model.blend/watertower.blend `
    Assets/models/watertower_collision.fbx `
    --exclude-prefix Ladder_ --config scripts/watertower_asset_pipeline.json
```

```json
"collision": {
  "mode": "collision_mesh",
  "filename": "models/watertower_collision.fbx",
  "surface_prop": "metal"
}
```

`export_collision_mesh.py` reproduces the pipeline's combine+export exactly
(`--config` keeps `global_scale`/axis in lock-step), so the collision mesh aligns
1:1 with the render mesh. It drops every object whose name starts with any
`--exclude-prefix`.

The **ladder trigger** itself stays a separate child: a trigger `BoxCollider` +
`DroneVsPlayers.LadderVolume`, sized over the ladder. See `WaterTower.prefab`'s
`Collision_Ladder`.

---

## Verify (always)

1. **Bounds non-zero.** After recompile, read the collider via MCP:
   `component_get { type: "ModelCollider" }` → `LocalBounds` must NOT be
   `mins 0,0,0 maxs 0,0,0`. Zero bounds = the physics node was ignored (see the
   gotcha) or the mesh wasn't found.
2. **Bounds match the renderer.** Compare `ModelCollider.LocalBounds` with the
   paired `ModelRenderer.LocalBounds`; for generated assets, run
   `scripts/agents/model_collision_scale_audit.ps1 -ShowInfo`. Any axis off by
   more than tolerance means the collider was authored in the wrong coordinate
   space.
3. **Gizmo.** Select the `Visual` object in the editor — the `ModelCollider` draws
   its mesh; it should trace the model. Turn on the `SelectedHierarchyColliderViewer`
   (`AlwaysDraw = true`) to also see trigger volumes.
4. **Playtest.** Static checks don't prove runtime behavior. Place the prefab in
   `main.scene` or a throwaway scene, press Play, confirm it renders, stays put,
   and blocks/traverses correctly. For ladders, climb it.

## Durability

Driving the physics node from the `collision` config means a `.blend` re-save
regenerates correct collision automatically — no `skip_vmdl`, no ad hoc ModelDoc
text edits to clobber. The `WaterTower` asset is the reference example.

## Coordinate calibration (this project)

For sizing the few things still authored by hand (trigger volumes, `TopExit`):

- model units = blender units × **2.54** (with `global_scale 0.0254`)
- root/prefab units = model units × the `Visual` child's scale (×**45** for the tower)
- the FBX export swaps blender **X↔Y** in model space (axis_forward `-Y`)

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `LocalBounds` is `0,0,0` | `PhysicsMeshFile` not inside `PhysicsShapeList`, or the FBX path is wrong. |
| Collision drifts from the visual | Colliders aren't on the `ModelRenderer` object. Use a `ModelCollider` on the `Visual`, not sibling boxes. |
| Player clips through a part | That part is excluded from the collision mesh — switch to `render_mesh`, or remove it from `--exclude-prefix`. |
| Player gets stuck on a hollow climbable | Keep the climbable in the collision mesh hollow (`collision_mesh` + exclude), let the `LadderVolume` drive movement. |
| Editing the `.vmdl`/`.prefab` on disk doesn't update the open scene | Editor caches prefab instances; `scene_open`/`scene_load` are no-ops on the already-open scene. Edit the file → the editor pops **"External Changes Detected" → Reload**. |
| MCP `sbox` tools disconnected | Hit the editor MCP over HTTP: JSON-RPC POST to `http://localhost:29015/mcp`. `component_set` takes the **GameObject id** + type; `scene_set_transform` position is **world** space. |

## New-object checklist

1. Model in Blender; save → the pipeline exports the FBX + `.vmdl`.
2. Add a `collision` block (`render_mesh` unless a part must be hollow).
3. In the prefab, put a `ModelCollider` (`Model` = the `.vmdl`, `Static = true`) on
   the `Visual` (the `ModelRenderer` object). Remove any old `Collision_*` body
   boxes.
4. Add trigger volumes (ladders, zones) as separate children.
5. Place via the prefab, never the raw `.vmdl`.
6. Verify: collider bounds match renderer bounds, gizmo traces the model, playtest
   from two directions, and the prop stays put.
