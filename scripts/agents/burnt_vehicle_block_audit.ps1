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

Write-AgentSection "Burnt Vehicle Block Audit"
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
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore Assets/scenes/main.scene before validating the burnt vehicle block."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before validating the burnt vehicle block."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @()
foreach ($rootObject in @($scene.GameObjects)) {
    $allObjects += Get-AllObjects -Object $rootObject
}

$vehicleMatches = @(Find-ObjectsByName -Objects $allObjects -Name "CenterLane_BurntVehicleBlock_North")
if ($vehicleMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "Expected exactly one CenterLane_BurntVehicleBlock_North; found $($vehicleMatches.Count)." "Keep one editor-authored north vehicle block instead of duplicating or deleting the target."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$vehicle = $vehicleMatches[0]
$vehiclePosition = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $vehicle -Name "Position")
if ($null -eq $vehiclePosition -or
    [Math]::Abs($vehiclePosition[0] - 923.058044) -gt 0.1 -or
    [Math]::Abs($vehiclePosition[1] - 690) -gt 0.1 -or
    [Math]::Abs($vehiclePosition[2]) -gt 0.1) {
    Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "CenterLane_BurntVehicleBlock_North is not at the expected ground anchor." "Keep the vehicle parent at 923.058044,690,0 and put geometry in local child offsets."
}

$vehicleScale = ([string](Get-JsonPropertyValue -Object $vehicle -Name "Scale")).Replace(" ", "")
if ($vehicleScale -ne "1,1,1") {
    Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "CenterLane_BurntVehicleBlock_North has scale '$vehicleScale'." "Keep the asset parent unscaled so child offsets stay local and auditable."
}

if (@(Get-ObjectComponents -Object $vehicle).Count -ne 0) {
    Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "CenterLane_BurntVehicleBlock_North still has direct placeholder components." "The parent should be an empty group; geometry belongs to named editor primitive children."
}

$children = @(Get-ObjectChildren -Object $vehicle)
$solidNames = @(
    "BurntVehicle_CrushedLowerShell",
    "BurntVehicle_LeftRocker_RustedSplit",
    "BurntVehicle_RightRocker_RustedSplit",
    "BurntVehicle_Hood_WarpedBlackPlate",
    "BurntVehicle_Trunk_CavedRustPlate",
    "BurntVehicle_Cabin_SootVoid",
    "BurntVehicle_Roof_CollapsedSootPlate",
    "BurntVehicle_Engine_ExposedBlock",
    "BurntVehicle_FrontBumper_HangingSteel",
    "BurntVehicle_RearBumper_SaggedRust",
    "BurntVehicle_Wheel_FL_CharredTire",
    "BurntVehicle_Wheel_FR_CharredTire",
    "BurntVehicle_Wheel_RL_ExposedRim",
    "BurntVehicle_Wheel_RR_BurnedHub"
)
$detailNames = @(
    "BurntVehicle_AshBed_GroundScorch",
    "BurntVehicle_AshDrift_Front",
    "BurntVehicle_AshDrift_Rear",
    "BurntVehicle_BrokenGlass_WindshieldShard",
    "BurntVehicle_BrokenGlass_SideShard",
    "BurntVehicle_RustStripe_LeftPanel",
    "BurntVehicle_RustStripe_RightPanel",
    "BurntVehicle_SootScale_Hood",
    "BurntVehicle_SootScale_Roof",
    "BurntVehicle_HotWarning_Reflector"
)

foreach ($required in @($solidNames + $detailNames)) {
    if (@(Find-ObjectsByName -Objects $children -Name $required).Count -ne 1) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "Missing required primitive child '$required'." "Keep the shell, cabin, wheels, ash bed, scorch, rust, and glass detail children intact."
    }
}

foreach ($child in $children) {
    $name = [string](Get-JsonPropertyValue -Object $child -Name "Name")
    $position = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $child -Name "Position")
    $renderer = Get-ComponentByTypeName -Object $child -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $child -TypeName "BoxCollider"

    if ($null -eq $position) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name has an invalid Position value." "Use explicit local child offsets under the vehicle parent."
    }
    elseif ([Math]::Abs($position[0]) -gt 160 -or [Math]::Abs($position[1]) -gt 75 -or $position[2] -lt 0 -or $position[2] -gt 115) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name has suspicious local offset $($position -join ',')." "MCP-created children should store local offsets, not world-origin or parent-negated coordinates."
    }

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name is missing ModelRenderer." "Every vehicle piece should be an editor-visible primitive."
        continue
    }

    $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    if ($model -notin @("models/dev/box.vmdl", "models/dev/sphere.vmdl")) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name uses model '$model'." "Keep this no-Blender vehicle block editor-native with dev box/sphere primitives."
    }

    if ($solidNames -contains $name) {
        if ($null -eq $collider) {
            Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name is missing BoxCollider." "Solid body and wheel pieces should block movement and projectiles."
        }
        else {
            $colliderScale = ([string](Get-JsonPropertyValue -Object $collider -Name "Scale")).Replace(" ", "")
            if ($colliderScale -ne "50,50,50") {
                Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name has BoxCollider scale '$colliderScale'." "Keep collider scale aligned with scaled S&Box dev primitives."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
                Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name collider is not static." "The burnt vehicle should be static tactical cover."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
                Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name collider is a trigger." "The burnt vehicle should be solid cover."
            }
        }
    }
    elseif ($null -ne $collider) {
        Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "$name has collision but should be visual detail only." "Keep ash, scorch, rust stripes, glass shards, and reflectors non-blocking."
    }
}

if ($children.Count -lt 24) {
    Add-AgentIssue $issues "Error" "Burnt Vehicle Block" $relative "CenterLane_BurntVehicleBlock_North has only $($children.Count) child object(s), expected at least 24." "Do not collapse the vehicle block back into a single placeholder."
}

if ($ShowInfo) {
    $solidCount = @($children | Where-Object { $solidNames -contains [string](Get-JsonPropertyValue -Object $_ -Name "Name") }).Count
    $detailCount = @($children | Where-Object { $detailNames -contains [string](Get-JsonPropertyValue -Object $_ -Name "Name") }).Count
    Add-AgentIssue $issues "Info" "Burnt Vehicle Block" $relative "Validated editor-native CenterLane_BurntVehicleBlock_North with $solidCount solid primitive pieces and $detailCount visual detail pieces."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
