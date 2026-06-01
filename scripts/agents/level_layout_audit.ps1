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

Write-AgentSection "Above/Below Layout Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Layout Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before layout validation."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Layout Scene" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before layout validation."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
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

function Get-AllRawObjects {
    param([object]$Object)

    $objects = @()
    if ($null -eq $Object) {
        return @()
    }

    $objects += $Object
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        foreach ($descendant in @(Get-AllRawObjects -Object $child)) {
            $objects += $descendant
        }
    }

    return $objects
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

function Get-PrefabRootForInstance {
    param([object]$Instance)

    $prefabPath = [string](Get-JsonPropertyValue -Object $Instance -Name "__Prefab")
    if ([string]::IsNullOrWhiteSpace($prefabPath)) {
        return $null
    }

    $relativePath = $prefabPath.Replace("/", "\")
    if ($relativePath.StartsWith("prefabs\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = "Assets\$relativePath"
    }

    $fullPrefabPath = Join-Path $Root $relativePath
    if (-not (Test-Path -LiteralPath $fullPrefabPath)) {
        return $null
    }

    if (-not $script:PrefabRootCache.ContainsKey($fullPrefabPath)) {
        try {
            $prefab = Read-AgentJson -Path $fullPrefabPath
            $script:PrefabRootCache[$fullPrefabPath] = Get-JsonPropertyValue -Object $prefab -Name "RootObject"
        }
        catch {
            $script:PrefabRootCache[$fullPrefabPath] = $null
        }
    }

    return $script:PrefabRootCache[$fullPrefabPath]
}

function Resolve-PrefabInstanceForAudit {
    param([object]$Instance)

    $prefabRoot = Get-PrefabRootForInstance -Instance $Instance
    if ($null -eq $prefabRoot) {
        return $null
    }

    $resolved = Copy-AgentJsonObject -Object $prefabRoot
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
    foreach ($node in @(Get-AllRawObjects -Object $resolved)) {
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

function Get-AllObjects {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    $walkObject = Resolve-PrefabInstanceForAudit -Instance $Object
    if ($null -eq $walkObject) {
        $walkObject = $Object
    }

    $objects = @($walkObject)
    foreach ($child in @(Get-ObjectChildren -Object $walkObject)) {
        foreach ($descendant in @(Get-AllObjects -Object $child)) {
            $objects += $descendant
        }
    }

    return $objects
}

function Find-ObjectsByName {
    param(
        [object[]]$Objects,
        [string]$Name
    )

    return @($Objects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $Name })
}

function Get-ComponentByTypeName {
    param(
        [object]$Object,
        [string]$TypeName
    )

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = Get-JsonPropertyValue -Object $component -Name "__type"
        if ($componentType -and $componentType.EndsWith($TypeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        if ($TypeName -eq "BoxCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale")) {
            return $component
        }

        if ($TypeName -eq "ModelRenderer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")) {
            return $component
        }

        if ($TypeName -eq "PointLight" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "LightColor") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Radius")) {
            return $component
        }
    }

    return $null
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

    $text = $Value.ToString()
    if ($Expected) {
        return $text -match "^(?i:true)$"
    }

    return $text -match "^(?i:false)$"
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

function Test-ObjectHasComponent {
    param(
        [object]$Object,
        [string]$TypeName
    )

    return $null -ne (Get-ComponentByTypeName -Object $Object -TypeName $TypeName)
}

function Get-SolidObjects {
    param([object]$Group)

    return @(Get-AllObjects -Object $Group | Where-Object {
        (Test-ObjectHasComponent -Object $_ -TypeName "BoxCollider") -and
        (Test-ObjectHasComponent -Object $_ -TypeName "ModelRenderer")
    })
}

function Get-VisualMarkerObjects {
    param([object]$Group)

    return @(Get-AllObjects -Object $Group | Where-Object {
        (Test-ObjectHasComponent -Object $_ -TypeName "ModelRenderer") -and
        -not (Test-ObjectHasComponent -Object $_ -TypeName "BoxCollider")
    })
}

function Test-RequiredObjects {
    param(
        [object[]]$AllObjects,
        [string]$Context,
        [string[]]$Names
    )

    foreach ($required in $Names) {
        if (@(Find-ObjectsByName -Objects $AllObjects -Name $required).Count -lt 1) {
            Add-AgentIssue $issues "Error" $Context $relative "Missing required object '$required'." "Restore or regenerate the Above/Below level pass."
        }
    }
}

function Get-ObjectName {
    param([object]$Object)
    return [string](Get-JsonPropertyValue -Object $Object -Name "Name")
}

$script:PrefabRootCache = @{}

$rootObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    foreach ($object in @(Get-AllObjects -Object $rootObject)) {
        $rootObjects += $object
    }
}

$levelPassMatches = @(Find-ObjectsByName -Objects $rootObjects -Name "LevelDesignPass_AboveBelow")
if ($levelPassMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Layout Pass" $relative "Expected exactly one LevelDesignPass_AboveBelow group; found $($levelPassMatches.Count)." "Regenerate the scene pass so layout validation has a single authoritative group."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$levelPass = $levelPassMatches[0]
$levelObjects = @(Get-AllObjects -Object $levelPass)
$levelNames = @($levelObjects | ForEach-Object { Get-ObjectName -Object $_ })

Test-RequiredObjects -AllObjects $levelObjects -Context "Layout Groups" -Names @(
    "Lane_North_Infiltration",
    "Lane_Center_Killbox",
    "Lane_South_Flank",
    "OperatorNestPatterns",
    "ReadabilityVFX_Blockout",
    "AssetProductionPlaceholders"
)

$laneChecks = @(
    @{ Name = "Lane_North_Infiltration"; MinSolid = 8; MinMarkers = 0; Required = @("NorthLane_WaterTower_Berm_West", "NorthLane_WaterTower_Berm_East", "NorthLane_RoadSightBreaker_Left", "NorthLane_RoadSightBreaker_Right") },
    @{ Name = "Lane_Center_Killbox"; MinSolid = 8; MinMarkers = 0; Required = @("CenterLane_GPSBreak_WestTall", "CenterLane_GPSBreak_EastTall", "CenterLane_ServiceBarricade_West", "CenterLane_ServiceBarricade_East") },
    @{ Name = "Lane_South_Flank"; MinSolid = 7; MinMarkers = 0; Required = @("SouthLane_TrenchConnector_West", "SouthLane_TrenchConnector_Mid", "SouthLane_DroneDive_Baffle", "SouthLane_EastHouse_BreachCover") }
)

foreach ($laneCheck in $laneChecks) {
    $lane = @(Find-ObjectsByName -Objects $levelObjects -Name $laneCheck.Name)
    if ($lane.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Lane Layout" $relative "Expected one $($laneCheck.Name) group; found $($lane.Count)." "Regenerate the Above/Below level pass."
        continue
    }

    $solidObjects = @(Get-SolidObjects -Group $lane[0])
    $markers = @(Get-VisualMarkerObjects -Group $lane[0])
    if ($solidObjects.Count -lt [int]$laneCheck.MinSolid) {
        Add-AgentIssue $issues "Error" "Lane Layout" $relative "$($laneCheck.Name) has $($solidObjects.Count) solid cover object(s), expected at least $($laneCheck.MinSolid)." "Add collision-bearing cover/sightline blockers to this lane."
    }
    if ($markers.Count -lt [int]$laneCheck.MinMarkers) {
        Add-AgentIssue $issues "Error" "Lane Readability" $relative "$($laneCheck.Name) has $($markers.Count) route marker object(s), expected at least $($laneCheck.MinMarkers)." "Add non-solid route/readability markers for the lane."
    }

    $positions = @($solidObjects | ForEach-Object { Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $_ -Name "Position") } | Where-Object { $null -ne $_ })
    $hasWest = @($positions | Where-Object { $_[0] -lt -900 }).Count -gt 0
    $hasMid = @($positions | Where-Object { $_[0] -ge -900 -and $_[0] -le 900 }).Count -gt 0
    $hasEast = @($positions | Where-Object { $_[0] -gt 900 }).Count -gt 0
    if (-not ($hasWest -and $hasMid -and $hasEast)) {
        Add-AgentIssue $issues "Error" "Lane Layout" $relative "$($laneCheck.Name) does not place solid cover across west, midfield, and east sections." "Keep the soldier lane readable from both directions instead of clustering cover in one area."
    }

    Test-RequiredObjects -AllObjects @(Get-AllObjects -Object $lane[0]) -Context "Lane Layout" -Names $laneCheck.Required

    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Lane Layout" $relative "$($laneCheck.Name): $($solidObjects.Count) solid object(s), $($markers.Count) marker object(s)."
    }
}

