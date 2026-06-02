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
        Add-AgentIssue $issues "Error" "Muzzle Flash Prefab" $RelativePath "Required file is missing." "Restore the file before auditing muzzle flash prefab ownership."
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
        Add-AgentIssue $issues "Error" "Muzzle Flash Prefab" $RelativePath $Message $Recommendation
    }
}

Write-AgentSection "Muzzle Flash Prefab Audit"

$prefabPath = "Assets/prefabs/effects/muzzle_flash.prefab"
$prefabText = Get-Text $prefabPath
Assert-Pattern $prefabPath $prefabText '"Name"\s*:\s*"MuzzleFlash"' "Muzzle flash prefab root has drifted." "Keep a stable reusable muzzle flash prefab root."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"DroneVsPlayers\.MuzzleFlashVisual"' "Muzzle flash prefab is missing its behavior component." "Keep MuzzleFlashVisual on the prefab root."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.SpriteRenderer"' "Muzzle flash prefab is missing its SpriteRenderer." "Let the prefab own the additive sprite; runtime creation should only repair damaged prefabs."
Assert-Pattern $prefabPath $prefabText '"__type"\s*:\s*"Sandbox\.PointLight"' "Muzzle flash prefab is missing its PointLight." "Let the prefab own the flash light; runtime creation should only repair damaged prefabs."
Assert-Pattern $prefabPath $prefabText '"Additive"\s*:\s*true' "Muzzle flash sprite should be additive." "Keep weapon-fire flashes visually consistent for both teams."
Assert-Pattern $prefabPath $prefabText '"Shadows"\s*:\s*false' "Muzzle flash prefab should not cast shadows." "Keep transient combat flashes cheap and visually clean."

$codePath = "Code/Player/MuzzleFlashVisual.cs"
$codeText = Get-Text $codePath
Assert-Pattern $codePath $codeText 'prefabs/effects/muzzle_flash\.prefab' "MuzzleFlashVisual should resolve the reusable prefab." "Spawn muzzle flashes from the prefab before falling back to a bare GameObject."
Assert-Pattern $codePath $codeText 'Components\.Get<SpriteRenderer>\(\)\s*\?\?\s*Components\.Create<SpriteRenderer>\(\)' "MuzzleFlashVisual should reuse prefab-authored SpriteRenderer before adding one." "Keep sprite creation as a fallback for damaged prefabs only."
Assert-Pattern $codePath $codeText 'Components\.Get<PointLight>\(\)\s*\?\?\s*Components\.Create<PointLight>\(\)' "MuzzleFlashVisual should reuse prefab-authored PointLight before adding one." "Keep light creation as a fallback for damaged prefabs only."

Add-AgentIssue $issues "Info" "Muzzle Flash Prefab" $prefabPath "Muzzle flash prefab check completed."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
