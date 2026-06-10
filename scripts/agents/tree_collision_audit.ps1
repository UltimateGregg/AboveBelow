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

$requiredBranchNames = @(
    "Collision_Branch_RootFlare_01",
    "Collision_Branch_RootFlare_02",
    "Collision_Branch_RootFlare_03",
    "Collision_Branch_RootFlare_04",
    "Collision_Branch_RootFlare_05",
    "Collision_Branch_DeadStub_01",
    "Collision_Branch_DeadStub_02",
    "Collision_Branch_DeadStub_03",
    "Collision_Branch_DeadStub_04",
    "Collision_Branch_DeadStub_05",
    "Collision_Branch_DeadStub_06",
    "Collision_Branch_Whorl_01",
    "Collision_Branch_Whorl_02",
    "Collision_Branch_Whorl_03",
    "Collision_Branch_Whorl_04",
    "Collision_Branch_Whorl_05",
    "Collision_Branch_Whorl_06",
    "Collision_Branch_Whorl_07",
    "Collision_Branch_Whorl_08",
    "Collision_Branch_Whorl_09",
    "Collision_Branch_Whorl_10",
    "Collision_Branch_Whorl_11",
    "Collision_Branch_Whorl_12",
    "Collision_Branch_Whorl_13",
    "Collision_Branch_Whorl_14",
    "Collision_Branch_Whorl_15",
    "Collision_Branch_Whorl_16",
    "Collision_Branch_Whorl_17",
    "Collision_Branch_Whorl_18",
    "Collision_Branch_Whorl_19",
    "Collision_Branch_Whorl_20",
    "Collision_Branch_Whorl_21",
    "Collision_Branch_Whorl_22",
    "Collision_Branch_Whorl_23",
    "Collision_Branch_Whorl_24",
    "Collision_Branch_Whorl_25",
    "Collision_Branch_Whorl_26"
)

$treeCollisionSpecs = @{
    "models/terrain_assets.vmdl" = @{
        TrunkLength = 1520.0
        TrunkWidth = 60.0
    }
    "models/terrain_pine.vmdl" = @{
        TrunkLength = 1520.0
        TrunkWidth = 60.0
    }
    "models/terrain_pine_broad.vmdl" = @{
        TrunkLength = 1410.0
        TrunkWidth = 64.0
    }
    "models/terrain_pine_windswept.vmdl" = @{
        TrunkLength = 1640.0
        TrunkWidth = 64.0
    }
}
$treeModelSet = @{}
foreach ($model in $treeCollisionSpecs.Keys) {
    $treeModelSet[$model] = $true
}
$treePrefabInstancePaths = @{
    "prefabs/environment/terrain_assets.prefab" = $true
    "prefabs/environment/terrain_pine.prefab" = $true
    "prefabs/environment/terrain_pine_broad.prefab" = $true
    "prefabs/environment/terrain_pine_windswept.prefab" = $true
}
$script:treePrefabRootCache = @{}

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

