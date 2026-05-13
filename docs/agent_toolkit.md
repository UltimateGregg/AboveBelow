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
| Prefab and Wiring Agent | Validate prefab shape and AutoWire references | `scripts/agents/prefab_wiring_audit.ps1` |
| Prefab Graph Audit | Validate GUID refs, component refs, prefab refs, and resource paths | `scripts/agents/prefab_graph_audit.ps1` |
| Scene Integrity Audit | Validate main scene managers, spawns, and collider patterns | `scripts/agents/scene_integrity_audit.ps1` |
| Asset Pipeline Agent | Validate `.blend` configs, targets, and material remaps | `scripts/agents/asset_pipeline_audit.ps1` |
| UI Flow Agent | Catch interactive-looking Razor UI without click behavior | `scripts/agents/ui_flow_audit.ps1` |
| Networking Review Agent | Surface authority and replication risks | `scripts/agents/networking_review_audit.ps1` |
| Playtest QA Agent | Generate editor and multiplayer checklists | `scripts/agents/playtest_checklist.ps1` |
| Docs and Roadmap Agent | Check doc presence and drift | `scripts/agents/docs_roadmap_audit.ps1` |
| Balance and Tuning Agent | Snapshot balance-related values | `scripts/agents/balance_tuning_report.ps1` |
| Current Log Audit | Search project and local app log locations for fresh runtime/editor logs | `scripts/agents/current_log_audit.ps1` |
| Feature Readiness Report | Map changed files to required checks and manual test focus | `scripts/agents/feature_readiness_report.ps1` |
| Pre-Handoff Agent | Orchestrate final checks | `scripts/agents/run_agent_checks.ps1` |

## Script Behavior

- Scripts print findings as `Error`, `Warning`, or `Info`.
- Errors return exit code `1`.
- Warnings return exit code `0` unless `-FailOnWarning` is supplied.
- Static-analysis warnings are prompts for manual inspection, not automatic proof of a bug.
- The build sentinel writes build output to `.tmpbuild/agent-build.log`.
- Full automation is still static unless paired with an editor playtest. Use `current_log_audit.ps1 -RequireFresh` after the playtest to verify current runtime logs.

## Recommended Usage By Change Type

Gameplay or C# changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

Prefab or scene changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

Blender or asset pipeline changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend
python scripts/texture_contact_sheet.py --config scripts/terrain_pine_asset_pipeline.json --out screenshots/asset_previews/terrain_pine_texture_sheet.png
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

Use the texture contact sheet for alpha-cutout assets such as tree foliage cards before accepting a Blender render. The Blender preview confirms shape; the contact sheet and S&Box editor screenshot confirm the material and transparent background behavior.

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

Balance changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Balance
```

UI or startup-flow changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
```

Docs/tooling changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/test_full_automation_layer.ps1
```

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
