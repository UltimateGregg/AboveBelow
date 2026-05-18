# S&Box Agent Toolkit

This project has a lightweight agent toolkit for Codex-facing workflows and repo-side validation scripts. The agents live under `.agents/sbox/`; the scripts live under `scripts/agents/`.

## Quick Start

Run the default pre-handoff suite:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

Run every report:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite full
```

## Agents

| Agent | Purpose | Script |
|---|---|---|
| Build and Log Sentinel | Compile and check fresh logs | `scripts/agents/build_log_sentinel.ps1` |
| Gameplay Systems Agent | Review gameplay architecture fit | Uses build and networking audits |
| Gameplay Regression Guard | Run focused slot and drone-control regression checks | `scripts/agents/gameplay_regression_guard.ps1` |
| Prefab and Wiring Agent | Validate prefab shape and AutoWire references | `scripts/agents/prefab_wiring_audit.ps1` |
| Prefab Graph Audit | Validate GUID refs, component refs, prefab refs, and resource paths | `scripts/agents/prefab_graph_audit.ps1` |
| Scene Integrity Audit | Validate main scene managers, spawns, and collider patterns | `scripts/agents/scene_integrity_audit.ps1` |
| Collision Authoring Agent | Validate `Collision_*`, ladder triggers, visual/collider alignment, and water-tower collision coverage | `scripts/agents/collision_authoring_agent.ps1` |
| Collision Agent Chain | Coordinate Codex explorer, implementer, verifier, and critic roles for collision-heavy work | `scripts/agents/collision_chain_report.ps1` |
| Collision Explorer Agent | Read-only collision discovery before edits | `.agents/sbox/collision-explorer-agent.md` |
| Collision Implementer Agent | Scoped collision edits after a contract is defined | `.agents/sbox/collision-implementer-agent.md` |
| Collision Verifier Agent | Evidence collection and runtime-gap reporting | `.agents/sbox/collision-verifier-agent.md` |
| Collision Critic Agent | Findings-first critique and rework routing | `.agents/sbox/collision-critic-agent.md` |
| Asset Pipeline Agent | Validate `.blend` configs, targets, and material remaps | `scripts/agents/asset_pipeline_audit.ps1` |
| ModelDoc Agent | Validate `.vmdl` source meshes, material targets, and config drift | `scripts/agents/modeldoc_audit.ps1` |
| Sound Control Plane Agent | Validate SoundEvent wrappers, attached playback, and editor-native sound workflows | `scripts/agents/run_agent_checks.ps1 -Suite sound` |
| Team Label Copy Audit | Keep player-facing role labels on Drone Pilots and Soldiers while preserving the project title | `scripts/agents/team_label_copy_audit.ps1` |
| UI Flow Agent | Catch interactive-looking Razor UI without click behavior | `scripts/agents/ui_flow_audit.ps1` |
| Networking Review Agent | Surface authority and replication risks | `scripts/agents/networking_review_audit.ps1` |
| Playtest QA Agent | Generate editor and multiplayer checklists | `scripts/agents/playtest_checklist.ps1` |
| Docs and Roadmap Agent | Check doc presence and drift | `scripts/agents/docs_roadmap_audit.ps1` |
| Balance and Tuning Agent | Snapshot balance-related values | `scripts/agents/balance_tuning_report.ps1` |
| Current Log Audit | Search project and local app log locations for fresh runtime/editor logs | `scripts/agents/current_log_audit.ps1` |
| Feature Readiness Report | Map changed files to required checks and manual test focus | `scripts/agents/feature_readiness_report.ps1` |
| Post-Task Training Agent | Inspect recent work and route durable hook, agent, pipeline, and docs improvements | `scripts/agents/post_task_training_agent.ps1` |
| Pre-Handoff Agent | Orchestrate final checks | `scripts/agents/run_agent_checks.ps1` |

## Script Behavior

- Scripts print findings as `Error`, `Warning`, or `Info`.
- Errors return exit code `1`.
- Warnings return exit code `0` unless `-FailOnWarning` is supplied.
- Static-analysis warnings are prompts for manual inspection, not automatic proof of a bug.
- The build sentinel writes build output to `.tmpbuild/agent-build.log`.
- The prefab wiring audit checks that code-driven child objects, such as drone propellers, are present in the prefab hierarchy the component scans.
- The networking audit enforces that `HitscanWeapon.RequestFire` stays a `[Rpc.Host]` intent request so the host owns ammo, cooldown, trace, and damage resolution.
- Full automation is still static unless paired with an editor playtest. Use `current_log_audit.ps1 -RequireFresh` after the playtest to verify current runtime logs.

## Recommended Usage By Change Type

Gameplay or C# changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

Drone input, pilot control, or drone HUD loadout changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Gameplay
```

