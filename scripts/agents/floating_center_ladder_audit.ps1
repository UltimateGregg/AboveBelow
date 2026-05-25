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
$sceneRelative = "Assets/scenes/main.scene"
$scenePath = Join-Path $Root $sceneRelative

function Get-AllSceneObjects {
    param($Object)

    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @($Object.Children)) {
        $objects += Get-AllSceneObjects -Object $child
    }

    return $objects
}

function Get-ObjectByName {
    param(
        [object[]]$Objects,
        [string]$Name
    )

    return @($Objects | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

function Get-ComponentByTypeName {
    param(
        $Object,
        [string]$TypeName
    )

    foreach ($component in @($Object.Components)) {
        $componentType = Get-JsonProperty -Object $component -Name "__type"
        if ($componentType -and $componentType.EndsWith($TypeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        if ($TypeName.EndsWith("BoxCollider", [System.StringComparison]::OrdinalIgnoreCase) -and
            $null -ne (Get-JsonProperty -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonProperty -Object $component -Name "Center") -and
            $null -ne (Get-JsonProperty -Object $component -Name "Scale")) {
            return $component
        }

        if ($TypeName.EndsWith("ModelRenderer", [System.StringComparison]::OrdinalIgnoreCase) -and
            $null -ne (Get-JsonProperty -Object $component -Name "Model") -and
            $null -ne (Get-JsonProperty -Object $component -Name "RenderType")) {
            return $component
        }

        if ($TypeName.EndsWith("LadderVolume", [System.StringComparison]::OrdinalIgnoreCase) -and
            $null -ne (Get-JsonProperty -Object $component -Name "AutoConfigureCollider") -and
            $null -ne (Get-JsonProperty -Object $component -Name "TopExitLocalOffset")) {
            return $component
        }
    }

    return $null
}

function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or $null -eq $Object.PSObject) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Convert-Vector {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parts = $Value.Split(",") | ForEach-Object { $_.Trim() }
    if ($parts.Count -lt 3) {
        return $null
    }

    try {
        return @([double]$parts[0], [double]$parts[1], [double]$parts[2])
    }
    catch {
        return $null
    }
}

function Test-BoolValue {
    param(
        $Value,
        [bool]$Expected
    )

    if ($Value -is [bool]) {
        return $Value -eq $Expected
    }

    return ([string]$Value).ToLowerInvariant() -eq ([string]$Expected).ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $scenePath)) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Main scene is missing." "Restore Assets/scenes/main.scene before validating the floating ladder."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Get-Content -LiteralPath $scenePath -Raw | ConvertFrom-Json
}
catch {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Scene JSON could not be parsed: $($_.Exception.Message)" "Fix scene JSON before validating the floating ladder."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllSceneObjects -Object $rootObject
}

$blockoutMap = @(Get-ObjectByName -Objects $allObjects -Name "BlockoutMap")
if ($blockoutMap.Count -eq 0) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "BlockoutMap was not found." "Keep authored map blockout additions under BlockoutMap."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$ladderGroups = @($blockoutMap[0].Children | Where-Object { $_.Name -eq "FloatingCenterLadder" })
if ($ladderGroups.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Expected exactly one FloatingCenterLadder under BlockoutMap; found $($ladderGroups.Count)." "Generate one centered floating ladder group through scripts/scene_blockout.py."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$group = $ladderGroups[0]
$position = Convert-Vector -Value ([string]$group.Position)
if ($null -eq $position -or [Math]::Abs($position[0] - 416.190948) -gt 0.01 -or [Math]::Abs($position[1]) -gt 0.01) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder is not centered on the current road/map center; Position='$($group.Position)'." "Use x=416.190948, y=0 so the ladder floats above the center road axis."
}

$children = @(Get-AllSceneObjects -Object $group)
$collision = @(Get-ObjectByName -Objects $children -Name "Collision_Ladder")
if ($collision.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder needs one Collision_Ladder child." "Add a trigger BoxCollider plus DroneVsPlayers.LadderVolume."
}
else {
    $box = Get-ComponentByTypeName -Object $collision[0] -TypeName "Sandbox.BoxCollider"
    $ladder = Get-ComponentByTypeName -Object $collision[0] -TypeName "DroneVsPlayers.LadderVolume"

    if ($null -eq $box) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Collision_Ladder is missing Sandbox.BoxCollider." "The BoxCollider defines the climbable trigger bounds."
    }
    elseif (-not (Test-BoolValue -Value $box.IsTrigger -Expected $true)) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Collision_Ladder BoxCollider is not a trigger." "Set IsTrigger true so GroundPlayerController can enter ladder movement."
    }

    if ($null -eq $ladder) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Collision_Ladder is missing DroneVsPlayers.LadderVolume." "Use the existing LadderVolume movement component instead of adding new movement code."
    }
    elseif (-not (Test-BoolValue -Value $ladder.UseTopExit -Expected $true)) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "Collision_Ladder LadderVolume does not use a top exit." "Enable UseTopExit and point TopExitLocalOffset at the landing platform."
    }
}

$landing = @(Get-ObjectByName -Objects $children -Name "TopLanding")
if ($landing.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder needs one solid TopLanding child." "Add a small solid landing at the top exit so climbing ends on walkable geometry."
}
else {
    $landingBox = Get-ComponentByTypeName -Object $landing[0] -TypeName "Sandbox.BoxCollider"
    $landingRenderer = Get-ComponentByTypeName -Object $landing[0] -TypeName "Sandbox.ModelRenderer"
    if ($null -eq $landingBox -or -not (Test-BoolValue -Value $landingBox.IsTrigger -Expected $false)) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "TopLanding must have a solid BoxCollider." "Keep the top exit walkable and non-trigger."
    }
    if ($null -eq $landingRenderer) {
        Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "TopLanding must be visible." "Visible geometry prevents invisible collision around the floating ladder."
    }
}

$visualRails = @($children | Where-Object { $_.Name -match "^Visual_Rail_" })
$visualRungs = @($children | Where-Object { $_.Name -match "^Visual_Rung_" })
if ($visualRails.Count -lt 2) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder needs at least two visible rails; found $($visualRails.Count)." "Keep the ladder readable from ground level."
}
if ($visualRungs.Count -lt 8) {
    Add-AgentIssue $issues "Error" "Floating Center Ladder" $sceneRelative "FloatingCenterLadder needs visible rungs; found $($visualRungs.Count)." "Use enough rung markers to make the climbable path obvious."
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Floating Center Ladder" $sceneRelative "Validated FloatingCenterLadder with $($visualRails.Count) rail(s), $($visualRungs.Count) rung(s), ladder trigger, and top landing."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
