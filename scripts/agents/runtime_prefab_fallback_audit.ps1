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

function Read-AgentText {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Runtime Prefab Fallback" $RelativePath "Required runtime file is missing." "Restore the file or update runtime_prefab_fallback_audit.ps1 intentionally."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Patterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Recommendation
    )

    $text = Read-AgentText $RelativePath
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Runtime Prefab Fallback" $RelativePath "Missing required marker '$pattern'." $Recommendation
        }
    }

    Add-AgentIssue $issues "Info" "Runtime Prefab Fallback" $RelativePath "Runtime GameObject fallback is classified."
}

Write-AgentSection "Runtime Prefab Fallback Audit"

$allowed = @{
    "Code/Drone/FiberCable.cs" = @{
        Patterns = @(
            'DetachedCablePrefabPath\s*=\s*"prefabs/effects/detached_fiber_cable\.prefab"',
            'GameObject\.GetPrefab\(\s*DetachedCablePrefabPath\s*\)',
            'Components\.Get<LineRenderer>'
        )
        Recommendation = "Keep detached fiber cable creation prefab-backed before using the local-only repair fallback."
    }
    "Code/Equipment/GrenadeEffectVisual.cs" = @{
        Patterns = @(
            'TrySpawnPrefab',
            'Components\.Get<GrenadeEffectVisual>',
            'GameObject\.Children\.FirstOrDefault',
            'Components\.Get<ParticleEffect>\(\)\s*\?\?\s*child\.Components\.Create<ParticleEffect>\(\)',
            'Components\.Get<PointLight>\(\)\s*\?\?\s*child\.Components\.Create<PointLight>\(\)'
        )
        Recommendation = "Keep grenade effect visual creation prefab-backed and limit child creation to repair fallbacks for damaged effect prefabs."
    }
    "Code/Equipment/ThrowableGrenade.cs" = @{
        Patterns = @(
            'DefaultProjectilePrefabPath\s*=\s*"prefabs/items/thrown_grenade_projectile\.prefab"',
            'GameObject\.GetPrefab\(\s*DefaultProjectilePrefabPath\s*\)',
            'Components\.Get<ThrownGrenadeProjectile>'
        )
        Recommendation = "Keep thrown grenade projectile creation prefab-backed before using the repair fallback."
    }
    "Code/Player/BallisticTracerRenderer.cs" = @{
        Patterns = @(
            'DefaultPrefabPath\s*=\s*"prefabs/effects/ballistic_tracer\.prefab"',
            'GameObject\.GetPrefab\(\s*DefaultPrefabPath\s*\)',
            'Components\.Get<BallisticTracerRenderer>'
        )
        Recommendation = "Keep lightweight ballistic tracer creation prefab-backed before using the repair fallback."
    }
    "Code/Player/DroneDeployer.cs" = @{
        Patterns = @(
            'HeldPropellerPrefabPath\s*=\s*"prefabs/items/held_drone_propeller\.prefab"',
            'GameObject\.GetPrefab\(\s*HeldPropellerPrefabPath\s*\)',
            'definition\.PrefabPath'
        )
        Recommendation = "Keep deployer held propeller visuals prefab-backed and launch selected drone variants from loadout/prefab resources."
    }
    "Code/Player/DroneJammerGun.cs" = @{
        Patterns = @(
            'DefaultBeamVisualPrefabPath\s*=\s*"prefabs/effects/jammer_beam\.prefab"',
            'GameObject\.GetPrefab\(\s*DefaultBeamVisualPrefabPath\s*\)',
            'Components\.Get<JammerConeVisual>'
        )
        Recommendation = "Keep jammer beam visuals prefab-backed before using the repair fallback."
    }
    "Code/Player/FirstPersonViewmodel.cs" = @{
        Patterns = @(
            'ViewmodelRootPrefabPath\s*=\s*"prefabs/items/local_first_person_viewmodel\.prefab"',
            'ViewmodelArmsPrefabPath\s*=\s*"prefabs/items/viewmodel_arms\.prefab"',
            'ViewmodelStockWeaponPrefabPath\s*=\s*"prefabs/items/viewmodel_stock_weapon\.prefab"',
            'ViewmodelCustomVisualPrefabPath\s*=\s*"prefabs/items/viewmodel_custom_visual\.prefab"',
            'ViewmodelStaticItemPrefabPath\s*=\s*"prefabs/items/viewmodel_static_item\.prefab"',
            'Components\.Get<ModelRenderer>\(\)'
        )
        Recommendation = "Keep reusable first-person roots prefab-backed; per-item source renderer copies may remain runtime children."
    }
    "Code/Player/MuzzleFlashVisual.cs" = @{
        Patterns = @(
            'DefaultPrefabPath\s*=\s*"prefabs/effects/muzzle_flash\.prefab"',
            'GameObject\.GetPrefab\(\s*DefaultPrefabPath\s*\)',
            'Components\.Get<MuzzleFlashVisual>'
        )
        Recommendation = "Keep muzzle flashes prefab-backed before using the repair fallback."
    }
    "Code/Player/TracerLifetime.cs" = @{
        Patterns = @(
            'DefaultGlowPrefabPath\s*=\s*"prefabs/effects/tracer_bullet_glow\.prefab"',
            'GameObject\.GetPrefab\(\s*DefaultGlowPrefabPath\s*\)',
            'Components\.Get<SpriteRenderer>'
        )
        Recommendation = "Keep tracer bullet glow creation prefab-backed before using the repair fallback."
    }
}

$codeRoot = Join-Path $Root "Code"
$proceduralFiles = @(Get-ChildItem -LiteralPath $codeRoot -Recurse -File -Filter "*.cs" | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw) -match 'new\s+GameObject'
} | ForEach-Object {
    $_.FullName.Substring($Root.Length).TrimStart([char[]]@("\", "/")).Replace("\", "/")
})

foreach ($relativePath in $proceduralFiles) {
    if (-not $allowed.ContainsKey($relativePath)) {
        Add-AgentIssue $issues "Error" "Runtime Prefab Fallback" $relativePath "Runtime code creates a GameObject without an explicit prefab-fallback classification." "Either move the reusable shape into a prefab first, or document why this object must remain runtime-created and add it to this audit."
    }
}

foreach ($entry in $allowed.GetEnumerator() | Sort-Object Name) {
    if ($proceduralFiles -notcontains $entry.Name) {
        Add-AgentIssue $issues "Warning" "Runtime Prefab Fallback" $entry.Name "Classified file no longer creates runtime GameObjects." "Remove stale allow-list entries after confirming the prefab path is still covered elsewhere."
        continue
    }

    Assert-Patterns -RelativePath $entry.Name -Patterns $entry.Value.Patterns -Recommendation $entry.Value.Recommendation
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
