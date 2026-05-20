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

Write-AgentSection "MCP Screenshot Audit"
Write-Host "Root: $Root"

$handlerPath = Join-Path $Root "Libraries\jtc.mcp-server\Editor\Handlers\EditorHandler.cs"
if (-not (Test-Path -LiteralPath $handlerPath)) {
    Add-AgentIssue $issues "Error" "MCP Screenshot" "Libraries/jtc.mcp-server/Editor/Handlers/EditorHandler.cs" "Editor MCP handler is missing." "Restore the native editor MCP handler source."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$text = Get-Content -LiteralPath $handlerPath -Raw

if ($text -match 'GetParameters\(\)\.Length\s*==\s*2[\s\S]{0,220}RenderToPixmap') {
    Add-AgentIssue $issues "Error" "MCP Screenshot" "Libraries/jtc.mcp-server/Editor/Handlers/EditorHandler.cs" "Screenshot render lookup still assumes a two-parameter RenderToPixmap extension." "Current S&Box exposes RenderToPixmap(CameraComponent, Pixmap, bool); accept both the legacy 2-param and current 3-param shapes."
}

if ($text -notmatch 'RenderToPixmap' -or $text -notmatch '\.Length\s*==\s*3' -or $text -notmatch 'new object\[\]\s*\{\s*camera,\s*pixmap,\s*false\s*\}') {
    Add-AgentIssue $issues "Error" "MCP Screenshot" "Libraries/jtc.mcp-server/Editor/Handlers/EditorHandler.cs" "Screenshot handler is not guarded for the current three-parameter RenderToPixmap signature." "Find and invoke RenderToPixmap(CameraComponent, Pixmap, bool) with a false final argument."
}

Add-AgentIssue $issues "Info" "MCP Screenshot" "Libraries/jtc.mcp-server" "Checked editor_take_screenshot against current S&Box RenderToPixmap API shape."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
