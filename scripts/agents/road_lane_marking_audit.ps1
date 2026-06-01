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

Write-AgentSection "Road Lane Marking Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

$roadCenterX = 416.190948
$dashSpacing = 260.0
$dashEdgeMargin = 260.0
$planeHalfUnit = 50.0
$boxHalfUnit = 25.0
$positionTolerance = 0.25
$scaleTolerance = 0.01

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
    param(
        [object[]]$Objects,
        [string]$Name
    )

    return @($Objects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $Name })
}

function Get-PrefabInstanceRootPropertyValue {
    param(
        [object]$Instance,
        [object]$PrefabRoot,
        [string]$PropertyName
    )

    $value = Get-JsonPropertyValue -Object $PrefabRoot -Name $PropertyName
    $rootGuid = [string](Get-JsonPropertyValue -Object $PrefabRoot -Name "__guid")
    $patch = Get-JsonPropertyValue -Object $Instance -Name "__PrefabInstancePatch"
    foreach ($override in @((Get-JsonPropertyValue -Object $patch -Name "PropertyOverrides"))) {
        $target = Get-JsonPropertyValue -Object $override -Name "Target"
        if ($null -eq $target) {
            continue
        }

        $targetType = [string](Get-JsonPropertyValue -Object $target -Name "Type")
        $targetId = [string](Get-JsonPropertyValue -Object $target -Name "IdValue")
        $overridePropertyName = [string](Get-JsonPropertyValue -Object $override -Name "Property")
        if ($targetType -eq "GameObject" -and $targetId -eq $rootGuid -and $overridePropertyName -eq $PropertyName) {
            $value = Get-JsonPropertyValue -Object $override -Name "Value"
        }
    }

    return $value
}

function Get-PrefabRootForInstance {
    param(
        [object]$Instance,
        [hashtable]$PrefabRootsByPath
    )

    $prefabPath = [string](Get-JsonPropertyValue -Object $Instance -Name "__Prefab")
    if ([string]::IsNullOrWhiteSpace($prefabPath)) {
        return $null
    }

    if ($PrefabRootsByPath.ContainsKey($prefabPath)) {
        return $PrefabRootsByPath[$prefabPath]
    }

    $assetsPath = "Assets/$prefabPath"
    if ($PrefabRootsByPath.ContainsKey($assetsPath)) {
        return $PrefabRootsByPath[$assetsPath]
    }

    return $null
}

function Get-RoadChildResolvedName {
    param(
        [object]$Child,
        [hashtable]$PrefabRootsByPath
    )

    $name = [string](Get-JsonPropertyValue -Object $Child -Name "Name")
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        return $name
    }

    $prefabRoot = Get-PrefabRootForInstance -Instance $Child -PrefabRootsByPath $PrefabRootsByPath
    if ($null -eq $prefabRoot) {
        return ""
    }

    return [string](Get-PrefabInstanceRootPropertyValue -Instance $Child -PrefabRoot $prefabRoot -PropertyName "Name")
}

function Get-RoadChildResolvedProperty {
    param(
        [object]$Child,
        [hashtable]$PrefabRootsByPath,
        [string]$PropertyName
    )

    $value = Get-JsonPropertyValue -Object $Child -Name $PropertyName
    if ($null -ne $value) {
        return $value
    }

    $prefabRoot = Get-PrefabRootForInstance -Instance $Child -PrefabRootsByPath $PrefabRootsByPath
    if ($null -eq $prefabRoot) {
        return $null
    }

    return Get-PrefabInstanceRootPropertyValue -Instance $Child -PrefabRoot $prefabRoot -PropertyName $PropertyName
}

function Find-RoadChildrenByResolvedName {
    param(
        [object[]]$Children,
        [hashtable]$PrefabRootsByPath,
        [string]$Name
    )

    return @($Children | Where-Object {
        (Get-RoadChildResolvedName -Child $_ -PrefabRootsByPath $PrefabRootsByPath) -eq $Name
    })
}

