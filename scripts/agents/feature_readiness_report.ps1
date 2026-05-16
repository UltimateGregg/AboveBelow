param(
    [string]$Root = "",
    [switch]$ShowFiles,
    [string]$OutFile = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Text = ""
    )
    $Lines.Add($Text)
}

$changed = @(Get-AgentChangedFiles -Root $Root | Where-Object {
    $_.Path -notmatch "^\.superpowers/brainstorm/"
})
$areas = [ordered]@{
    Gameplay = New-Object System.Collections.Generic.List[string]
    Networking = New-Object System.Collections.Generic.List[string]
    PrefabScene = New-Object System.Collections.Generic.List[string]
    AssetPipeline = New-Object System.Collections.Generic.List[string]
    ModelDoc = New-Object System.Collections.Generic.List[string]
    UI = New-Object System.Collections.Generic.List[string]
    Balance = New-Object System.Collections.Generic.List[string]
    Docs = New-Object System.Collections.Generic.List[string]
    Tooling = New-Object System.Collections.Generic.List[string]
}

foreach ($file in $changed) {
    $path = $file.Path
    $isAgentTooling = $path -match "^scripts/agents/|^\.agents/|^\.codex/|^docs/agent_toolkit\.md$"
    $isProductionAssetTool = $path -match "^scripts/blender_asset_audit\.py$|^scripts/render_asset_preview\.py$|^scripts/asset_quality_profiles\.json$|^scripts/agents/(blender_quality_audit|material_texture_audit|asset_visual_review|new_asset_brief)\.ps1$"
    $isAssetPipelineDoc = $path -match "^docs/(asset_pipeline|automation)\.md$"
    $isModelDocTooling = $path -match "^scripts/agents/modeldoc_audit\.ps1$|^\.agents/sbox/modeldoc-|^docs/agent_toolkit\.md$"

    if ($isAgentTooling) {
        $areas.Tooling.Add($path)
        if ($isProductionAssetTool) {
            $areas.AssetPipeline.Add($path)
        }
        if ($isModelDocTooling) {
            $areas.ModelDoc.Add($path)
        }
        if ($path -match "\.md$|^docs/") {
            $areas.Docs.Add($path)
        }
        continue
    }

    if ($path -match "^Code/(Game|Player|Drone|Equipment|Common)/") {
        $areas.Gameplay.Add($path)
    }
    if ($path -match "^Code/(Game|Player|Drone|Equipment)/" -or $path -match "Network|Rpc|Sync") {
        $areas.Networking.Add($path)
    }
    if ($path -match "^Assets/(prefabs|scenes)/" -or $path -match "^Code/code/Wiring/") {
        $areas.PrefabScene.Add($path)
    }
    if ($path -match "\.blend" -or $path -match "^Assets/(models|materials|sounds)/" -or $path -match "^scripts/.*asset_pipeline.*\.json$|^scripts/(asset_pipeline|smart_asset_export|scaffold_asset_config)" -or $isAssetPipelineDoc) {
        $areas.AssetPipeline.Add($path)
    }
    if ($path -match "^Assets/models/.*\.vmdl$" -or $isModelDocTooling) {
        $areas.ModelDoc.Add($path)
    }
    if ($isProductionAssetTool) {
        $areas.AssetPipeline.Add($path)
        $areas.Tooling.Add($path)
    }
    if ($path -match "^Code/UI/|^Assets/ui/|\.razor|\.scss") {
        $areas.UI.Add($path)
    }
    if ($path -match "GameRules|balance|soldier_|drone_|weapon|grenade|HitscanWeapon|ShotgunWeapon|DroneWeapon|DroneJammerGun") {
        $areas.Balance.Add($path)
    }
    if ($path -match "^(docs/|README\.md|ROADMAP\.md|TESTING_GUIDE\.md|WIRING\.md|AGENTS\.md|CLAUDE\.md)") {
        $areas.Docs.Add($path)
    }
}

$touchesDroneControlFlow = @($changed | Where-Object {
    $_.Path -match "^(Code/(Drone/DroneWeapon|Player/(DroneDeployer|PilotSoldier|RemoteController))\.cs|Code/UI/HudPanel\.razor|Assets/prefabs/(drone_fpv|drone_fpv_fiber|pilot_ground)\.prefab|scripts/(check_drone_kamikaze_primary|check_loadout_slots)\.ps1)"
}).Count -gt 0

