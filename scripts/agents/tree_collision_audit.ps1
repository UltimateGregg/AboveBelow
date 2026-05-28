param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Tree Collision Audit"
Write-Host "Root: $Root"

$treeModels = @(
    "models/terrain_assets.vmdl",
    "models/terrain_pine.vmdl",
    "models/terrain_pine_broad.vmdl",
    "models/terrain_pine_windswept.vmdl"
)
$expectedTreeCapsuleRadius = 40.0
$treeModelSet = @{}
foreach ($model in $treeModels) {
    $treeModelSet[$model] = $true
}

function Get-JsonPropertyValue {
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

function Get-ObjectChildren {
    param([object]$Object)

    $children = Get-JsonPropertyValue -Object $Object -Name "Children"
    if ($null -eq $children) {
        return @()
    }

    return @($children)
}

function Get-ObjectComponents {
    param([object]$Object)

    $components = Get-JsonPropertyValue -Object $Object -Name "Components"
    if ($null -eq $components) {
        return @()
    }

    return @($components)
}

function Convert-AgentVectorText {
    param(
        [object]$Value,
        [double[]]$Default = @(0.0, 0.0, 0.0)
    )

    if ($null -eq $Value) {
        return $Default
    }

    $parts = @($Value.ToString() -split "," | ForEach-Object {
        $parsed = 0.0
        if ([double]::TryParse($_.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            $parsed
        }
        else {
            $null
        }
    })

    if ($parts.Count -ne 3 -or $parts -contains $null) {
        return $Default
    }

    return $parts
}

function Test-JsonBool {
    param(
        [object]$Value,
        [bool]$Expected
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value -eq $Expected
    }

    return $Value.ToString().Equals($Expected.ToString(), [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-AllObjects {
    param(
        [object]$Object,
        [string]$Path = "",
        [double[]]$ParentScale = @(1.0, 1.0, 1.0)
    )

    if ($null -eq $Object) {
        return @()
    }

    $name = [string](Get-JsonPropertyValue -Object $Object -Name "Name")
    $currentPath = if ([string]::IsNullOrWhiteSpace($Path)) { $name } else { "$Path/$name" }
    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Object -Name "Scale") -Default @(1.0, 1.0, 1.0)
    $parentX = [double]($ParentScale[0])
    $parentY = [double]($ParentScale[1])
    $parentZ = [double]($ParentScale[2])
    $scaleX = [double]($scale[0])
    $scaleY = [double]($scale[1])
    $scaleZ = [double]($scale[2])
    $worldScale = New-Object 'double[]' 3
    $worldScale[0] = $parentX * $scaleX
    $worldScale[1] = $parentY * $scaleY
    $worldScale[2] = $parentZ * $scaleZ

    $objects = @([pscustomobject]@{
        Object = $Object
        Path = $currentPath
        WorldScale = $worldScale
    })

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $objects += @(Get-AllObjects -Object $child -Path $currentPath -ParentScale $worldScale)
    }

    return $objects
}

function Get-TreeModel {
    param([object]$Object)

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        $hasRendererShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")
        if ($componentType -ne "Sandbox.ModelRenderer" -and -not $hasRendererShape) {
            continue
        }

        $model = ([string](Get-JsonPropertyValue -Object $component -Name "Model")).Replace("\", "/")
        if ($treeModelSet.ContainsKey($model)) {
            return $model
        }
    }

    return $null
}

function Get-ColliderComponents {
    param([object]$Object)

    $colliders = @()
    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        $hasColliderShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            (
                $null -ne (Get-JsonPropertyValue -Object $component -Name "Radius") -or
                $null -ne (Get-JsonPropertyValue -Object $component -Name "Height") -or
                $null -ne (Get-JsonPropertyValue -Object $component -Name "Start") -or
                $null -ne (Get-JsonPropertyValue -Object $component -Name "End") -or
                $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale") -or
                $null -ne (Get-JsonPropertyValue -Object $component -Name "BoxSize")
            )
        if ($componentType.EndsWith("Collider", [System.StringComparison]::OrdinalIgnoreCase) -or $hasColliderShape) {
            $colliders += $component
        }
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $childName = [string](Get-JsonPropertyValue -Object $child -Name "Name")
        if (-not $childName.StartsWith("Collision_", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        foreach ($component in @(Get-ObjectComponents -Object $child)) {
            $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
            $hasColliderShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
                (
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Radius") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Height") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Start") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "End") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "BoxSize")
                )
            if ($componentType.EndsWith("Collider", [System.StringComparison]::OrdinalIgnoreCase) -or $hasColliderShape) {
                $colliders += $component
            }
        }
    }

    return $colliders
}

function Get-ColliderWorldRadius {
    param(
        [object]$Collider,
        [double[]]$WorldScale
    )

    $radius = Get-JsonPropertyValue -Object $Collider -Name "Radius"
    if ($null -ne $radius) {
        return [double]$radius * [Math]::Max([double]$WorldScale[0], [double]$WorldScale[1])
    }

    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Collider -Name "Scale") -Default @(0.0, 0.0, 0.0)
    return ([Math]::Max([double]$scale[0] * [double]$WorldScale[0], [double]$scale[1] * [double]$WorldScale[1])) * 0.5
}

function Get-ColliderLocalRadius {
    param([object]$Collider)

    $radius = Get-JsonPropertyValue -Object $Collider -Name "Radius"
    if ($null -eq $radius) {
        return $null
    }

    return [double]$radius
}

function Get-ColliderWorldHeight {
    param(
        [object]$Collider,
        [double[]]$WorldScale
    )

    $height = Get-JsonPropertyValue -Object $Collider -Name "Height"
    if ($null -ne $height) {
        return [double]$height * [double]$WorldScale[2]
    }

    $start = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Collider -Name "Start") -Default @(0.0, 0.0, 0.0)
    $end = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Collider -Name "End") -Default @(0.0, 0.0, 0.0)
    $deltaX = ([double]$end[0] - [double]$start[0]) * [double]$WorldScale[0]
    $deltaY = ([double]$end[1] - [double]$start[1]) * [double]$WorldScale[1]
    $deltaZ = ([double]$end[2] - [double]$start[2]) * [double]$WorldScale[2]
    $capsuleHeight = [Math]::Sqrt(($deltaX * $deltaX) + ($deltaY * $deltaY) + ($deltaZ * $deltaZ))
    if ($capsuleHeight -gt 0.0) {
        return $capsuleHeight
    }

    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Collider -Name "Scale") -Default @(0.0, 0.0, 0.0)
    return [double]$scale[2] * [double]$WorldScale[2]
}