The `drone-control-regression-check` Claude hook runs the same guard when `DroneWeapon`, `DroneDeployer`, `RemoteController`, `PilotSoldier`, the drone HUD, or FPV/pilot prefabs change.

Prefab or scene changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -ShowInfo
```

For prop collision specifically, also run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_chain_report.ps1 -ShowInfo
```

The collision agent catches the failure mode where a visible `Visual` child is rotated while sibling `Collision_*` children stay on the old parent transform. Rotate the prop root instead, then verify in the editor with collider gizmos and a short walk-into-the-prop playtest.

For larger collision work, start with `.agents/sbox/collision-chain-agent.md`. The chain splits Codex work into explorer, implementer, verifier, and critic handoffs so a second pass can challenge broad invisible blockers, stale editor state, and weak evidence before final handoff. The report script runs the static evidence stack and writes `.tmpbuild/collision-chain-report.md` as the handoff packet for the next Codex role.

Blender or asset pipeline changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend
python scripts/texture_contact_sheet.py --config scripts/terrain_assets_asset_pipeline.json --out screenshots/asset_previews/terrain_assets_texture_sheet.png
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

Use the texture contact sheet for alpha-cutout assets such as tree foliage cards before accepting a Blender render. The Blender preview confirms shape; the contact sheet and S&Box editor screenshot confirm the material and transparent background behavior.

ModelDoc or VMDL changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
```

The ModelDoc audit checks source mesh references, material remap targets, config-to-VMDL drift, and strict material source naming rules. It does not replace Blender visual review, prefab wiring checks, or an editor playtest.

Blender visible MCP or add-on changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite blender-live
python -m py_compile blender_addons/sbox_asset_toolkit/__init__.py scripts/start_visible_blender_asset_toolkit.py
node .\mcp\node_modules\typescript\bin\tsc -p .\mcp\tsconfig.json
```

The `S&Box Asset Toolkit` Blender add-on is the visible control surface for live
Blender work. It can start the bridge inside the open Blender window, scaffold
production roots/sockets/materials, create briefs, render previews, export to
S&Box, and run the asset-production suite. The MCP side exposes the same visible
workflow through tools such as `blender_sbox_setup_asset_scene`,
`blender_sbox_add_socket`, and `blender_sbox_export_current_asset`.

Native S&Box editor control-plane or sound changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sound -ShowInfo
python scripts/audio/generate_project_sounds.py --root .
dotnet build Libraries\jtc.mcp-server\Editor\mcp-server.editor.csproj --no-restore
```

The native editor MCP server at `http://localhost:29015/mcp` is the primary
control plane for scene, component, asset, docs, screenshot, play/stop, and
sound workflows. Use `control_plane_status` first, then sound tools such as
`sound_list`, `sound_inspect`, `sound_preview`, `sound_find_hooks`, and
`sound_place_point` when wiring audio in the visible editor. Search stock/editor
audio before generating local WAV fallbacks, but keep committed gameplay
references pointed at local `Assets/sounds/*.sound` wrappers. Use the
deterministic script above so known stock WAVs are imported first and generated
fallbacks stay layered, filtered, and repeatable. Held-item sounds such as gun
fire, reloads, dry-fire clicks, jammer loops, and throw cues should route through
`SoundPlayback.PlayAttached` so their handles follow the weapon or player object
instead of remaining at an old world position.

Balance changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Balance
```

UI or startup-flow changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/team_label_copy_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
```

Docs/tooling changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/test_full_automation_layer.ps1
```

Post-task workflow training:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite train
```

Run this after a task reveals a reusable lesson, after changing hooks or agents, or when the user types exactly `train`. The training suite writes `.tmpbuild/post-task-training-report.md` and points the next Codex pass at durable workflow surfaces instead of task-specific product edits.

Changed-file readiness report:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles
```

Current runtime/editor logs after playtest:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh
```

## Boundaries

These agents do not replace editor playtests or 2-client multiplayer tests. They exist to make routine inspection repeatable, catch obvious drift, and make final handoffs more honest.
