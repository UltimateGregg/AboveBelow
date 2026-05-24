param(
    [string]$Root = ""
)

. "$PSScriptRoot\agents\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

function Read-ProjectText {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Two-Client Lobby Flow" $RelativePath "Required file is missing." "Restore the file or update this guard intentionally."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Require-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Path,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Two-Client Lobby Flow" $Path $Message $Recommendation
    }
}

Write-AgentSection "Two-Client Lobby Flow"
Write-Host "Root: $Root"

$setupPath = "Code\Game\GameSetup.cs"
$debugPath = "Code\Game\RoundFlowDebugCommands.cs"
$gameplayGuardPath = "scripts\agents\gameplay_regression_guard.ps1"
$testingGuidePath = "TESTING_GUIDE.md"
$agentToolkitPath = "docs\agent_toolkit.md"

$setup = Read-ProjectText $setupPath
$debug = Read-ProjectText $debugPath
$gameplayGuard = Read-ProjectText $gameplayGuardPath
$testingGuide = Read-ProjectText $testingGuidePath
$agentToolkit = Read-ProjectText $agentToolkitPath

Require-Match $setup 'JoinExistingEditorLobbyOnStart' $setupPath `
    "GameSetup needs an editor two-client join-first toggle." `
    "Add a property that lets editor play sessions try an existing lobby before creating a new one."

Require-Match $setup '(?s)TryJoinExistingEditorLobby\s*\(.*?\).*?Networking\.CreateLobby' $setupPath `
    "GameSetup must attempt the editor join path before creating a new lobby." `
    "In OnLoad, try JoinBestLobby for the current project ident in editor play before falling back to CreateLobby."

Require-Match $setup 'Project\.Current\??\.Config\??\.FullIdent' $setupPath `
    "Editor lobby join should use the current project full ident." `
    "Use Project.Current.Config.FullIdent so the second editor joins the same project lobby instead of an unrelated target."

Require-Match $setup 'Networking\.JoinBestLobby\s*\(' $setupPath `
    "GameSetup does not call Networking.JoinBestLobby." `
    "Try joining an existing editor lobby before creating a host lobby."

Require-Match $setup 'Networking\.QueryLobbies\s*\(\s*filters' $setupPath `
    "GameSetup should have a queried-lobby fallback for editor sessions." `
    "Use the same game-filtered lobby query pattern as the S&Box menu before creating a second local host."

Require-Match $setup 'Networking\.TryConnectSteamId\s*\(\s*lobby\.LobbyId\s*\)' $setupPath `
    "Queried editor lobby fallback should connect with the lobby id." `
    "Use TryConnectSteamId(lobby.LobbyId), matching S&Box menu code, not the lobby owner id."

Require-Match $setup 'Networking\.SetData\s*\(\s*"dvp_local_editor"' $setupPath `
    "Host editor lobbies should mark themselves as local editor sessions." `
    "Set lobby data after CreateLobby so probes and future tooling can distinguish local editor sessions."

Require-Match $setup '(?s)OnDestroy\s*\(\s*\).*?Networking\.Disconnect\s*\(' $setupPath `
    "Editor play stop should disconnect stale local networking sessions." `
    "Disconnect editor play sessions on GameSetup destruction so the next proof attempt does not reuse a stale host/client singleton."

Require-Match $setup '\[Sync\]\s+public\s+string\s+EditorAutodriveMode' $setupPath `
    "GameSetup should expose DEBUG synced editor autodrive state." `
    "Use synced GameSetup state so a host console command can drive the second editor without file IO or Roslyn scripting."

Require-Match $setup 'EditorDebugSnapshot' $setupPath `
    "GameSetup should expose a DEBUG snapshot for MCP component_get proof." `
    "Expose connection, team, pawn, score, and round state through a read-only debug property."

Require-Match $debug '\[ConCmd\(\s*"dvp_round_probe"' $debugPath `
    "Missing round-flow probe console command." `
    "Add dvp_round_probe so MCP console_run can write a runtime snapshot when Roslyn scripting is unavailable."

Require-Match $debug '\[ConCmd\(\s*"dvp_select_soldier"' $debugPath `
    "Missing soldier selection console command." `
    "Add dvp_select_soldier to drive the same GameSetup selection path during local two-client proof."