$gpsBreakWest = @(Find-ObjectsByName -Objects $levelObjects -Name "CenterLane_GPSBreak_WestTall")
$gpsBreakEast = @(Find-ObjectsByName -Objects $levelObjects -Name "CenterLane_GPSBreak_EastTall")
foreach ($breaker in @($gpsBreakWest + $gpsBreakEast)) {
    if ($null -eq $breaker) {
        continue
    }

    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $breaker -Name "Scale")
    if ($null -eq $scale -or $scale[2] -lt 5.0) {
        Add-AgentIssue $issues "Error" "Drone Sightlines" $relative "$(Get-ObjectName -Object $breaker) is not tall enough to interrupt GPS sightlines." "Keep center lane GPS blockers tall while preserving ground route gaps."
    }
}

$nestChecks = @(
    @{ Name = "OperatorNest_EastLaunch"; MinSolid = 3; Required = @("EastLaunch_SignalLight") },
    @{ Name = "OperatorNest_MidService"; MinSolid = 3; Required = @("MidService_SignalLight") },
    @{ Name = "OperatorNest_NorthHouse"; MinSolid = 2; Required = @("NorthHouse_SignalLight") },
    @{ Name = "OperatorNest_SouthHouse"; MinSolid = 2; Required = @("SouthHouse_SignalLight") }
)

