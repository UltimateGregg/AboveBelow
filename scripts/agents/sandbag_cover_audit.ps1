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

Write-AgentSection "Sandbag Cover Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

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

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating the sandbag cover."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating the sandbag cover."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

$roadMatches = @(Find-ObjectsByName -Objects $allObjects -Name "RoadCorridor_Main")
if ($roadMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "Expected exactly one RoadCorridor_Main; found $($roadMatches.Count)." "Keep the editor-authored cover parented to the active road corridor."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$road = $roadMatches[0]
$coverMatches = @(Get-ObjectChildren -Object $road | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "RoadSandbagCover_Mid" })
if ($coverMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "Expected exactly one RoadSandbagCover_Mid under RoadCorridor_Main; found $($coverMatches.Count)." "Create one editor-authored sandbag group on the road instead of duplicating cover groups."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$cover = $coverMatches[0]
$coverObjects = @(Get-AllObjects -Object $cover)
$bagObjects = @($coverObjects | Where-Object {
    $name = [string](Get-JsonPropertyValue -Object $_ -Name "Name")
    $name -match "^Sandbag_(Back|Second|Top|Left_Return|Right_Return)"
})
$seamObjects = @($coverObjects | Where-Object {
    $name = [string](Get-JsonPropertyValue -Object $_ -Name "Name")
    $name -match "^Sandbag_Seam_"
})

$expectedBagMaterial = "materials/environment/sandbag_canvas.vmat"

if ($bagObjects.Count -lt 12) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "RoadSandbagCover_Mid has only $($bagObjects.Count) sandbag body object(s)." "Keep enough stacked and return sandbag bodies for readable road cover; do not remove the cover shape."
}
if ($bagObjects.Count -gt 18) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "RoadSandbagCover_Mid has $($bagObjects.Count) sandbag body object(s), expected no more than 18." "Preserve user-deleted pieces instead of recreating or duplicating sandbags."
}
if ($seamObjects.Count -gt 5) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "RoadSandbagCover_Mid has $($seamObjects.Count) seam marker object(s), expected no more than 5." "Preserve user-deleted seam/detail strips instead of recreating extras."
}

foreach ($bag in $bagObjects) {
    $name = [string](Get-JsonPropertyValue -Object $bag -Name "Name")
    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $bag -Name "Position")
    $renderer = Get-ComponentByTypeName -Object $bag -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $bag -TypeName "BoxCollider"

    if ($null -eq $position) {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name has an invalid Position value." "Use explicit scene coordinates so the cover stays on the road."
    }
    else {
        if ($position[0] -lt 211 -or $position[0] -gt 622 -or $position[1] -lt 80 -or $position[1] -gt 245) {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name is outside the expected road-cover bounds at $($position -join ',')." "Keep sandbag centers within the north-south road corridor near x=416, y=220."
        }
    }

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name is missing ModelRenderer." "Use S&Box editor primitives for every sandbag body."
    }
    else {
        $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
        $material = [string](Get-JsonPropertyValue -Object $renderer -Name "MaterialOverride")
        if ($model -ne "models/dev/sphere.vmdl") {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name uses model '$model' instead of models/dev/sphere.vmdl." "Keep this cover editor-native; do not route it through Blender or a bespoke model asset."
        }
        if ($material -ne $expectedBagMaterial) {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name uses material '$material' instead of $expectedBagMaterial." "Use the detailed local sandbag canvas material with per-bag tint variation."
        }
    }

    if ($null -eq $collider) {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name is missing BoxCollider." "Sandbag bodies should be solid static cover."
    }
    else {
        $colliderScale = ([string](Get-JsonPropertyValue -Object $collider -Name "Scale")).Replace(" ", "")
        if ($colliderScale -ne "50,50,50") {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name has BoxCollider scale '$colliderScale'." "Keep collider scale aligned with scaled S&Box dev primitive renderers."
        }
        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name collider is not static." "Road cover should be static scene geometry."
        }
        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name collider is a trigger." "Sandbag cover should block movement and projectiles as solid cover."
        }
    }
}

$spacingContracts = @(
    @{ Label = "Back row"; Regex = "^Sandbag_Back_Row_"; Axis = 0; MaxSpacing = 66.0 },
    @{ Label = "Second row"; Regex = "^Sandbag_Second_Row_"; Axis = 0; MaxSpacing = 66.0 },
    @{ Label = "Top row"; Regex = "^Sandbag_Top_Row_"; Axis = 0; MaxSpacing = 60.0 },
    @{ Label = "Left return"; Regex = "^Sandbag_Left_Return_"; Axis = 1; MaxSpacing = 58.0 },
    @{ Label = "Right return"; Regex = "^Sandbag_Right_Return_"; Axis = 1; MaxSpacing = 58.0 }
)
foreach ($contract in $spacingContracts) {
    $row = @($bagObjects | Where-Object {
        $name = [string](Get-JsonPropertyValue -Object $_ -Name "Name")
        $name -match $contract.Regex
    } | ForEach-Object {
        $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $_ -Name "Position")
        if ($null -ne $position) {
            [pscustomobject]@{
                Name = [string](Get-JsonPropertyValue -Object $_ -Name "Name")
                Position = $position
                SortValue = [double]$position[[int]$contract.Axis]
            }
        }
    } | Sort-Object SortValue)

    if ($row.Count -lt 2) {
        continue
    }

    for ($i = 1; $i -lt $row.Count; $i++) {
        $spacing = [math]::Abs($row[$i].SortValue - $row[$i - 1].SortValue)
        if ($spacing -gt [double]$contract.MaxSpacing) {
            Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$($contract.Label) spacing between $($row[$i - 1].Name) and $($row[$i].Name) is $([math]::Round($spacing, 2)), above $($contract.MaxSpacing)." "Move adjacent sandbags closer together so the cover reads as continuous with no visible gaps."
        }
    }
}

foreach ($seam in $seamObjects) {
    $name = [string](Get-JsonPropertyValue -Object $seam -Name "Name")
    $renderer = Get-ComponentByTypeName -Object $seam -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $seam -TypeName "BoxCollider"

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name is missing ModelRenderer." "Seam strips should be visible thin box primitives."
        continue
    }

    $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    if ($model -ne "models/dev/box.vmdl") {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name uses model '$model' instead of models/dev/box.vmdl." "Use visual-only box strips for seams."
    }
    if ($null -ne $collider) {
        Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "$name has collision." "Seam strips should stay visual-only; collision belongs on the sandbag bodies."
    }
}

$maxBagHeight = 0.0
foreach ($bag in $bagObjects) {
    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $bag -Name "Position")
    if ($null -ne $position -and $position[2] -gt $maxBagHeight) {
        $maxBagHeight = $position[2]
    }
}
if ($maxBagHeight -lt 75) {
    Add-AgentIssue $issues "Error" "Road Sandbag Cover" $relative "RoadSandbagCover_Mid is too low; tallest sandbag center is z=$maxBagHeight." "Keep a three-row waist-high stack for readable cover."
}

if ($ShowInfo) {
    $seamDetail = if ($seamObjects.Count -eq 0) { "no seam strips present; preserving deleted detail strips" } else { "$($seamObjects.Count) visual seam strip(s)" }
    Add-AgentIssue $issues "Info" "Road Sandbag Cover" $relative "Validated editor-authored RoadSandbagCover_Mid with $($bagObjects.Count) solid sandbag bodies, $seamDetail, tight spacing, and detailed sandbag material."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
