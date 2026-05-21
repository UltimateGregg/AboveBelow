param(
    [string]$Root = ".",
    [int]$ExpectedSeconds = 180
)

$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]
$expectedFloat = "${ExpectedSeconds}f"

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

$gameRules = Read-ProjectFile "Code/Game/GameRules.cs"
$roundManager = Read-ProjectFile "Code/Game/RoundManager.cs"
$scene = Read-ProjectFile "Assets/scenes/main.scene"
$gameplayLoop = Read-ProjectFile "docs/gameplay_loop.md"
$gameRulesScenePattern = '"__type"\s*:\s*"DroneVsPlayers\.GameRules"[\s\S]{0,2400}"RoundTimeSeconds"\s*:\s*' + $ExpectedSeconds + '\b'
$roundManagerScenePattern = '"__type"\s*:\s*"DroneVsPlayers\.RoundManager"[\s\S]{0,1600}"RoundLengthSeconds"\s*:\s*' + $ExpectedSeconds + '\b'
$gameplayLoopPattern = "\|\s*Active round\s*\|\s*$ExpectedSeconds s\s*\|\s*" + [regex]::Escape('`GameRules.RoundTimeSeconds`')

Require-Match "GameRules should default active round time to $ExpectedSeconds seconds." `
    $gameRules "\bRoundTimeSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*$ExpectedSeconds\s*;"

Require-Match "RoundManager fallback round length should default to $ExpectedSeconds seconds." `
    $roundManager "\bRoundLengthSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*$expectedFloat\s*;"

Require-Match "RoundManager should still apply GameRules.RoundTimeSeconds to runtime round length." `
    $roundManager "RoundLengthSeconds\s*=\s*Rules\.RoundTimeSeconds\s*;"

Require-Match "Main scene GameRules should serialize RoundTimeSeconds as $ExpectedSeconds." `
    $scene $gameRulesScenePattern

Require-Match "Main scene RoundManager should serialize RoundLengthSeconds as $ExpectedSeconds." `
    $scene $roundManagerScenePattern

Require-Match "Gameplay loop docs should describe the active round as $ExpectedSeconds seconds." `
    $gameplayLoop $gameplayLoopPattern

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Match length check passed."
