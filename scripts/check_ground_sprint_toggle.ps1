param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]

function Read-ProjectFile {
    param([string]$Path)

    $fullPath = Join-Path $Root $Path
    if (!(Test-Path -LiteralPath $fullPath)) {
        $failures.Add("Missing file: $Path")
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Require-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if (![regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

function Reject-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if ([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

$controller = Read-ProjectFile "Code/Player/GroundPlayerController.cs"

Require-Match "GroundPlayerController should store sprint as a local toggle state." `
    $controller "\bbool\s+_sprintToggled\b"

Require-Match "GroundPlayerController should toggle sprint from a Run press edge." `
    $controller "Input\.Pressed\(\s*""Run""\s*\)[\s\S]{0,220}_sprintToggled\s*=\s*!\s*_sprintToggled"

Require-Match "GroundPlayerController should keep sprint intent separate from held Run input." `
    $controller "IsSprinting\s*=\s*_sprintToggled\s*&&\s*hasMoveInput\s*&&\s*canSprint"

Require-Match "GroundPlayerController should clear latched sprint when stamina is below the sprint threshold." `
    $controller "if\s*\(\s*!hasStamina\s*\)[\s\S]{0,90}_sprintToggled\s*=\s*false"

Require-Match "GroundPlayerController should clear latched sprint when movement input stops." `
    $controller "if\s*\(\s*!hasMoveInput\s*\)[\s\S]{0,90}_sprintToggled\s*=\s*false"

Require-Match "GroundPlayerController should use the faster arcade sprint limit." `
    $controller "StaminaMaxSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*4f"

Require-Match "GroundPlayerController should use the faster arcade sprint recovery." `
    $controller "StaminaRefillSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*3f"

Require-Match "GroundPlayerController should expose sprint exhaustion cooldown tuning." `
    $controller "SprintCooldownSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*0\.75f"

Require-Match "GroundPlayerController should expose the stamina threshold required to resume sprint after exhaustion." `
    $controller "StaminaResumeThreshold\s*\{\s*get;\s*set;\s*\}\s*=\s*0\.20f"

Require-Match "GroundPlayerController should sync sprint lock state for HUD and gameplay." `
    $controller "\[Sync\]\s+public\s+bool\s+IsSprintLocked\s*\{\s*get;\s*set;\s*\}"

Require-Match "GroundPlayerController should lock sprint and clear sprint intent when stamina is exhausted." `
    $controller "Stamina\s*<=\s*0f[\s\S]{0,220}IsSprintLocked\s*=\s*true[\s\S]{0,220}ClearSprintIntent\(\)"

Require-Match "GroundPlayerController should keep stamina from recovering during the exhaustion cooldown." `
    $controller "IsSprintLocked\s*&&\s*_timeSinceSprintLocked\s*<\s*SprintCooldownSeconds"

Require-Match "GroundPlayerController should unlock sprint only after the resume threshold is recovered." `
    $controller "Stamina\s*>=\s*StaminaResumeThreshold[\s\S]{0,120}IsSprintLocked\s*=\s*false"

Reject-Match 'Ground sprint should not be held directly by Input.Down("Run").' `
    $controller "var\s+wantsSprint\s*=\s*Input\.Down\(\s*""Run""\s*\)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Ground sprint toggle check passed."
