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
        Add-AgentIssue $issues "Error" "Startup Camera Lift" $RelativePath "Required file is missing." "Add the planned startup camera lift code or prefab wiring."
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
        Add-AgentIssue $issues "Error" "Startup Camera Lift" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Startup Camera Lift Audit"

$codePath = "Code/Game/StartupCameraLift.cs"
$codeText = Read-AgentText $codePath
if (-not [string]::IsNullOrWhiteSpace($codeText)) {
    Assert-Pattern $codePath $codeText 'public\s+sealed\s+class\s+StartupCameraLift\s*:\s*Component' "StartupCameraLift component class is missing or not sealed." "Add a sealed S&Box Component for the startup camera lift."
    Assert-Pattern $codePath $codeText 'Range\(\s*0f\s*,\s*5000f\s*\)\]\s*public\s+float\s+LiftDistanceUnits' "LiftDistanceUnits range must allow the 200-foot lift default." "Keep the inspector range wide enough for 2400 S&Box units."
    Assert-Pattern $codePath $codeText 'LiftDistanceUnits\s*\{\s*get;\s*set;\s*\}\s*=\s*2400f' "LiftDistanceUnits must default to 2400 units." "Keep the requested 200-foot lift as 2400 S&Box units."
    Assert-Pattern $codePath $codeText 'DurationSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*6f' "DurationSeconds must default to 6 seconds." "Keep the 200-foot lift at half the previous movement speed."
    Assert-Pattern $codePath $codeText 'ExternalMoveTolerance\s*\{\s*get;\s*set;\s*\}\s*=\s*1f' "ExternalMoveTolerance must default to 1 unit." "Stop the lift if another camera driver takes ownership."
    Assert-Pattern $codePath $codeText 'Vector3\.Up\s*\*\s*LiftDistanceUnits' "Lift must move vertically in world Z." "Use world vertical lift, not camera-local forward/up."
    Assert-Pattern $codePath $codeText 't\s*\*\s*t\s*\*\s*\(\s*3f\s*-\s*2f\s*\*\s*t\s*\)' "Lift must use smoothstep interpolation." "Smooth the startup camera movement instead of snapping or linear-only movement."
    Assert-Pattern $codePath $codeText 'WorldPosition\.Distance\s*\(\s*_lastAppliedPosition\s*\)\s*>\s*ExternalMoveTolerance' "Lift must detect external camera movement." "Do not fight player or drone camera controllers after they move the camera."
}

$prefabPath = "Assets/prefabs/systems/main_camera.prefab"
$prefabText = Read-AgentText $prefabPath
if (-not [string]::IsNullOrWhiteSpace($prefabText)) {
    Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.StartupCameraLift"' "main_camera prefab is missing StartupCameraLift." "Attach the startup lift component to the camera prefab, not a direct scene-only object."
    Assert-Pattern $prefabPath $prefabText '"LiftDistanceUnits"\s*:\s*2400' "main_camera prefab must set LiftDistanceUnits to 2400." "Keep the prefab default aligned with the requested 200-foot lift."
    Assert-Pattern $prefabPath $prefabText '"DurationSeconds"\s*:\s*6' "main_camera prefab must set DurationSeconds to 6." "Keep the prefab default aligned with the requested half-speed lift."
    Assert-Pattern $prefabPath $prefabText '"ExternalMoveTolerance"\s*:\s*1' "main_camera prefab must set ExternalMoveTolerance to 1." "Keep the prefab default aligned with controller handoff tolerance."
}

Add-AgentIssue $issues "Info" "Startup Camera Lift" $codePath "Startup camera lift contract check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