function Get-PrefabRootObjectForTreeInstance {
    param(
        [object]$Object,
        [string]$Path
    )

    $prefabPath = [string](Get-JsonPropertyValue -Object $Object -Name "__Prefab")
    if ([string]::IsNullOrWhiteSpace($prefabPath)) {
        return $null
    }

    $normalizedPrefabPath = $prefabPath.Replace("\", "/")
    if (-not $script:treePrefabInstancePaths.ContainsKey($normalizedPrefabPath)) {
        return $null
    }

    if ($script:treePrefabRootCache.ContainsKey($normalizedPrefabPath)) {
        return $script:treePrefabRootCache[$normalizedPrefabPath]
    }

    $fullPrefabPath = Join-Path $Root ("Assets\" + $normalizedPrefabPath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $fullPrefabPath)) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "Scene references missing tree prefab '$normalizedPrefabPath'." "Restore the tree prefab before relying on prefab-backed scene tree collision."
        return $null
    }

    try {
        $prefabJson = Read-AgentJson -Path $fullPrefabPath
        $rootObject = Get-JsonPropertyValue -Object $prefabJson -Name "RootObject"
        $script:treePrefabRootCache[$normalizedPrefabPath] = $rootObject
        return $rootObject
    }
    catch {
        Add-AgentIssue $issues "Error" "Tree Collision" (ConvertTo-AgentRelativePath -Path $fullPrefabPath -Root $Root) "Could not parse tree prefab JSON: $($_.Exception.Message)" "Fix invalid prefab JSON before auditing tree collision."
        return $null
    }
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
        [string]$Path = ""
    )

    if ($null -eq $Object) {
        return @()
    }

    $name = [string](Get-JsonPropertyValue -Object $Object -Name "Name")
    $currentPath = if ([string]::IsNullOrWhiteSpace($Path)) { $name } else { "$Path/$name" }
    $effectiveObject = Get-PrefabRootObjectForTreeInstance -Object $Object -Path $currentPath
    if ($null -eq $effectiveObject) {
        $effectiveObject = $Object
    }

    $objects = @([pscustomobject]@{
        Object = $effectiveObject
        Path = $currentPath
    })

    foreach ($child in @(Get-ObjectChildren -Object $effectiveObject)) {
        $objects += @(Get-AllObjects -Object $child -Path $currentPath)
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

function Test-IsColliderComponent {
    param([object]$Component)

    $componentType = [string](Get-JsonPropertyValue -Object $Component -Name "__type")
    if ($componentType.EndsWith("Collider", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $null -ne (Get-JsonPropertyValue -Object $Component -Name "IsTrigger") -and
        (
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "Radius") -or
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "Height") -or
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "Start") -or
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "End") -or
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "Scale") -or
            $null -ne (Get-JsonPropertyValue -Object $Component -Name "BoxSize")
        )
}

function Test-IsBoxColliderComponent {
    param([object]$Component)

    $componentType = [string](Get-JsonPropertyValue -Object $Component -Name "__type")
    if ($componentType -eq "Sandbox.BoxCollider") {
        return $true
    }

    return $null -ne (Get-JsonPropertyValue -Object $Component -Name "Center") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "Scale") -and
        $null -eq (Get-JsonPropertyValue -Object $Component -Name "Radius") -and
        $null -eq (Get-JsonPropertyValue -Object $Component -Name "Start") -and
        $null -eq (Get-JsonPropertyValue -Object $Component -Name "End")
}

function Test-IsHierarchyColliderViewerComponent {
    param([object]$Component)

    $componentType = [string](Get-JsonPropertyValue -Object $Component -Name "__type")
    if ($componentType -eq "DroneVsPlayers.SelectedHierarchyColliderViewer" -or
        $componentType -eq "SelectedHierarchyColliderViewer") {
        return $true
    }

    return $null -ne (Get-JsonPropertyValue -Object $Component -Name "AlwaysDraw") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "IncludeTriggers") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "SolidColliderColor") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "TriggerColliderColor")
}

function Test-HierarchyColliderViewer {
    param(
        [object]$TreeObject,
        [string]$ObjectPath,
        [string]$Path,
        [string]$Model
    )

    foreach ($component in @(Get-ObjectComponents -Object $TreeObject)) {
        if (Test-IsHierarchyColliderViewerComponent -Component $component) {
            return $true
        }
    }

    Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath uses $Model but lacks SelectedHierarchyColliderViewer on the tree root." "Add the hierarchy collider viewer to pine roots so selecting the tree draws all trunk and branch child collider boxes in the editor."
    return $false
}

function Get-BlockingBoxCollider {
    param([object]$Object)

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        if (-not (Test-IsBoxColliderComponent -Component $component)) {
            continue
        }

        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $component -Name "Static") -Expected $true)) {
            continue
        }

        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -Expected $false)) {
            continue
        }

        $flags = [string](Get-JsonPropertyValue -Object $component -Name "ColliderFlags")
        if ($flags -match "IgnoreTraces|IgnoreMass") {
            continue
        }

        return $component
    }

    return $null
}

function Get-ChildByName {
    param(
        [object]$Object,
        [string]$Name
    )

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $childName = [string](Get-JsonPropertyValue -Object $child -Name "Name")
        if ($childName.Equals($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $child
        }
    }

    return $null
}

