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

function Get-Text {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Team Comms Prefab" $RelativePath "Required file is missing." "Restore the file before auditing team comms prefab ownership."
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Assert-Pattern {
    param(
        [string]$RelativePath,
        [string]$Text,
        [string]$Pattern,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Team Comms Prefab" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Team Comms Prefab Audit"

$prefabPath = "Assets/prefabs/systems/game_manager.prefab"
$prefabText = Get-Text $prefabPath
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.TeamComms"' "GameManager prefab is missing TeamComms." "Keep shared team chat routing on the GameManager prefab instead of adding it only at runtime."
Assert-Pattern $prefabPath $prefabText '"EnableTeamChat"\s*:\s*true' "TeamComms should default team chat on." "Keep the shared team text-chat service enabled unless a design pass changes this deliberately."
Assert-Pattern $prefabPath $prefabText '"TeamPrefix"\s*:\s*"\[TEAM\]"' "TeamComms should keep the standard team prefix." "Keep team chat output recognizable for both teams."

$setupPath = "Code/Game/GameSetup.cs"
$setupText = Get-Text $setupPath
Assert-Pattern $setupPath $setupText 'Components\.Get<TeamComms>\(\)' "GameSetup should look for prefab-authored TeamComms before adding a fallback." "Prefer prefab-authored TeamComms while keeping runtime repair for legacy or damaged scenes."
Assert-Pattern $setupPath $setupText 'Components\.Create<TeamComms>\(\)' "GameSetup should keep a TeamComms fallback." "Do not strand team chat if a prefab is temporarily missing TeamComms during iteration."
Assert-Pattern $setupPath $setupText 'comms\.Setup\s*=\s*this' "GameSetup should assign itself to TeamComms." "Keep the shared team chat service connected to the authoritative team setup."

Add-AgentIssue $issues "Info" "Team Comms Prefab" $prefabPath "TeamComms prefab ownership check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
