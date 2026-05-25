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

function Get-AllObjects {
    param([object]$Object)

    $objects = @()
    if ($null -eq $Object) {
        return @()
    }

    $objects += $Object
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
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
    @{ Name = "Lane_North_Infiltration"; MinSolid = 8; MinMarkers = 3; Required = @("NorthLane_WaterTower_Berm_West", "NorthLane_WaterTower_Berm_East", "NorthLane_RoadSightBreaker_Left", "NorthLane_RoadSightBreaker_Right") },
    @{ Name = "Lane_Center_Killbox"; MinSolid = 8; MinMarkers = 2; Required = @("CenterLane_GPSBreak_WestTall", "CenterLane_GPSBreak_EastTall", "CenterLane_ServiceBarricade_West", "CenterLane_ServiceBarricade_East") },
    @{ Name = "Lane_South_Flank"; MinSolid = 7; MinMarkers = 3; Required = @("SouthLane_TrenchConnector_West", "SouthLane_TrenchConnector_Mid", "SouthLane_DroneDive_Baffle", "SouthLane_EastHouse_BreachCover") }
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
    @{ Name = "OperatorNest_EastLaunch"; MinSolid = 3; Required = @("EastLaunch_ApproachPaint_North", "EastLaunch_ApproachPaint_South", "EastLaunch_EscapeRead_East", "EastLaunch_SignalLight") },
    @{ Name = "OperatorNest_MidService"; MinSolid = 3; Required = @("MidService_ApproachPaint_West", "MidService_ApproachPaint_South", "MidService_EscapeRead_East", "MidService_SignalLight") },
    @{ Name = "OperatorNest_NorthHouse"; MinSolid = 2; Required = @("NorthHouse_ApproachPaint_West", "NorthHouse_ApproachPaint_South", "NorthHouse_EscapeRead_Roof", "NorthHouse_SignalLight") },
    @{ Name = "OperatorNest_SouthHouse"; MinSolid = 2; Required = @("SouthHouse_ApproachPaint_West", "SouthHouse_ApproachPaint_North", "SouthHouse_EscapeRead_Roof", "SouthHouse_SignalLight") }
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
    if ($approachMarkers.Count -lt 2) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) has $($approachMarkers.Count) visible soldier approach marker(s), expected at least 2." "Each nest needs at least two readable soldier approach routes."
    }
    if ($escapeMarkers.Count -lt 1) {
        Add-AgentIssue $issues "Error" "Operator Nests" $relative "$($nestCheck.Name) has no visible escape/read marker." "Each nest needs one obvious escape or read path so it is not a sealed safe room."
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
    "SouthRoof_PerchMarker",
    "BreachMarker_NorthHouse_West",
    "BreachMarker_NorthHouse_South",
    "BreachMarker_SouthHouse_West",
    "BreachMarker_SouthHouse_North"
)

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