function Convert-RoadDashChild {
    param(
        [object]$Child,
        [hashtable]$PrefabRootsByPath
    )

    $name = Get-RoadChildResolvedName -Child $Child -PrefabRootsByPath $PrefabRootsByPath
    if ($name.StartsWith("RoadDash_", [System.StringComparison]::Ordinal)) {
        $position = Get-RoadChildResolvedProperty -Child $Child -PrefabRootsByPath $PrefabRootsByPath -PropertyName "Position"
        $scale = Get-RoadChildResolvedProperty -Child $Child -PrefabRootsByPath $PrefabRootsByPath -PropertyName "Scale"
        return [pscustomobject]@{
            Name = $name
            Position = Convert-AgentVectorText -Value $position
            Scale = Convert-AgentVectorText -Value $scale
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

function Test-VectorNear {
    param(
        [double[]]$Actual,
        [double[]]$Expected,
        [double]$Tolerance
    )

    if ($null -eq $Actual -or $Actual.Count -ne $Expected.Count) {
        return $false
    }

    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ([Math]::Abs($Actual[$i] - $Expected[$i]) -gt $Tolerance) {
            return $false
        }
    }

    return $true
}

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating road lane markings."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating road lane markings."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

$roadMatches = @(Find-ObjectsByName -Objects $allObjects -Name "RoadCorridor_Main")
if ($roadMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one RoadCorridor_Main; found $($roadMatches.Count)." "Keep one north-south road corridor as the lane-marking source of truth."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$road = $roadMatches[0]
$roadChildren = @(Get-ObjectChildren -Object $road)
$roadPrefabRootsByPath = @{}
foreach ($roadPrefabRelativePath in @(
    "Assets\prefabs\environment\road_lane_dash.prefab",
    "Assets\prefabs\environment\road_surface.prefab",
    "Assets\prefabs\environment\road_shoulder.prefab",
    "Assets\prefabs\environment\road_curb.prefab"
)) {
    $roadPrefabPath = Join-Path $Root $roadPrefabRelativePath
    if (Test-Path -LiteralPath $roadPrefabPath) {
        try {
            $roadPrefab = Read-AgentJson -Path $roadPrefabPath
            $rootObject = Get-JsonPropertyValue -Object $roadPrefab -Name "RootObject"
            $normalizedRelativePath = $roadPrefabRelativePath.Replace("\", "/")
            $roadPrefabRootsByPath[$normalizedRelativePath] = $rootObject
            $roadPrefabRootsByPath[$normalizedRelativePath.Replace("Assets/", "")] = $rootObject
        }
        catch {
            $roadPrefabDisplayPath = ConvertTo-AgentRelativePath -Path $roadPrefabPath -Root $Root
            Add-AgentIssue $issues "Error" "Road Lane Markings" $roadPrefabDisplayPath "Could not parse road prefab JSON: $($_.Exception.Message)" "Fix the prefab before validating prefab-backed road placements."
        }
    }
}

$surface = @(Find-RoadChildrenByResolvedName -Children $roadChildren -PrefabRootsByPath $roadPrefabRootsByPath -Name "RoadSurface_Main")
if ($surface.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one RoadSurface_Main under RoadCorridor_Main; found $($surface.Count)." "Keep the road surface parented directly under the road corridor."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$surfaceScale = Convert-AgentVectorText -Value (Get-RoadChildResolvedProperty -Child $surface[0] -PrefabRootsByPath $roadPrefabRootsByPath -PropertyName "Scale")
if ($null -eq $surfaceScale) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "RoadSurface_Main has an invalid Scale value." "Use explicit numeric scene scale for road coverage checks."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

foreach ($shoulderName in @("RoadShoulder_West", "RoadShoulder_East")) {
    $shoulder = @(Find-RoadChildrenByResolvedName -Children $roadChildren -PrefabRootsByPath $roadPrefabRootsByPath -Name $shoulderName)
    if ($shoulder.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one $shoulderName under RoadCorridor_Main; found $($shoulder.Count)." "Keep both road shoulders parented directly under the road corridor."
        continue
    }

    $shoulderScale = Convert-AgentVectorText -Value (Get-RoadChildResolvedProperty -Child $shoulder[0] -PrefabRootsByPath $roadPrefabRootsByPath -PropertyName "Scale")
    if ($null -eq $shoulderScale) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$shoulderName has an invalid Scale value." "Use explicit numeric scene scale for road shoulder coverage checks."
        continue
    }

    if ([Math]::Abs($shoulderScale[1] - $surfaceScale[1]) -gt $scaleTolerance) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$shoulderName length scale is $($shoulderScale[1]), but RoadSurface_Main length scale is $($surfaceScale[1])." "Keep road shoulders the same rendered length as the asphalt plane."
    }
}

$surfaceHalfLength = $surfaceScale[1] * $planeHalfUnit
foreach ($curbName in @("RoadCurb_West", "RoadCurb_East")) {
    $curb = @(Find-RoadChildrenByResolvedName -Children $roadChildren -PrefabRootsByPath $roadPrefabRootsByPath -Name $curbName)
    if ($curb.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one $curbName under RoadCorridor_Main; found $($curb.Count)." "Keep both road curbs parented directly under the road corridor."
        continue
    }

    $curbScale = Convert-AgentVectorText -Value (Get-RoadChildResolvedProperty -Child $curb[0] -PrefabRootsByPath $roadPrefabRootsByPath -PropertyName "Scale")
    if ($null -eq $curbScale) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$curbName has an invalid Scale value." "Use explicit numeric scene scale for road curb coverage checks."
        continue
    }

    $curbHalfLength = $curbScale[1] * $boxHalfUnit
    if ([Math]::Abs($curbHalfLength - $surfaceHalfLength) -gt $scaleTolerance) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$curbName half-length is $([Math]::Round($curbHalfLength, 2)), but RoadSurface_Main half-length is $([Math]::Round($surfaceHalfLength, 2))." "Match rendered curb length to the asphalt plane; dev boxes use a 25-unit half extent while dev planes use 50."
    }
}

$dashExtent = [Math]::Floor(($surfaceHalfLength - $dashEdgeMargin) / $dashSpacing) * $dashSpacing
if ($dashExtent -lt $dashSpacing) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "RoadSurface_Main is too short to derive centerline dash coverage." "Check the road surface scale before validating dashes."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$expectedDashYs = New-Object System.Collections.Generic.List[double]
for ($y = -$dashExtent; $y -le $dashExtent + 0.01; $y += $dashSpacing) {
    $expectedDashYs.Add([double]$y)
}

$dashes = @($roadChildren | ForEach-Object {
    Convert-RoadDashChild -Child $_ -PrefabRootsByPath $roadPrefabRootsByPath
} | Where-Object { $null -ne $_ } | Sort-Object { if ($null -eq $_.Position) { [double]::NegativeInfinity } else { $_.Position[1] } })

if ($dashes.Count -ne $expectedDashYs.Count) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected $($expectedDashYs.Count) centered road dash(es) for the current road length; found $($dashes.Count)." "Copy the dash markers down the full road at 260-unit intervals."
}

