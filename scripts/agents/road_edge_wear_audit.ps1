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

Write-AgentSection "Road Edge Wear Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

$roadCenterX = 416.190948
$roadLengthScale = 218.529922
$boxUnit = 50.0
$expectedMaterial = "materials/arena/road_edge_wear.vmat"
$expectedWearPerSide = 12

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

function Convert-AgentQuaternionText {
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

    if ($parts.Count -ne 4 -or $parts -contains $null) {
        return $null
    }

    return $parts
}

function Get-ComponentByTypeName {
    param(
        [object]$Object,
        [string]$TypeName
    )

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        if ($componentType.EndsWith($TypeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        if ($TypeName -eq "ModelRenderer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")) {
            return $component
        }

        if ($TypeName -eq "BoxCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale")) {
            return $component
        }
    }

    return $null
}

function Test-MaterialReference {
    param(
        [string]$MaterialResourcePath,
        [string]$TextureKey,
        [string]$ExpectedTexture
    )

    $materialFullPath = Resolve-AgentResourcePath -ResourcePath $MaterialResourcePath -Root $Root
    if ($null -eq $materialFullPath -or -not (Test-Path -LiteralPath $materialFullPath)) {
        Add-AgentIssue $issues "Error" "Road Edge Wear Material" "Assets/$MaterialResourcePath" "Road edge wear material is missing." "Add a real textured material for the road-edge wear decals."
        return
    }

    $materialRelative = ConvertTo-AgentRelativePath -Path $materialFullPath -Root $Root
    $text = Get-Content -LiteralPath $materialFullPath -Raw
    if ($text -notmatch '"F_ALPHA_TEST"\s*"1"') {
        Add-AgentIssue $issues "Error" "Road Edge Wear Material" $materialRelative "Material is not alpha-tested." "Use a translucency mask so the road wear reads as an irregular texture instead of a rectangle."
    }

    $escapedKey = [regex]::Escape($TextureKey)
    $match = [regex]::Match($text, '"' + $escapedKey + '"\s*"(?<value>[^"]+)"')
    if (-not $match.Success) {
        Add-AgentIssue $issues "Error" "Road Edge Wear Material" $materialRelative "Material is missing $TextureKey." "Reference the generated road-edge wear texture maps from the material."
        return
    }

    $actualTexture = $match.Groups["value"].Value.Replace("\", "/")
    if (-not $actualTexture.Equals($ExpectedTexture, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-AgentIssue $issues "Error" "Road Edge Wear Material" $materialRelative "$TextureKey points at '$actualTexture'." "Keep $TextureKey on $ExpectedTexture so the audit proves the intended texture is used."
    }

    $textureFullPath = Resolve-AgentResourcePath -ResourcePath $actualTexture -Root $Root
    if ($null -eq $textureFullPath -or -not (Test-Path -LiteralPath $textureFullPath)) {
        Add-AgentIssue $issues "Error" "Road Edge Wear Material" $materialRelative "$TextureKey texture '$actualTexture' is missing." "Generate and commit the referenced road-edge wear texture."
    }
}

Test-MaterialReference -MaterialResourcePath $expectedMaterial -TextureKey "TextureColor" -ExpectedTexture "materials/arena/road_edge_wear_color.png"
Test-MaterialReference -MaterialResourcePath $expectedMaterial -TextureKey "TextureTranslucency" -ExpectedTexture "materials/arena/road_edge_wear_trans.png"

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating road edge wear."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating road edge wear."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

$roadMatches = @(Find-ObjectsByName -Objects $allObjects -Name "RoadCorridor_Main")
if ($roadMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Expected exactly one RoadCorridor_Main; found $($roadMatches.Count)." "Keep one north-south road corridor as the road-wear source of truth."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$road = $roadMatches[0]
$roadChildren = @(Get-ObjectChildren -Object $road)
$wearObjects = @($roadChildren | Where-Object {
    ([string](Get-JsonPropertyValue -Object $_ -Name "Name")).StartsWith("RoadEdgeWear_", [System.StringComparison]::Ordinal)
})

$expectedWearTotal = $expectedWearPerSide * 2
if ($wearObjects.Count -ne $expectedWearTotal) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Expected $expectedWearTotal road-edge wear decals; found $($wearObjects.Count)." "Generate a stable randomized decal set across both road edges."
}

$roadHalfLength = ($roadLengthScale * $boxUnit) / 2.0
$minY = -$roadHalfLength + 420.0
$maxY = $roadHalfLength - 420.0
$westXs = New-Object System.Collections.Generic.List[double]
$eastXs = New-Object System.Collections.Generic.List[double]
$ys = New-Object System.Collections.Generic.List[double]
$rotated = 0

foreach ($wear in $wearObjects) {
    $name = [string](Get-JsonPropertyValue -Object $wear -Name "Name")
    if ($name -notmatch "^RoadEdgeWear_(West|East)_\d{2}$") {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' does not use RoadEdgeWear_West_## or RoadEdgeWear_East_## naming." "Keep road-edge wear names stable so generator reruns replace the old boxes cleanly."
    }

    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $wear -Name "Position")
    $scale = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $wear -Name "Scale")
    $rotation = Convert-AgentQuaternionText -Value (Get-JsonPropertyValue -Object $wear -Name "Rotation")
    $renderer = Get-ComponentByTypeName -Object $wear -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $wear -TypeName "BoxCollider"

    if ($null -eq $position) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' has an invalid Position value." "Use explicit numeric scene coordinates for every road-edge decal."
        continue
    }

    if ($null -eq $scale) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' has an invalid Scale value." "Use explicit numeric scene scale for every road-edge decal."
        continue
    }

    $ys.Add([double]$position[1])
    if ($null -ne $rotation -and [Math]::Abs($rotation[2]) -gt 0.001) {
        $rotated++
    }

    if ($null -ne $collider) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' still has a BoxCollider." "Road wear must be visual texture decals, not colliding boxes."
    }

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' is missing a ModelRenderer." "Render each road-edge decal as a textured plane."
    }
    else {
        $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
        $material = [string](Get-JsonPropertyValue -Object $renderer -Name "MaterialOverride")

        if (-not $model.Equals("models/dev/plane.vmdl", [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' uses model '$model'." "Use models/dev/plane.vmdl so road wear is a flat texture decal instead of a box."
        }

        if (-not $material.Equals($expectedMaterial, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' uses material '$material'." "Apply the road_edge_wear material instead of tinting concrete boxes."
        }
    }

    if ($position[1] -lt $minY -or $position[1] -gt $maxY) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' is at y=$($position[1]), outside the road-safe range." "Keep randomized road wear on the road surface, away from the clipped road ends."
    }

    if ([Math]::Abs($position[2] - 0.42) -gt 0.08) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' is at z=$($position[2]), expected near z=0.42." "Keep flat wear decals just above the road surface without floating above lane markings."
    }

    if ($name -match "^RoadEdgeWear_West_") {
        $westXs.Add([double]$position[0])
        if ($position[0] -lt ($roadCenterX - 184.0) -or $position[0] -gt ($roadCenterX - 122.0)) {
            Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "West wear decal '$name' is at x=$($position[0])." "Keep west road-edge wear on the west asphalt edge, inside the curb."
        }
    }
    elseif ($name -match "^RoadEdgeWear_East_") {
        $eastXs.Add([double]$position[0])
        if ($position[0] -lt ($roadCenterX + 122.0) -or $position[0] -gt ($roadCenterX + 184.0)) {
            Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "East wear decal '$name' is at x=$($position[0])." "Keep east road-edge wear on the east asphalt edge, inside the curb."
        }
    }

    if ($scale[0] -lt 0.65 -or $scale[0] -gt 1.65 -or $scale[1] -lt 2.5 -or $scale[1] -gt 7.2) {
        Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Wear decal '$name' has scale $($scale -join ',')." "Use varied but road-sized decal scales instead of tall box strips."
    }
}

