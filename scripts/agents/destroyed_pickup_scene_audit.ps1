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

Write-AgentSection "Destroyed Pickup Scene Audit"
Write-Host "Root: $Root"

function Get-JsonPropertyValue {
    param([object]$Object, [string]$Name)

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

function Set-JsonPropertyValue {
    param([object]$Object, [string]$Name, [object]$Value)

    if ($null -eq $Object -or $null -eq $Object.PSObject) {
        return
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $property.Value = $Value
    }
}

function Get-AllObjects {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $objects += Get-AllObjects -Object $child
    }

    return $objects
}

function Find-ObjectsByName {
    param([object[]]$Objects, [string]$Name)

    return @($Objects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $Name })
}

function Find-DestroyedPickupGroups {
    param(
        [object[]]$Objects,
        [string]$Name,
        [object]$PrefabRoot
    )

    $matches = @(Find-ObjectsByName -Objects $Objects -Name $Name)
    foreach ($object in @($Objects)) {
        $prefabPath = [string](Get-JsonPropertyValue -Object $object -Name "__Prefab")
        if ($prefabPath -notin @("prefabs/environment/burnt_car_wreck.prefab", "Assets/prefabs/environment/burnt_car_wreck.prefab")) {
            continue
        }

        $resolved = Resolve-PrefabInstanceForAudit -Instance $object -PrefabRoot $PrefabRoot
        if ($null -eq $resolved) {
            continue
        }

        if ([string](Get-JsonPropertyValue -Object $resolved -Name "Name") -eq $Name) {
            $matches += $resolved
        }
    }

    return @($matches)
}

function Get-ObjectAndComponentGuids {
    param([object]$Object)

    $items = @()
    foreach ($node in @(Get-AllObjects -Object $Object)) {
        $nodeName = [string](Get-JsonPropertyValue -Object $node -Name "Name")
        $items += [pscustomobject]@{
            Guid = [string](Get-JsonPropertyValue -Object $node -Name "__guid")
            Owner = $nodeName
        }

        foreach ($component in @(Get-ObjectComponents -Object $node)) {
            $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
            $items += [pscustomobject]@{
                Guid = [string](Get-JsonPropertyValue -Object $component -Name "__guid")
                Owner = "$nodeName/$componentType"
            }
        }
    }

    return @($items)
}

function Copy-AgentJsonObject {
    param([object]$Object)

    return ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Get-PrefabInstanceIdMap {
    param([object]$Instance)

    $map = @{}
    $rawMap = Get-JsonPropertyValue -Object $Instance -Name "__PrefabIdToInstanceId"
    if ($null -eq $rawMap -or $null -eq $rawMap.PSObject) {
        return $map
    }

    foreach ($property in @($rawMap.PSObject.Properties)) {
        $map[[string]$property.Name] = [string]$property.Value
    }

    return $map
}

function Find-PrefabNodeByGuid {
    param([object]$Object, [string]$Guid, [string]$TargetType)

    if ($null -eq $Object) {
        return $null
    }

    if ($TargetType -eq "GameObject" -and [string](Get-JsonPropertyValue -Object $Object -Name "__guid") -eq $Guid) {
        return $Object
    }

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        if ($TargetType -eq "Component" -and [string](Get-JsonPropertyValue -Object $component -Name "__guid") -eq $Guid) {
            return $component
        }
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $match = Find-PrefabNodeByGuid -Object $child -Guid $Guid -TargetType $TargetType
        if ($null -ne $match) {
            return $match
        }
    }

    return $null
}

function Resolve-PrefabInstanceForAudit {
    param([object]$Instance, [object]$PrefabRoot)

    if ($null -eq $Instance -or $null -eq $PrefabRoot) {
        return $null
    }

    $resolved = Copy-AgentJsonObject -Object $PrefabRoot
    $patch = Get-JsonPropertyValue -Object $Instance -Name "__PrefabInstancePatch"
    foreach ($override in @((Get-JsonPropertyValue -Object $patch -Name "PropertyOverrides"))) {
        $target = Get-JsonPropertyValue -Object $override -Name "Target"
        if ($null -eq $target) {
            continue
        }

        $targetType = [string](Get-JsonPropertyValue -Object $target -Name "Type")
        $targetId = [string](Get-JsonPropertyValue -Object $target -Name "IdValue")
        $propertyName = [string](Get-JsonPropertyValue -Object $override -Name "Property")
        $value = Get-JsonPropertyValue -Object $override -Name "Value"

        if ([string]::IsNullOrWhiteSpace($targetType) -or
            [string]::IsNullOrWhiteSpace($targetId) -or
            [string]::IsNullOrWhiteSpace($propertyName)) {
            continue
        }

        $targetObject = Find-PrefabNodeByGuid -Object $resolved -Guid $targetId -TargetType $targetType
        if ($null -ne $targetObject) {
            Set-JsonPropertyValue -Object $targetObject -Name $propertyName -Value $value
        }
    }

    $idMap = Get-PrefabInstanceIdMap -Instance $Instance
    foreach ($node in @(Get-AllObjects -Object $resolved)) {
        $nodeGuid = [string](Get-JsonPropertyValue -Object $node -Name "__guid")
        if ($idMap.ContainsKey($nodeGuid)) {
            Set-JsonPropertyValue -Object $node -Name "__guid" -Value $idMap[$nodeGuid]
        }

        foreach ($component in @(Get-ObjectComponents -Object $node)) {
            $componentGuid = [string](Get-JsonPropertyValue -Object $component -Name "__guid")
            if ($idMap.ContainsKey($componentGuid)) {
                Set-JsonPropertyValue -Object $component -Name "__guid" -Value $idMap[$componentGuid]
            }
        }
    }

    return $resolved
}

