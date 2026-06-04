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

When a script edits `Assets/scenes/main.scene` while the editor is open, check `editor_scene_info` first. If the editor is clean, reload the current scene through the native MCP `scene_load` / `scene_open` tool after the saved-file edit so the user does not have to clear the reload prompt manually. Do not reload over user-owned unsaved editor changes.

## Agents

| Agent | Purpose | Script |
|---|---|---|
| Editor-First Workflow Agent | Route editor-capable tasks through live S&Box MCP inspection, mutation, save, screenshot, play, and log proof before static fallback | `scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo` |
| Build and Log Sentinel | Compile and check fresh logs | `scripts/agents/build_log_sentinel.ps1` |
| Gameplay Systems Agent | Review gameplay architecture fit | Uses build and networking audits |
| Gameplay Regression Guard | Run focused slot and drone-control regression checks | `scripts/agents/gameplay_regression_guard.ps1` |
| Round Re-Prompt Guard | Keep next-round reset from auto-respawning stale team/loadout choices | `scripts/check_round_reprompt_flow.ps1` |
| Two-Client Lobby Guard | Keep editor play sessions join-first and preserve round probe commands | `scripts/check_two_client_lobby_flow.ps1` |
| Prefab and Wiring Agent | Validate prefab shape and AutoWire references | `scripts/agents/prefab_wiring_audit.ps1` |
| Held Item Prefab Template Audit | Keep reusable weapon, grenade, and pilot-controller item prefabs under `Assets/prefabs/items/` synced from the active loadout child graphs | `scripts/agents/run_agent_checks.ps1 -Suite held-items -ShowInfo` |
| First-Person Viewmodel Guard | Keep the shared local-only first-person viewmodel root, arms child, stock animation driver, custom visual container, and static item container prefab-backed, including prefab-owned fallback renderers while per-selection copies stay runtime children | `scripts/agents/run_agent_checks.ps1 -Suite viewmodel-prefab -ShowInfo` |
| Scene Marker Prefab Audit | Keep reusable player spawn and training dummy spawn marker prefabs under `Assets/prefabs/markers/` available for scene authoring and referenced by saved-scene prefab instances | `scripts/agents/run_agent_checks.ps1 -Suite scene-markers -ShowInfo` |
| Scene Prefab Coverage Audit | Keep component-bearing saved scene objects prefab-backed except for scene metadata and the unique ArenaFloor terrain | `scripts/agents/run_agent_checks.ps1 -Suite scene-prefab-coverage -ShowInfo` |
| Blockout Blue Line Audit | Keep generated and live level blockouts free of retired glowing line strip markers | `scripts/agents/run_agent_checks.ps1 -Suite blue-lines -ShowInfo` |
| Arena Boundary Wall Prefab Guard | Keep the four Source 2-style clip blockers backed by `Assets/prefabs/environment/arena_boundary_wall.prefab` with invisible collision and selection-only editor wireframes | `scripts/agents/scene_integrity_audit.ps1 -Root . -ShowInfo` |
| Terrain Scene Object Prefab Migration | Convert repeated terrain trees, rocks, full and partial grass-card clumps, ground-polish patches, berm soft caps, shape-matching landforms, exact bespoke landforms, and trench segment roots to local environment prefab instances while preserving unknown or hand-edited mismatches | `scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -Root . -DryRun` |
| Terrain Scene Prefab Migration Audit | Fail when shape-matching terrain, landform, grass, trench, skyline, or level-design scene objects remain expanded instead of prefab-backed | `scripts/agents/run_agent_checks.ps1 -Suite terrain-scene-prefabs -ShowInfo` |
| Composed Environment Prop Prefab Guard | Keep authored prop roots such as `WaterTower` prefab-backed while visual, collider, and ladder children stay owned by the prefab template | `scripts/agents/collision_authoring_agent.ps1 -Root . -ShowInfo` plus `scripts/agents/scene_integrity_audit.ps1 -Root . -ShowInfo` |
| Building Scene Prefab Audit | Keep playable large and small house roots prefab-backed while visual, collider, ladder, and zone helper children stay owned by the prefab template | `scripts/agents/building_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated` |
| Stock Scene Prop Prefab Audit | Keep reusable prefab templates, migration tooling, and saved-scene prefab instances for mounted stock scene props under `Assets/prefabs/environment/stock/` | `scripts/agents/stock_scene_prop_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated` |
| Transient Combat Prefab Audit | Keep default ballistic tracers, muzzle flashes, tracer bullet glows, jammer beams, detached fiber cables, grenade detonation visuals, and thrown grenade projectiles prefab-backed while preserving procedural fallbacks | `scripts/agents/run_agent_checks.ps1 -Suite transient-combat -ShowInfo` |
| Runtime Prefab Fallback Audit | Classify every runtime `new GameObject` path in `Code/` as a prefab-backed repair fallback or intentional per-item runtime copy | `scripts/agents/run_agent_checks.ps1 -Suite runtime-prefab-fallbacks -ShowInfo` |
| Destroyed Pickup Prefab Audit | Keep the S&Box-native crashed pickup prefab placeable, primitive-backed, scene-instance-backed, and free of retired VMDL collision | `scripts/agents/destroyed_pickup_prefab_audit.ps1` plus `scripts/agents/destroyed_pickup_scene_audit.ps1 -Root . -ShowInfo` |
| Sandbag Cover Prefab Audit | Keep the road sandbag cover spacing, height, material, solid collision, and scene prefab instance contract intact | `scripts/agents/sandbag_cover_audit.ps1 -Root . -ShowInfo` |
| Road Cover Barrier Prefab Audit | Keep the northwest road-cover barrier prefab-backed with 10 solid concrete pieces and 9 visual detail pieces | `scripts/agents/road_cover_barrier_audit.ps1 -Root . -ShowInfo` |
| Road Corridor Prefab Audit | Keep the road surface, shoulders, curbs, and 41 centerline dashes prefab-backed while preserving road-length spacing and stable names | `scripts/agents/road_lane_marking_audit.ps1 -Root . -ShowInfo` |
| Road Edge Wear Prefab Audit | Keep road-edge wear as 24 visual-only prefab-backed decal placements with stable names and randomized edge placement | `scripts/agents/road_edge_wear_audit.ps1 -Root . -ShowInfo` |
| Level Design Cover Box Prefab Migration | Keep repeated `LevelDesignPass_AboveBelow` collision-bearing dev boxes plus `DroneLaunchPad` and `NorthLowCover` backed by `blockout_cover_box.prefab` while preserving per-placement transform, material, tint, and stable names | `scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -Root . -DryRun` |
| Skyline Model-Collider Box Prefab Migration | Keep skyline dev boxes that need `ModelCollider` backed by `skyline_model_collider_box.prefab` while preserving per-placement transform, material, tint, and stable names | `scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -Root . -DryRun` |
| Visual Dev Box Prefab Migration | Keep renderer-only glow markers, skyline masses, and window-band dev boxes backed by `visual_dev_box.prefab` while preserving per-placement transform, material, tint, and stable names | `scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -Root . -DryRun` |
| Prefab Visual Quality Agent | Catch valid-but-underbaked primitive prefabs before handoff, including silhouette, material massing, collision/detail split, and screenshot proof expectations | `scripts/agents/prefab_visual_quality_audit.ps1` |
| Prefab Graph Audit | Validate GUID refs, component refs, prefab refs, and resource paths | `scripts/agents/prefab_graph_audit.ps1` |
| Scene Integrity Audit | Validate main scene managers, spawns, and collider patterns | `scripts/agents/scene_integrity_audit.ps1` |
| Terrain Floor Audit | Keep `ArenaFloor` backed by native `Sandbox.Terrain` and a source-controlled `.terrain` asset | `scripts/agents/run_agent_checks.ps1 -Suite terrain -ShowInfo` |
| Editor-Native Cover Agent | Review S&Box-editor primitive cover, spacing, material, and preserved deletions | `scripts/agents/sandbag_cover_audit.ps1`; `scripts/agents/burnt_vehicle_block_audit.ps1` |
| Collision Authoring Agent | Validate `Collision_*`, building-root coverage, ladder triggers, visual/collider alignment, and water-tower collision coverage | `scripts/agents/collision_authoring_agent.ps1` |
| Collision Agent Chain | Coordinate Codex explorer, implementer, verifier, and critic roles for collision-heavy work | `scripts/agents/collision_chain_report.ps1` |
| Collision Explorer Agent | Read-only collision discovery before edits | `.agents/sbox/collision-explorer-agent.md` |
| Collision Implementer Agent | Scoped collision edits after a contract is defined | `.agents/sbox/collision-implementer-agent.md` |
| Collision Verifier Agent | Evidence collection and runtime-gap reporting | `.agents/sbox/collision-verifier-agent.md` |
| Collision Critic Agent | Findings-first critique and rework routing | `.agents/sbox/collision-critic-agent.md` |
| Asset Pipeline Agent | Validate `.blend` configs, targets, and material remaps | `scripts/agents/asset_pipeline_audit.ps1` |
| ModelDoc Agent | Validate `.vmdl` source meshes, material targets, and config drift | `scripts/agents/modeldoc_audit.ps1` |
| Jigglebone Cosmetic Agent | Review skinned cosmetic bone merge, ModelDoc physics shapes, joint anchors, and editor motion proof | `scripts/agents/run_agent_checks.ps1 -Suite modeldoc` plus editor playtest |
| AAA Asset Quality Agent | Coordinate reference, Production Quality Targets, material roles, visual proof, and S&Box import validation for high-polish Blender assets | `scripts/agents/aaa_asset_quality_audit.ps1` |
| Sound Control Plane Agent | Validate SoundEvent wrappers, attached playback, and editor-native sound workflows | `scripts/agents/run_agent_checks.ps1 -Suite sound` |
| Team Label Copy Audit | Keep player-facing role labels on Drone Pilots and Hunters while preserving the project title | `scripts/agents/team_label_copy_audit.ps1` |
| UI Flow Agent | Catch interactive-looking Razor UI without click behavior, missing `BuildHash()`, and per-frame `StateHasChanged()` refreshes | `scripts/agents/ui_flow_audit.ps1` |
| Networking Review Agent | Surface authority and replication risks | `scripts/agents/networking_review_audit.ps1` |
| Large Component Risk Audit | Keep broad components from absorbing new responsibilities; currently guards the extracted `GameSetupPrefabResolver` seam | `scripts/agents/large_component_risk_audit.ps1` |
| Playtest QA Agent | Generate editor and multiplayer checklists | `scripts/agents/playtest_checklist.ps1` |
| Docs and Roadmap Agent | Check doc presence and drift | `scripts/agents/docs_roadmap_audit.ps1` |
| Balance Config Audit | Keep runtime tuning centralized in `BalanceConfigResource` and applied through spawned pawn/drone helpers | `scripts/agents/run_agent_checks.ps1 -Suite balance -ShowInfo` |
| Balance and Tuning Agent | Snapshot balance-related values | `scripts/agents/balance_tuning_report.ps1` |
| Current Log Audit | Search project and local app log locations for fresh runtime/editor logs | `scripts/agents/current_log_audit.ps1` |
| S&Box Engine Reference Agent | Verify external S&Box/Source 2 research and guard against obsolete guidance | `scripts/agents/sbox_engine_reference_audit.ps1` |
| S&Box Docs Source Agent | Refresh and inspect the official `Facepunch/sbox-docs` markdown source before broad official-docs training | `scripts/agents/sbox_docs_source_audit.ps1 -Refresh -ShowInfo` |
| S&Box Release Notes Intake Agent | Convert official S&Box release notes and API changes into dated project guidance, hooks, and audits | `scripts/agents/sbox_release_notes_audit.ps1` |
| S&Box Code Search Agent | Use public package examples from `https://sbox.game/codesearch` for pattern discovery while verifying exact symbols locally | `scripts/agents/run_agent_checks.ps1 -Suite code-search -ShowInfo` |
| S&Box API Lookup | Query local `API.json` for exact S&Box types, members, attributes, and summaries | `scripts/agents/sbox_api_lookup.ps1` |
| S&Box Learn Intake Agent | Convert useful S&Box Learn tutorials into project docs, audits, hooks, and routing | `scripts/agents/sbox_learn_intake_audit.ps1` |
| Editor Node Tool Agent | Keep custom S&Box Node Editor tooling editor-only and free of copied tutorial placeholders | `scripts/agents/editor_node_tool_audit.ps1` |
| UI Razor Reactivity Agent | Subagent for dynamic Razor values, `BuildHash()`, and stale UI refresh bugs | `scripts/agents/ui_flow_audit.ps1 -FailOnWarning` |
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
- The networking audit also enforces that `GameSetup.RequestSpawn` stays a `[Rpc.Host]` intent request so team/class/variant selection is applied only by the host.
- The UI flow audit checks both interaction affordances and Razor refresh contracts. Dynamic rendered values should be listed in `BuildHash()`, not forced through `StateHasChanged()` in `Tick()`.
- The Learn intake audit keeps S&Box Learn tutorial lessons wired through a specific agent, Razor subagent, docs, suite, self-test, and Claude hook instead of living only in chat.
- The docs source audit keeps official `Facepunch/sbox-docs` intake routed through a source clone, dated reference note, agent routing, suite wiring, self-test, and hook instead of brittle page scraping.
- The release notes audit keeps official S&Box patch-note/API-change lessons dated, source-linked, routed through a dedicated agent, and protected by Suite release-notes instead of living only in chat.
- The Code Search audit, `sbox_code_search_audit.ps1`, keeps `https://sbox.game/codesearch` available as a public-package pattern resource without treating package source as verified API authority.
- The scene marker and stock scene prop audits accept strict migration checks when direct marker or mounted stock prop placements are expected to have been converted to saved-scene prefab instances.
- Full automation is still static unless paired with an editor playtest. Use `current_log_audit.ps1 -RequireFresh` after the playtest to verify current runtime logs.

