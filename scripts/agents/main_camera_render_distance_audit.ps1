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

function Read-AgentText {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Main Camera Render Distance" $RelativePath "Required file is missing." "Restore the main camera prefab before auditing render distance."
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
        Add-AgentIssue $issues "Error" "Main Camera Render Distance" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Main Camera Render Distance Audit"

$prefabPath = "Assets/prefabs/systems/main_camera.prefab"
$prefabText = Read-AgentText $prefabPath
if (-not [string]::IsNullOrWhiteSpace($prefabText)) {
    Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.CameraComponent"' "main_camera prefab is missing CameraComponent." "Keep render-distance ownership on the main camera prefab."
    Assert-Pattern $prefabPath $prefabText '"ZFar"\s*:\s*50000' "main_camera ZFar must be 50000." "Increase the main camera far clip so the raised startup view can render the full arena."
    Assert-Pattern $prefabPath $prefabText '"ZNear"\s*:\s*10' "main_camera ZNear should remain 10." "Keep near clipping stable while increasing far distance."
}

Add-AgentIssue $issues "Info" "Main Camera Render Distance" $prefabPath "Main camera render-distance contract check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
