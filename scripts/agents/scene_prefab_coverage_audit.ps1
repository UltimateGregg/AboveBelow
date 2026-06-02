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

$scriptPath = Join-Path $PSScriptRoot "scene_prefab_coverage_audit.js"
$nodeArgs = @($scriptPath, "--root", $Root)
if ($ShowInfo) {
    $nodeArgs += "--show-info"
}
if ($FailOnWarning) {
    $nodeArgs += "--fail-on-warning"
}

& node @nodeArgs
exit $LASTEXITCODE