Require-Match $debug '\[ConCmd\(\s*"dvp_select_drone"' $debugPath `
    "Missing drone selection console command." `
    "Add dvp_select_drone to drive the same GameSetup selection path during local two-client proof."

Require-Match $debug '\[ConCmd\(\s*"dvp_kill_team"' $debugPath `
    "Missing team elimination console command." `
    "Add dvp_kill_team so the round end and re-prompt path can be tested without relying on manual aim."

Require-Match $debug '\[ConCmd\(\s*"dvp_connect_local"' $debugPath `
    "Missing direct local connect probe command." `
    "Keep a DEBUG command that calls Networking.Connect/TryConnect paths directly when built-in console commands are unavailable through MCP."

Require-Match $debug '(?s)\[RoundProbe\].*connections=' $debugPath `
    "Probe output should include a parseable [RoundProbe] log line." `
    "Log connection, team, round, score, and pawn state so current log checks can prove the runtime state."

Require-Match $debug 'SteamId' $debugPath `
    "Probe output should include SteamId details for local two-editor diagnosis." `
    "Log SteamId/address so agents can distinguish real two-peer failures from same-account local editor limits."

Require-Match $debug '\[ConCmd\(\s*"dvp_round_autodrive"' $debugPath `
    "Missing host-driven autodrive console command." `
    "Add dvp_round_autodrive so one MCP-controlled host can drive loadout choices on both editor processes."

Require-Match $gameplayGuard 'check_two_client_lobby_flow\.ps1' $gameplayGuardPath `
    "Gameplay regression guard does not run the two-client lobby flow guard." `
    "Wire scripts/check_two_client_lobby_flow.ps1 into gameplay_regression_guard.ps1."

Require-Match $testingGuide 'dvp_round_probe' $testingGuidePath `
    "Testing guide is missing the two-client probe commands." `
    "Document the local two-editor proof commands and expected log probe output."

Require-Match $testingGuide 'same `SteamId`' $testingGuidePath `
    "Testing guide should document same-account two-editor blockers." `
    "Call out same SteamId/lobby-query/socket-bind symptoms so agents do not misreport environment failures as gameplay passes."

Require-Match $agentToolkit 'check_two_client_lobby_flow\.ps1' $agentToolkitPath `
    "Agent toolkit is missing the two-client lobby guard." `
    "Document the guard and runtime probe workflow for future agents."

Require-Match $agentToolkit 'EditorDebugSnapshot' $agentToolkitPath `
    "Agent toolkit should document the component snapshot proof surface." `
    "Tell agents to use GameSetup.EditorDebugSnapshot through MCP component_get for live two-editor state."

$mcpAutoStartPath = "Libraries\jtc.mcp-server\Editor\McpAutoStart.cs"
$mcpEditorSessionPath = "Libraries\jtc.mcp-server\Editor\Handlers\EditorSession.cs"
$mcpEditorHandlerPath = "Libraries\jtc.mcp-server\Editor\Handlers\EditorHandler.cs"
$mcpAutoStart = Read-ProjectText $mcpAutoStartPath
$mcpEditorSession = Read-ProjectText $mcpEditorSessionPath
$mcpEditorHandler = Read-ProjectText $mcpEditorHandlerPath

Require-Match $mcpAutoStart 'DefaultPort\s*\+\s*offset' $mcpAutoStartPath `
    "MCP autostart should try fallback ports for multiple open editors." `
    "Probe each editor over its own MCP endpoint instead of assuming only localhost:29015 exists."

Require-Match $mcpEditorSession 'TryPlayNative' $mcpEditorSessionPath `
    "MCP editor_play should expose the native editor play path." `
    "Use EditorScene.Play before SetPlaying fallback so components tick and Networking starts."

Require-Match $mcpEditorHandler 'EditorScene\.Play' $mcpEditorHandlerPath `
    "MCP editor_play should report/use the native play method." `
    "Prefer native EditorScene.Play so local editor proof is not a half-play scene."

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Two-Client Lobby Flow" "" "Static two-client lobby/probe contract is present."
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