foreach ($nestCheck in $nestChecks) {
    $nest = @(Find-ObjectsByName -Objects $levelObjects -Name $nestCheck.Name)
    if ($nest.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "Expected one $($nestCheck.Name) group; found $($nest.Count)." "Regenerate the operator nest layout."
        continue
    }

    $nestObjects = @(Get-AllObjects -Object $nest[0])
    $solidObjects = @(Get-SolidObjects -Group $nest[0])
    $approachMarkers = @($nestObjects | Where-Object { (Get-ObjectName -Object $_) -match "ApproachPaint" })
    $escapeMarkers = @($nestObjects | Where-Object { (Get-ObjectName -Object $_) -match "EscapeRead" })
    if ($solidObjects.Count -lt [int]$nestCheck.MinSolid) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) has $($solidObjects.Count) solid cover object(s), expected at least $($nestCheck.MinSolid)." "Keep each operator nest defensible with authored cover."
    }
    if ($approachMarkers.Count -gt 0) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) still contains $($approachMarkers.Count) cyan approach paint marker(s)." "Use physical cover, silhouettes, or non-blue escape/read markers instead of blue blockout line strips."
    }
    if ($escapeMarkers.Count -gt 0) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) still contains $($escapeMarkers.Count) escape/read line marker(s)." "Use physical cover, silhouettes, or arted non-line readability instead of blockout line strips."
    }

    $solidDirections = New-Object System.Collections.Generic.HashSet[string]
    foreach ($solid in $solidObjects) {
        $solidName = Get-ObjectName -Object $solid
        foreach ($direction in @("North", "South", "East", "West")) {
            if ($solidName -match $direction) {
                [void]$solidDirections.Add($direction)
            }
        }
    }
    if ($solidDirections.Count -ge 4) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) appears to have solid cover on all four cardinal sides." "Remove one blocker or replace it with a visual marker so the nest stays breachable."
    }

    Test-RequiredObjects -AllObjects $nestObjects -Context "Operator Nests" -Names $nestCheck.Required

    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Operator Nests" $relative "$($nestCheck.Name): $($solidObjects.Count) solid object(s), $($approachMarkers.Count) approach marker(s), $($escapeMarkers.Count) escape/read marker(s)."
    }
}

Test-RequiredObjects -AllObjects $levelObjects -Context "Readability VFX" -Names @(
    "LaunchPad_Glow_North",
    "LaunchPad_Glow_South",
    "WaterTower_PerchMarker",
    "NorthRoof_PerchMarker",
    "SouthRoof_PerchMarker"
)

$prohibitedBlueLineNames = @($levelObjects | Where-Object {
    (Get-ObjectName -Object $_) -match "PaintedRoute|ApproachPaint|BreachMarker|DangerStripe|EscapeRead|LaunchPad_Glow_.*_GlowMarker"
})
foreach ($marker in $prohibitedBlueLineNames) {
    Add-AgentIssue $issues "Error" "Readability VFX" $relative "$(Get-ObjectName -Object $marker) is a retired blockout line marker." "Remove line strips from the playable level and keep the scene generator from recreating them."
}

