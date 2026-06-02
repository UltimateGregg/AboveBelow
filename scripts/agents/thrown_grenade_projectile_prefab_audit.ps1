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

function Get-Text {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Thrown Grenade Projectile Prefab" $RelativePath "Required file is missing." "Restore the file before auditing thrown grenade projectile prefab ownership."
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Assert-Pattern {
    param(
        [string]$RelativePath,
        [string]$Text,
        [string]$Pattern,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Thrown Grenade Projectile Prefab" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Thrown Grenade Projectile Prefab Audit"

$prefabPath = "Assets/prefabs/items/thrown_grenade_projectile.prefab"
$prefabText = Get-Text $prefabPath
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.ThrownGrenadeProjectile"' "Projectile prefab is missing the behavior component." "Keep thrown grenade projectiles prefab-backed with the runtime component on the root."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.ModelRenderer"' "Projectile prefab is missing a ModelRenderer." "Let the prefab own the renderer and let ThrowableGrenade only assign the grenade-specific model."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.CapsuleCollider"' "Projectile prefab is missing a CapsuleCollider." "Let the prefab own the collision component that runtime physics configures."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.Rigidbody"' "Projectile prefab is missing a Rigidbody." "Let the prefab own the host-simulated physics body."
Assert-Pattern $prefabPath $prefabText '"Body"\s*:\s*\{\s*"_type"\s*:\s*"component"[\s\S]*?"component_id"\s*:\s*"ff089f9f-5166-57ad-8150-34e2bb2e8f61"[\s\S]*?"component_type"\s*:\s*"Rigidbody"' "ThrownGrenadeProjectile.Body is not wired to the prefab Rigidbody." "Keep root component references prefab-owned; runtime repair should only cover damaged prefabs."
Assert-Pattern $prefabPath $prefabText '"Collider"\s*:\s*\{\s*"_type"\s*:\s*"component"[\s\S]*?"component_id"\s*:\s*"f9c7edfe-671b-502a-9bff-1a6723c4a431"[\s\S]*?"component_type"\s*:\s*"CapsuleCollider"' "ThrownGrenadeProjectile.Collider is not wired to the prefab CapsuleCollider." "Keep root component references prefab-owned; runtime repair should only cover damaged prefabs."

$throwablePath = "Code/Equipment/ThrowableGrenade.cs"
$throwableText = Get-Text $throwablePath
Assert-Pattern $throwablePath $throwableText 'prefabs/items/thrown_grenade_projectile\.prefab' "ThrowableGrenade should resolve the shared projectile prefab." "Spawn thrown grenade projectiles from the reusable prefab before using the procedural fallback."
Assert-Pattern $throwablePath $throwableText 'Components\.Get<ModelRenderer>\(\)' "ThrowableGrenade should reuse prefab-authored ModelRenderer before adding one." "Keep renderer creation as a fallback for damaged prefabs only."
Assert-Pattern $throwablePath $throwableText 'Components\.Get<ThrownGrenadeProjectile>\(\)' "ThrowableGrenade should reuse prefab-authored ThrownGrenadeProjectile before adding one." "Keep behavior component creation as a fallback for damaged prefabs only."

Add-AgentIssue $issues "Info" "Thrown Grenade Projectile Prefab" $prefabPath "Thrown grenade projectile prefab check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