## Recommended Usage By Change Type

Editor-capable scene, prefab, component, asset, sound, screenshot, terrain, or playtest work:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo
```

Start with `.agents/sbox/editor-first-workflow-agent.md`. Check `control_plane_status` or JSON-RPC `tools/list`, inspect with `editor_scene_info` plus scene/component tools, mutate through native MCP where available, save with `editor_save_scene` only when the editor was not already dirty and the edits are agent-owned, and use screenshot/play/log tools for proof. If the editor is pre-dirty, the editor or required tool domain is unavailable, or save ownership is uncertain, report that clearly and separate static fallback work from live-editor proof.

Level blockout or generator changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite blue-lines -ShowInfo
```

Do not reintroduce route, approach, danger, escape/read, breach, or launch-pad glow line strips to the playable level. Use collision-bearing cover, materialized surfaces, or non-line readability cues instead.

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

Round flow, selection, spawn, score, or round-reset changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_round_reprompt_flow.ps1
powershell -ExecutionPolicy Bypass -File scripts/check_two_client_lobby_flow.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite gameplay-regression -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite networking -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Gameplay
```

For local two-editor proof, use the DEBUG console probes when Roslyn scripting is unavailable through MCP:

```text
dvp_round_probe before-selection
dvp_connect_local <target>
dvp_select_drone Gps
dvp_select_soldier Assault
dvp_kill_team Pilot
dvp_round_probe after-reset
```

With two editors open, MCP autostart should give each process an endpoint (`29015`, then `29016`, etc.). Use `component_get` on `GameSetup.EditorDebugSnapshot` for a direct state read; it includes `SteamId`, address, connection count, teams, pawns, score, and round state. If both editors show the same `SteamId`, lobby queries return zero, or the second host logs `Couldnt start TcpSocket`, record an environment/session-identity blocker and do not claim a true two-client pass until a distinct client identity or supported server setup is available.

If only the host editor has MCP control, run `dvp_round_autodrive host-pilot` in that editor. The host syncs DEBUG autodrive state through `GameSetup`, both editor processes drive one host/client loadout pass, one host-side elimination is forced, and `[RoundProbe]`/`EditorDebugSnapshot` output provides the comparison surface.

The `drone-control-regression-check` Claude hook runs the same guard when `DroneWeapon`, `DroneDeployer`, `RemoteController`, `PilotSoldier`, the drone HUD, or FPV/pilot prefabs change.

Prefab or scene changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite held-items -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_scene_markers_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite scene-markers -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_arena_boundaries_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/sync_stock_scene_prop_prefabs.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_stock_scene_props_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite stock-scene-props -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/stock_scene_prop_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite transient-combat -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/road_cover_barrier_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/road_lane_marking_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -ShowInfo
```