function Test-TreeBlockingCollider {
    param(
        [object]$Collider,
        [double[]]$WorldScale
    )

    if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $Collider -Name "Static") -Expected $true)) {
        return $false
    }

    if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $Collider -Name "IsTrigger") -Expected $false)) {
        return $false
    }

    $flags = [string](Get-JsonPropertyValue -Object $Collider -Name "ColliderFlags")
    if ($flags -match "IgnoreTraces|IgnoreMass") {
        return $false
    }

    $localRadius = Get-ColliderLocalRadius -Collider $Collider
    if ($null -eq $localRadius -or [Math]::Abs([double]$localRadius - $script:expectedTreeCapsuleRadius) -gt 0.01) {
        return $false
    }

    $worldHeight = Get-ColliderWorldHeight -Collider $Collider -WorldScale $WorldScale

    return $worldHeight -ge 650.0
}

function Test-TreeObject {
    param(
        [object]$Object,
        [string]$ObjectPath,
        [double[]]$WorldScale,
        [string]$Path
    )

    $model = Get-TreeModel -Object $Object
    if ([string]::IsNullOrWhiteSpace($model)) {
        return $false
    }

    $script:treeCount++
    $colliders = @(Get-ColliderComponents -Object $Object)
    if ($colliders.Count -eq 0) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath uses $model but has no trunk collider." "Give every gameplay tree a static trunk blocker so players cannot walk through the visible trunk."
        return $true
    }

    foreach ($collider in $colliders) {
        if (Test-TreeBlockingCollider -Collider $collider -WorldScale $WorldScale) {
            $script:blockingTreeCount++
            return $true
        }
    }

    $details = @($colliders | ForEach-Object {
        $type = [string](Get-JsonPropertyValue -Object $_ -Name "__type")
        $static = [string](Get-JsonPropertyValue -Object $_ -Name "Static")
        $trigger = [string](Get-JsonPropertyValue -Object $_ -Name "IsTrigger")
        $flags = [string](Get-JsonPropertyValue -Object $_ -Name "ColliderFlags")
        $localRadius = Get-ColliderLocalRadius -Collider $_
        $radius = [Math]::Round((Get-ColliderWorldRadius -Collider $_ -WorldScale $WorldScale), 2)
        $height = [Math]::Round((Get-ColliderWorldHeight -Collider $_ -WorldScale $WorldScale), 2)
        "$type static=$static trigger=$trigger flags=$flags localRadius=$localRadius radius=$radius height=$height"
    }) -join "; "

    Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath uses $model but lacks a runtime-blocking static trunk collider with Radius=$script:expectedTreeCapsuleRadius ($details)." "Use a non-trigger static CapsuleCollider with Radius=$script:expectedTreeCapsuleRadius and enough height for the visible trunk; do not rely on non-static or ignore-flagged hulls."
    return $true
}

