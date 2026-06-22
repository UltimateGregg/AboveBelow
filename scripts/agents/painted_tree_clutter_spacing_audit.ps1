param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [string]$TreeClutterPath = "Assets/clutter/stock_trees.clutter",
    [string]$TreePrefab = "prefabs/environment/stock/tree_oak_big_a.prefab",
    [double]$MinTreeDistance = 650,
    [double]$MaxTreeDensity = 0.0125,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Painted Tree Clutter Spacing Audit"
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

function ConvertTo-AgentDouble {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $parsed = 0.0
    if ([double]::TryParse($Value.ToString(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function ConvertTo-AgentVector3 {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $parts = $Value.ToString().Split(",")
    if ($parts.Count -lt 3) {
        return $null
    }

    $x = ConvertTo-AgentDouble -Value $parts[0].Trim()
    $y = ConvertTo-AgentDouble -Value $parts[1].Trim()
    $z = ConvertTo-AgentDouble -Value $parts[2].Trim()
    if ($null -eq $x -or $null -eq $y -or $null -eq $z) {
        return $null
    }

    [pscustomobject]@{
        X = [double]$x
        Y = [double]$y
        Z = [double]$z
    }
}

function Get-PrefabOverrideValue {
    param(
        [object]$Object,
        [string]$PropertyName
    )

    $patch = Get-JsonPropertyValue -Object $Object -Name "__PrefabInstancePatch"
    foreach ($override in @(Get-JsonPropertyValue -Object $patch -Name "PropertyOverrides")) {
        if ([string](Get-JsonPropertyValue -Object $override -Name "Property") -eq $PropertyName) {
            return (Get-JsonPropertyValue -Object $override -Name "Value")
        }
    }

    return $null
}

function Get-PaintedTreeEntries {
    param([object[]]$Objects)

    $entries = @()
    foreach ($object in @($Objects | Where-Object { $null -ne $_ })) {
        $prefab = [string](Get-JsonPropertyValue -Object $object -Name "__Prefab")
        if (-not $prefab.Equals($TreePrefab, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $tags = [string](Get-PrefabOverrideValue -Object $object -PropertyName "Tags")
        if ($tags.IndexOf("clutter_painted", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        $positionValue = Get-PrefabOverrideValue -Object $object -PropertyName "Position"
        if ($null -eq $positionValue) {
            $positionValue = Get-JsonPropertyValue -Object $object -Name "Position"
        }

        $position = ConvertTo-AgentVector3 -Value $positionValue
        if ($null -eq $position) {
            Add-AgentIssue $issues "Error" "Painted Tree Clutter" $script:sceneRelative "Painted tree '$([string](Get-JsonPropertyValue -Object $object -Name "__guid"))' has no parseable position." "Fix the tree instance transform before auditing spacing."
            continue
        }

        $name = [string](Get-PrefabOverrideValue -Object $object -PropertyName "Name")
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string](Get-JsonPropertyValue -Object $object -Name "Name")
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string](Get-JsonPropertyValue -Object $object -Name "__guid")
        }

        $entries += [pscustomobject]@{
            Name = $name
            Guid = [string](Get-JsonPropertyValue -Object $object -Name "__guid")
            Position = $position
        }
    }

    return $entries
}

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$script:sceneRelative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root
$fullClutterPath = if ([System.IO.Path]::IsPathRooted($TreeClutterPath)) { $TreeClutterPath } else { Join-Path $Root $TreeClutterPath }
$clutterRelative = ConvertTo-AgentRelativePath -Path $fullClutterPath -Root $Root

if (-not (Test-Path -LiteralPath $fullClutterPath)) {
    Add-AgentIssue $issues "Error" "Painted Tree Clutter" $clutterRelative "Tree clutter resource is missing." "Restore stock_trees.clutter before using the clutter tool for tree placement."
}
else {
    try {
        $clutter = Read-AgentJson -Path $fullClutterPath
        $scatterer = Get-JsonPropertyValue -Object $clutter -Name "Scatterer"
        $density = ConvertTo-AgentDouble -Value (Get-JsonPropertyValue -Object $scatterer -Name "Density")
        if ($null -eq $density) {
            Add-AgentIssue $issues "Error" "Painted Tree Clutter" $clutterRelative "Tree clutter density is missing or not numeric." "Set a conservative tree clutter Density so painted trees do not generate as a tight cluster."
        }
        elseif ($density -gt $MaxTreeDensity) {
            Add-AgentIssue $issues "Error" "Painted Tree Clutter" $clutterRelative "Tree clutter Density is $density, above the project maximum $MaxTreeDensity." "Lower stock tree clutter density; SimpleScatterer has no minimum-spacing property, so density is the tool-level guardrail."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Painted Tree Clutter" $clutterRelative $_.Exception.Message "Fix stock_trees.clutter JSON before auditing tree clutter spacing."
    }
}

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Painted Tree Clutter" $script:sceneRelative "Scene file is missing." "Restore the scene before checking painted tree clutter spacing."
}
else {
    try {
        $scene = Read-AgentJson -Path $fullScenePath
        $trees = @(Get-PaintedTreeEntries -Objects @(Get-JsonPropertyValue -Object $scene -Name "GameObjects"))
        $offenders = @()

        for ($i = 0; $i -lt $trees.Count; $i++) {
            for ($j = $i + 1; $j -lt $trees.Count; $j++) {
                $dx = $trees[$i].Position.X - $trees[$j].Position.X
                $dy = $trees[$i].Position.Y - $trees[$j].Position.Y
                $distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
                if ($distance -lt $MinTreeDistance) {
                    $offenders += [pscustomobject]@{
                        Distance = $distance
                        A = $trees[$i]
                        B = $trees[$j]
                    }
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $examples = @($offenders | Sort-Object Distance | Select-Object -First 8 | ForEach-Object {
                "$($_.A.Name) <-> $($_.B.Name) distance=$([Math]::Round($_.Distance, 1))"
            }) -join "; "
            Add-AgentIssue $issues "Error" "Painted Tree Clutter" $script:sceneRelative "$($offenders.Count) painted stock tree pair(s) are closer than $MinTreeDistance units. Examples: $examples" "Move or erase painted tree clutter until stock tree colliders cannot overlap."
        }

        if ($ShowInfo) {
            Add-AgentIssue $issues "Info" "Painted Tree Clutter" $script:sceneRelative "Checked $($trees.Count) painted stock tree instance(s) with minimum spacing $MinTreeDistance." ""
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Painted Tree Clutter" $script:sceneRelative $_.Exception.Message "Fix scene JSON before auditing painted tree clutter spacing."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