function Get-ComponentByTypeName {
    param([object]$Object, [string]$TypeName)

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        if ($componentType.EndsWith($TypeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        if ($TypeName -eq "BoxCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale")) {
            return $component
        }

        if ($TypeName -eq "ModelRenderer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")) {
            return $component
        }
    }

    return $null
}

function Convert-AgentVectorText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
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
        return $null
    }

    return $parts
}

function Test-JsonBool {
    param([object]$Value, [bool]$Expected)

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value -eq $Expected
    }

    return $Value.ToString().Equals($Expected.ToString(), [System.StringComparison]::OrdinalIgnoreCase)
}

$solidNames = @(
    "Pickup_Frame_CrushedBase",
    "Pickup_Cab_CrushedCore",
    "Pickup_Cab_Roof_Collapsed",
    "Pickup_Hood_BentOpen",
    "Pickup_Bed_TwistedFloor",
    "Pickup_Bed_LeftWall_Bent",
    "Pickup_Bed_RightWall_Collapsed",
    "Pickup_Tailgate_Twisted",
    "Pickup_Door_Left_Displaced",
    "Pickup_Door_Right_Caved",
    "Pickup_FrameRail_Left",
    "Pickup_FrameRail_Right",
    "Pickup_Bumper_Front_Hanging",
    "Pickup_Bumper_Rear_Crushed",
    "Pickup_Axle_Front_Bent",
    "Pickup_Axle_Rear_Exposed",
    "Pickup_Wheel_FL_Destroyed",
    "Pickup_Wheel_FR_Destroyed",
    "Pickup_Wheel_RL_RimOnly",
    "Pickup_Wheel_RR_RimOnly",
    "Pickup_Engine_Block_Exposed",
    "Pickup_Radiator_Crushed",
    "Pickup_Fender_Left_Crumpled",
    "Pickup_Fender_Right_MissingLip"
)

$detailNames = @(
    "Pickup_Cab_A_Pillar_Left",
    "Pickup_Cab_A_Pillar_Right",
    "Pickup_Cab_B_Pillar_Left",
    "Pickup_Cab_B_Pillar_Right",
    "Pickup_Windshield_Frame_Top",
    "Pickup_Windshield_Frame_Bottom",
    "Pickup_Glass_WindshieldShard",
    "Pickup_Glass_SideShard_Left",
    "Pickup_Glass_SideShard_Right",
    "Pickup_Hood_Crease_Left",
    "Pickup_Hood_Crease_Right",
    "Pickup_ScrapeMark_Left",
    "Pickup_ScrapeMark_Right",
    "Pickup_Bed_Rail_Left_Torn",
    "Pickup_Bed_Rail_Right_Torn",
    "Pickup_Grille_Slat_01",
    "Pickup_Grille_Slat_02",
    "Pickup_Grille_Slat_03",
    "Pickup_Headlight_Left_Broken",
    "Pickup_Headlight_Right_Broken",
    "Pickup_Rim_FL_Dented",
    "Pickup_Rim_FR_Dented",
    "Pickup_Rim_RL_Bare",
    "Pickup_Rim_RR_Bare",
    "Pickup_Tire_FL_FlatPatch",
    "Pickup_Tire_FR_FlatPatch",
    "Pickup_PaintScar_Cab",
    "Pickup_PaintScar_Bed",
    "Pickup_Debris_HoodShard",
    "Pickup_Debris_BedShard",
    "Pickup_Debris_GlassScatter",
    "Pickup_Debris_MudDrag",
    "Pickup_Debris_RoadScuff",
    "Pickup_Debris_BoltScatter_01",
    "Pickup_Debris_BoltScatter_02",
    "Pickup_Debris_BoltScatter_03"
)

