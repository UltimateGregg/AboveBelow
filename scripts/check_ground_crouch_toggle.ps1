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

Require-Match "GroundPlayerController should store crouch as a local toggle state." `
    $controller "\bbool\s+_crouchToggled\b"

Require-Match "GroundPlayerController should flip crouch state from a Duck press edge." `
    $controller "Input\.Pressed\(\s*""Duck""\s*\)[\s\S]{0,220}_crouchToggled\s*=\s*!\s*_crouchToggled"

Require-Match "GroundPlayerController crouch target should use the stored toggle state or force crouch while sliding." `
    $controller "var\s+wantsCrouch\s*=\s*\(_crouchToggled\s*\|\|\s*IsSliding\)\s*&&\s*!\s*IsProxy\s*&&\s*!\s*IsClimbingLadder"

Require-Match "GroundPlayerController should keep slide entry edge-detected from Duck input." `
    $controller "var\s+duckDown\s*=\s*!\s*inputBlocked\s*&&\s*Input\.Down\(\s*""Duck""\s*\)[\s\S]{0,140}var\s+duckPressed\s*=\s*duckDown\s*&&\s*!\s*_prevDuckDown"

Reject-Match 'Ground crouch target should not be held directly by Input.Down("Duck").' `
    $controller "var\s+wantsCrouch\s*=\s*\(\s*Input\.Down\(\s*""Duck""\s*\)\s*\|\|\s*IsSliding\s*\)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Ground crouch toggle check passed."
