param(
    [string]$Root = "",
    [string]$PrefabPath = "Assets/prefabs/environment/burnt_car_wreck.prefab",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Destroyed Pickup Prefab Audit"
Write-Host "Root: $Root"

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
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger")) {
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

$fullPrefabPath = if ([System.IO.Path]::IsPathRooted($PrefabPath)) { $PrefabPath } else { Join-Path $Root $PrefabPath }
$relative = ConvertTo-AgentRelativePath -Path $fullPrefabPath -Root $Root

if (-not (Test-Path -LiteralPath $fullPrefabPath)) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab file is missing." "Restore the destroyed pickup prefab at the stable environment prefab path."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$raw = Get-Content -LiteralPath $fullPrefabPath -Raw
try {
    $prefab = $raw | ConvertFrom-Json
}
catch {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab JSON could not be parsed: $($_.Exception.Message)" "Fix invalid prefab JSON before validating the destroyed pickup contract."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

if ($raw -match "models/burnt_car_wreck\.vmdl") {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab still references the retired Blender-backed burnt car VMDL." "Use S&Box dev primitives directly and leave the old model pipeline unused."
}

if ($raw -match '"__type"\s*:\s*"Sandbox\.ModelCollider"') {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab still uses ModelCollider instead of primitive BoxCollider pieces." "Use static BoxCollider components on the solid primitive children."
}

if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $prefab -Name "ShowInMenu") -Expected $true)) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab is not visible in the S&Box asset menu." "Set ShowInMenu to true so the destroyed pickup can be placed from the editor."
}

$menuPath = [string](Get-JsonPropertyValue -Object $prefab -Name "MenuPath")
if ($menuPath -ne "Above Below/Environment/Destroyed Pickup") {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "MenuPath '$menuPath' does not identify the asset as an ABOVE/BELOW destroyed pickup." "Use the stable editor menu path Above Below/Environment/Destroyed Pickup."
}

$rootObject = Get-JsonPropertyValue -Object $prefab -Name "RootObject"
if ($null -eq $rootObject) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Prefab has no RootObject." "Restore the BurntCarWreck root object."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

if ([string](Get-JsonPropertyValue -Object $rootObject -Name "Name") -ne "BurntCarWreck") {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Root object name changed from BurntCarWreck." "Keep the public prefab identity stable while replacing its contents."
}

if (@(Get-ObjectComponents -Object $rootObject).Count -ne 0) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Root object has direct components." "Keep the root as a placement group and put renderer/collider components on named pickup children."
}

$children = @(Get-ObjectChildren -Object $rootObject)
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
    "Pickup_Wheel_RR_RimOnly"
)

$detailNames = @(
    "Pickup_Glass_WindshieldShard",
    "Pickup_Glass_SideShard_Left",
    "Pickup_Glass_SideShard_Right",
    "Pickup_ScrapeMark_Left",
    "Pickup_ScrapeMark_Right",
    "Pickup_Debris_HoodShard",
    "Pickup_Debris_BedShard",
    "Pickup_Debris_GlassScatter",
    "Pickup_Debris_MudDrag",
    "Pickup_Debris_RoadScuff"
)

foreach ($required in @($solidNames + $detailNames)) {
    $matches = @($children | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $required })
    if ($matches.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Expected exactly one primitive child '$required'; found $($matches.Count)." "Keep the crashed pickup silhouette and detail contract intact."
    }
}

$solidCount = 0
$detailCount = 0
$boxRendererCount = 0
$sphereRendererCount = 0
foreach ($child in $children) {
    $name = [string](Get-JsonPropertyValue -Object $child -Name "Name")
    if ($name -match "^BurntVehicle_") {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Child '$name' still uses old burnt-vehicle naming." "Rename authored children to the Pickup_* crashed-pickup contract."
    }

    $renderer = Get-ComponentByTypeName -Object $child -TypeName "ModelRenderer"
    $collider = Get-ComponentByTypeName -Object $child -TypeName "BoxCollider"

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name is missing ModelRenderer." "Every pickup child should be visible as an S&Box primitive."
        continue
    }

    $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    if ($model -eq "models/dev/box.vmdl") {
        $boxRendererCount++
    }
    elseif ($model -eq "models/dev/sphere.vmdl") {
        $sphereRendererCount++
    }
    else {
        Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name uses model '$model' instead of S&Box dev primitives." "Use models/dev/box.vmdl or models/dev/sphere.vmdl for this S&Box-native prefab."
    }

    if ($solidNames -contains $name) {
        $solidCount++
        if ($null -eq $collider) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name is missing BoxCollider." "Major pickup body, frame, bumper, axle, and wheel pieces should be static cover."
        }
        else {
            $colliderScale = ([string](Get-JsonPropertyValue -Object $collider -Name "Scale")).Replace(" ", "")
            if ($colliderScale -ne "50,50,50") {
                Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name BoxCollider scale is '$colliderScale'." "Keep collider scale aligned with the scaled S&Box dev primitive renderer."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
                Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name collider is not static." "Destroyed pickup cover should be static environment collision."
            }
            if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
                Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name collider is a trigger." "Destroyed pickup cover should block movement and projectiles."
            }
        }
    }
    elseif ($detailNames -contains $name) {
        $detailCount++
        if ($null -ne $collider) {
            Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "$name has collision but should be visual detail only." "Keep glass shards, scrape marks, and small debris non-blocking."
        }
    }
}

if ($solidCount -lt 20) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Only $solidCount required solid pickup pieces were found." "Keep enough static body/frame pieces for cover and silhouette readability."
}

if ($detailCount -lt 10) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Only $detailCount required detail pickup pieces were found." "Keep glass, scrape, and debris pieces for crashed-not-burned readability."
}

if ($boxRendererCount -lt 20 -or $sphereRendererCount -lt 4) {
    Add-AgentIssue $issues "Error" "Destroyed Pickup Prefab" $relative "Expected at least 20 box primitives and 4 sphere primitives, found $boxRendererCount box and $sphereRendererCount sphere renderer(s)." "Use boxes for crushed panels/frame and spheres for ruined tires/rims."
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Destroyed Pickup Prefab" $relative "Checked $($children.Count) child primitive(s), $solidCount solid cover piece(s), and $detailCount visual detail piece(s)."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
