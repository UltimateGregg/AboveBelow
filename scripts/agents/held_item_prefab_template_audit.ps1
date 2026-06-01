param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "held_item_prefab_template_audit.js"
$nodeArgs = @($scriptPath, "-Root", $Root)
if ($ShowInfo) {
    $nodeArgs += "-ShowInfo"
}
if ($FailOnWarning) {
    $nodeArgs += "-FailOnWarning"
}

& node @nodeArgs
exit $LASTEXITCODE