function Get-BranchChildren {
    param([object]$Object)

    $children = @()
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $childName = [string](Get-JsonPropertyValue -Object $child -Name "Name")
        if ($childName.StartsWith("Collision_Branch_", [System.StringComparison]::OrdinalIgnoreCase)) {
            $children += $child
        }
    }

    return $children
}

function Test-TrunkBox {
    param(
        [object]$TreeObject,
        [string]$ObjectPath,
        [string]$Path,
        [string]$Model
    )

    $trunk = Get-ChildByName -Object $TreeObject -Name "Collision_Trunk"
    if ($null -eq $trunk) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath uses $Model but lacks a Collision_Trunk child." "Add a dedicated static BoxCollider child that covers the tree base/trunk from ground to crown."
        return $false
    }

    $collider = Get-BlockingBoxCollider -Object $trunk
    if ($null -eq $collider) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath/Collision_Trunk is not a non-trigger static Sandbox.BoxCollider." "Replace capsule trunk coverage with a BoxCollider child; the pine contract is trunk box plus branch boxes."
        return $false
    }

    $scale = @(Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $collider -Name "Scale") -Default @(0.0, 0.0, 0.0))
    $sorted = @($scale | Sort-Object -Descending)
    $spec = $script:treeCollisionSpecs[$Model]
    $longest = [double]$sorted[0]
    $crossA = [double]$sorted[1]
    $crossB = [double]$sorted[2]
    if ($longest -lt ([double]$spec.TrunkLength * 0.98) -or $crossA -lt [double]$spec.TrunkWidth -or $crossB -lt [double]$spec.TrunkWidth) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath/Collision_Trunk BoxCollider scale $($scale -join ',') does not cover trunk length>=$([Math]::Round([double]$spec.TrunkLength * 0.98, 2)) and width>=$([double]$spec.TrunkWidth)." "Size the trunk box to encompass the base of the pine all the way up."
        return $false
    }

    $position = @(Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $trunk -Name "Position") -Default @(0.0, 0.0, 0.0))
    $requiredMidHeight = [double]$spec.TrunkLength * 0.5
    if ([Math]::Abs([double]$position[2] - $requiredMidHeight) -gt ([double]$spec.TrunkLength * 0.15)) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath/Collision_Trunk center z=$([Math]::Round([double]$position[2], 2)) is not centered along the trunk height $([Math]::Round([double]$spec.TrunkLength, 2))." "Position the trunk box around the vertical trunk span instead of leaving it at the origin."
        return $false
    }

    return $true
}

function Test-BranchBoxes {
    param(
        [object]$TreeObject,
        [string]$ObjectPath,
        [string]$Path,
        [string]$Model
    )

    $branchChildren = @(Get-BranchChildren -Object $TreeObject)
    if ($branchChildren.Count -lt $script:requiredBranchNames.Count) {
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath uses $Model but has $($branchChildren.Count) branch collision child(ren); expected at least $($script:requiredBranchNames.Count)." "Give every authored pine branch its own static BoxCollider child, matching the generated pine branch set."
        return $false
    }

    $ok = $true
    foreach ($branchName in $script:requiredBranchNames) {
        $branch = Get-ChildByName -Object $TreeObject -Name $branchName
        if ($null -eq $branch) {
            Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath is missing $branchName." "Keep one collision child per authored pine branch."
            $ok = $false
            continue
        }

        $collider = Get-BlockingBoxCollider -Object $branch
        if ($null -eq $collider) {
            Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath/$branchName is not a non-trigger static Sandbox.BoxCollider." "Use branch-specific BoxCollider children instead of shared capsules or non-blocking helpers."
            $ok = $false
            continue
        }

        $scale = @(Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $collider -Name "Scale") -Default @(0.0, 0.0, 0.0))
        $sorted = @($scale | Sort-Object -Descending)
        if ([double]$sorted[0] -lt 20.0 -or [double]$sorted[1] -lt 12.0 -or [double]$sorted[2] -lt 12.0) {
            Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath/$branchName BoxCollider scale $($scale -join ',') is too small to cover branch wood." "Size every branch box to cover the visible pine branch cylinder, not only a point on it."
            $ok = $false
        }
    }

    return $ok
}

