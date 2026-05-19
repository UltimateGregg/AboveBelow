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

function Get-ProjectText {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Grenade Physics" $RelativePath "Expected file is missing." "Restore the grenade implementation or update this audit if ownership moved."
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

Write-AgentSection "Grenade Physics and FX Audit"
Write-Host "Root: $Root"

$projectilePath = "Code/Equipment/ThrownGrenadeProjectile.cs"
$projectile = Get-ProjectText $projectilePath
if ($null -ne $projectile) {
    foreach ($required in @("Rigidbody", "CapsuleCollider", "AngularVelocity", "LinearDamping", "AngularDamping")) {
        if ($projectile -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Grenade Physics" $projectilePath "Thrown grenade projectile is missing '$required'." "Use a host-owned Rigidbody with a collider and angular velocity so grenades tumble and settle naturally."
        }
    }

    if ($projectile -match 'WorldRotation\s*=\s*_baseRotation\s*;') {
        Add-AgentIssue $issues "Error" "Grenade Physics" $projectilePath "Projectile still forces its landing rotation back to the launch/base rotation." "Do not reset WorldRotation on rest; let physics preserve the landed orientation."
    }

    if ($projectile -match 'void\s+MoveProjectile\s*\(' -and $projectile -match 'Scene\.Trace\s*\.Ray') {
        Add-AgentIssue $issues "Error" "Grenade Physics" $projectilePath "Projectile still owns trace-only movement." "Let Rigidbody simulation move the grenade; use tracing only for optional diagnostics or emergency stuck handling."
    }
}

$throwablePath = "Code/Equipment/ThrowableGrenade.cs"
$throwable = Get-ProjectText $throwablePath
if ($null -ne $throwable) {
    foreach ($required in @("ProjectileColliderRadius", "ProjectileColliderLength", "ProjectileMass", "ProjectileLinearDamping", "ProjectileAngularDamping", "ProjectileSpinMin", "ProjectileSpinMax")) {
        if ($throwable -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Grenade Physics" $throwablePath "Throwable grenade tuning is missing '$required'." "Expose projectile physics tuning on ThrowableGrenade so prefab defaults can be adjusted without changing code."
        }
    }
}

$effectPath = "Code/Equipment/GrenadeEffectVisual.cs"
$effect = Get-ProjectText $effectPath
if ($null -ne $effect) {
    if ($effect -match 'models/dev/box\.vmdl') {
        Add-AgentIssue $issues "Error" "Grenade FX" $effectPath "Grenade fallback FX still renders dev-box fragments." "Replace pixel-like dev boxes with typed particle-style flash, smoke, sparks, and rings."
    }

    foreach ($required in @("ParticleEffect", "ParticleConeEmitter", "ParticleSphereEmitter", "PointLight")) {
        if ($effect -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Grenade FX" $effectPath "Grenade fallback FX is missing '$required'." "Use native S&Box particle/light components for the no-prefab fallback path."
        }
    }
}

$autoWirePath = "Code/code/Wiring/AutoWire.cs"
$autoWire = Get-ProjectText $autoWirePath
if ($null -ne $autoWire) {
    foreach ($required in @("ChaffGrenade", "EmpGrenade", "EffectPrefab", "prefabs/killstreaks/missile_explosion.prefab")) {
        if ($autoWire -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Grenade FX" $autoWirePath "AutoWire grenade FX wiring is missing '$required'." "Wire typed grenade effect prefab defaults for frag, chaff, and EMP."
        }
    }
}

Add-AgentIssue $issues "Info" "Grenade Physics" "" "Checked grenade projectile physics, fallback FX, and AutoWire effect wiring."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