$prohibitedEmpGlowLines = @($levelObjects | Where-Object {
    $renderer = Get-ComponentByTypeName -Object $_ -TypeName "ModelRenderer"
    if ($null -eq $renderer) {
        return $false
    }

    $material = [string](Get-JsonPropertyValue -Object $renderer -Name "MaterialOverride")
    $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    if ($model -ne "models/dev/box.vmdl" -or $material -ne "materials/emp_glow.vmat") {
        return $false
    }

    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $_ -Name "Scale")
    if ($null -eq $scale) {
        return $false
    }

    $thinAxes = @($scale | Where-Object { $_ -le 0.09 }).Count
    $longAxes = @($scale | Where-Object { $_ -ge 1.5 }).Count
    return ($thinAxes -ge 1 -and $longAxes -ge 1)
})
foreach ($marker in $prohibitedEmpGlowLines) {
    Add-AgentIssue $issues "Error" "Readability VFX" $relative "$(Get-ObjectName -Object $marker) is a line-like emp_glow dev box." "Use non-line, arted readability cues instead of glowing blockout strips."
}

$solidColliderObjects = @(Get-AllObjects -Object $levelPass | Where-Object { Test-ObjectHasComponent -Object $_ -TypeName "BoxCollider" })
foreach ($object in $solidColliderObjects) {
    $name = Get-ObjectName -Object $object
    $box = Get-ComponentByTypeName -Object $object -TypeName "BoxCollider"
    $model = Get-ComponentByTypeName -Object $object -TypeName "ModelRenderer"
    if ($null -eq $model) {
        Add-AgentIssue $issues "Error" "Collision Contract" $relative "$name has collision but no renderer in the Above/Below level pass." "Avoid invisible wall boxes across playable openings."
    }

    $isTrigger = Get-JsonPropertyValue -Object $box -Name "IsTrigger"
    if (-not (Test-JsonBool -Value $isTrigger -Expected $false)) {
        Add-AgentIssue $issues "Error" "Collision Contract" $relative "$name has a trigger BoxCollider in the Above/Below pass." "Keep new level-pass solids non-trigger; ladder volumes remain authored elsewhere."
    }

    $colliderScale = [string](Get-JsonPropertyValue -Object $box -Name "Scale")
    if ($colliderScale.Replace(" ", "") -ne "50,50,50") {
        Add-AgentIssue $issues "Error" "Collision Contract" $relative "$name uses BoxCollider scale '$colliderScale' instead of local 50,50,50." "Keep blockout collider scale aligned with the scaled dev-box renderer."
    }

    if ($name -match "Paint|Marker|Glow|BreachMarker|Stripe|Read") {
        Add-AgentIssue $issues "Error" "Collision Contract" $relative "$name is a readability marker with collision." "Readability markers must stay visual-only."
    }

    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $object -Name "Scale")
    if ($null -ne $scale) {
        $x = [Math]::Abs($scale[0])
        $y = [Math]::Abs($scale[1])
        $z = [Math]::Abs($scale[2])
        $broadWall = (($x -ge 8.0 -and $y -ge 1.0) -or ($y -ge 8.0 -and $x -ge 1.0)) -and $z -ge 2.0
        if ($broadWall) {
            Add-AgentIssue $issues "Error" "Collision Contract" $relative "$name is broad enough to risk blocking a playable opening (scale $($scale -join ','))." "Split it into readable cover pieces instead of one broad wall."
        }
    }
}

$visualMarkers = @(Get-VisualMarkerObjects -Group $levelPass)
foreach ($marker in $visualMarkers) {
    $name = Get-ObjectName -Object $marker
    if ($name -notmatch "Paint|Marker|Glow|Breach|Stripe|Read|BurntVehicle_(Ash|BrokenGlass|SootScale|HotWarning)") {
        Add-AgentIssue $issues "Warning" "Readability VFX" $relative "$name is visual-only but does not use a known marker/readability name." "Confirm this is intentional and not missing collision."
    }
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Layout Pass" $relative "Validated $($levelObjects.Count) object(s), $($solidColliderObjects.Count) collision-bearing object(s), and $($visualMarkers.Count) visual marker object(s) in LevelDesignPass_AboveBelow."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
