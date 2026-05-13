param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Scene Integrity Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore the startup scene or update the audit scene path."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues)
}

$raw = Get-Content -LiteralPath $fullScenePath -Raw
if ($null -eq $raw) {
    $raw = ""
}

$requiredComponents = @(
    "DroneVsPlayers.GameRules",
    "DroneVsPlayers.GameStats",
    "DroneVsPlayers.GameSetup",
    "DroneVsPlayers.RoundManager",
    "DroneVsPlayers.AutoWireHelper",
    "DroneVsPlayers.HudPanel"
)

foreach ($type in $requiredComponents) {
    if ($raw -notmatch ('"__type"\s*:\s*"' + [regex]::Escape($type) + '"')) {
        Add-AgentIssue $issues "Error" "Scene Components" $relative "Missing required scene component '$type'." "Restore the GameManager/ScreenPanel setup in the editor."
    }
}

$pilotSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Pilot"').Count
$soldierSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Soldier"').Count
$allSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"').Count

if ($pilotSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Pilot PlayerSpawn components found." "Add at least one pilot spawn point."
}
if ($soldierSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Soldier PlayerSpawn components found." "Add at least one soldier spawn point."
}
if ($allSpawns -gt ($pilotSpawns + $soldierSpawns)) {
    Add-AgentIssue $issues "Warning" "Spawns" $relative "Some PlayerSpawn components do not declare Pilot or Soldier role." "Check spawn roles in the editor."
}

$devBoxBlocks = [regex]::Matches($raw, '"Model"\s*:\s*"models/dev/box\.vmdl"[\s\S]{0,1800}?"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,500}?"Scale"\s*:\s*"(?<scale>[^"]+)"')
$badColliderScales = 0
foreach ($match in $devBoxBlocks) {
    $scale = $match.Groups["scale"].Value
    if ($scale -ne "50,50,50") {
        $badColliderScales += 1
    }
}

if ($badColliderScales -gt 0) {
    Add-AgentIssue $issues "Warning" "Dev Box Colliders" $relative "$badColliderScales dev-box collider block(s) do not use local scale 50,50,50." "Run scripts/sync_box_colliders_to_renderers.ps1 -All -Apply after confirming these are blockout colliders."
}
else {
    Add-AgentIssue $issues "Info" "Dev Box Colliders" $relative "No obvious dev-box collider scale drift found."
}

$ladderBlocks = [regex]::Matches($raw, '"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,700}?"IsTrigger"\s*:\s*(?<trigger>true|false)[\s\S]{0,1200}?"__type"\s*:\s*"DroneVsPlayers\.LadderVolume"')
$solidLadderVolumes = 0
foreach ($match in $ladderBlocks) {
    if ($match.Groups["trigger"].Value -ne "true") {
        $solidLadderVolumes += 1
    }
}
if ($solidLadderVolumes -gt 0) {
    Add-AgentIssue $issues "Error" "Ladder Volumes" $relative "$solidLadderVolumes LadderVolume block(s) appear to use non-trigger colliders." "Ladder volumes should be trigger colliders so character movement can attach."
}

Add-AgentIssue $issues "Info" "Spawns" $relative "Found $pilotSpawns pilot spawn(s), $soldierSpawns soldier spawn(s), $allSpawns total PlayerSpawn component(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
