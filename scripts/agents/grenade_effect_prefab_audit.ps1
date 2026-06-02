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
        Add-AgentIssue $issues "Error" "Grenade Effect Prefab" $RelativePath "Required file is missing." "Restore the file before auditing grenade effect prefab ownership."
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
        Add-AgentIssue $issues "Error" "Grenade Effect Prefab" $RelativePath $Message $Recommendation
    }
}

function Assert-EffectChild {
    param(
        [string]$PrefabPath,
        [string]$Text,
        [string]$Name,
        [string]$EmitterType
    )

    $namePattern = ('"Name"\s*:\s*"{0}"' -f [regex]::Escape($Name))
    Assert-Pattern $PrefabPath $Text $namePattern "Grenade effect prefab is missing child '$Name'." "Keep particle/light child objects prefab-authored; GrenadeEffectVisual should only repair damaged prefabs."
    Assert-Pattern $PrefabPath $Text '"__type"\s*:\s*"Sandbox\.ParticleEffect"' "Grenade effect prefab is missing ParticleEffect children." "Prefab-own the particle effect components that GrenadeEffectVisual configures at runtime."
    Assert-Pattern $PrefabPath $Text '"__type"\s*:\s*"Sandbox\.ParticleSpriteRenderer"' "Grenade effect prefab is missing ParticleSpriteRenderer children." "Prefab-own the particle renderers that GrenadeEffectVisual configures at runtime."
    Assert-Pattern $PrefabPath $Text ('"__type"\s*:\s*"Sandbox\.{0}"' -f [regex]::Escape($EmitterType)) "Grenade effect prefab is missing $EmitterType for '$Name'." "Prefab-own the emitter components that GrenadeEffectVisual configures at runtime."
}

Write-AgentSection "Grenade Effect Prefab Audit"

$effects = @(
    @{
        Path = "Assets/prefabs/effects/chaff_burst.prefab"
        Root = "ChaffGrenadeEffect"
        Children = @(
            @{ Name = "Chaff Smoke"; Emitter = "ParticleConeEmitter" },
            @{ Name = "Chaff Metallic Flash"; Emitter = "ParticleSphereEmitter" }
        )
    },
    @{
        Path = "Assets/prefabs/effects/emp_burst.prefab"
        Root = "EmpGrenadeEffect"
        Children = @(
            @{ Name = "EMP Ring"; Emitter = "ParticleConeEmitter" },
            @{ Name = "EMP Spark Pulse"; Emitter = "ParticleSphereEmitter" }
        )
    },
    @{
        Path = "Assets/prefabs/effects/frag_burst.prefab"
        Root = "FragGrenadeEffect"
        Children = @(
            @{ Name = "Frag Fireball"; Emitter = "ParticleSphereEmitter" },
            @{ Name = "Frag Smoke"; Emitter = "ParticleConeEmitter" },
            @{ Name = "Frag Sparks"; Emitter = "ParticleSphereEmitter" }
        )
    }
)

foreach ($effect in $effects) {
    $text = Get-Text $effect.Path
    Assert-Pattern $effect.Path $text ('"Name"\s*:\s*"{0}"' -f [regex]::Escape($effect.Root)) "Grenade effect prefab root has drifted." "Keep a stable reusable grenade effect prefab root."
    Assert-Pattern $effect.Path $text '"__type"\s*:\s*"DroneVsPlayers\.GrenadeEffectVisual"' "Grenade effect prefab is missing GrenadeEffectVisual." "Keep the typed runtime configurator on the prefab root."
    Assert-Pattern $effect.Path $text '"Name"\s*:\s*"Explosion Light"' "Grenade effect prefab is missing its Explosion Light child." "Prefab-own the point light that GrenadeEffectVisual fades at runtime."
    Assert-Pattern $effect.Path $text '"__type"\s*:\s*"Sandbox\.PointLight"' "Grenade effect prefab is missing PointLight." "Prefab-own the explosion light component."

    foreach ($child in $effect.Children) {
        Assert-EffectChild $effect.Path $text $child.Name $child.Emitter
    }
}

$codePath = "Code/Equipment/GrenadeEffectVisual.cs"
$codeText = Get-Text $codePath
Assert-Pattern $codePath $codeText 'GameObject\.Children\.FirstOrDefault' "GrenadeEffectVisual should look for prefab-authored child objects." "Reuse prefab child particle/light objects before creating fallback children."
Assert-Pattern $codePath $codeText 'Components\.Get<ParticleEffect>\(\)\s*\?\?\s*child\.Components\.Create<ParticleEffect>\(\)' "GrenadeEffectVisual should reuse prefab ParticleEffect components." "Keep particle component creation as a repair fallback for damaged prefabs."
Assert-Pattern $codePath $codeText 'Components\.Get<ParticleSpriteRenderer>\(\)\s*\?\?\s*child\.Components\.Create<ParticleSpriteRenderer>\(\)' "GrenadeEffectVisual should reuse prefab ParticleSpriteRenderer components." "Keep renderer creation as a repair fallback for damaged prefabs."
Assert-Pattern $codePath $codeText 'Components\.Get<PointLight>\(\)\s*\?\?\s*child\.Components\.Create<PointLight>\(\)' "GrenadeEffectVisual should reuse prefab PointLight components." "Keep light creation as a repair fallback for damaged prefabs."

Add-AgentIssue $issues "Info" "Grenade Effect Prefab" "Assets/prefabs/effects" "Grenade effect prefab child ownership check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