$lines = New-Object System.Collections.Generic.List[string]
Add-Line $lines "# Feature Readiness Report"
Add-Line $lines ""
Add-Line $lines "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Line $lines ""

if ($changed.Count -eq 0) {
    Add-Line $lines "No git working-tree changes detected."
}
else {
    Add-Line $lines "Detected $($changed.Count) changed path(s)."
}
Add-Line $lines ""

Add-Line $lines "## Areas"
Add-Line $lines ""
foreach ($key in $areas.Keys) {
    $count = $areas[$key].Count
    Add-Line $lines ("- {0}: {1}" -f $key, $count)
}
Add-Line $lines ""

if ($ShowFiles) {
    Add-Line $lines "## Changed Files"
    Add-Line $lines ""
    foreach ($file in $changed) {
        Add-Line $lines "- [$($file.Status)] $($file.Path)"
    }
    Add-Line $lines ""
}

Add-Line $lines "## Required Checks"
Add-Line $lines ""
Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1`'

if ($areas.Gameplay.Count -gt 0 -or $touchesDroneControlFlow) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1`'
}

if ($areas.PrefabScene.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1`'
}
if ($areas.AssetPipeline.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1 -ShowInfo`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production`'
}
if ($areas.ModelDoc.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc`'
}
if ($areas.UI.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1`'
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI`'
}
if ($areas.Networking.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1`'
    Add-Line $lines "- [ ] 2-client local playtest for RPC/[Sync]/ownership behavior"
}
if ($areas.Balance.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1`'
}
if ($areas.Docs.Count -gt 0 -or $areas.Tooling.Count -gt 0) {
    Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1`'
}
Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh` after editor playtest, if runtime behavior changed'
Add-Line $lines ""

Add-Line $lines "## Manual Test Focus"
Add-Line $lines ""
if ($areas.Gameplay.Count -gt 0) {
    Add-Line $lines "- Gameplay: class/variant selection, combat path touched by the change, round-end behavior."
}
if ($touchesDroneControlFlow) {
    Add-Line $lines "- Drone controls: FPV and Fiber FPV launch on ground-side LMB, second ground-side LMB or F enters drone view, and only drone-view LMB detonates."
}
if ($areas.Networking.Count -gt 0) {
    Add-Line $lines "- Networking: host-only mutations, replicated state, remote client visuals/notifications."
}
if ($areas.PrefabScene.Count -gt 0) {
    Add-Line $lines "- Prefab/scene: editor load, AutoWire results, spawn points, collider gizmos."
}
if ($areas.AssetPipeline.Count -gt 0) {
    Add-Line $lines "- Assets: save/export loop, model/material reload, missing/error material check."
    Add-Line $lines "- Multi-material foliage: editor inspector shows the intended model, no default material fallback, and no scene `MaterialOverride` or `Materials.indexed` on tree instances."
}
if ($areas.ModelDoc.Count -gt 0) {
    Add-Line $lines "- ModelDoc: source mesh path, material remap, owning config drift, FBX material slots, and `use_global_default` fallback."
}
if ($areas.UI.Count -gt 0) {
    Add-Line $lines "- UI: startup flow, only-live menu actions, 1280x720 HUD fit, class picker, scoreboard, kill feed, loadout state."
}
if ($areas.Balance.Count -gt 0) {
    Add-Line $lines "- Balance: counter-triangle smoke test and before/after tuning notes."
}
if ($areas.Tooling.Count -gt 0) {
    Add-Line $lines '- Tooling: run `scripts/agents/test_full_automation_layer.ps1` and the full agent suite.'
}
if ($changed.Count -eq 0) {
    Add-Line $lines "- No changed files detected; choose checks based on the intended work area."
}

$text = $lines -join [Environment]::NewLine
if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $target = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $Root $OutFile }
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    $text | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Host "Wrote readiness report: $(ConvertTo-AgentRelativePath -Path $target -Root $Root)"
}
else {
    Write-Host $text
}
