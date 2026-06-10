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

function Test-FilePattern {
    param(
        [string]$Path,
        [string]$Area,
        [string]$Pattern,
        [string]$Message,
        [string]$Recommendation
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $Path "Required file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    if ($text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" $Area $Path $Message $Recommendation
        return
    }

    Add-AgentIssue $issues "Info" $Area $Path $Message
}

Write-AgentSection "Balance Config Audit"
Write-Host "Root: $Root"

Test-FilePattern `
    -Path "Code/Game/BalanceConfigResource.cs" `
    -Area "Balance Config" `
    -Pattern 'AssetType\([\s\S]*Extension\s*=\s*"dvpbalance"[\s\S]*class\s+BalanceConfigResource\s*:\s*GameResource' `
    -Message "BalanceConfigResource should be a DVP GameResource with the .dvpbalance extension." `
    -Recommendation "Create a centralized balance resource before adding more prefab-only tuning."

foreach ($section in @(
    "MatchBalanceSettings",
    "SoldierBalanceSettings",
    "DroneBalanceSettings",
    "WeaponBalanceSettings",
    "JammerBalanceSettings",
    "GrenadeBalanceSettings"
)) {
    Test-FilePattern `
        -Path "Code/Game/BalanceConfigResource.cs" `
        -Area "Balance Config" `
        -Pattern ("class\s+" + [regex]::Escape($section)) `
        -Message "BalanceConfigResource should expose $section." `
        -Recommendation "Keep match, pawn, weapon, jammer, and grenade tuning in the central balance resource."
}

Test-FilePattern `
    -Path "Code/Game/GameRules.cs" `
    -Area "Balance Config" `
    -Pattern 'BalanceConfigResource\s+BalanceConfig[\s\S]*GetActiveBalanceConfig\s*\([\s\S]*ApplyBalanceConfig\s*\(' `
    -Message "GameRules should own the active balance config and apply match-level values." `
    -Recommendation "Route active match settings through GameRules instead of duplicating defaults in prefabs and docs."

Test-FilePattern `
    -Path "Code/Game/BalanceApplier.cs" `
    -Area "Balance Application" `
    -Pattern 'static\s+class\s+BalanceApplier[\s\S]*ApplyPilotGround[\s\S]*ApplySoldier[\s\S]*ApplyDrone[\s\S]*ApplyTrainingDummy' `
    -Message "BalanceApplier should provide focused application methods for spawned runtime objects." `
    -Recommendation "Use a helper seam so GameSetup and DroneDeployer do not grow more balance-application logic."

Test-FilePattern `
    -Path "Code/Game/GameSetup.Spawning.cs" `
    -Area "Balance Application" `
    -Pattern 'BalanceApplier\.ApplyPilotGround[\s\S]*BalanceApplier\.ApplySoldier[\s\S]*BalanceApplier\.ApplyTrainingDummy' `
    -Message "GameSetup should apply central balance to pilot, soldier, and solo dummy spawns." `
    -Recommendation "Apply central balance immediately after cloning runtime pawns."

Test-FilePattern `
    -Path "Code/Player/DroneDeployer.cs" `
    -Area "Balance Application" `
    -Pattern 'BalanceApplier\.ApplyDrone' `
    -Message "DroneDeployer should apply central balance to launched drones." `
    -Recommendation "Apply drone balance when the runtime drone clone is created, not only through prefab defaults."

Test-FilePattern `
    -Path "scripts/agents/balance_tuning_report.ps1" `
    -Area "Balance Report" `
    -Pattern 'BalanceConfigResource\.cs|BalanceConfig Defaults' `
    -Message "Balance report should include centralized BalanceConfig defaults." `
    -Recommendation "Keep balance reporting centered on the authoritative data source."

Test-FilePattern `
    -Path "scripts/agents/run_agent_checks.ps1" `
    -Area "Suite Wiring" `
    -Pattern 'balance_config_audit\.ps1' `
    -Message "The balance suite should run the centralized balance audit." `
    -Recommendation "Wire balance_config_audit.ps1 into run_agent_checks.ps1 -Suite balance."

Test-FilePattern `
    -Path "docs/balance_rps.md" `
    -Area "Balance Docs" `
    -Pattern 'BalanceConfig|\.dvpbalance' `
    -Message "Balance docs should name the centralized balance resource." `
    -Recommendation "Document that prefab values are spawn defaults and the balance resource is the tuning owner."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
