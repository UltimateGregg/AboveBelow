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

function Test-RequiredText {
    param(
        [string]$Path,
        [string]$Area,
        [string[]]$Patterns,
        [string]$Recommendation
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $Path "Required file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $Path "Missing required marker '$pattern'." $Recommendation
        }
    }

    Add-AgentIssue $issues "Info" $Area $Path "Transient combat prefab check completed."
}

Write-AgentSection "Transient Combat Prefab Audit"

Test-RequiredText -Path "Assets/prefabs/effects/muzzle_flash.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"MuzzleFlash"',
        '"__type"\s*:\s*"DroneVsPlayers\.MuzzleFlashVisual"',
        '"__type"\s*:\s*"Sandbox\.SpriteRenderer"',
        '"__type"\s*:\s*"Sandbox\.PointLight"'
    ) `
    -Recommendation "Create a reusable muzzle flash prefab that owns its sprite and light, and keep MuzzleFlashVisual.Spawn prefab-backed with a procedural fallback."

Test-RequiredText -Path "Assets/prefabs/effects/tracer_bullet_glow.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"TracerBulletGlow"',
        '"__type"\s*:\s*"Sandbox\.SpriteRenderer"'
    ) `
    -Recommendation "Create a reusable tracer bullet glow prefab and keep TracerLifetime prefab-backed for its glow child."

Test-RequiredText -Path "Assets/prefabs/tracer_default.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"Tracer"',
        '"__type"\s*:\s*"Sandbox\.LineRenderer"',
        '"__type"\s*:\s*"DroneVsPlayers\.TracerLifetime"'
    ) `
    -Recommendation "Keep the default ballistic tracer prefab reusable for soldier, pilot, and drone hitscan weapons."

Test-RequiredText -Path "Assets/prefabs/effects/jammer_beam.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"JammerBeamVisual"',
        '"__type"\s*:\s*"DroneVsPlayers\.JammerConeVisual"',
        '"__type"\s*:\s*"Sandbox\.ParticleEffect"',
        '"__type"\s*:\s*"Sandbox\.ParticleConeEmitter"',
        '"__type"\s*:\s*"Sandbox\.ParticleSpriteRenderer"',
        '"PrimaryTexturePath"\s*:\s*"textures/beams/beam_noise05\.vtex"'
    ) `
    -Recommendation "Create a reusable wavy jammer cone prefab and keep DroneJammerGun visuals prefab-backed with a procedural particle fallback."

Test-RequiredText -Path "Assets/prefabs/effects/detached_fiber_cable.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"DetachedFiberCable"',
        '"__type"\s*:\s*"Sandbox\.LineRenderer"'
    ) `
    -Recommendation "Create a reusable detached fiber cable prefab and keep FiberCable detach visuals prefab-backed with a procedural fallback."

Test-RequiredText -Path "Assets/prefabs/items/thrown_grenade_projectile.prefab" `
    -Area "Transient Combat Prefab" `
    -Patterns @(
        '"Name"\s*:\s*"ThrownGrenadeProjectile"',
        '"__type"\s*:\s*"DroneVsPlayers\.ThrownGrenadeProjectile"',
        '"__type"\s*:\s*"Sandbox\.ModelRenderer"',
        '"__type"\s*:\s*"Sandbox\.CapsuleCollider"',
        '"__type"\s*:\s*"Sandbox\.Rigidbody"',
        '"Body"\s*:\s*\{\s*"_type"\s*:\s*"component"',
        '"Collider"\s*:\s*\{\s*"_type"\s*:\s*"component"'
    ) `
    -Recommendation "Create a reusable thrown grenade projectile prefab with renderer, physics components, and wired behavior refs that runtime configures."

foreach ($effect in @(
    @{ Path = "Assets/prefabs/effects/chaff_burst.prefab"; Name = "ChaffGrenadeEffect" },
    @{ Path = "Assets/prefabs/effects/emp_burst.prefab"; Name = "EmpGrenadeEffect" },
    @{ Path = "Assets/prefabs/effects/frag_burst.prefab"; Name = "FragGrenadeEffect" }
)) {
    Test-RequiredText -Path $effect.Path `
        -Area "Transient Combat Prefab" `
        -Patterns @(
            ('"Name"\s*:\s*"{0}"' -f [regex]::Escape($effect.Name)),
            '"__type"\s*:\s*"DroneVsPlayers\.GrenadeEffectVisual"',
            '"__type"\s*:\s*"Sandbox\.ParticleEffect"',
            '"__type"\s*:\s*"Sandbox\.ParticleSpriteRenderer"',
            '"__type"\s*:\s*"Sandbox\.PointLight"'
        ) `
        -Recommendation "Create reusable grenade detonation effect prefabs with prefab-owned particle/light children and keep grenade effect spawning prefab-backed with typed repair fallbacks."
}

Test-RequiredText -Path "Code/Player/MuzzleFlashVisual.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/muzzle_flash\.prefab',
        'GameObject\.GetPrefab',
        'Components\.Get<MuzzleFlashVisual>'
    ) `
    -Recommendation "Spawn muzzle flashes from the reusable prefab first, with the existing code-built fallback for resilience."

Test-RequiredText -Path "Code/Player/TracerLifetime.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/tracer_bullet_glow\.prefab',
        'GameObject\.GetPrefab',
        'Components\.Get<SpriteRenderer>'
    ) `
    -Recommendation "Spawn tracer bullet glow visuals from the reusable prefab first, with the existing code-built fallback for resilience."

foreach ($tracerUser in @(
    @{ Path = "Code/Player/HitscanWeapon.cs"; Area = "Transient Combat Code" },
    @{ Path = "Code/Player/ShotgunWeapon.cs"; Area = "Transient Combat Code" },
    @{ Path = "Code/Drone/DroneWeapon.cs"; Area = "Transient Combat Code" }
)) {
    Test-RequiredText -Path $tracerUser.Path `
        -Area $tracerUser.Area `
        -Patterns @(
            'TracerPrefab',
            'TracerPrefab\.Clone',
            'Components\.Get<TracerLifetime>'
        ) `
        -Recommendation "Keep hitscan weapon tracer visuals prefab-backed through the shared tracer_default prefab before using procedural fallbacks."
}

