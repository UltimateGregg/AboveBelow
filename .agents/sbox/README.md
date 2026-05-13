# S&Box Agent Toolkit

These project agents are working guides for Codex and other AI assistants in this repo. They pair judgment-heavy review checklists with repo-side scripts that produce objective evidence.

Use these agents as helpers, not autonomous owners. Gameplay, UI, prefab, asset, and networking changes still happen as small, separate phases.

## Routing

| Need | Use | Evidence command |
|---|---|---|
| Final sanity pass after code changes | `pre-handoff-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick` |
| Build and editor/runtime log pass | `build-log-sentinel.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1` |
| Gameplay implementation review | `gameplay-systems-agent.md` | Build sentinel plus focused code inspection |
| Prefab, scene, or AutoWire review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1` |
| Deep prefab/reference graph review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1` |
| Main scene/spawn/collider review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1` |
| Blender or generated asset review | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1` |
| New asset request or source brief | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon` |
| Blender source-scene production quality | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1` |
| Material and texture production quality | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1` |
| Visual preview review for a Blender asset | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend` |
| Full asset production readiness | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production` |
| UI/startup-flow interaction review | `ui-flow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1` |
| Multiplayer authority review | `networking-review-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1` |
| Manual editor test planning | `playtest-qa-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea All` |
| Docs freshness review | `docs-roadmap-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1` |
| Balance and tuning review | `balance-tuning-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1` |
| Changed-file readiness report | `pre-handoff-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles` |
| Current editor/runtime log discovery | `build-log-sentinel.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh` |

## Operating Rules

- Prefer inspection and reports before edits.
- Do not rename public S&Box classes, components, prefabs, or assets unless asked.
- Treat networked gameplay as host-authoritative.
- Use `[Sync]` for replicated state and RPCs for notifications or validated requests.
- Extend `Code/code/Wiring/AutoWire.cs` when new prefab references need repeatable wiring.
- After meaningful C# or scene/prefab edits, run the build/log sentinel and the most relevant specialist audit.
- After UI or startup-flow edits, run the UI flow audit and an editor click-test checklist.
- If runtime logs are stale or unavailable, say that directly and do not overclaim editor validation.
- Static file audits do not replace an editor playtest or a 2-client multiplayer test when runtime behavior changed.
