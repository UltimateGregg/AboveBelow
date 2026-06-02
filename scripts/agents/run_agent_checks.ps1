param(
    [string]$Root = "",
    [ValidateSet("quick", "full", "build", "ui", "prefab", "prefab-graph", "held-items", "viewmodel-prefab", "runtime-prefab-fallbacks", "terrain-scene-prefabs", "scene-prefab-coverage", "scene-markers", "buildings", "readability-lights", "ambient-sounds", "scene-singletons", "ballistic-tracers", "muzzle-flash-prefab", "grenade-effects", "team-voice-prefabs", "team-comms-prefab", "training-dummy-prefab", "thrown-grenade-projectile", "stock-scene-props", "transient-combat", "scene", "blue-lines", "terrain", "collision", "collision-chain", "nav", "asset", "asset-production", "modeldoc", "blender-live", "sound", "networking", "gameplay-regression", "docs", "api", "sbox-docs", "release-notes", "code-search", "learn", "editor-node-tool", "editor-first", "balance", "playtest", "logs", "readiness", "train", "self-test")]
    [string]$Suite = "quick",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Invoke-AgentScript {
    param(
        [string]$Name,
        [string[]]$ScriptArgs = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $Name
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "[Error] Missing script: $scriptPath"
        return 1
    }

    Write-Host ""
    Write-Host "---- Running $Name ----"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ScriptArgs 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    return $exitCode
}

$commonArgs = @("-Root", $Root)
if ($ShowInfo) {
    $commonArgs += "-ShowInfo"
}
if ($FailOnWarning) {
    $commonArgs += "-FailOnWarning"
}

$sceneMarkerArgs = $commonArgs + "-RequireMigrated"
$buildingSceneArgs = $commonArgs + "-RequireMigrated"
$readabilityLightArgs = $commonArgs + "-RequireMigrated"
$ambientSoundArgs = $commonArgs + "-RequireMigrated"
$sceneSingletonArgs = $commonArgs + "-RequireMigrated"

$quickLogArgs = @("-Root", $Root, "-ShowInfo")
if ($FailOnWarning) {
    $quickLogArgs += "-FailOnWarning"
}

$scripts = @()
switch ($Suite) {
    "quick" {
        $scripts = @(
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "sbox_whitelist_audit.ps1"; Args = $commonArgs },
            @{ Name = "gameplay_regression_guard.ps1"; Args = $commonArgs },
            @{ Name = "m4_fire_rate_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "held_item_prefab_template_audit.ps1"; Args = $commonArgs },
            @{ Name = "first_person_viewmodel_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_marker_prefab_audit.ps1"; Args = $sceneMarkerArgs },
            @{ Name = "stock_scene_prop_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "building_scene_prefab_audit.ps1"; Args = $buildingSceneArgs },
            @{ Name = "readability_light_scene_prefab_audit.ps1"; Args = $readabilityLightArgs },
            @{ Name = "ambient_sound_scene_prefab_audit.ps1"; Args = $ambientSoundArgs },
            @{ Name = "scene_singleton_prefab_audit.ps1"; Args = $sceneSingletonArgs },
            @{ Name = "terrain_scene_prefab_migration_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_prefab_coverage_audit.ps1"; Args = $commonArgs },
            @{ Name = "ballistic_tracer_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "muzzle_flash_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "grenade_effect_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_voice_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_comms_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "training_dummy_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "thrown_grenade_projectile_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "transient_combat_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "blockout_blue_line_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
            @{ Name = "tree_collision_audit.ps1"; Args = $commonArgs },
            @{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_agent_chain_audit.ps1"; Args = $commonArgs },
            @{ Name = "aaa_asset_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "modeldoc_audit.ps1"; Args = $commonArgs },
            @{ Name = "sound_asset_audit.ps1"; Args = $commonArgs },
            @{ Name = "ambient_noise_audit.ps1"; Args = $commonArgs },
            @{ Name = "sound_playback_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_label_copy_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "mcp_screenshot_audit.ps1"; Args = $commonArgs },
            @{ Name = "networking_review_audit.ps1"; Args = $commonArgs },
            @{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_docs_source_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_release_notes_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_code_search_audit.ps1"; Args = $commonArgs },
            @{ Name = "code_search_feature_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs },
            @{ Name = "current_log_audit.ps1"; Args = $quickLogArgs },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root) }
        )
    }
    "full" {
        $scripts = @(
            @{ Name = "test_full_automation_layer.ps1"; Args = @("-Root", $Root) },
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "sbox_whitelist_audit.ps1"; Args = $commonArgs },
            @{ Name = "gameplay_regression_guard.ps1"; Args = $commonArgs },
            @{ Name = "m4_fire_rate_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "held_item_prefab_template_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_marker_prefab_audit.ps1"; Args = $sceneMarkerArgs },
            @{ Name = "stock_scene_prop_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "building_scene_prefab_audit.ps1"; Args = $buildingSceneArgs },
            @{ Name = "readability_light_scene_prefab_audit.ps1"; Args = $readabilityLightArgs },
            @{ Name = "ambient_sound_scene_prefab_audit.ps1"; Args = $ambientSoundArgs },
            @{ Name = "scene_singleton_prefab_audit.ps1"; Args = $sceneSingletonArgs },
            @{ Name = "terrain_scene_prefab_migration_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_prefab_coverage_audit.ps1"; Args = $commonArgs },
            @{ Name = "ballistic_tracer_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "muzzle_flash_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "grenade_effect_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_voice_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_comms_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "training_dummy_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "thrown_grenade_projectile_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "transient_combat_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "blockout_blue_line_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
            @{ Name = "tree_collision_audit.ps1"; Args = $commonArgs },
            @{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_agent_chain_audit.ps1"; Args = $commonArgs },
            @{ Name = "aaa_asset_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "modeldoc_audit.ps1"; Args = $commonArgs },
            @{ Name = "fbx_material_slot_audit.ps1"; Args = $commonArgs },
            @{ Name = "sound_asset_audit.ps1"; Args = $commonArgs },
            @{ Name = "ambient_noise_audit.ps1"; Args = $commonArgs },
            @{ Name = "sound_playback_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_label_copy_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "mcp_screenshot_audit.ps1"; Args = $commonArgs },
            @{ Name = "networking_review_audit.ps1"; Args = $commonArgs },
            @{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_docs_source_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_release_notes_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_code_search_audit.ps1"; Args = $commonArgs },
            @{ Name = "code_search_feature_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs },
            @{ Name = "current_log_audit.ps1"; Args = $commonArgs },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") },
            @{ Name = "balance_tuning_report.ps1"; Args = @("-Root", $Root) },
            @{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "All") }
        )
    }
    "build" {
        $scripts = @(
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "sbox_whitelist_audit.ps1"; Args = $commonArgs }
        )
    }
    "ui" {
        $scripts = @(
            @{ Name = "team_label_copy_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "UI") },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
        )
    }
    "prefab" {
        $scripts = @(
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "held_item_prefab_template_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_marker_prefab_audit.ps1"; Args = $sceneMarkerArgs },
            @{ Name = "stock_scene_prop_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "building_scene_prefab_audit.ps1"; Args = $buildingSceneArgs },
            @{ Name = "readability_light_scene_prefab_audit.ps1"; Args = $readabilityLightArgs },
            @{ Name = "ambient_sound_scene_prefab_audit.ps1"; Args = $ambientSoundArgs },
            @{ Name = "scene_singleton_prefab_audit.ps1"; Args = $sceneSingletonArgs },
            @{ Name = "terrain_scene_prefab_migration_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_prefab_coverage_audit.ps1"; Args = $commonArgs },
            @{ Name = "ballistic_tracer_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "muzzle_flash_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "grenade_effect_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_voice_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "team_comms_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "training_dummy_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "thrown_grenade_projectile_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "transient_combat_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "runtime_prefab_fallback_audit.ps1"; Args = $commonArgs },
            @{ Name = "destroyed_pickup_prefab_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_visual_quality_audit.ps1"; Args = $commonArgs }
        )
    }
    "prefab-graph" { $scripts = @(@{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs }) }
    "held-items" { $scripts = @(@{ Name = "held_item_prefab_template_audit.ps1"; Args = $commonArgs }) }
    "viewmodel-prefab" { $scripts = @(@{ Name = "first_person_viewmodel_prefab_audit.ps1"; Args = $commonArgs }) }
    "runtime-prefab-fallbacks" { $scripts = @(@{ Name = "runtime_prefab_fallback_audit.ps1"; Args = $commonArgs }) }
    "terrain-scene-prefabs" { $scripts = @(@{ Name = "terrain_scene_prefab_migration_audit.ps1"; Args = $commonArgs }) }
    "scene-prefab-coverage" { $scripts = @(@{ Name = "scene_prefab_coverage_audit.ps1"; Args = $commonArgs }) }
    "scene-markers" { $scripts = @(@{ Name = "scene_marker_prefab_audit.ps1"; Args = $sceneMarkerArgs }) }
    "buildings" { $scripts = @(@{ Name = "building_scene_prefab_audit.ps1"; Args = $buildingSceneArgs }) }
    "readability-lights" { $scripts = @(@{ Name = "readability_light_scene_prefab_audit.ps1"; Args = $readabilityLightArgs }) }
    "ambient-sounds" { $scripts = @(@{ Name = "ambient_sound_scene_prefab_audit.ps1"; Args = $ambientSoundArgs }) }
    "scene-singletons" { $scripts = @(@{ Name = "scene_singleton_prefab_audit.ps1"; Args = $sceneSingletonArgs }) }
    "ballistic-tracers" { $scripts = @(@{ Name = "ballistic_tracer_prefab_audit.ps1"; Args = $commonArgs }) }
    "muzzle-flash-prefab" { $scripts = @(@{ Name = "muzzle_flash_prefab_audit.ps1"; Args = $commonArgs }) }
    "grenade-effects" { $scripts = @(@{ Name = "grenade_effect_prefab_audit.ps1"; Args = $commonArgs }) }
    "team-voice-prefabs" { $scripts = @(@{ Name = "team_voice_prefab_audit.ps1"; Args = $commonArgs }) }
    "team-comms-prefab" { $scripts = @(@{ Name = "team_comms_prefab_audit.ps1"; Args = $commonArgs }) }
    "training-dummy-prefab" { $scripts = @(@{ Name = "training_dummy_prefab_audit.ps1"; Args = $commonArgs }) }
    "thrown-grenade-projectile" { $scripts = @(@{ Name = "thrown_grenade_projectile_prefab_audit.ps1"; Args = $commonArgs }) }
    "stock-scene-props" { $scripts = @(@{ Name = "stock_scene_prop_prefab_audit.ps1"; Args = $commonArgs }) }
    "transient-combat" { $scripts = @(@{ Name = "transient_combat_prefab_audit.ps1"; Args = $commonArgs }) }
    "scene" {
        $scripts = @(
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "blockout_blue_line_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "floating_center_ladder_audit.ps1"; Args = $commonArgs },
            @{ Name = "sandbag_cover_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_cover_barrier_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_lane_marking_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_edge_wear_audit.ps1"; Args = $commonArgs },
            @{ Name = "destroyed_pickup_scene_audit.ps1"; Args = $commonArgs },
            @{ Name = "building_scene_prefab_audit.ps1"; Args = $buildingSceneArgs },
            @{ Name = "readability_light_scene_prefab_audit.ps1"; Args = $readabilityLightArgs },
            @{ Name = "ambient_sound_scene_prefab_audit.ps1"; Args = $ambientSoundArgs },
            @{ Name = "scene_singleton_prefab_audit.ps1"; Args = $sceneSingletonArgs },
            @{ Name = "level_layout_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
            @{ Name = "tree_collision_audit.ps1"; Args = $commonArgs },
            @{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs }
        )
    }
    "blue-lines" { $scripts = @(@{ Name = "blockout_blue_line_audit.ps1"; Args = $commonArgs }) }
    "terrain" { $scripts = @(@{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs }) }
    "collision" {
        $scripts = @(
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
            @{ Name = "tree_collision_audit.ps1"; Args = $commonArgs },
            @{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs },
            @{ Name = "floating_center_ladder_audit.ps1"; Args = $commonArgs },
            @{ Name = "level_layout_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_agent_chain_audit.ps1"; Args = $commonArgs }
        )
    }
    "nav" { $scripts = @(@{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs }) }
    "collision-chain" {
        $scripts = @(
            @{ Name = "collision_agent_chain_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_chain_report.ps1"; Args = $commonArgs }
        )
    }
    "asset" {
        $scripts = @(
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_variant_visual_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_fpv_propeller_texture_audit.ps1"; Args = $commonArgs },
            @{ Name = "fbx_material_slot_audit.ps1"; Args = $commonArgs }
        )
    }
    "modeldoc" {
        $scripts = @(
            @{ Name = "modeldoc_audit.ps1"; Args = $commonArgs },
            @{ Name = "fbx_material_slot_audit.ps1"; Args = $commonArgs }
        )
    }
    "asset-production" {
        $scripts = @(
            @{ Name = "aaa_asset_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "blender_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "material_texture_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_variant_visual_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_fpv_propeller_texture_audit.ps1"; Args = $commonArgs },
            @{ Name = "modeldoc_audit.ps1"; Args = $commonArgs },
            @{ Name = "fbx_material_slot_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
        )
    }
    "blender-live" { $scripts = @(@{ Name = "blender_live_toolkit_self_test.ps1"; Args = @("-Root", $Root) }) }
    "sound" {
        $scripts = @(
            @{ Name = "sound_asset_audit.ps1"; Args = $commonArgs },
            @{ Name = "ambient_noise_audit.ps1"; Args = $commonArgs },
            @{ Name = "sound_playback_audit.ps1"; Args = $commonArgs }
        )
    }
    "networking" { $scripts = @(@{ Name = "networking_review_audit.ps1"; Args = $commonArgs }) }
    "gameplay-regression" { $scripts = @(@{ Name = "gameplay_regression_guard.ps1"; Args = $commonArgs }) }
    "docs" {
        $scripts = @(
            @{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_docs_source_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_release_notes_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_code_search_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_variant_visual_audit.ps1"; Args = $commonArgs }
        )
    }
    "sbox-docs" { $scripts = @(@{ Name = "sbox_docs_source_audit.ps1"; Args = $commonArgs }) }
    "release-notes" {
        $scripts = @(
            @{ Name = "sbox_release_notes_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs }
        )
    }
    "code-search" {
        $scripts = @(
            @{ Name = "sbox_code_search_audit.ps1"; Args = $commonArgs },
            @{ Name = "code_search_feature_audit.ps1"; Args = $commonArgs },
            @{ Name = "nav_collision_qa_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs }
        )
    }
    "api" {
        $scripts = @(
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_lookup.ps1"; Args = @("-Root", $Root, "-Query", "SyncAttribute", "-Limit", "5") }
        )
    }
    "learn" {
        $scripts = @(
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs }
        )
    }
    "editor-node-tool" { $scripts = @(@{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs }) }
    "editor-first" { $scripts = @(@{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs }) }
    "balance" {
        $scripts = @(
            @{ Name = "m4_fire_rate_audit.ps1"; Args = $commonArgs },
            @{ Name = "balance_tuning_report.ps1"; Args = @("-Root", $Root) }
        )
    }
    "playtest" { $scripts = @(@{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "All") }) }
    "logs" { $scripts = @(@{ Name = "current_log_audit.ps1"; Args = $commonArgs }) }
    "readiness" { $scripts = @(@{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }) }
    "train" {
        $scripts = @(
            @{ Name = "post_task_training_agent.ps1"; Args = @("-Root", $Root, "-ShowFiles", "-WriteReport") },
            @{ Name = "aaa_asset_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_docs_source_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_release_notes_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_code_search_audit.ps1"; Args = $commonArgs },
            @{ Name = "code_search_feature_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_visual_quality_audit.ps1"; Args = $commonArgs }
        )
    }
    "self-test" { $scripts = @(@{ Name = "test_full_automation_layer.ps1"; Args = @("-Root", $Root) }) }
}

$failed = New-Object System.Collections.Generic.List[string]
foreach ($script in $scripts) {
    $exitCode = Invoke-AgentScript -Name $script.Name -ScriptArgs $script.Args
    if ($exitCode -ne 0) {
        $failed.Add("$($script.Name) exited $exitCode")
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "Agent check suite '$Suite' failed:"
    $failed | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Agent check suite '$Suite' completed."