For arena floor terrain or heightmap/sculpting changes, use the native terrain workflow:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite terrain -ShowInfo
```

`ArenaFloor` should stay as one stable scene object with a `Sandbox.Terrain` component linked to `terrain/arena_floor.terrain`. Because `Sandbox.Terrain` is corner-origin, the 21600-unit arena terrain is positioned at `-10800,-10800,-8` so it remains centered on the arena. If the terrain asset is missing, has drifted from the expected footprint, or will not load in the editor, run the DEBUG editor console command `dvp_link_arena_terrain`; it creates or repairs the terrain through S&Box `TerrainStorage` and saves the active scene. To rebuild the current rolling heightmap and grass variation splat layer, run `dvp_generate_arena_terrain_variance`; the terrain audit decodes the compressed maps and samples road/building protected points.

For editor-native cover or small scene-only blockout props, start with `.agents/sbox/editor-native-cover-agent.md`. Inspect the live editor scene before file edits, preserve user-deleted primitive children, avoid Blender unless the request becomes a bespoke mesh, and run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sandbag_cover_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/burnt_vehicle_block_audit.ps1 -ShowInfo
```

For prop collision specifically, also run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_chain_report.ps1 -ShowInfo
```

The collision agent catches missing building-root coverage and the failure mode where a visible `Visual` child is rotated while sibling `Collision_*` children stay on the old parent transform. For buildings, inspect the house/building root before adding duplicate colliders to `Model_Visual`; renderer-only visual children are valid when sibling `Collision_*` helpers own the blocking shape. Rotate the prop root instead of the visual child, then verify in the editor with collider gizmos and a short walk-into-the-prop playtest.

For playable house prefab migrations, use `house_large_playable.prefab`, `house_small_playable.prefab`, and `house_small_collision_playable.prefab` as separate contracts; the collision-only small-house placements do not share the same child graph as the visual small-house placements.

For readability light marker migrations, use `migrate_readability_light_scene_objects_to_prefab_instances.ps1` and `readability_light_scene_prefab_audit.ps1`; the prefab roots own the `PointLight` and optional glow marker while scene patches keep local radius, color, placement, and marker scale.

For ambient sound emitter migrations, use `migrate_ambient_sound_scene_objects_to_prefab_instances.ps1` and `ambient_sound_scene_prefab_audit.ps1`; the prefab root owns the `AmbientSound` component while scene patches keep local sound events, loop timing, volume, and placement.

For fallback ballistic tracer work, use `ballistic_tracer_prefab_audit.ps1`; `tracer_default.prefab` remains the normal weapon tracer path, while `ballistic_tracer.prefab` backs the lightweight renderer fallback.
For newly added runtime `new GameObject` code, use `runtime_prefab_fallback_audit.ps1`; reusable objects should resolve a prefab before repair-fallback construction, while intentionally dynamic per-item copies need an explicit allow-list rationale.
For project-owned scene singleton and reusable engine roots, use `migrate_scene_singletons_to_prefab_instances.ps1 -DryRun` and `scene_singleton_prefab_audit.ps1 -RequireMigrated`; this keeps `GameManager`, `HUD`, `BlindingSun_WestSky`, `Sun`, `2D Skybox`, and `Camera` prefab-backed without broad terrain, boundary, or jammer validation. `Scene Information` remains direct scene metadata.

For character voice prefab ownership, use `team_voice_prefab_audit.ps1`; non-jammer soldier/pilot prefabs should own `TeamVoice`, while `GameSetup` keeps the runtime fallback for old or damaged prefabs.
For shared team chat prefab ownership, use `team_comms_prefab_audit.ps1`; `game_manager.prefab` should own `TeamComms`, while `GameSetup` keeps the runtime fallback for old or damaged scenes.
For thrown grenade projectile prefab ownership, use `thrown_grenade_projectile_prefab_audit.ps1`; the projectile prefab should own renderer, collider, rigidbody, and behavior refs, while `ThrowableGrenade` only assigns the per-grenade model and runtime values.
For muzzle flash prefab ownership, use `muzzle_flash_prefab_audit.ps1`; the prefab should own the additive sprite and light components that `MuzzleFlashVisual` configures at runtime.
For grenade detonation effect prefab ownership, use `grenade_effect_prefab_audit.ps1`; chaff, EMP, and frag burst prefabs should own their particle child objects and `Explosion Light` child while `GrenadeEffectVisual` only configures runtime values.

For training dummy prefab ownership, use `training_dummy_prefab_audit.ps1`; the prefab should own `NavMeshAgent` and wire `TrainingDummy.NavAgent`, while `TrainingDummy` keeps its repair fallback.

For larger collision work, start with `.agents/sbox/collision-chain-agent.md`. The chain splits Codex work into explorer, implementer, verifier, and critic handoffs so a second pass can challenge broad invisible blockers, stale editor state, and weak evidence before final handoff. The report script runs the static evidence stack and writes `.tmpbuild/collision-chain-report.md` as the handoff packet for the next Codex role.

Blender or asset pipeline changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon
powershell -ExecutionPolicy Bypass -File scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4_realistic.blend
python scripts/texture_contact_sheet.py --config scripts/terrain_assets_asset_pipeline.json --out screenshots/asset_previews/terrain_assets_texture_sheet.png
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/drone_variant_visual_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

For AAA-quality or otherwise high-polish assets, use `.agents/sbox/aaa-asset-quality-agent.md` first. The generated brief should include reference requirements, Production Quality Targets, material roles, sockets, scale/orientation notes, and a Visual Review Plan before detailed modeling. The proof chain is brief -> Blender source quality -> material/texture audit -> visual preview/contact sheet -> export/import -> ModelDoc and FBX material-slot validation -> S&Box prefab or editor screenshot.

For drone variants with a distinct visible identity, run `scripts/agents/drone_variant_visual_audit.ps1` before accepting the handoff. It catches the specific drift where a variant prefab or held preview still points at a shared/base body even though the variant now has its own Blender source, VMDL, and material identity.

For drone propeller placement, spin direction, or spin-speed changes, run `scripts/agents/drone_propeller_spin_audit.ps1 -ShowInfo` or `scripts/agents/run_agent_checks.ps1 -Suite asset -ShowInfo`. It validates the code-driven propeller scan, motor naming, GPS pivot hierarchy, and the variant-specific `PropellerSpinDegreesPerSecond` overrides.

Use the texture contact sheet for alpha-cutout assets such as tree foliage cards before accepting a Blender render. The Blender preview confirms shape; the contact sheet and S&Box editor screenshot confirm the material and transparent background behavior.

ModelDoc or VMDL changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
```