$knownNames = @($solidNames + $detailNames)

function Test-DestroyedPickupGroup {
    param(
        [object]$Group,
        [string]$Name,
        [double[]]$ExpectedPosition,
        [string]$Relative
    )

    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $Group -Name "Position")
    if ($null -eq $position -or
        [Math]::Abs($position[0] - $ExpectedPosition[0]) -gt 0.1 -or
        [Math]::Abs($position[1] - $ExpectedPosition[1]) -gt 0.1 -or
        [Math]::Abs($position[2] - $ExpectedPosition[2]) -gt 0.1) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name is not at the expected ground anchor." "Keep the destroyed pickup group position stable and use local child offsets."
    }

    $scale = ([string](Get-JsonPropertyValue -Object $Group -Name "Scale")).Replace(" ", "")
    if ($scale -ne "1,1,1") {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name has scale '$scale'." "Keep the group unscaled so local child offsets stay auditable."
    }

    if (@(Get-ObjectComponents -Object $Group).Count -ne 0) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name has direct components." "The group should be empty; geometry belongs to Pickup_* child primitives."
    }

    $children = @(Get-ObjectChildren -Object $Group)
    foreach ($required in @($solidNames + $detailNames)) {
        if (@($children | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $required }).Count -ne 1) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name is missing required child '$required'." "Keep the scene pickup in sync with the S&Box-native prefab contract."
        }
    }

    $solidCount = 0
    $detailCount = 0
    foreach ($child in $children) {
        $childName = [string](Get-JsonPropertyValue -Object $child -Name "Name")
        if ($childName -match "^BurntVehicle_") {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name still contains old child '$childName'." "Replace old BurntVehicle_* scene children with the Pickup_* crashed-pickup layout."
        }
        if ($knownNames -notcontains $childName) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name contains unexpected child '$childName'." "Keep scene pickup instances in sync with the polished prefab contract."
        }

        $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $child -Name "Position")
        if ($null -eq $position) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName has an invalid Position value." "Use explicit local child offsets under the pickup group."
        }
        elseif ([Math]::Abs($position[0]) -gt 210 -or [Math]::Abs($position[1]) -gt 100 -or $position[2] -lt 0 -or $position[2] -gt 110) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName has suspicious local offset $($position -join ',')." "Store local offsets, not world positions, under the pickup group."
        }

        $renderer = Get-ComponentByTypeName -Object $child -TypeName "ModelRenderer"
        $collider = Get-ComponentByTypeName -Object $child -TypeName "BoxCollider"
        if ($null -eq $renderer) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName is missing ModelRenderer." "Every scene pickup child should be editor-visible."
            continue
        }

        $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
        if ($model -notin @("models/dev/box.vmdl", "models/dev/sphere.vmdl")) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName uses model '$model'." "Keep the scene pickup S&Box-native with dev box/sphere primitives."
        }

        if ($solidNames -contains $childName) {
            $solidCount++
            if ($null -eq $collider) {
                Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName is missing BoxCollider." "Solid body, frame, bumper, axle, and wheel pieces should block movement and projectiles."
            }
            else {
                $colliderScale = ([string](Get-JsonPropertyValue -Object $collider -Name "Scale")).Replace(" ", "")
                if ($colliderScale -ne "50,50,50") {
                    Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName has BoxCollider scale '$colliderScale'." "Keep collider scale aligned with scaled S&Box dev primitives."
                }
                if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
                    Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName collider is not static." "The destroyed pickup should be static tactical cover."
                }
                if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
                    Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName collider is a trigger." "The destroyed pickup should be solid cover."
                }
            }
        }
        elseif ($detailNames -contains $childName) {
            $detailCount++
            if ($null -ne $collider) {
                Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName has collision but should be visual detail only." "Keep glass, scrape marks, and small debris non-blocking."
            }
        }
        elseif ($null -ne $collider) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name/$childName has collision but is not listed as solid cover." "Keep collision-bearing pickup pieces explicit in the audit contract."
        }
    }

    if ($solidCount -lt 24 -or $detailCount -lt 36 -or $children.Count -lt 55) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $Relative "$Name is under-detailed: $solidCount solid, $detailCount detail, $($children.Count) total." "Keep scene pickup instances denser than the original blockout-style vehicle."
    }

    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Destroyed Pickup Scene" $Relative "Validated $Name with $solidCount solid piece(s), $detailCount detail piece(s), and $($children.Count) child object(s)."
    }
}

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root
if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating destroyed pickups."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating destroyed pickups."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$destroyedPickupPrefabPath = Join-Path $Root "Assets\prefabs\environment\burnt_car_wreck.prefab"
$destroyedPickupPrefabRelative = ConvertTo-AgentRelativePath -Path $destroyedPickupPrefabPath -Root $Root
$destroyedPickupPrefabRoot = $null
if (-not (Test-Path -LiteralPath $destroyedPickupPrefabPath)) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $destroyedPickupPrefabRelative "Destroyed pickup prefab is missing." "Restore the prefab before validating prefab-backed scene placements."
}
else {
    try {
        $destroyedPickupPrefab = Read-AgentJson -Path $destroyedPickupPrefabPath
        $destroyedPickupPrefabRoot = Get-JsonPropertyValue -Object $destroyedPickupPrefab -Name "RootObject"
        if ($null -eq $destroyedPickupPrefabRoot) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $destroyedPickupPrefabRelative "Destroyed pickup prefab has no RootObject." "Restore the prefab root before validating scene placements."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $destroyedPickupPrefabRelative "Could not parse destroyed pickup prefab JSON: $($_.Exception.Message)" "Fix the prefab before validating prefab-backed scene placements."
    }
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

foreach ($object in $allObjects) {
    $objectName = [string](Get-JsonPropertyValue -Object $object -Name "Name")
    $usesRetiredModel = $false
    foreach ($component in @(Get-ObjectComponents -Object $object)) {
        $model = [string](Get-JsonPropertyValue -Object $component -Name "Model")
        if (-not $usesRetiredModel -and $model -eq "models/burnt_car_wreck.vmdl") {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $relative "$objectName references retired oversized model '$model'." "Use the S&Box-native Pickup_* primitive vehicle and keep the broken Blender-backed VMDL out of the scene."
            $usesRetiredModel = $true
        }
    }
}

foreach ($oldName in @(
    "CenterLane_BurntVehicleBlock_North",
    "CenterLane_BurntVehicleBlock_South",
    "CenterLane_DestroyedPickup_South",
    "BurntCarWreck_NorthLane",
    "BurntCarWreck_SouthLane"
)) {
    $oldMatches = @(Find-ObjectsByName -Objects $allObjects -Name $oldName)
    if ($oldMatches.Count -gt 0) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $relative "Found retired vehicle scene object '$oldName'." "Keep exactly one destroyed pickup in the scene: CenterLane_DestroyedPickup_North."
    }
}

