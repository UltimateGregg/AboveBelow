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

$weapon = Read-ProjectFile "Code/Drone/DroneWeapon.cs"
$pilotLink = Read-ProjectFile "Code/Drone/PilotLink.cs"
$fiberCable = Read-ProjectFile "Code/Drone/FiberCable.cs"
$killFeed = Read-ProjectFile "Code/UI/KillFeedTracker.cs"

Require-Match "DroneWeapon should guard against duplicate detonation requests." `
    $weapon "_detonationRequested"

Require-Match "DroneWeapon should play a local explosion sound fallback." `
    $weapon 'DefaultExplosionSoundPath\s*=\s*"sounds/grenade_explosion\.sound"[\s\S]*?Sound\.Play\(\s*DefaultExplosionSoundPath\s*,\s*center\s*\)'

Require-Match "DroneWeapon should spawn procedural frag feedback if the explosion prefab is missing." `
    $weapon "GrenadeEffectVisual\.Spawn\(\s*center\s*,\s*GrenadeEffectKind\.Frag\s*,\s*KamikazeRadius\s*\)"

Require-Match "DroneWeapon should explicitly request a host-side despawn after detonation." `
    $weapon "RequestKillAndDespawnDrone\(\s*WorldPosition\s*\)"

Require-Match "DroneWeapon should destroy the exploded drone object on the host." `
    $weapon "RequestKillAndDespawnDrone[\s\S]{0,700}GameObject\.Destroy\(\)"

Require-Match "DroneWeapon should detach the fiber cable on every peer before despawning the exploded drone." `
    $weapon "void\s+RequestKillAndDespawnDrone\(\s*Vector3\s+center\s*\)[\s\S]{0,220}DetachFiberCableBeforeDespawn\(\)[\s\S]{0,220}CanMutateState\(\)"

Require-Match "PilotLink should play a local explosion sound fallback." `
    $pilotLink 'DefaultExplosionSoundPath\s*=\s*"sounds/grenade_explosion\.sound"[\s\S]*?Sound\.Play\(\s*DefaultExplosionSoundPath\s*,\s*center\s*\)'

Require-Match "PilotLink should spawn procedural frag feedback if the explosion prefab is missing." `
    $pilotLink "GrenadeEffectVisual\.Spawn\(\s*center\s*,\s*GrenadeEffectKind\.Frag\s*,\s*ExplosionEffectRadius\s*\)"

Require-Match "PilotLink should explicitly request a host-side despawn after crash detonation." `
    $pilotLink "RequestKillAndDespawnDrone\(\s*WorldPosition\s*\)"

Require-Match "PilotLink should destroy the exploded drone object on the host." `
    $pilotLink "RequestKillAndDespawnDrone[\s\S]{0,700}GameObject\.Destroy\(\)"

Require-Match "PilotLink should detach the fiber cable on every peer before despawning the crashed drone." `
    $pilotLink "void\s+RequestKillAndDespawnDrone\(\s*Vector3\s+center\s*\)[\s\S]{0,220}DetachFiberCableBeforeDespawn\(\)[\s\S]{0,220}CanMutateState\(\)"

Require-Match "FiberCable should expose a detach method that stops following live drone and pilot endpoints." `
    $fiberCable "public\s+void\s+DetachFromLiveEndpoints\(\)"

Require-Match "FiberCable detach should create a standalone LineRenderer so the wire survives drone destruction." `
    $fiberCable "new\s+GameObject\(\s*true,\s*""Detached Fiber Cable""\s*\)[\s\S]{0,900}Components\.Create<LineRenderer>\(\)"

Require-Match "FiberCable updates should stop rebuilding from live endpoints after detachment." `
    $fiberCable "_detachedFromLiveEndpoints[\s\S]{0,500}return;"

Require-Match "Kill feed should ignore unattributed internal cleanup deaths." `
    $killFeed "void\s+OnHealthKilled\(\s*Health\s+victim,\s*DamageInfo\s+info\s*\)[\s\S]{0,180}if\s*\(\s*info\.AttackerId\s*==\s*default\s*\)\s*return;"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "ERROR: $_" }
    exit 1
}

Write-Host "Drone explosion feedback check passed."
