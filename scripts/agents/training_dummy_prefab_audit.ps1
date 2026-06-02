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
        Add-AgentIssue $issues "Error" "Training Dummy Prefab" $RelativePath "Required file is missing." "Restore the file before auditing training dummy prefab ownership."
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
        Add-AgentIssue $issues "Error" "Training Dummy Prefab" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Training Dummy Prefab Audit"

$prefabPath = "Assets/prefabs/training_dummy.prefab"
$prefabText = Get-Text $prefabPath
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.TrainingDummy"' "Training dummy prefab should carry the TrainingDummy component." "Keep solo target behavior on the prefab root."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.NavMeshAgent"' "Training dummy prefab should carry NavMeshAgent." "Keep navmesh movement support on the prefab instead of relying only on runtime component creation."
Assert-Pattern $prefabPath $prefabText '"NavAgent"\s*:\s*\{[\s\S]*?"component_type"\s*:\s*"NavMeshAgent"' "TrainingDummy.NavAgent should reference the prefab-authored NavMeshAgent." "Wire the component reference in the prefab so runtime repair is only a fallback."

$codePath = "Code/Game/TrainingDummy.cs"
$codeText = Get-Text $codePath
Assert-Pattern $codePath $codeText 'Components\.Get<NavMeshAgent>\(\)' "TrainingDummy should still repair missing prefab NavMeshAgent." "Keep the repair fallback for legacy or damaged prefabs."
Assert-Pattern $codePath $codeText 'Components\.Create<NavMeshAgent>\(\)' "TrainingDummy should still create NavMeshAgent on host if missing." "Do not strand dummy movement when a prefab is temporarily broken."
Assert-Pattern $codePath $codeText 'NavAgent\.WishVelocity' "TrainingDummy should continue using NavMeshAgent movement output." "Keep navmesh movement behavior intact after prefab ownership changes."

Add-AgentIssue $issues "Info" "Training Dummy Prefab" $prefabPath "Training dummy prefab check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
