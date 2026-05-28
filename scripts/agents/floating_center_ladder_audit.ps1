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
$sceneRelative = "Assets/scenes/main.scene"
$scenePath = Join-Path $Root $sceneRelative

function Get-AllSceneObjects {
    param($Object)

    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @($Object.Children)) {
        $objects += Get-AllSceneObjects -Object $child
    }

    return $objects
}

if (-not (Test-Path -LiteralPath $scenePath)) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Main scene is missing." "Restore Assets/scenes/main.scene before validating scene ladder policy."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Get-Content -LiteralPath $scenePath -Raw | ConvertFrom-Json
}
catch {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Scene JSON could not be parsed: $($_.Exception.Message)" "Fix scene JSON before validating scene ladder policy."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllSceneObjects -Object $rootObject
}

$ladderObjects = @($allObjects | Where-Object { $_.Name -like "*FloatingCenterLadder*" })
if ($ladderObjects.Count -gt 0) {
    $names = ($ladderObjects | ForEach-Object { $_.Name }) -join ", "
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder content is not allowed in the main scene: $names." "Remove the floating center ladder; this map should not require or regenerate it."
}
elseif ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Floating Center Ladder" $sceneRelative "No FloatingCenterLadder content is present."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
