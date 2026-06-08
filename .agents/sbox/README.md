# S&Box Agent Toolkit

These project agents are working guides for Codex and other AI assistants in this repo. They pair judgment-heavy review checklists with repo-side scripts that produce objective evidence.

Use these agents as helpers, not autonomous owners. Gameplay, UI, prefab, asset, and networking changes still happen as small, separate phases.

## Routing

| Need | Use | Evidence command |
|---|---|---|
| Editor-capable command execution | `editor-first-workflow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo` |
| Final sanity pass after code changes | `pre-handoff-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick` |
| Build and editor/runtime log pass | `build-log-sentinel.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1` |
| Gameplay implementation review | `gameplay-systems-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1` plus build sentinel |
| Prefab, scene, or AutoWire review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1` |
| Deep prefab/reference graph review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1` |
| Primitive prefab visual polish | `prefab-visual-quality-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_visual_quality_audit.ps1 -ShowInfo` |
| Main scene/spawn/collider review | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1` |
| Glowing blockout line cleanup or prevention | `editor-first-workflow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite blue-lines -ShowInfo` |
| Editor-native cover/blockout prop | `editor-native-cover-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sandbag_cover_audit.ps1 -ShowInfo`; `powershell -ExecutionPolicy Bypass -File scripts/agents/burnt_vehicle_block_audit.ps1 -ShowInfo` |
| Prop/building collision — mesh `ModelCollider` + `PhysicsMeshFile` methodology (see `docs/collision_authoring.md`) | `collision-authoring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo`; `powershell -ExecutionPolicy Bypass -File scripts/agents/model_collision_scale_audit.ps1 -ShowInfo` |
| Multi-agent collision exploration, implementation, verification, and critique | `collision-chain-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo` |
| Read-only collision discovery before edits | `collision-explorer-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo` |
| Scoped collision implementation after a contract is defined | `collision-implementer-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo` |
| Collision evidence and runtime-gap verification | `collision-verifier-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite scene -ShowInfo` |
| Findings-first collision critique and rework routing | `collision-critic-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo` |
| Blender or generated asset review | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1`; `powershell -ExecutionPolicy Bypass -File scripts/agents/model_collision_scale_audit.ps1 -ShowInfo` |
| Designing the ModelDoc automation agent | `modeldoc-agent-builder.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc` |
| ModelDoc/VMDL validation | `modeldoc-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo` |
| Animated Model import, AnimGraph, or sequence playback | `animated-model-intake-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/animated_model_intake_audit.ps1 -ShowInfo` |
| AAA-quality Blender asset production | `aaa-asset-quality-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo` |
| New asset request or source brief | `asset-brief-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon` |
| Blender source-scene production quality | `blender-quality-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1` |
| Material and texture production quality | `material-texture-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1` |
| Blender procedural look needs to match in S&Box | `procedural-texture-transfer-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production` |
| Visual preview review for a Blender asset | `visual-review-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend` |
| Drone variant model identity | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/drone_variant_visual_audit.ps1 -ShowInfo` |
| Full asset production readiness | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production` |
| Cosmetic jigglebone setup | `jigglebone-cosmetic-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc` plus editor bone-merge playtest |
| Sound assets and native editor audio wiring | `sound-control-plane-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sound -ShowInfo` |
| Unified editor MCP capability/status check | `sound-control-plane-agent.md` | `control_plane_status` in the S&Box MCP server |
| UI/startup-flow and Razor refresh review | `ui-flow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning` |
| Multiplayer authority review | `networking-review-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1` |
| Manual editor test planning | `playtest-qa-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea All` |
| Docs freshness review | `docs-roadmap-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1` |
| Balance and tuning review | `balance-tuning-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1` |
| Changed-file readiness report | `pre-handoff-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles` |
| Current editor/runtime log discovery | `build-log-sentinel.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh` |
| S&Box engine/API research intake | `sbox-engine-reference-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_engine_reference_audit.ps1 -Root . -ShowInfo` |
| Official S&Box docs source intake | `sbox-docs-source-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_docs_source_audit.ps1 -Root . -Refresh -ShowInfo` |
| Official S&Box release notes intake | `sbox-release-notes-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite release-notes -ShowInfo` |
| S&Box Code Search public package examples | `sbox-code-search-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_code_search_audit.ps1 -Root . -ShowInfo` |
| Editor Node Tool review | `editor-node-tool-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/editor_node_tool_audit.ps1 -Root . -ShowInfo` |
| S&Box API Lookup for exact symbols | `sbox-engine-reference-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Type Sandbox.GameObject -Member NetworkSpawn` |
| S&Box Learn tutorial intake | `sbox-learn-intake-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_learn_intake_audit.ps1 -Root . -ShowInfo` |
| Dynamic Razor value refresh review | `ui-razor-reactivity-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning -ShowInfo` |
| Post-task workflow training | `post-task-training-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite train` |

