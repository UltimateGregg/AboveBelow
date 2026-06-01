param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "sync_tree_branch_collisions.py"
$arguments = @($scriptPath, "--root", $Root, "--scene", $ScenePath)
if ($DryRun) {
    $arguments += "--dry-run"
}

python @arguments
exit $LASTEXITCODE