The ModelDoc audit checks source mesh references, material remap targets, config-to-VMDL drift, and strict material source naming rules. It does not replace Blender visual review, prefab wiring checks, or an editor playtest.

Cosmetic jigglebone changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
```

Use `.agents/sbox/jigglebone-cosmetic-agent.md` before accepting a skinned cosmetic with local bone physics. Static checks prove the asset graph; the required manual proof is an editor playtest with the cosmetic bone-merged to a citizen or human while an animation or body parameter drives visible motion.

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
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo
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

For first-person held-item hand or IK fixes, keep the proof loop in the editor:
spawn/select the relevant pawn in play mode, inspect the held item with
`scene_find_objects` / `scene_find_by_component` and `component_get`, tune
temporary values with `component_set`, and capture `editor_take_screenshot`
proof before copying values back to prefab JSON or reusable held-item templates.
Grip targets should normally be visual-relative anchors on the rendered item so
the hand stays connected while the player moves or turns.

Balance changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Balance
```

UI or startup-flow changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/team_label_copy_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
```

Docs/tooling changes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sbox-docs -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite code-search -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_engine_reference_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_reference_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/test_full_automation_layer.ps1
```

`test_full_automation_layer.ps1` defaults to wiring and fixture red/green checks so `run_agent_checks.ps1 -Suite self-test` stays fast and has a clean success transcript. Use `test_full_automation_layer.ps1 -ProjectSmoke` only when you also want the old broad pass that runs each agent script directly against the current project; `run_agent_checks.ps1 -Suite full` already covers current-project audit execution.

