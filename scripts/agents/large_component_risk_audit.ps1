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

function Test-Pattern {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Area,
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

function Test-NotPattern {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Area,
        [string]$Message,
        [string]$Recommendation
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $Path "Required file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    if ($text -match $Pattern) {
        Add-AgentIssue $issues "Error" $Area $Path $Message $Recommendation
        return
    }

    Add-AgentIssue $issues "Info" $Area $Path $Message
}

Write-AgentSection "Large Component Risk Audit"
Write-Host "Root: $Root"

Test-Pattern `
    -Path "Code/Game/GameSetupPrefabResolver.cs" `
    -Pattern 'static\s+class\s+GameSetupPrefabResolver[\s\S]*ResolvePilotGroundPrefab[\s\S]*ResolveTrainingDummyPrefab[\s\S]*ResolveSoldierPrefab[\s\S]*ResolveDronePrefab' `
    -Area "GameSetup Extraction" `
    -Message "Prefab and loadout path resolution should live in GameSetupPrefabResolver." `
    -Recommendation "Extract prefab/loadout resolution out of GameSetup so spawn flow stays focused."

foreach ($gameSetupPart in @("Code/Game/GameSetup.cs", "Code/Game/GameSetup.Networking.cs", "Code/Game/GameSetup.Selection.cs", "Code/Game/GameSetup.Spawning.cs")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $gameSetupPart))) { continue }
    Test-NotPattern `
        -Path $gameSetupPart `
        -Pattern 'GameObject\s+Resolve(PilotGround|TrainingDummy|Soldier|Drone)Prefab\s*\(' `
        -Area "GameSetup Extraction" `
        -Message "GameSetup should not own bulky prefab resolver methods." `
        -Recommendation "Call GameSetupPrefabResolver from spawn code instead of keeping resolver implementations inside GameSetup."
}

Test-Pattern `
    -Path "Code/Game/GameSetup.Spawning.cs" `
    -Pattern 'GameSetupPrefabResolver\.ResolvePilotGroundPrefab[\s\S]*GameSetupPrefabResolver\.ResolveSoldierPrefab[\s\S]*GameSetupPrefabResolver\.ResolveTrainingDummyPrefab' `
    -Area "GameSetup Extraction" `
    -Message "GameSetup spawn paths should call the extracted prefab resolver." `
    -Recommendation "Use the helper in pilot, soldier, and solo dummy spawn paths."

Test-Pattern `
    -Path "docs/agent_toolkit.md" `
    -Pattern 'Large Component Risk Audit|large-component' `
    -Area "Tooling Docs" `
    -Message "Agent toolkit should document the large-component risk guard." `
    -Recommendation "Document the guard so future refactors preserve extracted seams."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
