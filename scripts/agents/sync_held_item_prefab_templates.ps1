param(
    [string]$Root = "",
    [switch]$Check
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "sync_held_item_prefab_templates.js"
$nodeArgs = @($scriptPath, "-Root", $Root)
if ($Check) {
    $nodeArgs += "-Check"
}

& node @nodeArgs
exit $LASTEXITCODE