External S&Box or Source 2 research intake:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_docs_source_audit.ps1 -Root . -Refresh -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sbox-docs -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_engine_reference_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Query SyncAttribute -ShowMembers
powershell -ExecutionPolicy Bypass -File scripts/agents/editor_node_tool_audit.ps1 -Root . -ShowInfo
```

Use `.agents/sbox/sbox-docs-source-agent.md` when the user links `Facepunch/sbox-docs` or asks for broad official docs training. The source snapshot belongs under `.tmpbuild/sbox-docs`; use `.tmpbuild/sbox-docs-source-index.md`, `toc.yml`, and `rg` to inspect it, record the reviewed commit/date, and do not vendor the full docs tree. Use `.agents/sbox/sbox-engine-reference-agent.md` before turning pasted engine research into standing guidance. Prefer official S&Box docs, the public engine repo, local `API.json`, and local project patterns. Keep volatile claims dated and sourced, and turn recurring stale-guidance risks into audit rules rather than leaving them only in chat history.

S&Box Code Search intake:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite code-search -ShowInfo
```

Use `.agents/sbox/sbox-code-search-agent.md` when reviewing `https://sbox.game/codesearch` or public package examples. Code Search is best for finding practical usage patterns across published game, editor, and unit-test code. Compare multiple recent examples, do not vendor package source, and verify exact C# symbols with `scripts/agents/sbox_api_lookup.ps1`, official API pages, docs source, or existing project code before implementation.

