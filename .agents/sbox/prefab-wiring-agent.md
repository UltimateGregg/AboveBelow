# Prefab and Wiring Agent

## Purpose

Protect prefab, scene, and AutoWire consistency for class, drone, weapon, and equipment work.

## Primary Areas

- `Assets/prefabs/`
- `Assets/scenes/main.scene`
- `Code/code/Wiring/AutoWire.cs`
- `WIRING.md`

## Review Rules

- Do not reorganize prefab structure without discussion.
- Preserve the per-class and per-variant prefab names listed in `AGENTS.md`.
- New prefab references should be repeatable through `AutoWire.cs` or documented manual inspector wiring.
- Soldier prefabs should keep `Body`, `Eye`, `Weapon` or `DroneDeployer`, and expected held equipment children.
- Reusable held-item prefabs live under `Assets/prefabs/items/` and are regenerated from the active class/pilot loadout children with `scripts/agents/sync_held_item_prefab_templates.ps1`.
- When `Weapon`, `Grenade`, or `DroneDeployer` child graphs change on active character prefabs, run the sync script and then `held_item_prefab_template_audit.ps1` so the standalone item templates do not drift.
- The pilot drone deployer's runtime held propeller preview should stay backed by `Assets/prefabs/items/held_drone_propeller.prefab`; `DroneDeployer` assigns the selected GPS/FPV propeller model after cloning it.
- The local first-person viewmodel root should stay backed by `Assets/prefabs/items/local_first_person_viewmodel.prefab`; `FirstPersonViewmodel` clones it before adding per-item runtime weapon and copied visual children.
- The local first-person arms child should stay backed by `Assets/prefabs/items/viewmodel_arms.prefab`; `FirstPersonViewmodel` clones it and assigns the stock or fallback arms model plus bonemerge/animgraph runtime state.
- The stock first-person weapon animation driver should stay backed by `Assets/prefabs/items/viewmodel_stock_weapon.prefab`; `FirstPersonViewmodel` clones it for both visible stock weapons and hidden custom-weapon animation drivers.
- Custom first-person visual roots and static fallback item roots should stay backed by `Assets/prefabs/items/viewmodel_custom_visual.prefab` and `Assets/prefabs/items/viewmodel_static_item.prefab`; copied renderer children remain runtime/per-item.
- Reusable scene marker prefabs live under `Assets/prefabs/markers/`. Keep `PlayerSpawn_Soldier`, `PlayerSpawn_Pilot`, and `TrainingDummySpawn` available for new map authoring instead of hand-building repeated marker GameObjects, and keep saved `main.scene` placements as prefab instances.
- The reusable arena boundary wall lives at `Assets/prefabs/environment/arena_boundary_wall.prefab`. Keep the four saved `main.scene` boundary walls as prefab instances, with hidden dev-box rendering, static solid collision, and `SelectedHierarchyColliderViewer` editor wireframes owned by the prefab.
- Reusable terrain tree, simple rock, model-collider exterior rock, grass-card, partial grass-card, ground-polish patch, berm soft-cap, landform, and trench segment prefabs live under `Assets/prefabs/environment/terrain_*.prefab`, `grass_clump.prefab`, `grass_clump_single_card.prefab`, `grass_clump_five_card.prefab`, `ground_grass_clump_patch.prefab`, `ground_worn_path_patch.prefab`, `berm_soft_cap.prefab`, `Berm.prefab`, `Hill.prefab`, `hill_central_north_box.prefab`, `Plateau.prefab`, `plateau_east_north_terrain.prefab`, and `TrenchSegment.prefab`. Use `scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1` for repeated placements whose child/component shape matches the template; create a distinct prefab contract for hills/plateaus whose child/component shape does not match the generic templates.
- Composed environment props with child collision, such as `Assets/prefabs/environment/WaterTower.prefab`, should own their visual/collider/ladder contract in the prefab. Saved scene placements should be prefab instances that only override the root name and transform; keep the prefab root at `0,0,0` / identity / `1,1,1`.
- The destroyed pickup cover prop lives at `Assets/prefabs/environment/burnt_car_wreck.prefab`. Keep `CenterLane_DestroyedPickup_North` as a saved scene prefab instance so the 60 primitive children, 24 solid pieces, and 36 detail pieces stay owned by the prefab contract instead of being hand-expanded in `main.scene`.
- The playable house props live at `Assets/prefabs/environment/house_large_playable.prefab`, `Assets/prefabs/environment/house_small_playable.prefab`, and `Assets/prefabs/environment/house_small_collision_playable.prefab`. Keep `House_Large_01`, `House_Large_02`, `House_Small_01`, `House_Small_02`, `House_Small_03`, and `House_Small_04` as saved scene prefab instances so visual, collision, ladder, and zone helper children stay owned by the prefab contract.
- The road sandbag cover prop lives at `Assets/prefabs/environment/road_sandbag_cover_mid.prefab`. Keep `RoadSandbagCover_Mid` as a saved scene prefab instance after spacing/height audits pass, with the prefab owning all 18 solid sandbag bodies.
- The northwest road barrier prop lives at `Assets/prefabs/environment/road_cover_northwest_barrier.prefab`. Keep `RoadCover_Northwest_Barrier` as a saved scene prefab instance after the barrier audit passes, with the prefab owning its 10 solid concrete pieces and 9 visual detail pieces.
- The road base templates live at `Assets/prefabs/environment/road_surface.prefab`, `road_shoulder.prefab`, and `road_curb.prefab`. Keep `RoadSurface_Main`, `RoadShoulder_West`, `RoadShoulder_East`, `RoadCurb_West`, and `RoadCurb_East` as saved scene prefab instances so material and renderer contracts are centralized.
- The road lane dash template lives at `Assets/prefabs/environment/road_lane_dash.prefab`. Keep the 41 `RoadDash_##` saved scene placements as prefab instances with only name/position/rotation/scale overrides.
- The road-edge wear decal template lives at `Assets/prefabs/environment/road_edge_wear_patch.prefab`. Keep the 24 `RoadEdgeWear_West_##` / `RoadEdgeWear_East_##` saved scene placements as prefab instances with only name/position/rotation/scale overrides.
- The LevelDesignPass cover-box template lives at `Assets/prefabs/environment/blockout_cover_box.prefab`. Keep repeated collision-bearing lane, operator-nest, asset-placeholder, `DroneLaunchPad`, and `NorthLowCover` dev boxes as prefab instances with local material, tint, transform, and stable-name overrides.
- The skyline model-collider box template lives at `Assets/prefabs/environment/skyline_model_collider_box.prefab`. Keep skyline dev boxes that require `ModelCollider` as prefab instances with local material, tint, transform, and stable-name overrides.
- The visual-only dev-box template lives at `Assets/prefabs/environment/visual_dev_box.prefab`. Keep repeated renderer-only glow markers, skyline tower masses, and window bands as prefab instances with local material, tint, transform, and stable-name overrides.
- Reusable readability light prefabs live at `Assets/prefabs/environment/operator_signal_light.prefab`, `Assets/prefabs/environment/launch_pad_glow_light.prefab`, and `Assets/prefabs/environment/perch_marker_light.prefab`. Keep the operator signal lights, launch-pad glow lights, and perch marker lights as saved scene prefab instances with per-placement root name, position, radius/color, and optional glow-marker scale/tint overrides.
- The ambient sound emitter template lives at `Assets/prefabs/environment/ambient_sound_point.prefab`. Keep `AmbientLightWind`, `AmbientBirdsChirping`, `AmbientBirdsCanopyFar`, and `AmbientCrowsDistant` as saved scene prefab instances with per-placement sound, loop timing, volume, and position overrides.
- Reusable stock scene prop prefabs live under `Assets/prefabs/environment/stock/`. Use them for repeated mounted stock shrubs, benches, fences, trees, and bins before hand-authoring direct model props in `main.scene`.
- Stock scene prop migration should use `scripts/agents/migrate_stock_scene_props_to_prefab_instances.ps1` or run through `dvp_preview_stock_scene_prop_prefab_migration` / `dvp_migrate_stock_scene_props_to_prefabs` after the editor has hotloaded `Editor/StockScenePropPrefabEditorCommands.cs`; do not hand-author prefab-instance JSON without current serialized evidence.
- Transient combat objects should stay prefab-backed when they have reusable behavior. Default ballistic tracers use `Assets/prefabs/tracer_default.prefab`; muzzle flashes use `Assets/prefabs/effects/muzzle_flash.prefab`; tracer bullet glows use `Assets/prefabs/effects/tracer_bullet_glow.prefab`; jammer beams use `Assets/prefabs/effects/jammer_beam.prefab`; detached fiber cables use `Assets/prefabs/effects/detached_fiber_cable.prefab`; grenade detonation visuals use `Assets/prefabs/effects/chaff_burst.prefab`, `Assets/prefabs/effects/emp_burst.prefab`, and `Assets/prefabs/effects/frag_burst.prefab`; thrown grenade projectiles use `Assets/prefabs/items/thrown_grenade_projectile.prefab`.
- The lightweight `BallisticTracerRenderer` fallback should also stay prefab-backed through `Assets/prefabs/effects/ballistic_tracer.prefab`; `tracer_default.prefab` remains the normal weapon tracer path when configured.
- Drone prefabs should keep `Visual`, `CameraSocket`, `MuzzleSocket`, and their variant identity component.
- Fiber FPV should keep `JamSusceptibility = 0` unless the balance spec changes.
- Run the loadout slot check when soldier held equipment changes.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/held_item_prefab_template_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/check_first_person_viewmodel_spawn.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_scene_markers_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_marker_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_arena_boundaries_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_building_scene_objects_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/building_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_readability_light_scene_objects_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/readability_light_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_ambient_sound_scene_objects_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/ambient_sound_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/sync_stock_scene_prop_prefabs.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/migrate_stock_scene_props_to_prefab_instances.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/agents/stock_scene_prop_prefab_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/stock_scene_prop_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated
powershell -ExecutionPolicy Bypass -File scripts/agents/destroyed_pickup_scene_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/road_cover_barrier_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/road_lane_marking_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/transient_combat_prefab_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/ballistic_tracer_prefab_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

## Output Shape

List prefab or scene problems first. Separate structural prefab failures from graph/resource-reference failures and scene/spawn/collider failures. For MCP/editor scene edits, summarize objects changed.
