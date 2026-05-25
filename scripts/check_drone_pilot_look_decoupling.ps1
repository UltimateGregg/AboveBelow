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

$ground = Read-ProjectFile "Code/Player/GroundPlayerController.cs"
$remote = Read-ProjectFile "Code/Player/RemoteController.cs"
$guard = Read-ProjectFile "scripts/agents/gameplay_regression_guard.ps1"

Require-Match "GroundPlayerController should own a drone-view input block helper." `
    $ground "bool\s+IsDroneViewInputBlocked\(\)[\s\S]{0,360}RemoteController[\s\S]{0,240}DroneViewActive"

Require-Match "GroundPlayerController OnUpdate should block HandleLook while drone view is active." `
    $ground "var\s+inputBlocked\s*=\s*LocalOptionsState\.ConsumesGameplayInput\s*\|\|\s*IsDroneViewInputBlocked\(\)[\s\S]{0,260}if\s*\(\s*inputBlocked\s*\)[\s\S]{0,260}else[\s\S]{0,160}HandleLook\(\)"

Require-Match "GroundPlayerController OnFixedUpdate should block movement while drone view is active." `
    $ground "OnFixedUpdate\(\)[\s\S]{0,180}var\s+inputBlocked\s*=\s*LocalOptionsState\.ConsumesGameplayInput\s*\|\|\s*IsDroneViewInputBlocked\(\)[\s\S]{0,220}WishVelocity\s*=\s*Vector3\.Zero"

Reject-Match "RemoteController should not rely on disabling GroundPlayerController to block drone-view input." `
    $remote "_groundController\.Enabled\s*=\s*!\s*DroneViewActive"

Require-Match "Gameplay regression suite should run the drone pilot look decoupling guard." `
    $guard "scripts\\check_drone_pilot_look_decoupling\.ps1"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Drone pilot look decoupling check passed."