foreach ($dash in $dashes) {
    if ($dash.Name -notmatch "^RoadDash_\d{2}$") {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' is not using a stable RoadDash_## name." "Rename copied dashes into the RoadDash_## sequence instead of leaving editor duplicate names."
    }

    if ($null -eq $dash.Position) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' has an invalid Position value." "Use explicit numeric scene coordinates for every centerline dash."
        continue
    }

    if ([Math]::Abs($dash.Position[0] - $roadCenterX) -gt $positionTolerance) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' is at x=$($dash.Position[0]), expected centerline x=$roadCenterX." "Center copied dashes on the road centerline."
    }

    if ([Math]::Abs($dash.Position[2] - 2.0) -gt $positionTolerance) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' is at z=$($dash.Position[2]), expected z=2." "Keep copied dashes flush with the other road markings."
    }

    if (-not (Test-VectorNear -Actual $dash.Scale -Expected @(0.16, 2.4, 0.04) -Tolerance $scaleTolerance)) {
        $scaleText = if ($null -eq $dash.Scale) { "<invalid>" } else { $dash.Scale -join "," }
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' has scale $scaleText." "Keep all center dashes at scale 0.16,2.4,0.04."
    }

    $matchedExpectedY = $false
    foreach ($expectedY in $expectedDashYs) {
        if ([Math]::Abs($dash.Position[1] - $expectedY) -le $positionTolerance) {
            $matchedExpectedY = $true
            break
        }
    }

    if (-not $matchedExpectedY) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Dash '$($dash.Name)' is at y=$($dash.Position[1]), which is outside the expected 260-unit centerline sequence." "Keep centerline dashes evenly spaced along the full road."
    }
}

foreach ($expectedY in $expectedDashYs) {
    $matches = @($dashes | Where-Object { $null -ne $_.Position -and [Math]::Abs($_.Position[1] - $expectedY) -le $positionTolerance })
    if ($matches.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected one centered dash at y=$expectedY; found $($matches.Count)." "Fill every 260-unit dash slot along the road centerline."
    }
}

if ($ShowInfo) {
    $firstY = if ($dashes.Count -gt 0 -and $null -ne $dashes[0].Position) { $dashes[0].Position[1] } else { "<none>" }
    $lastDash = if ($dashes.Count -gt 0) { $dashes[$dashes.Count - 1] } else { $null }
    $lastY = if ($null -ne $lastDash -and $null -ne $lastDash.Position) { $lastDash.Position[1] } else { "<none>" }
    Add-AgentIssue $issues "Info" "Road Lane Markings" $relative "Road surface scaleY=$($surfaceScale[1]); expected dash range -$dashExtent to $dashExtent; actual dash range $firstY to $lastY."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
