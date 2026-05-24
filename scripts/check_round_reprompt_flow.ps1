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
        Add-AgentIssue $issues "Error" "Round Re-Prompt" $RelativePath "Required file is missing." "Restore the file before checking round flow."
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
        Add-AgentIssue $issues "Error" "Round Re-Prompt" $Path $Message $Recommendation
    }
}

function Require-NotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Path,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -match $Pattern) {
        Add-AgentIssue $issues "Error" "Round Re-Prompt" $Path $Message $Recommendation
    }
}

Write-AgentSection "Round Re-Prompt Flow"
Write-Host "Root: $Root"

$setupPath = "Code\Game\GameSetup.cs"
$roundPath = "Code\Game\RoundManager.cs"
$hudPath = "Code\UI\HudPanel.razor"
$gameplayDocPath = "docs\gameplay_loop.md"
$architectureDocPath = "docs\architecture.md"
$testingDocPath = "TESTING_GUIDE.md"

$setup = Read-ProjectText $setupPath
$round = Read-ProjectText $roundPath
$hud = Read-ProjectText $hudPath
$gameplayDoc = Read-ProjectText $gameplayDocPath
$architectureDoc = Read-ProjectText $architectureDocPath
$testingDoc = Read-ProjectText $testingDocPath

Require-Match $setup '\[Sync\]\s+public\s+int\s+SelectionGeneration\s*\{\s*get;\s*set;\s*\}' $setupPath `
    "GameSetup must expose a synced selection generation for round-reset UI refresh." `
    "Add a [Sync] SelectionGeneration that increments when the host reopens team/loadout selection."

Require-Match $setup 'public\s+void\s+BeginNextRoundSelection\s*\(' $setupPath `
    "GameSetup must provide a host-owned next-round selection reset method." `
    "Add BeginNextRoundSelection() to despawn old pawns, clear teams, and broadcast local loadout clearing."

Require-Match $setup '(?s)BeginNextRoundSelection\s*\([^)]*\)\s*\{.*DespawnPawn\s*\(.*ClearLocalLoadoutChoice\s*\(' $setupPath `
    "Next-round selection reset must despawn old pawns and clear local client loadout choices." `
    "Destroy stale pawns/drones before showing the picker so clients cannot keep playing the previous round pawn."

$clearChoiceMethod = [regex]::Match($setup, '(?s)\[Rpc\.Broadcast\]\s*\r?\n\s*void\s+ClearLocalLoadoutChoice\s*\([^)]*\)\s*\{.*?\n\s*\}')
if (-not $clearChoiceMethod.Success) {
    Add-AgentIssue $issues "Error" "Round Re-Prompt" $setupPath "GameSetup must broadcast a client-local loadout reset." "Add ClearLocalLoadoutChoice as a [Rpc.Broadcast] method."
}
else {
    Require-Match $clearChoiceMethod.Value '_hasLocalLoadout\s*=\s*false' $setupPath `
        "Client-local loadout reset must clear the queued loadout flag." `
        "Set _hasLocalLoadout = false so the next round cannot auto-spawn the previous choice."
    Require-Match $clearChoiceMethod.Value '_selectedLocalRole\s*=\s*PlayerRole\.Spectator' $setupPath `
        "Client-local loadout reset must clear the selected role." `
        "Reset _selectedLocalRole to Spectator when reopening selection."
}

Require-Match $setup 'public\s+bool\s+HasReadyPlayers\s*\(\s*int\s+minPlayers\s*\)' $setupPath `
    "RoundManager needs a GameSetup readiness check before countdown." `
    "Expose HasReadyPlayers(minPlayers) so countdown waits for required clients to choose and receive pawns."

Require-NotMatch $setup '(?s)if\s*\(\s*RequireRoleChoice\s*&&\s*isLocalConnection\s*\).*?// Auto-fill smaller team for non-local connections' $setupPath `
    "GameSetup still auto-fills non-local clients while role choice is required." `
    "When RequireRoleChoice is true, every connection should wait for its own RequestSpawn selection."

$waitingCase = [regex]::Match($round, '(?s)case\s+RoundState\.WaitingForPlayers\s*:.*?break\s*;')
if (-not $waitingCase.Success) {
    Add-AgentIssue $issues "Error" "Round Re-Prompt" $roundPath "RoundManager WaitingForPlayers case is missing." "Restore the round state machine before checking readiness."
}
else {
    Require-Match $waitingCase.Value 'IsReadyToStartRound\s*\(' $roundPath `
        "WaitingForPlayers must wait for selected/spawned players before countdown." `
        "Gate EnterCountdown() through a readiness helper, not just Connection.All.Count."
}

Require-Match $round '(?s)bool\s+IsReadyToStartRound\s*\(\s*\)\s*\{.*Connection\.All\.Count\s*<\s*MinPlayers.*Setup\.HasReadyPlayers\s*\(\s*MinPlayers\s*\)' $roundPath `
    "Round readiness helper must require both minimum connections and GameSetup ready players." `
    "Have IsReadyToStartRound() check Connection.All.Count and Setup.HasReadyPlayers(MinPlayers)."

$resetMethod = [regex]::Match($round, '(?s)void\s+ResetForNextRound\s*\(\s*\)\s*\{.*?\n\s*\}')
if (-not $resetMethod.Success) {
    Add-AgentIssue $issues "Error" "Round Re-Prompt" $roundPath "ResetForNextRound method is missing." "Restore the round reset method."
}
else {
    Require-Match $resetMethod.Value 'Setup\.BeginNextRoundSelection\s*\(' $roundPath `
        "Round reset must reopen selection through GameSetup." `
        "Call Setup.BeginNextRoundSelection() instead of immediately respawning saved loadouts."
    Require-Match $resetMethod.Value 'EnterWaitingForPlayers\s*\(' $roundPath `
        "Round reset must return to WaitingForPlayers." `
        "Return to WaitingForPlayers so the next countdown waits for fresh choices."
    Require-NotMatch $resetMethod.Value 'RespawnWithSelectedLoadout|PromotePilot' $roundPath `
        "Round reset still respawns previous loadouts automatically." `
        "Remove automatic next-round respawns from ResetForNextRound; the picker should drive the next spawn."
}

Require-Match $hud 'ObservedSelectionGeneration' $hudPath `
    "HudPanel must reset its local loadout picker state when GameSetup opens a new selection generation." `
    "Track Setup.SelectionGeneration and reset SelectedLoadoutTeam/slot when it changes."

Require-NotMatch $gameplayDoc 'Next Round:\s+Respawns players with their latest selected soldier class / drone variant' $gameplayDocPath `
    "Gameplay loop docs still describe next-round auto-respawn." `
    "Document that next round reopens team/class/variant selection."

Require-NotMatch $architectureDoc 'Respawns each player with their latest selected class or drone variant' $architectureDocPath `
    "Architecture docs still describe next-round auto-respawn." `
    "Document the selection reset and readiness gate."

Require-NotMatch $testingDoc 'Next round prompts class picker again \(or uses legacy auto-respawn fallback\)' $testingDocPath `
    "Testing guide still allows the legacy auto-respawn fallback." `
    "Make next-round re-prompt a required test expectation."

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Round Re-Prompt" "" "Static round re-prompt contract is present."
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
