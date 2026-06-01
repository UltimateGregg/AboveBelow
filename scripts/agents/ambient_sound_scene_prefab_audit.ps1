param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning,
    [switch]$RequireMigrated
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "ambient_sound_scene_prefab_audit.js"
$nodeArgs = @($scriptPath, "--root", $Root)
if ($ShowInfo) {
    $nodeArgs += "--show-info"
}
if ($FailOnWarning) {
    $nodeArgs += "--fail-on-warning"
}
if ($RequireMigrated) {
    $nodeArgs += "--require-migrated"
}

& node @nodeArgs
exit $LASTEXITCODE
