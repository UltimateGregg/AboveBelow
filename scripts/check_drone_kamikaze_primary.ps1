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

$weapon = Read-ProjectFile "Code/Drone/DroneWeapon.cs"
$hud = Read-ProjectFile "Code/UI/HudPanel.razor"
$deployer = Read-ProjectFile "Code/Player/DroneDeployer.cs"
$pilot = Read-ProjectFile "Code/Player/PilotSoldier.cs"

Require-Match "DroneWeapon should expose a PrimaryUsesKamikaze contract for no-hitscan kamikaze drones." `
    $weapon "PrimaryUsesKamikaze\s*=>\s*EnableKamikaze\s*&&\s*!\s*EnableHitscan"

Require-Match "DroneWeapon should detonate from Attack1 when PrimaryUsesKamikaze is true." `
    $weapon "PrimaryUsesKamikaze[\s\S]{0,180}Input\.Pressed\(\s*""Attack1""\s*\)[\s\S]{0,180}RequestDetonate\(\)"

Require-Match "DroneWeapon should keep Attack2 from also being the kamikaze input for primary-kamikaze drones." `
    $weapon "!\s*PrimaryUsesKamikaze[\s\S]{0,160}Input\.Pressed\(\s*""Attack2""\s*\)"

Require-Match "Pilot drone HUD should put kamikaze on slot 1 with LMB for primary-kamikaze drones." `
    $hud "weapon\.PrimaryUsesKamikaze[\s\S]{0,260}new LoadoutSlot\(\s*1,[\s\S]{0,160}Kamikaze Charge[\s\S]{0,160}LMB"

Require-Match "Pilot drone HUD should not keep slot 2 as the active kamikaze control for primary-kamikaze drones." `
    $hud "weapon\.PrimaryUsesKamikaze[\s\S]{0,360}DisabledSlot\(\s*2,[\s\S]{0,160}Primary fire detonates"

Require-Match "DroneDeployer should keep second ground-side LMB as enter-drone-control." `
    $deployer "DroneInFlight[\s\S]{0,180}EnterDroneView\(\s*remote\s*\)"

Reject-Match "DroneDeployer should not detonate primary-kamikaze drones before the pilot enters drone control." `
    $deployer "TryDetonateLinkedPrimaryKamikaze"

Reject-Match "Pilot ground HUD should not label airborne FPV slot 1 as detonate; the detonate action belongs to drone view." `
    $hud "Detonate drone"

Require-Match "PilotSoldier.ResolveDrone should ignore dead linked drones so redeploy cooldown can start after detonation." `
    $pilot "ResolveDrone\(\)[\s\S]{0,420}!\s*health\.IsDead"

foreach ($prefab in @("Assets/prefabs/drone_fpv.prefab", "Assets/prefabs/drone_fpv_fiber.prefab")) {
    $text = Read-ProjectFile $prefab
    Require-Match "$prefab should disable hitscan." $text '"EnableHitscan"\s*:\s*false'
    Require-Match "$prefab should enable kamikaze." $text '"EnableKamikaze"\s*:\s*true'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Drone kamikaze primary check passed."
