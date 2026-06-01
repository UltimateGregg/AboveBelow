param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [string]$McpUrl = "http://localhost:29015/mcp",
    [int]$Limit = 0,
    [switch]$ViewerOnly
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$scriptPath = Join-Path $PSScriptRoot "sync_tree_branch_collisions_live_editor.py"
$arguments = @($scriptPath, "--root", $Root, "--scene", $ScenePath, "--mcp", $McpUrl)
if ($Limit -gt 0) {
    $arguments += @("--limit", $Limit.ToString())
}
if ($ViewerOnly) {
    $arguments += "--viewer-only"
}

python @arguments
exit $LASTEXITCODE
