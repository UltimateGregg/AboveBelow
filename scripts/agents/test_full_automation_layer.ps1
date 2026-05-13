param(
    [string]$Root = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

$requiredScripts = @(
    "scripts/agents/ui_flow_audit.ps1",
    "scripts/agents/prefab_graph_audit.ps1",
    "scripts/agents/scene_integrity_audit.ps1",
    "scripts/agents/current_log_audit.ps1",
    "scripts/agents/feature_readiness_report.ps1",
    "scripts/agents/blender_quality_audit.ps1",
    "scripts/agents/material_texture_audit.ps1",
    "scripts/agents/asset_visual_review.ps1",
    "scripts/agents/blender_live_toolkit_self_test.ps1"
)

foreach ($script in $requiredScripts) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $script))) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" $script "Required full-layer script is missing." "Create the script and wire it into run_agent_checks.ps1."
    }
}

$runner = Join-Path $Root "scripts/agents/run_agent_checks.ps1"
if (Test-Path -LiteralPath $runner) {
    $runnerText = Get-Content -LiteralPath $runner -Raw
    $validateSetMatch = [regex]::Match($runnerText, '\[ValidateSet\((?<values>[^\)]*)\)\]')
    if (-not $validateSetMatch.Success) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner does not declare a ValidateSet for suites." "Restore suite validation on the Suite parameter."
    }

    foreach ($suite in @("ui", "prefab-graph", "scene", "logs", "readiness", "asset-production", "blender-live")) {
        $quotedSuite = '"' + [regex]::Escape($suite) + '"'
        if ($validateSetMatch.Success -and $validateSetMatch.Groups["values"].Value -notmatch $quotedSuite) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner ValidateSet does not expose suite '$suite'." "Add the suite to the Suite parameter ValidateSet."
        }

        $switchCasePattern = '(?m)^\s*"' + [regex]::Escape($suite) + '"\s*\{'
        if ($runnerText -notmatch $switchCasePattern) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner does not wire switch case '$suite'." "Add the suite case to the switch block."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner script is missing." "Restore the runner."
}

foreach ($script in $requiredScripts) {
    if ($script -eq "scripts/agents/asset_visual_review.ps1") {
        continue
    }

    $full = Join-Path $Root $script
    if (-not (Test-Path -LiteralPath $full)) {
        continue
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $full -Root $Root | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" $script "Script exited with $LASTEXITCODE on the current project." "Fix the script or the issue it detected."
    }
}

$uiAudit = Join-Path $Root "scripts/agents/ui_flow_audit.ps1"
if (Test-Path -LiteralPath $uiAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-ui-flow-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\UI") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $fixturePath = Join-Path $tempRoot "Code\UI\Fixture.razor"
        '<root><div class="choice pilot">Dead Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit did not fail on a dead interactive-looking fixture." "Keep the fixture red/green test aligned with the audit rules."
        }

        '<root><div class="choice pilot" onclick=@DoThing>Live Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit failed on a fixture with an onclick handler." "Avoid false positives for valid clickable elements."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
