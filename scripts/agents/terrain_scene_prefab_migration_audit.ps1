param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Terrain Scene Prefab Migration Audit"

$migrationScript = Join-Path $PSScriptRoot "migrate_terrain_scene_objects_to_prefab_instances.ps1"
if (-not (Test-Path -LiteralPath $migrationScript)) {
    Add-AgentIssue $issues "Error" "Terrain Scene Prefab Migration" "scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1" "Required migration script is missing." "Restore the terrain scene prefab migration script or remove this audit intentionally."
}
else {
    Push-Location $Root
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $migrationScript -Root $Root -DryRun 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $outputText = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        $summary = if ([string]::IsNullOrWhiteSpace($outputText)) {
            "Migration dry-run exited with $exitCode."
        }
        else {
            ($outputText -split [Environment]::NewLine | Select-Object -First 1)
        }

        Add-AgentIssue $issues "Error" "Terrain Scene Prefab Migration" "scripts/agents/migrate_terrain_scene_objects_to_prefab_instances.ps1" $summary "Fix the migration dry-run before trusting terrain scene prefab state."
    }
    elseif ($outputText -notmatch 'Would migrate 0 scene object placement\(s\) to prefab instances\.') {
        Add-AgentIssue $issues "Error" "Terrain Scene Prefab Migration" "Assets/scenes/main.scene" $outputText "Run migrate_terrain_scene_objects_to_prefab_instances.ps1 intentionally so matching terrain, landform, and level-design scene objects stay prefab-backed."
    }
    else {
        Add-AgentIssue $issues "Info" "Terrain Scene Prefab Migration" "Assets/scenes/main.scene" "No shape-matching terrain scene objects remain expanded outside prefab instances."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
