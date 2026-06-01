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
$promptRenderer = Read-ProjectFile "Code/UI/InteractionPromptRenderer.cs"
$deployer = Read-ProjectFile "Code/Player/DroneDeployer.cs"
$pilot = Read-ProjectFile "Code/Player/PilotSoldier.cs"

Require-Match "DroneWeapon should expose a PrimaryUsesKamikaze contract for no-hitscan kamikaze drones." `
    $weapon "PrimaryUsesKamikaze\s*=>\s*EnableKamikaze\s*&&\s*!\s*EnableHitscan"

Require-Match "DroneWeapon should detonate from Attack1 when PrimaryUsesKamikaze is true." `
    $weapon "PrimaryUsesKamikaze[\s\S]{0,180}Input\.Pressed\(\s*""Attack1""\s*\)[\s\S]{0,180}RequestDetonate\(\)"

Require-Match "DroneWeapon should keep Attack2 from also being the kamikaze input for primary-kamikaze drones." `
    $weapon "!\s*PrimaryUsesKamikaze[\s\S]{0,160}Input\.Pressed\(\s*""Attack2""\s*\)"

Require-Match "Pilot drone HUD should hide bottom loadout cards while the local pilot is in drone view." `
    $hud "ShowLoadoutHud\s*=>[\s\S]{0,260}!\s*LocalDroneViewActive"

Require-Match "Pilot drone HUD should render a single drone action prompt inside the existing reticle stack." `
    $hud "<div\s+class=""reticle-stack"">[\s\S]{0,900}ShowDroneActionPrompt[\s\S]{0,700}drone-action-prompt"

Require-Match "Pilot drone HUD should render the drone action prompt through the shared interaction prompt renderer." `
    $hud "ShowDroneActionPrompt[\s\S]{0,900}InteractionPromptRenderer\.Render[\s\S]{0,180}drone-action-prompt"

Require-Match "InteractionPromptRenderer should show a left mouse icon for LMB prompts." `
    $promptRenderer "glyph\.Equals\(\s*""LMB""[\s\S]{0,900}mouse-icon[\s\S]{0,260}mouse-button\s+left"

Require-Match "Pilot drone HUD should label primary-kamikaze FPV drones as DETONATE." `
    $hud "DroneActionLabel[\s\S]{0,520}PrimaryUsesKamikaze[\s\S]{0,160}""DETONATE"""

Require-Match "Pilot drone HUD should label GPS hitscan drones as GPS LASER." `
    $hud "DroneActionLabel[\s\S]{0,620}DroneType\.Gps[\s\S]{0,180}""GPS LASER"""

Require-Match "Pilot drone HUD should gate the LCD overlay to first-person drone camera view." `
    $hud "ShowDroneLcdOverlay\s*=>[\s\S]{0,260}LocalDroneViewActive[\s\S]{0,260}LocalDroneCamera\.IsValid\(\)[\s\S]{0,160}LocalDroneCamera\.IsFirstPersonActive"

Require-Match "Pilot drone HUD should render the LCD overlay from the main HUD tree." `
    $hud "ShowDroneLcdOverlay[\s\S]{0,420}drone-lcd-overlay"

Reject-Match "Pilot drone HUD should not keep a drone-view slot 2 card for primary-kamikaze drones." `
    $hud "weapon\.PrimaryUsesKamikaze[\s\S]{0,420}DisabledSlot\(\s*2,[\s\S]{0,180}Primary fire detonates"

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

foreach ($stylePath in @(
    "Code/UI/HudPanel.razor.scss",
    "Code/UI/HudPanel.cs.scss",
    "Assets/ui/hudpanel.cs.scss"
)) {
    $style = Read-ProjectFile $stylePath

    Require-Match "$stylePath should style the reticle drone action prompt." `
        $style "\.drone-action-prompt"

    Require-Match "$stylePath should draw the left mouse action icon." `
        $style "\.mouse-icon[\s\S]{0,500}\.mouse-button"

    Require-Match "$stylePath should style the full-screen drone LCD overlay." `
        $style "\.drone-lcd-overlay"

    Require-Match "$stylePath should include LCD scanlines." `
        $style "\.lcd-scanlines"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Drone kamikaze primary check passed."