if ($westXs.Count -ne $expectedWearPerSide) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Expected $expectedWearPerSide west road-edge wear decals; found $($westXs.Count)." "Keep both road edges populated by the randomized decal generator."
}

if ($eastXs.Count -ne $expectedWearPerSide) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Expected $expectedWearPerSide east road-edge wear decals; found $($eastXs.Count)." "Keep both road edges populated by the randomized decal generator."
}

$uniqueWestX = @($westXs | ForEach-Object { [Math]::Round($_, 1) } | Select-Object -Unique).Count
$uniqueEastX = @($eastXs | ForEach-Object { [Math]::Round($_, 1) } | Select-Object -Unique).Count
if ($uniqueWestX -lt 6 -or $uniqueEastX -lt 6) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Road-edge wear x placement is not varied enough." "Randomize lateral decal placement inside each road edge instead of copying one straight line."
}

$sortedYs = @($ys | Sort-Object)
$spacings = New-Object System.Collections.Generic.List[double]
for ($i = 1; $i -lt $sortedYs.Count; $i++) {
    $spacings.Add([Math]::Round($sortedYs[$i] - $sortedYs[$i - 1], 1))
}
$uniqueSpacings = @($spacings | Select-Object -Unique).Count
if ($uniqueSpacings -lt 8) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Road-edge wear y spacing is too uniform." "Use deterministic random placement along the road instead of evenly copied boxes."
}

if ($rotated -lt 10) {
    Add-AgentIssue $issues "Error" "Road Edge Wear" $relative "Only $rotated road-edge wear decals have visible rotation variation." "Randomize decal rotation so the texture placement does not read as repeated boxes."
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Road Edge Wear" $relative "Checked $($wearObjects.Count) road-edge wear decals using $expectedMaterial."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