function Test-TreeObject {
    param(
        [object]$Object,
        [string]$ObjectPath,
        [string]$Path
    )

    $model = Get-TreeModel -Object $Object
    if ([string]::IsNullOrWhiteSpace($model)) {
        return $false
    }

    $script:treeCount++

    # Current standard: EXACT mesh collision. A static, non-trigger
    # Sandbox.ModelCollider on the same GameObject as the renderer, whose
    # Model matches the render model, satisfies the contract (the vmdl
    # carries a PhysicsMeshFile baked by the asset pipeline's collision
    # block). terrain_pine_broad / terrain_pine_windswept use this. The
    # legacy trunk+branch BoxCollider contract below remains valid for
    # terrain_pine, which has no source .blend to re-export from.
    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        # PS 5.1 ConvertFrom-Json strips "__type" (JavaScriptSerializer treats
        # it as type metadata), so detect ModelCollider by shape as well:
        # Model + IsTrigger + Static and no RenderType (which renderers have).
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        $hasModelColliderShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Static") -and
            $null -eq (Get-JsonPropertyValue -Object $component -Name "RenderType")
        if ($componentType -ne "Sandbox.ModelCollider" -and -not $hasModelColliderShape) {
            continue
        }
        $componentEnabled = Get-JsonPropertyValue -Object $component -Name "__enabled"
        if ($componentEnabled -is [bool] -and -not $componentEnabled) {
            continue
        }
        $componentTrigger = Get-JsonPropertyValue -Object $component -Name "IsTrigger"
        if ($componentTrigger -is [bool] -and $componentTrigger) {
            continue
        }
        $componentStatic = Get-JsonPropertyValue -Object $component -Name "Static"
        if (-not ($componentStatic -is [bool] -and $componentStatic)) {
            continue
        }
        $componentModel = [string](Get-JsonPropertyValue -Object $component -Name "Model")
        if (-not $componentModel.Equals($model, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $script:blockingTreeCount++
        return $true
    }

    $ok = $true

    $rootColliders = @()
    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        if (Test-IsColliderComponent -Component $component) {
            $rootColliders += $component
        }
    }
    if ($rootColliders.Count -gt 0) {
        $rootTypes = @($rootColliders | ForEach-Object { [string](Get-JsonPropertyValue -Object $_ -Name "__type") }) -join ", "
        Add-AgentIssue $issues "Error" "Tree Collision" $Path "$ObjectPath still has root collider component(s): $rootTypes." "Use a static ModelCollider matching the render model (mesh-collision contract), or the legacy Collision_Trunk plus Collision_Branch_* BoxCollider children."
        $ok = $false
    }

    if (-not (Test-HierarchyColliderViewer -TreeObject $Object -ObjectPath $ObjectPath -Path $Path -Model $model)) {
        $ok = $false
    }

    if (-not (Test-TrunkBox -TreeObject $Object -ObjectPath $ObjectPath -Path $Path -Model $model)) {
        $ok = $false
    }

    if (-not (Test-BranchBoxes -TreeObject $Object -ObjectPath $ObjectPath -Path $Path -Model $model)) {
        $ok = $false
    }

    if ($ok) {
        $script:blockingTreeCount++
    }

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
            Test-TreeObject -Object $entry.Object -ObjectPath $entry.Path -Path $relative | Out-Null
        }
        return
    }

    foreach ($gameObject in @(Get-JsonPropertyValue -Object $json -Name "GameObjects")) {
        $objects = @(Get-AllObjects -Object $gameObject)
        foreach ($entry in $objects) {
            Test-TreeObject -Object $entry.Object -ObjectPath $entry.Path -Path $relative | Out-Null
        }
    }
}

$script:treeCount = 0
$script:blockingTreeCount = 0
$script:requiredBranchNames = $requiredBranchNames
$script:treeCollisionSpecs = $treeCollisionSpecs

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
        Add-AgentIssue $issues "Error" "Tree Collision" (ConvertTo-AgentRelativePath -Path $prefabPath -Root $Root) "Tree prefab is missing." "Keep each local pine model available as a prefab with built-in trunk and branch collision."
    }
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Tree Collision" "" "Checked $script:treeCount pine tree object(s); $script:blockingTreeCount have trunk BoxCollider coverage and $($script:requiredBranchNames.Count) branch BoxCollider children."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
