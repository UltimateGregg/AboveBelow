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
        Add-AgentIssue $issues "Error" "Team Voice Prefabs" $RelativePath "Required file is missing." "Restore the file before auditing team voice prefab ownership."
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
        Add-AgentIssue $issues "Error" "Team Voice Prefabs" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Team Voice Prefab Audit"

foreach ($prefabPath in @(
    "Assets/prefabs/soldier.prefab",
    "Assets/prefabs/soldier_assault.prefab",
    "Assets/prefabs/soldier_heavy.prefab",
    "Assets/prefabs/pilot_ground.prefab"
)) {
    $text = Get-Text $prefabPath
    Assert-Pattern $prefabPath $text '"__type"\s*:\s*"DroneVsPlayers\.TeamVoice"' "Character prefab is missing TeamVoice." "Keep shared team voice routing on the prefab root instead of adding it only at spawn time."
    Assert-Pattern $prefabPath $text '"TeamOnly"\s*:\s*true' "TeamVoice should default to team-only routing." "Keep voice traffic scoped to teammates unless a design pass changes this deliberately."
    Assert-Pattern $prefabPath $text '"RoleAwareRouting"\s*:\s*true' "TeamVoice should default to role-aware radio/proximity routing." "Keep pilot radio and hunter proximity behavior on the prefab contract."
}

$setupPath = "Code/Game/GameSetup.cs"
$setupText = Get-Text $setupPath
Assert-Pattern $setupPath $setupText 'Components\.Get<TeamVoice>\(\s*FindMode\.EverythingInSelfAndDescendants\s*\)' "GameSetup should look for prefab-authored TeamVoice before adding a fallback." "Prefer prefab-authored TeamVoice while keeping fallback repair for legacy or broken prefabs."
Assert-Pattern $setupPath $setupText 'Components\.Create<TeamVoice>\(\)' "GameSetup should keep a TeamVoice fallback." "Do not strand voice routing if a prefab is temporarily missing TeamVoice during iteration."
Assert-Pattern $setupPath $setupText 'voice\.Setup\s*=\s*this' "GameSetup should assign itself to TeamVoice." "Keep spawned voice components connected to the authoritative team setup."
Assert-Pattern $setupPath $setupText 'voice\.ApplyVoiceRoutingProfile\(\)' "GameSetup should apply the voice routing profile after spawn." "Keep prefab-authored TeamVoice configured after the pawn owner and role are known."

Add-AgentIssue $issues "Info" "Team Voice Prefabs" "Assets/prefabs" "Non-jammer character TeamVoice prefab check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