Official S&Box release notes intake:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite release-notes -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_release_notes_audit.ps1 -Root . -ShowInfo
```

Use `.agents/sbox/sbox-release-notes-agent.md` when reviewing `https://sbox.game/release-notes`, S&Box news update posts, or `https://sbox.game/api/changes`. Capture only reusable creator-facing lessons, date the reviewed release/API sources, and verify exact C# symbols with local `API.json` before implementation. Release-note lessons that become standing guidance should be protected by `sbox_release_notes_audit.ps1` and the `sbox-release-notes-check` hook.

For S&Box Node Editor work, use `.agents/sbox/editor-node-tool-agent.md` as the implementation checklist. Keep `GraphView`, `NodeUI`, `INodeType`, and `IPlug` code under `Editor/` or a library `Editor/` folder, replace tutorial `NotImplementedException` placeholders before testing, and manually open the tool in the editor because static audits cannot prove node creation, selection, or connection behavior.

S&Box Learn tutorial intake:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite learn -ShowInfo
```

Use `.agents/sbox/sbox-learn-intake-agent.md` when reviewing `https://sbox.game/learn` tutorials. Route dynamic Razor UI lessons through `.agents/sbox/ui-razor-reactivity-agent.md`, then protect the lesson with `ui_flow_audit.ps1`, docs, self-test fixtures, and the `sbox-learn-intake-check` hook.
Route Node Editor lessons through `.agents/sbox/editor-node-tool-agent.md`, then protect editor-only placement and tutorial-placeholder cleanup with `editor_node_tool_audit.ps1`.
For Facepunch Learn pages, also capture the authoring surface clearly: a Sandbox Entity `.sent` is a spawn-menu resource pointing at a prefab, while behavior still belongs in `Component` code and exact symbols still need local API lookup when they affect C#.

The `sbox-engine-reference-check` Claude hook runs the docs suite when docs, agent routing, `AGENTS.md`, `API.json`, or engine/API reference suite scripts change.

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
