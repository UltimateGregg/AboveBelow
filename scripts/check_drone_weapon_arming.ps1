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

$remote = Read-ProjectFile "Code/Player/RemoteController.cs"
$controller = Read-ProjectFile "Code/Drone/DroneController.cs"
$weapon = Read-ProjectFile "Code/Drone/DroneWeapon.cs"
$guard = Read-ProjectFile "scripts/agents/gameplay_regression_guard.ps1"
$flightInputMethod = [regex]::Match(
    $controller,
    "public\s+static\s+bool\s+HasLocalFlightInput\(\)\s*\{(?<body>[\s\S]*?)\n\t\}",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
).Groups["body"].Value

Require-Match "RemoteController should expose a 3 second drone weapon auto-arm delay." `
    $remote "DroneWeaponAutoArmDelay\s*\{[^}]*\}\s*=\s*3f"

Require-Match "RemoteController should reset weapon arming when drone view is newly enabled." `
    $remote "active\s*&&\s*!\s*wasActive[\s\S]{0,140}ResetDroneWeaponArming\(\)"

Require-Match "RemoteController should consume the entry Attack1 press when arming is reset." `
    $remote "ResetDroneWeaponArming\(\)[\s\S]{0,260}Input\.Clear\(\s*""Attack1""\s*\)"

Require-Match "RemoteController should require Attack1 release after entering drone view." `
    $remote "_attack1ReleasedSinceDroneViewEntry\s*=\s*!\s*Input\.Down\(\s*""Attack1""\s*\)"

Require-Match "RemoteController should arm drone weapons from deliberate flight input." `
    $remote "DroneController\.HasLocalFlightInput\(\)[\s\S]{0,160}_droneWeaponsArmed\s*=\s*true"

Require-Match "RemoteController should arm drone weapons after the configured timeout." `
    $remote "_timeSinceDroneViewEntered\s*>=\s*DroneWeaponAutoArmDelay[\s\S]{0,160}_droneWeaponsArmed\s*=\s*true"

Require-Match "RemoteController should preserve manual drone testing when no local remote exists." `
    $remote "AreLocalDroneWeaponsReady\(\s*Scene\s+scene\s*\)[\s\S]{0,240}!\s*local\.IsValid\(\)\s*\|\|\s*local\.AreDroneWeaponsReady\(\)"

Require-Match "DroneController should expose a shared local flight input helper." `
    $controller "public\s+static\s+bool\s+HasLocalFlightInput\("

Require-Match "DroneController flight input should include analog movement." `
    $controller "Input\.AnalogMove[\s\S]{0,220}MathF\.Abs\(\s*move\.x\s*\)[\s\S]{0,260}MathF\.Abs\(\s*move\.y\s*\)"

Require-Match "DroneController flight input should include ascend and descend controls." `
    $controller "Input\.Down\(\s*""Jump""\s*\)[\s\S]{0,180}Input\.Down\(\s*""Duck""\s*\)[\s\S]{0,180}Input\.Down\(\s*""Crouch""\s*,\s*false\s*\)"

Reject-Match "DroneController flight input should not treat mouse look as movement arming." `
    $flightInputMethod "Input\.MouseDelta"

Require-Match "DroneWeapon should gate all drone weapon input behind the local arming check." `
    $weapon "AreLocalDroneWeaponsReady\(\s*Scene\s*\)[\s\S]{0,120}return;[\s\S]{0,260}PrimaryUsesKamikaze[\s\S]{0,600}Attack2"

Require-Match "Gameplay regression suite should run the drone weapon arming guard." `
    $guard "scripts\\check_drone_weapon_arming\.ps1"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Drone weapon arming check passed."
