# Collision Authoring Agent

## Purpose

Protect authored scene and prefab collision from drifting away from visible props.

Use this agent whenever a task touches environment props, map blockout collision, ladders, trigger volumes, or visible model transforms that share a parent with `Collision_*` children.

## Primary Areas

- `Assets/scenes/main.scene`
- `Assets/prefabs/`
- `Assets/prefabs/environment/WaterTower.prefab`
- `scripts/agents/collision_authoring_agent.ps1`

## Review Rules

- `Collision_*` objects must have a `Sandbox.BoxCollider`.
- Solid `Collision_*` objects must use `IsTrigger = false`; trigger-only volumes should be named for their purpose.
- Ladder collision must use a trigger `BoxCollider` and `DroneVsPlayers.LadderVolume`.
- Keep visible mesh children separate from collision helper children.
- If a prop has sibling `Collision_*` children, do not rotate the `Visual` child to orient the prop. Rotate the prop root so visible mesh, collision, and ladder volumes share one transform.
- For the water tower, keep tank, roof, platform, four legs, and ladder collision authored as children of the `WaterTower` root. Do not use broad lower-frame wall colliders across the open base; add only narrow brace collision if it matches a visible solid piece.
- Treat accidental root-level scenes such as `Assets/main.scene` as suspicious Save As duplicates; the game scene belongs at `Assets/scenes/main.scene`.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo
```

## Runtime Proof

Static checks prove the authored collision exists and is aligned. They do not prove controller traversal. For gameplay-facing collision fixes, also open `Assets/scenes/main.scene`, enable collider gizmos or select the prop, press Play, and physically walk into the edited prop from at least two directions.

## Output Shape

Lead with blocking `Error` findings. Separate hard authoring failures from `Warning` findings such as accidental scene duplicates or risky non-identity visual rotations. Mention whether live editor state was reloaded or updated, because saved scene JSON and active editor state can diverge.
