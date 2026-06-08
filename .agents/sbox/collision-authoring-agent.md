# Collision Authoring Agent

## Purpose

Keep authored collision matching the visible geometry, and keep the project on the
**mesh-collision methodology** (see `docs/collision_authoring.md`). Use this agent
whenever a task touches environment props, buildings, ladders, trigger volumes, or
model collision.

## The methodology (default for any model that needs collision)

1. **Model:** the `.vmdl` gets exact mesh collision via a `PhysicsMeshFile` node.
   The asset pipeline writes it from a `collision` block in
   `scripts/<name>_asset_pipeline.json` (`"mode": "render_mesh"` for solid,
   non-deforming props; `"collision_mesh"` + a generated FBX to make a part
   hollow; `"primitives"` only when the brief documents the exception and the
   dimensions come from exported source-unit mesh bounds). **`PhysicsMeshFile` MUST sit inside
   `PhysicsShapeList`** or the compiler silently drops it (zero collision).
2. **Prefab/scene:** a single `ModelCollider` (`Model` = the `.vmdl`,
   `Static = true`) on the **same GameObject as the `ModelRenderer`** (the `Visual`
   child). This rides the exact visual transform, so it stays aligned under
   non-uniform instance scale + rotation.

Place solid props through the prefab, not by dragging the raw `.vmdl`; raw model
placement can create a dynamic Prop that falls on play.

Do **not** reintroduce per-part `Collision_*` body boxes (tank/roof/legs/etc.) —
the `ModelCollider` replaces them. Trigger volumes (ladders, zones) remain separate
children. The water tower / `WaterTower.prefab` is the reference example; evaluate
building root collision coverage before judging a selected visual child in isolation.

## Primary Areas

- `Assets/scenes/main.scene`, `Assets/prefabs/`
- `Assets/prefabs/environment/WaterTower.prefab` (reference example)
- `Assets/models/*.vmdl` + `scripts/*_asset_pipeline.json` (`collision` block)
- `scripts/asset_pipeline.py`, `scripts/export_collision_mesh.py`
- `scripts/agents/collision_authoring_agent.ps1`

## Review Rules

- A model that needs collision should have a `ModelCollider` on its renderer object,
  backed by a `.vmdl` whose `PhysicsShapeList` contains a `PhysicsMeshFile` (or, for
  legacy/simple cases, primitives). Flag models rendered with no collider coverage.
- For solid props, fail primitive or legacy `physics_shapes` collision unless the
  exception reason is documented and `model_collision_scale_audit.ps1` proves the
  primitive bounds match the render bounds.
- If a `.vmdl` has a `PhysicsMeshFile`/`PhysicsHullFile`, it must be nested inside a
  `PhysicsShapeList`. A file-physics node directly under `RootNode` is a silent-fail
  bug — flag it.
- A pipeline config that uses `"collision": {"mode": "render_mesh"|"collision_mesh"}`
  should NOT also set `skip_vmdl` (let the pipeline own the physics node).
- Ladder collision: a trigger `BoxCollider` + `DroneVsPlayers.LadderVolume`, sized
  over the ladder. The ladder mesh itself may be solid (climb against it) or hollow
  (excluded via `collision_mesh`); both are valid — don't require either.
- Trigger-only volumes use `IsTrigger = true`; solid helpers use `IsTrigger = false`
  and should be `Static`.
- Don't rotate a `Visual` child to orient a prop that has sibling trigger volumes;
  rotate the prop root so mesh, collision, and triggers share one transform.
- Treat an accidental `Assets/main.scene` (vs `Assets/scenes/main.scene`) as a
  suspicious Save-As duplicate.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/model_collision_scale_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo
```

## Runtime Proof

Static checks prove the authored collision exists and is wired; they do not prove
traversal. For gameplay-facing collision, open `Assets/scenes/main.scene`, select
the prop (the `ModelCollider` gizmo traces the mesh) or enable collider gizmos,
press Play, and walk into the prop from at least two directions. Climb any ladder.
Verify `ModelCollider.LocalBounds` is non-zero and approximately matches
`ModelRenderer.LocalBounds` via the MCP (`component_get`). If the bounds differ by
more than the audit tolerance or the prop falls when play starts, the asset is not
done even if export/modeldoc audits pass.

## Output Shape

Lead with blocking `Error` findings (missing collider coverage, `PhysicsMeshFile`
outside `PhysicsShapeList`, `skip_vmdl` fighting a `collision` block). Separate hard
failures from `Warning`s (Save-As duplicates, non-identity visual rotations). Note
whether live editor state was reloaded, since saved JSON and active editor state can
diverge (use "External Changes Detected → Reload").
