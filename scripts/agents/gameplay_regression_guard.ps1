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

Write-AgentSection "Gameplay Regression Guard"
Write-Host "Root: $Root"

function Invoke-GuardScript {
    param(
        [string]$RelativePath,
        [string[]]$ScriptArgs = @()
    )

    $scriptPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Add-AgentIssue $issues "Error" "Gameplay Regression" $RelativePath "Required guard script is missing." "Restore the script or remove it from gameplay_regression_guard.ps1 intentionally."
        return
    }

    Push-Location $Root
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ScriptArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $outputText = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        $summary = if ([string]::IsNullOrWhiteSpace($outputText)) {
            "Script exited with $exitCode."
        }
        else {
            ($outputText -split [Environment]::NewLine | Select-Object -First 1)
        }

        Add-AgentIssue $issues "Error" "Gameplay Regression" $RelativePath $summary "Fix the regression check before continuing gameplay or HUD work."
        return
    }

    Add-AgentIssue $issues "Info" "Gameplay Regression" $RelativePath "Passed."
}

Invoke-GuardScript -RelativePath "scripts\check_loadout_slots.ps1" -ScriptArgs @("-PrefabDir", (Join-Path $Root "Assets\prefabs"))
Invoke-GuardScript -RelativePath "scripts\check_drone_kamikaze_primary.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_drone_explosion_feedback.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_drone_weapon_arming.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_ground_crouch_toggle.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_ground_sprint_toggle.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_hud_sprint_meter.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_hud_damage_arc_attribution.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_ui_scale_default.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\check_first_person_viewmodel_spawn.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\agents\drone_propeller_spin_audit.ps1" -ScriptArgs @("-Root", $Root)
Invoke-GuardScript -RelativePath "scripts\agents\grenade_physics_fx_audit.ps1" -ScriptArgs @("-Root", $Root)

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
