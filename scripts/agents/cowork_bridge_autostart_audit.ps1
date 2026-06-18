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

Write-AgentSection "Cowork Bridge Autostart Audit"

$bridgePath = "Editor/CoworkBridge.cs"
$fullBridgePath = Join-Path $Root $bridgePath
if (-not (Test-Path -LiteralPath $fullBridgePath)) {
    Add-AgentIssue $issues "Error" "CoworkBridge" $bridgePath "CoworkBridge source is missing." "Restore the editor bridge source or remove the fallback bridge workflow."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$text = Get-Content -LiteralPath $fullBridgePath -Raw

$requiredPatterns = @(
    @{
        Area = "Autostart State"
        Pattern = 'static\s+bool\s+_autoStartAttempted\s*;'
        Message = "Missing one-shot autostart state."
        Recommendation = "Track whether the editor-frame autostart already ran so failures do not spam every frame."
    },
    @{
        Area = "Autostart Entry"
        Pattern = 'static\s+void\s+EnsureStartedForEditorFrame\s*\(\s*\)'
        Message = "Missing editor-frame autostart helper."
        Recommendation = "Add a helper that attempts Start() once from the editor frame pump."
    },
    @{
        Area = "Frame Pump"
        Pattern = '(?s)\[EditorEvent\.Frame\]\s*static\s+void\s+Pump\s*\(\s*\)\s*\{\s*EnsureStartedForEditorFrame\s*\(\s*\)\s*;\s*while\s*\('
        Message = "The editor frame pump does not attempt CoworkBridge startup before draining requests."
        Recommendation = "Call EnsureStartedForEditorFrame() at the top of Pump() so the bridge starts when the editor loads."
    },
    @{
        Area = "Autostart Behavior"
        Pattern = '(?s)static\s+void\s+EnsureStartedForEditorFrame\s*\(\s*\)\s*\{.*if\s*\(\s*_autoStartAttempted\s*\).*_autoStartAttempted\s*=\s*true\s*;.*if\s*\(\s*IsRunning\s*\).*Start\s*\(\s*\)\s*;.*\}'
        Message = "Autostart helper is not clearly one-shot and Start()-backed."
        Recommendation = "Guard with _autoStartAttempted, mark it true, skip if already running, then call Start()."
    }
)

foreach ($check in $requiredPatterns) {
    if ($text -notmatch $check.Pattern) {
        Add-AgentIssue $issues "Error" $check.Area $bridgePath $check.Message $check.Recommendation
    }
}

$stopMatch = [regex]::Match($text, '(?s)\[Menu\(\s*"Editor"\s*,\s*"Cowork/Stop MCP Bridge"\s*\)\]\s*public\s+static\s+void\s+Stop\s*\(\s*\)\s*\{(?<body>.*?)\n\t\}')
if (-not $stopMatch.Success) {
    Add-AgentIssue $issues "Error" "Manual Stop" $bridgePath "Could not find the manual CoworkBridge Stop() menu handler." "Keep a manual stop command available for the fallback bridge."
}
elseif ($stopMatch.Groups["body"].Value -match '_autoStartAttempted\s*=\s*false\s*;') {
    Add-AgentIssue $issues "Error" "Manual Stop" $bridgePath "Stop() resets autostart state, so the frame pump can immediately restart after a manual stop." "Leave _autoStartAttempted true when Stop() is called; manual Start remains the explicit restart path."
}

$runnerPath = "scripts/agents/run_agent_checks.ps1"
$fullRunnerPath = Join-Path $Root $runnerPath
if (-not (Test-Path -LiteralPath $fullRunnerPath)) {
    Add-AgentIssue $issues "Error" "Suite Wiring" $runnerPath "Agent check runner is missing." "Restore run_agent_checks.ps1 and wire cowork_bridge_autostart_audit.ps1 into the editor-first suite."
}
else {
    $runnerText = Get-Content -LiteralPath $fullRunnerPath -Raw
    if ($runnerText -notmatch 'cowork_bridge_autostart_audit\.ps1') {
        Add-AgentIssue $issues "Error" "Suite Wiring" $runnerPath "Editor-first checks do not run the CoworkBridge autostart audit." "Wire cowork_bridge_autostart_audit.ps1 into Suite editor-first."
    }
}

Add-AgentIssue $issues "Info" "CoworkBridge" "" "Checked one-shot editor-frame autostart, manual Stop behavior, and editor-first suite wiring." ""

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
