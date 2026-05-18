# Collision Chain Agent

## Purpose

Coordinate Codex subagents for collision-heavy work so authored props are explored, edited, verified, and critiqued by separate roles before handoff.

Use this chain when a task touches environment collision, `Collision_*` helpers, ladders, trigger volumes, tree or prop blockers, water-tower changes, or a user reports invisible collision.

## Role Stack

Default flow: Coordinator -> Explorer -> Implementer -> Verifier -> Critic. The critic can return focused rework to the implementer, and the verifier reruns evidence before the critic sees the work again.

### Coordinator

The main Codex agent owns user intent, scope, dirty-worktree safety, and final integration. It decides which child agent gets work, passes only the context that role needs, and keeps the user-facing plan current.

The coordinator does not delegate the immediate blocking action if it can do it faster locally. It uses subagents for sidecar exploration, bounded implementation, verifier passes, and critique.

### Explorer

Use `collision-explorer-agent.md` for read-only discovery. The explorer maps scene and prefab structure, compares visible assets against collision helpers, finds old failure patterns, and returns a collision contract. It does not edit files.

### Implementer

Use `collision-implementer-agent.md` for scoped edits. The implementer receives owned files, exact desired behavior, known dirty files, and verification commands. It must not revert unrelated work and must list every changed file.

### Verifier

Use `collision-verifier-agent.md` after edits. The verifier runs the collision suite, related scene checks, focused build checks when C# or editor-facing logic changed, and live-editor checks when available. It reports evidence, stale-log limits, and remaining runtime gaps.

### Critic

Use `collision-critic-agent.md` as the last pass before handoff or when verifier evidence is weak. The critic reviews the explorer contract, implementation diff, and verifier output. It leads with defects and either returns `PASS`, `REWORK`, `BLOCKED`, or `OUT_OF_SCOPE`.

## Handoff Protocol

Every down-chain handoff should include:

- `Goal`: the user-visible behavior being fixed.
- `Scope`: allowed files, assets, and systems.
- `Do Not Touch`: unrelated dirty files and systems.
- `Current Evidence`: commands already run and what they proved.
- `Known Risks`: editor drift, stale logs, broad colliders, trigger-vs-solid mistakes, or untested runtime traversal.
- `Expected Output`: findings, changed files, evidence, or critique status.

Every up-chain response should include:

- `Status`: `PASS`, `REWORK`, `BLOCKED`, or `OUT_OF_SCOPE`.
- `Findings`: concrete file paths, object names, and line references where possible.
- `Evidence`: exact commands and results.
- `Next Handoff`: which role should receive the next packet.

## Rework Loop

The critic or verifier can pass work back down by returning `REWORK` with a focused defect. The coordinator then sends that defect to the implementer with the same file ownership rules. After the implementer responds, the verifier reruns only the relevant evidence first, then broadens if the fix touched shared behavior.

Do not run an endless loop. If the same failure survives two implementer passes, mark `BLOCKED` and summarize the root uncertainty for the user.

## Collision Acceptance Rules

- `Collision_*` helpers must have `Sandbox.BoxCollider`.
- Solid collision helpers must be non-trigger and static unless deliberately dynamic.
- Trigger-only volumes should be named for their purpose and should not double as physical blockers.
- Ladder volumes must use a trigger `BoxCollider` plus `DroneVsPlayers.LadderVolume`.
- Visible mesh children and collision helper children should share the same prop root transform.
- If a prop has sibling collision helpers, keep the `Visual` child identity-aligned and rotate or move the prop root instead.
- For the water tower, keep tank, roof, platform, four legs, and ladder collision. Do not use broad lower-frame `Collision_Frame_*` wall boxes across the open base.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_chain_report.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite scene -ShowInfo
dotnet build Code\dronevsplayers.csproj --no-restore
powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh -ShowInfo
```

Use live editor hierarchy or collider-gizmo checks for gameplay-facing collision when the editor is available. Static JSON checks do not prove controller traversal.
