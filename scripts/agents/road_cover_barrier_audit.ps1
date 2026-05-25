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

Write-AgentSection "Road Cover Barrier Audit"
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
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating road-cover barriers."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating road-cover barriers."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

$roadMatches = @(Find-ObjectsByName -Objects $allObjects -Name "RoadCorridor_Main")
if ($roadMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "Expected exactly one RoadCorridor_Main; found $($roadMatches.Count)." "Keep the editor-authored barrier parented to the active road corridor."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$road = $roadMatches[0]
$coverMatches = @(Get-ObjectChildren -Object $road | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "RoadCover_Northwest_Barrier" })
if ($coverMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "Expected exactly one RoadCover_Northwest_Barrier under RoadCorridor_Main; found $($coverMatches.Count)." "Replace the old placeholder with one editor-authored primitive barrier group."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$cover = $coverMatches[0]
$coverPosition = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $cover -Name "Position")
if ($null -eq $coverPosition -or [Math]::Abs($coverPosition[0] - 111.190948) -gt 0.1 -or [Math]::Abs($coverPosition[1] - 1185) -gt 0.1 -or [Math]::Abs($coverPosition[2]) -gt 0.1) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "RoadCover_Northwest_Barrier is not at the expected northwest placeholder position." "Keep the replacement group centered where the placeholder stood."
}

if (@(Get-ObjectComponents -Object $cover).Count -ne 0) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "RoadCover_Northwest_Barrier still has direct components." "The parent should be a grouping object; geometry belongs to editor primitive children."
}

$children = @(Get-ObjectChildren -Object $cover)
$solidNames = @(
    "NWBarrier_Base_Foot",
    "NWBarrier_Lower_Block",
    "NWBarrier_Upper_Core",
    "NWBarrier_Top_Cap",
    "NWBarrier_North_Sloped_Face",
    "NWBarrier_South_Sloped_Face",
    "NWBarrier_Left_End_Cap",
    "NWBarrier_Right_End_Cap",
    "NWBarrier_North_Toe",
    "NWBarrier_South_Toe"
)
$detailNames = @(
    "NWBarrier_Reflector_Left",
    "NWBarrier_Reflector_Right",
    "NWBarrier_HazardStripe_Left",
    "NWBarrier_HazardStripe_Mid",
    "NWBarrier_HazardStripe_Right",
    "NWBarrier_ConcreteChip_Left",
    "NWBarrier_ConcreteChip_Right",
    "NWBarrier_DirtScuff_Lower",
    "NWBarrier_DirtScuff_Top"
)

foreach ($required in @($solidNames + $detailNames)) {
    if (@(Find-ObjectsByName -Objects $children -Name $required).Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "Missing required primitive child '$required'." "Keep the concrete body, sloped faces, end caps, reflectors, hazard stripes, and wear details intact."
    }
}

foreach ($child in $children) {
    $name = [string](Get-JsonPropertyValue -Object $child -Name "Name")
    $renderer = Get-ComponentByTypeName -Object $child -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $child -TypeName "BoxCollider"

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name is missing ModelRenderer." "Every barrier piece should be an editor-visible primitive."
        continue
    }

    $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    if ($model -ne "models/dev/box.vmdl") {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name uses model '$model' instead of models/dev/box.vmdl." "Keep the barrier editor-native; do not replace it with a Blender or imported model asset."
    }

    if ($solidNames -contains $name) {
        if ($null -eq $collider) {
            Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name is missing BoxCollider." "Concrete barrier body pieces should be solid static cover."
        }
        else {
            $colliderScale = ([string](Get-JsonPropertyValue -Object $collider -Name "Scale")).Replace(" ", "")
            if ($colliderScale -ne "50,50,50") {
                Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name has BoxCollider scale '$colliderScale'." "Keep collider scale aligned with scaled S&Box dev primitive renderers."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
                Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name collider is not static." "Road cover should be static scene geometry."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
                Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name collider is a trigger." "Road cover should block movement and projectiles as solid cover."
            }
        }
    }
    elseif ($null -ne $collider) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "$name has collision but should be visual detail only." "Keep stripes, reflectors, chips, and scuffs visual-only."
    }
}

if ($children.Count -lt 19) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "RoadCover_Northwest_Barrier has $($children.Count) child object(s), expected at least 19." "Do not collapse the editor-authored barrier back into one placeholder box."
}

if ($ShowInfo) {
    $solidCount = @($children | Where-Object { $solidNames -contains [string](Get-JsonPropertyValue -Object $_ -Name "Name") }).Count
    $detailCount = @($children | Where-Object { $detailNames -contains [string](Get-JsonPropertyValue -Object $_ -Name "Name") }).Count
    Add-AgentIssue $issues "Info" "Road Cover Barrier" $relative "Validated editor-authored RoadCover_Northwest_Barrier with $solidCount solid primitive body pieces and $detailCount visual detail pieces."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
