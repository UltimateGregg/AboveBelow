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

Write-AgentSection "First-Person Viewmodel Prefab Audit"

$scriptPath = Join-Path $Root "scripts\check_first_person_viewmodel_spawn.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Add-AgentIssue $issues "Error" "First-Person Viewmodel Prefab" "scripts/check_first_person_viewmodel_spawn.ps1" "Required guard script is missing." "Restore the guard before changing first-person viewmodel prefab contracts."
}
else {
    Push-Location $Root
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Root $Root 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $outputText = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        $summary = if ([string]::IsNullOrWhiteSpace($outputText)) {
            "Guard exited with $exitCode."
        }
        else {
            ($outputText -split [Environment]::NewLine | Select-Object -First 1)
        }

        Add-AgentIssue $issues "Error" "First-Person Viewmodel Prefab" "scripts/check_first_person_viewmodel_spawn.ps1" $summary "Fix the viewmodel prefab guard before continuing first-person item prefab work."
    }
    else {
        Add-AgentIssue $issues "Info" "First-Person Viewmodel Prefab" "scripts/check_first_person_viewmodel_spawn.ps1" "First-person viewmodel prefab guard passed."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
