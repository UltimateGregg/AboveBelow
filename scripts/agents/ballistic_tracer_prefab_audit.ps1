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
        Add-AgentIssue $issues "Error" "Ballistic Tracer Prefab" $RelativePath "Required file is missing." "Restore the file before auditing tracer prefab usage."
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
        Add-AgentIssue $issues "Error" "Ballistic Tracer Prefab" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Ballistic Tracer Prefab Audit"

$prefabPath = "Assets/prefabs/effects/ballistic_tracer.prefab"
$prefabText = Get-Text $prefabPath
Assert-Pattern $prefabPath $prefabText '"Name"\s*:\s*"BallisticTracer"' "Ballistic tracer prefab root should be named BallisticTracer." "Keep the fallback tracer as a reusable prefab root."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.BallisticTracerRenderer"' "Ballistic tracer prefab should carry BallisticTracerRenderer." "Keep fallback tracer behavior on the prefab instead of direct-only code construction."
Assert-Pattern $prefabPath $prefabText '"NetworkMode"\s*:\s*2' "Ballistic tracer prefab should stay local-only in saved data." "Runtime clones also force NetworkMode.Never for resilience."

$rendererPath = "Code/Player/BallisticTracerRenderer.cs"
$rendererText = Get-Text $rendererPath
Assert-Pattern $rendererPath $rendererText 'DefaultPrefabPath\s*=\s*"prefabs/effects/ballistic_tracer\.prefab"' "BallisticTracerRenderer should declare the reusable fallback prefab path." "Resolve the prefab before constructing a bare GameObject."
Assert-Pattern $rendererPath $rendererText 'GameObject\.GetPrefab\(\s*DefaultPrefabPath\s*\)' "BallisticTracerRenderer should resolve the reusable prefab." "Resolve the prefab before constructing a bare GameObject."
Assert-Pattern $rendererPath $rendererText 'prefab\.Clone' "BallisticTracerRenderer should clone the reusable prefab when available." "Clone the prefab and configure the component before falling back to procedural creation."
Assert-Pattern $rendererPath $rendererText 'Components\.Get<BallisticTracerRenderer>' "BallisticTracerRenderer should read the component from the cloned prefab." "Fail over only if the prefab does not carry the expected component."
Assert-Pattern $rendererPath $rendererText 'clone\.NetworkMode\s*=\s*NetworkMode\.Never' "Cloned fallback tracers should remain local-only." "Keep fallback visual-only tracer objects off networking."
Assert-Pattern $rendererPath $rendererText 'new\s+GameObject\(\s*true,\s*"Ballistic Tracer"\s*\)' "BallisticTracerRenderer should keep a procedural fallback." "Do not break combat visuals if the prefab is unavailable during editor iteration."

foreach ($weaponPath in @(
    "Code/Player/HitscanWeapon.cs",
    "Code/Player/ShotgunWeapon.cs"
)) {
    $weaponText = Get-Text $weaponPath
    Assert-Pattern $weaponPath $weaponText 'BallisticTracerRenderer\.Spawn' "Weapon fallback path should still call BallisticTracerRenderer.Spawn." "Keep the shared fallback renderer path for weapons that lack a configured tracer prefab."
}

Add-AgentIssue $issues "Info" "Ballistic Tracer Prefab" $prefabPath "Ballistic tracer prefab check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
