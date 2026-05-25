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
$boxUnit = 50.0
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
$surface = @(Find-ObjectsByName -Objects $roadChildren -Name "RoadSurface_Main")
if ($surface.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one RoadSurface_Main under RoadCorridor_Main; found $($surface.Count)." "Keep the road surface parented directly under the road corridor."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$surfaceScale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $surface[0] -Name "Scale")
if ($null -eq $surfaceScale) {
    Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "RoadSurface_Main has an invalid Scale value." "Use explicit numeric scene scale for road coverage checks."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

foreach ($curbName in @("RoadCurb_West", "RoadCurb_East")) {
    $curb = @(Find-ObjectsByName -Objects $roadChildren -Name $curbName)
    if ($curb.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "Expected exactly one $curbName under RoadCorridor_Main; found $($curb.Count)." "Keep both road curbs parented directly under the road corridor."
        continue
    }

    $curbScale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $curb[0] -Name "Scale")
    if ($null -eq $curbScale) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$curbName has an invalid Scale value." "Use explicit numeric scene scale for road curb coverage checks."
        continue
    }

    if ([Math]::Abs($curbScale[1] - $surfaceScale[1]) -gt $scaleTolerance) {
        Add-AgentIssue $issues "Error" "Road Lane Markings" $relative "$curbName length scale is $($curbScale[1]), but RoadSurface_Main length scale is $($surfaceScale[1])." "Extend both curbs to the full road-surface length."
    }
}

$surfaceHalfLength = ($surfaceScale[1] * $boxUnit) / 2.0
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

$dashes = @($roadChildren | Where-Object {
    ([string](Get-JsonPropertyValue -Object $_ -Name "Name")).StartsWith("RoadDash_", [System.StringComparison]::Ordinal)
} | ForEach-Object {
    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $_ -Name "Position")
    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $_ -Name "Scale")
    [pscustomobject]@{
        Name = [string](Get-JsonPropertyValue -Object $_ -Name "Name")
        Position = $position
        Scale = $scale
    }
} | Sort-Object { if ($null -eq $_.Position) { [double]::NegativeInfinity } else { $_.Position[1] } })

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