$expectedGroups = @(
    @{ Name = "CenterLane_DestroyedPickup_North"; Position = @(923.058044, 690.0, 0.0) }
)

$presentExpectedGroups = @()
foreach ($expected in $expectedGroups) {
    $presentExpectedGroups += @(Find-DestroyedPickupGroups -Objects $allObjects -Name $expected.Name -PrefabRoot $destroyedPickupPrefabRoot)
}
if ($presentExpectedGroups.Count -eq 0) {
    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Destroyed Pickup Scene" $relative "No CenterLane_DestroyedPickup_* group is present; skipped legacy destroyed-pickup layout checks for the current park terrain scene."
    }
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

foreach ($expected in $expectedGroups) {
    $matches = @(Find-DestroyedPickupGroups -Objects $allObjects -Name $expected.Name -PrefabRoot $destroyedPickupPrefabRoot)
    if ($matches.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $relative "Expected exactly one $($expected.Name); found $($matches.Count)." "Keep exactly one destroyed pickup in the center lane."
        continue
    }

    Test-DestroyedPickupGroup -Group $matches[0] -Name $expected.Name -ExpectedPosition $expected.Position -Relative $relative
}

$pickupGuidOwners = @{}
foreach ($expected in $expectedGroups) {
    $matches = @(Find-DestroyedPickupGroups -Objects $allObjects -Name $expected.Name -PrefabRoot $destroyedPickupPrefabRoot)
    if ($matches.Count -ne 1) {
        continue
    }

    foreach ($item in @(Get-ObjectAndComponentGuids -Object $matches[0])) {
        if ([string]::IsNullOrWhiteSpace($item.Guid)) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $relative "$($item.Owner) is missing a scene GUID." "Keep generated pickup scene objects and components addressable in the editor."
            continue
        }

        if ($pickupGuidOwners.ContainsKey($item.Guid)) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Scene" $relative "$($item.Owner) reuses scene GUID $($item.Guid) from $($pickupGuidOwners[$item.Guid])." "Namespace generated pickup GUIDs by scene group so north and south wrecks do not collide."
        }
        else {
            $pickupGuidOwners[$item.Guid] = $item.Owner
        }
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
