param(
    [string]$Root = "",
    [switch]$DryRun
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "migrate_arena_boundaries_to_prefab_instances.js"
$nodeArgs = @($scriptPath, "--root", $Root)
if ($DryRun) {
    $nodeArgs += "--dry-run"
}

& node @nodeArgs
exit $LASTEXITCODE
