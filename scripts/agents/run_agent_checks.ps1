param(
    [string]$Root = "",
    [ValidateSet("quick", "full", "build", "ui", "prefab", "prefab-graph", "scene", "terrain", "collision", "collision-chain", "asset", "asset-production", "modeldoc", "blender-live", "sound", "networking", "gameplay-regression", "docs", "api", "learn", "editor-node-tool", "editor-first", "balance", "playtest", "logs", "readiness", "train", "self-test")]
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

$quickLogArgs = @("-Root", $Root, "-ShowInfo")
if ($FailOnWarning) {
    $quickLogArgs += "-FailOnWarning"
}

$scripts = @()
switch ($Suite) {
    "quick" {
        $scripts = @(
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "gameplay_regression_guard.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
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
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
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
            @{ Name = "gameplay_regression_guard.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
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
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
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
    "build" { $scripts = @(@{ Name = "build_log_sentinel.ps1"; Args = $commonArgs }) }
    "ui" {
        $scripts = @(
            @{ Name = "team_label_copy_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "UI") },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
        )
    }
    "prefab" { $scripts = @(@{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs }) }
    "prefab-graph" { $scripts = @(@{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs }) }
    "scene" {
        $scripts = @(
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs },
            @{ Name = "floating_center_ladder_audit.ps1"; Args = $commonArgs },
            @{ Name = "sandbag_cover_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_cover_barrier_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_lane_marking_audit.ps1"; Args = $commonArgs },
            @{ Name = "road_edge_wear_audit.ps1"; Args = $commonArgs },
            @{ Name = "burnt_vehicle_block_audit.ps1"; Args = $commonArgs },
            @{ Name = "level_layout_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs }
        )
    }
    "terrain" { $scripts = @(@{ Name = "terrain_floor_audit.ps1"; Args = $commonArgs }) }
    "collision" {
        $scripts = @(
            @{ Name = "collision_authoring_agent.ps1"; Args = $commonArgs },
            @{ Name = "floating_center_ladder_audit.ps1"; Args = $commonArgs },
            @{ Name = "level_layout_audit.ps1"; Args = $commonArgs },
            @{ Name = "collision_agent_chain_audit.ps1"; Args = $commonArgs }
        )
    }
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
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs },
            @{ Name = "drone_variant_visual_audit.ps1"; Args = $commonArgs }
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
    "balance" { $scripts = @(@{ Name = "balance_tuning_report.ps1"; Args = @("-Root", $Root) }) }
    "playtest" { $scripts = @(@{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "All") }) }
    "logs" { $scripts = @(@{ Name = "current_log_audit.ps1"; Args = $commonArgs }) }
    "readiness" { $scripts = @(@{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }) }
    "train" {
        $scripts = @(
            @{ Name = "post_task_training_agent.ps1"; Args = @("-Root", $Root, "-ShowFiles", "-WriteReport") },
            @{ Name = "aaa_asset_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_engine_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_api_reference_audit.ps1"; Args = $commonArgs },
            @{ Name = "sbox_learn_intake_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_node_tool_audit.ps1"; Args = $commonArgs },
            @{ Name = "editor_first_workflow_audit.ps1"; Args = $commonArgs }
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