function Test-JsonFile {
    param([string]$FullPath)

    $relative = ConvertTo-AgentRelativePath -Path $FullPath -Root $Root
    try {
        $json = Read-AgentJson -Path $FullPath
    }
    catch {
        Add-AgentIssue $issues "Error" "Tree Collision" $relative "Could not parse JSON: $($_.Exception.Message)" "Fix invalid scene/prefab JSON before auditing tree collision."
        return
    }

    $rootObject = Get-JsonPropertyValue -Object $json -Name "RootObject"
    if ($null -ne $rootObject) {
        $objects = @(Get-AllObjects -Object $rootObject)
        foreach ($entry in $objects) {
            Test-TreeObject -Object $entry.Object -ObjectPath $entry.Path -WorldScale $entry.WorldScale -Path $relative | Out-Null
        }
        return
    }

    foreach ($gameObject in @(Get-JsonPropertyValue -Object $json -Name "GameObjects")) {
        $objects = @(Get-AllObjects -Object $gameObject)
        foreach ($entry in $objects) {
            Test-TreeObject -Object $entry.Object -ObjectPath $entry.Path -WorldScale $entry.WorldScale -Path $relative | Out-Null
        }
    }
}

$script:treeCount = 0
$script:blockingTreeCount = 0

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Tree Collision" (ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root) "Scene file is missing." "Restore the main scene before validating tree collision."
}
else {
    Test-JsonFile -FullPath $fullScenePath
}

$prefabDir = Join-Path $Root "Assets\prefabs\environment"
foreach ($prefabName in @("terrain_assets.prefab", "terrain_pine.prefab", "terrain_pine_broad.prefab", "terrain_pine_windswept.prefab")) {
    $prefabPath = Join-Path $prefabDir $prefabName
    if (Test-Path -LiteralPath $prefabPath) {
        Test-JsonFile -FullPath $prefabPath
    }
    else {
        Add-AgentIssue $issues "Error" "Tree Collision" (ConvertTo-AgentRelativePath -Path $prefabPath -Root $Root) "Tree prefab is missing." "Keep each local tree model available as a prefab with built-in trunk collision."
    }
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Tree Collision" "" "Checked $script:treeCount tree object(s); $script:blockingTreeCount have runtime-blocking static trunk collision."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