## Operating Rules

- Prefer inspection and reports before edits.
- For editor-capable tasks, start with `editor-first-workflow-agent.md`: check `control_plane_status` or `tools/list`, inspect the active editor scene/components, mutate through native MCP when possible, save with `editor_save_scene`, and state any fallback honestly.
- For S&Box-native primitive prefabs, use `prefab-visual-quality-agent.md` before handoff so a valid prefab does not ship as a blockout; require silhouette/detail review and editor screenshot proof.
- Do not rename public S&Box classes, components, prefabs, or assets unless asked.
- Treat networked gameplay as host-authoritative.
- Use `[Sync]` for replicated state and RPCs for notifications or validated requests.
- Extend `Code/code/Wiring/AutoWire.cs` when new prefab references need repeatable wiring.
- After meaningful C# or scene/prefab edits, run the build/log sentinel and the most relevant specialist audit.
- For editor-native cover or blockout props, inspect the live editor scene before file edits, preserve user-deleted primitive children, and use focused audits such as `sandbag_cover_audit.ps1` or `burnt_vehicle_block_audit.ps1` to lock spacing, material, local-offset, and placement contracts.
- Do not add glowing blockout line strips to playable level geometry; after scene or level-generator work, run the `blue-lines` suite when route/readability markers were touched.
- After map prop or building collision edits, run the collision authoring agent and then verify in the live editor; saved scene JSON and active editor state can diverge after Save As or MCP edits.
- For collision-heavy tasks, use `collision-chain-agent.md` to split work across explorer, implementer, verifier, and critic roles before final handoff.
- When the user types exactly `train`, respond with `On it!`, run the post-task training workflow, and apply durable hook, agent, pipeline, or documentation updates that will help future tasks.
- When the user asks for AAA-quality Blender/S&Box assets, route through `aaa-asset-quality-agent.md`: start from a brief with reference requirements and Production Quality Targets, then prove Blender quality, material/texture readiness, visual previews, export/import, ModelDoc/FBX slots, and S&Box prefab/editor appearance.
- For animated model imports, route through `animated-model-intake-agent.md` and `editor-first-workflow-agent.md`: prove clips in ModelDoc or AnimGraph editor tooling before wiring `SkinnedModelRenderer.Sequence`, `Parameters.Set`, `AnimGraphDirectPlayback`, 1D blendspace, or state machine behavior.
- For Blender-to-S&Box texture transfer, inspect whether the Blender material is procedural or image-backed before editing `.vmat` files. Procedural looks need baked project textures and strict VMDL material-slot validation.
- For cosmetic jigglebones, route through `jigglebone-cosmetic-agent.md`: prove skeleton binding, bone merge, ModelDoc physics shapes, joint anchors, and editor motion before treating the asset as ready.
- For sound work, treat `.sound` wrappers as gameplay assets and raw audio as source data. Run the sound suite before wiring or previewing audio in the editor.
- Prefer the native S&Box MCP server at `http://localhost:29015/mcp` as the unified editor control plane; use CoworkBridge only as a fallback for operations not exposed through MCP.
- After UI or startup-flow edits, run the UI flow audit and an editor click-test checklist. Dynamic Razor values should be covered by `BuildHash()` rather than per-frame `StateHasChanged()` refreshes.
- If runtime logs are stale or unavailable, say that directly and do not overclaim editor validation.
- Static file audits do not replace an editor playtest or a 2-client multiplayer test when runtime behavior changed.
- Treat pasted S&Box or Source 2 research as useful input, not authority. Route it through `sbox-engine-reference-agent.md`, prefer official docs/public source, query local `API.json` with `sbox_api_lookup.ps1` for exact symbols, and add source/date markers for volatile API or release claims. When the user links `Facepunch/sbox-docs`, use `sbox-docs-source-agent.md` and refresh `.tmpbuild/sbox-docs` before broad docs intake.
- Treat official S&Box release notes as high-value but volatile. Route patch-note and API-change sweeps through `sbox-release-notes-agent.md`, date the reviewed release/API sources, verify exact symbols against local `API.json`, and protect adopted lessons with `sbox_release_notes_audit.ps1`.
- Treat S&Box Code Search as practical example discovery, not authority. Route `https://sbox.game/codesearch` and public package examples through `sbox-code-search-agent.md`, compare multiple recent packages, verify exact symbols locally, and protect adopted lessons with `sbox_code_search_audit.ps1`.
- Treat S&Box Learn pages as useful community tutorials. Route them through `sbox-learn-intake-agent.md`; if they affect Razor refresh behavior, use `ui-razor-reactivity-agent.md`; if they affect Node Editor tooling, use `editor-node-tool-agent.md`; preserve the focused audits, hook, and `learn` suite.