Test-RequiredText -Path "Code/Player/DroneJammerGun.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/jammer_beam\.prefab',
        'GameObject\.GetPrefab',
        'Components\.Get<JammerConeVisual>',
        'Configure\( origin, forward, MaxRange, ConeHalfAngle, BeamVisualColor, true \)'
    ) `
    -Recommendation "Spawn jammer cone visuals from the reusable prefab first, with the existing code-built fallback for resilience."

Test-RequiredText -Path "Code/Player/JammerConeVisual.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'sealed class JammerConeVisual',
        'ParticleConeEmitter',
        'ParticleSpriteRenderer',
        'textures/beams/beam_noise05\.vtex',
        'EmitConeParticles',
        '\.Emit\( position, Time\.Delta \)',
        'Texture\.Load',
        'Sprite\.FromTexture'
    ) `
    -Recommendation "Keep the jammer cone visual as a reusable typed particle component with stock wavy texture fallbacks."

Test-RequiredText -Path "Code/Drone/FiberCable.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/detached_fiber_cable\.prefab',
        'GameObject\.GetPrefab',
        'Components\.Get<LineRenderer>'
    ) `
    -Recommendation "Spawn detached fiber cable visuals from the reusable prefab first, with the existing code-built fallback for resilience."

Test-RequiredText -Path "Code/Equipment/ThrowableGrenade.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/items/thrown_grenade_projectile\.prefab',
        'GameObject\.GetPrefab',
        'Components\.Get<ThrownGrenadeProjectile>'
    ) `
    -Recommendation "Spawn thrown grenade projectiles from the reusable prefab first, then configure the same runtime physics values."

Test-RequiredText -Path "Code/Equipment/GrenadeEffectVisual.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'TrySpawnPrefab',
        'Components\.Get<GrenadeEffectVisual>',
        'Configure\( kind, radius \)',
        'GameObject\.Children\.FirstOrDefault',
        'Components\.Get<ParticleEffect>\(\)\s*\?\?\s*child\.Components\.Create<ParticleEffect>\(\)',
        'Components\.Get<PointLight>\(\)\s*\?\?\s*child\.Components\.Create<PointLight>\(\)'
    ) `
    -Recommendation "Let grenade effect prefabs reuse GrenadeEffectVisual and prefab-authored particle/light children while still applying grenade-specific radius and kind at spawn time."

Test-RequiredText -Path "Code/Equipment/ChaffGrenade.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/chaff_burst\.prefab',
        'GrenadeEffectVisual\.TrySpawnPrefab'
    ) `
    -Recommendation "Resolve the local chaff burst prefab before falling back to procedural grenade feedback."

Test-RequiredText -Path "Code/Equipment/EmpGrenade.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/emp_burst\.prefab',
        'GrenadeEffectVisual\.TrySpawnPrefab'
    ) `
    -Recommendation "Resolve the local EMP burst prefab before falling back to procedural grenade feedback."

Test-RequiredText -Path "Code/Equipment/FragGrenade.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/effects/frag_burst\.prefab',
        'GrenadeEffectVisual\.TrySpawnPrefab'
    ) `
    -Recommendation "Resolve the local frag burst prefab before falling back to procedural grenade feedback."

Test-RequiredText -Path "Code/code/Wiring/AutoWire.cs" `
    -Area "Transient Combat Code" `
    -Patterns @(
        'prefabs/tracer_default\.prefab',
        'prefabs/effects/chaff_burst\.prefab',
        'prefabs/effects/emp_burst\.prefab',
        'prefabs/effects/frag_burst\.prefab'
    ) `
    -Recommendation "Prefer local reusable tracer and grenade effect prefabs during AutoWire before checking mounted stock fallbacks."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
