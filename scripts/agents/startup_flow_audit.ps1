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

Write-AgentSection "Startup Flow Audit"
Write-Host "Root: $Root"

function Read-StartupText {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Startup Flow" $RelativePath "Required file is missing." "Restore the startup runtime flow file before auditing."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

$setupPath = "Code/Game/GameSetup.cs"
$setupText = Read-StartupText $setupPath
if (-not [string]::IsNullOrWhiteSpace($setupText)) {
    $skipMatch = [regex]::Match($setupText, 'bool\s+ShouldSkipRuntimeScene\s*\(\s*\)\s*\{(?<body>[\s\S]*?)\n\s*\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $skipMatch.Success) {
        Add-AgentIssue $issues "Error" "Startup Flow" $setupPath "GameSetup.ShouldSkipRuntimeScene is missing." "Keep startup gating centralized so editor-play and packaged startup flow share one audited path."
    }
    else {
        $body = $skipMatch.Groups["body"].Value
        if ($body -match 'return\s+Scene\.IsEditor\s*;') {
            Add-AgentIssue $issues "Error" "Startup Flow" $setupPath "GameSetup skips runtime startup for every editor scene, including editor play." "Gate editor-only skips with Game.IsPlaying so play-in-editor still starts networking, role choice, HUD menu, and pawn camera handoff."
        }

        if ($body -notmatch 'Game\.IsPlaying') {
            Add-AgentIssue $issues "Error" "Startup Flow" $setupPath "GameSetup startup gating does not account for editor play mode." "Use Game.IsPlaying with Scene.IsEditor instead of relying on a hidden debug inspector toggle."
        }
    }
}

$prefabPath = "Assets/prefabs/systems/game_manager.prefab"
$prefabText = Read-StartupText $prefabPath
if (-not [string]::IsNullOrWhiteSpace($prefabText)) {
    if ($prefabText -match '"EditorRuntimePlaytestEnabled"\s*:\s*true') {
        Add-AgentIssue $issues "Warning" "Startup Flow" $prefabPath "GameManager prefab relies on the debug editor-runtime override." "Keep startup working through runtime gating so the main menu does not depend on a hidden debug checkbox."
    }

    if ($prefabText -notmatch '"RequireRoleChoice"\s*:\s*true') {
        Add-AgentIssue $issues "Error" "Startup Flow" $prefabPath "GameManager prefab does not require role choice on startup." "Keep the HUD startup menu visible until the local player picks a role and loadout."
    }
}

$hudPath = "Code/UI/HudPanel.razor"
$hudText = Read-StartupText $hudPath
if (-not [string]::IsNullOrWhiteSpace($hudText)) {
    if ($hudText -notmatch 'bool\s+NeedsRoleChoice\s*=>\s*Setup\?\.NeedsLocalRoleChoice\(\)\s*\?\?\s*false') {
        Add-AgentIssue $issues "Error" "Startup Flow" $hudPath "HUD startup menu is not driven by GameSetup.NeedsLocalRoleChoice()." "Keep menu visibility tied to the authoritative startup role-choice state."
    }

    if ($hudText -notmatch 'bool\s+ShowMainMenuShell\s*=>\s*NeedsRoleChoice\s*&&') {
        Add-AgentIssue $issues "Error" "Startup Flow" $hudPath "Main menu shell is not gated by NeedsRoleChoice." "Render the startup menu while the local player still needs role choice."
    }
}

Add-AgentIssue $issues "Info" "Startup Flow" $setupPath "Startup flow contract check completed."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
