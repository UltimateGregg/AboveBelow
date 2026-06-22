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
    param(
        [object[]]$Objects,
        [string]$Name
    )

    return @($Objects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $Name })
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

function Find-RoadCoverBarrierGroups {
    param([object]$Road, [object]$PrefabRoot)

    $matches = @(Get-ObjectChildren -Object $Road | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "RoadCover_Northwest_Barrier" })
    foreach ($child in @(Get-ObjectChildren -Object $Road)) {
        $prefabPath = [string](Get-JsonPropertyValue -Object $child -Name "__Prefab")
        if ($prefabPath -notin @("prefabs/environment/road_cover_northwest_barrier.prefab", "Assets/prefabs/environment/road_cover_northwest_barrier.prefab")) {
            continue
        }

        $resolved = Resolve-PrefabInstanceForAudit -Instance $child -PrefabRoot $PrefabRoot
        if ($null -ne $resolved -and [string](Get-JsonPropertyValue -Object $resolved -Name "Name") -eq "RoadCover_Northwest_Barrier") {
            $matches += $resolved
        }
    }

    return @($matches)
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

        if ($TypeName -eq "ModelCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Static") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "ColliderFlags")) {
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

function Test-ModelBackedBarrierContract {
    param(
        [object]$Cover,
        [string]$Relative
    )

    $expectedModel = "models/road_cover_northwest_barrier.vmdl"
    $children = @(Get-ObjectChildren -Object $Cover)
    $visual = @($children | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "Visual" } | Select-Object -First 1)
    if ($visual.Count -eq 0) {
        return $false
    }

    $renderer = Get-ComponentByTypeName -Object $visual[0] -TypeName "ModelRenderer"
    $modelCollider = Get-ComponentByTypeName -Object $visual[0] -TypeName "ModelCollider"
    $rendererModel = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
    $colliderModel = [string](Get-JsonPropertyValue -Object $modelCollider -Name "Model")

    if ($rendererModel -ne $expectedModel -and $colliderModel -ne $expectedModel) {
        return $false
    }

    if ($children.Count -ne 1) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $Relative "Model-backed RoadCover_Northwest_Barrier should have exactly one Visual child; found $($children.Count)." "Keep authored model/collision details in the VMDL and the scene instance lightweight."
    }

    if ($null -eq $renderer -or $rendererModel -ne $expectedModel) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $Relative "Visual should render $expectedModel." "Keep the scene instance backed by the road_cover_northwest_barrier model asset."
    }

    if ($null -eq $modelCollider -or $colliderModel -ne $expectedModel) {
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $Relative "Visual should carry a ModelCollider for $expectedModel." "Use the VMDL's generated mesh collision instead of stale primitive child colliders."
    }
    else {
        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $modelCollider -Name "Static") -Expected $true)) {
            Add-AgentIssue $issues "Error" "Road Cover Barrier" $Relative "Visual ModelCollider is not static." "Road cover should be static scene geometry."
        }
        if (-not (Test-JsonBool -Value (Get-JsonPropertyValue -Object $modelCollider -Name "IsTrigger") -Expected $false)) {
            Add-AgentIssue $issues "Error" "Road Cover Barrier" $Relative "Visual ModelCollider is a trigger." "Road cover should block movement and projectiles as solid cover."
        }
    }

    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Road Cover Barrier" $Relative "Validated model-backed RoadCover_Northwest_Barrier using $expectedModel and ModelCollider."
    }

    return $true
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

$barrierPrefabPath = Join-Path $Root "Assets\prefabs\environment\road_cover_northwest_barrier.prefab"
$barrierPrefabRoot = $null
if (Test-Path -LiteralPath $barrierPrefabPath) {
    try {
        $barrierPrefab = Read-AgentJson -Path $barrierPrefabPath
        $barrierPrefabRoot = Get-JsonPropertyValue -Object $barrierPrefab -Name "RootObject"
    }
    catch {
        $barrierPrefabRelative = ConvertTo-AgentRelativePath -Path $barrierPrefabPath -Root $Root
        Add-AgentIssue $issues "Error" "Road Cover Barrier" $barrierPrefabRelative "Could not parse road cover barrier prefab JSON: $($_.Exception.Message)" "Fix the prefab before validating prefab-backed barrier placement."
    }
}

$roadMatches = @(Find-ObjectsByName -Objects $allObjects -Name "RoadCorridor_Main")
if ($roadMatches.Count -ne 1) {
    Add-AgentIssue $issues "Error" "Road Cover Barrier" $relative "Expected exactly one RoadCorridor_Main; found $($roadMatches.Count)." "Keep the editor-authored barrier parented to the active road corridor."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$road = $roadMatches[0]
$coverMatches = @(Find-RoadCoverBarrierGroups -Road $road -PrefabRoot $barrierPrefabRoot)
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

if (Test-ModelBackedBarrierContract -Cover $cover -Relative $relative) {
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
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
