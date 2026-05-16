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

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
