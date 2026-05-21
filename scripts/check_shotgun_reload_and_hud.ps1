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

$shotgun = Read-ProjectFile "Code/Player/ShotgunWeapon.cs"
$hud = Read-ProjectFile "Code/UI/HudPanel.razor"

Require-Match "ShotgunWeapon should declare a 6-shell magazine." `
    $shotgun "\[Property\]\s+public\s+int\s+MagazineSize\s*\{\s*get;\s*set;\s*\}\s*=\s*6\s*;"

Require-Match "ShotgunWeapon should declare reserve ammo." `
    $shotgun "\[Property\]\s+public\s+int\s+StartingReserveAmmo\s*\{\s*get;\s*set;\s*\}\s*=\s*24\s*;"

Require-Match "ShotgunWeapon should declare reload timing." `
    $shotgun "\[Property\]\s+public\s+float\s+ReloadSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*2\.4f\s*;"

foreach ($name in @("AmmoInMagazine", "AmmoReserve", "IsReloading", "ReloadFinishTime")) {
    Require-Match "ShotgunWeapon should sync $name." `
        $shotgun "\[Sync\]\s+public\s+[\w]+\s+$name\s*\{\s*get;\s*set;\s*\}"
}

Require-Match "ShotgunWeapon should block firing while reloading." `
    $shotgun "if\s*\(\s*IsReloading\s*\)\s*return\s*;"

Require-Match "ShotgunWeapon should decrement one shell per shot." `
    $shotgun "AmmoInMagazine\s*=\s*Math\.Max\s*\(\s*0\s*,\s*AmmoInMagazine\s*-\s*1\s*\)"

Require-Match "ShotgunWeapon should request reload from Reload input." `
    $shotgun "Input\.Pressed\s*\(\s*""Reload""\s*\)[\s\S]{0,140}RequestReload\s*\("

Require-Match "ShotgunWeapon should use a host fire request." `
    $shotgun "\[Rpc\.Host\]\s*void\s+RequestFire\s*\("

Require-Match "ShotgunWeapon should broadcast reload animation start." `
    $shotgun "\[Rpc\.Broadcast\]\s*void\s+BroadcastReloadStart\s*\("

Require-Match "HudPanel should expose a shotgun ammo weapon path." `
    $hud "ShotgunWeapon\s+CurrentShotgunAmmoWeapon"

Require-Match "HudPanel should show ammo HUD for shotgun weapons." `
    $hud "CurrentShotgunAmmoWeapon\.IsValid\(\)"

Require-Match "HudPanel should render shotgun reload text." `
    $hud "CurrentShotgunAmmoWeapon\.AmmoDisplay"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Shotgun reload and HUD check passed."
