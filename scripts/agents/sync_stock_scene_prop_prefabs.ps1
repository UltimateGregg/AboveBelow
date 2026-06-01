param(
    [string]$Root = "",
    [switch]$Check
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "sync_stock_scene_prop_prefabs.js"
$nodeArgs = @($scriptPath, "--root", $Root)
if ($Check) {
    $nodeArgs += "--check"
}

& node @nodeArgs
exit $LASTEXITCODE
