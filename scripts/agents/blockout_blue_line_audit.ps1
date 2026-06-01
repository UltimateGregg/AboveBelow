param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [string]$GeneratorPath = "scripts/scene_blockout.py",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Blockout Blue Line Audit"
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

function Get-AllObjects {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $objects += @(Get-AllObjects -Object $child)
    }

    return $objects
}

function Convert-AgentVectorText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $parts = @($Value.ToString() -split "," | ForEach-Object {
        $parsed = 0.0
        if ([double]::TryParse($_.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            [Math]::Abs($parsed)
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

function Test-LineLikeScale {
    param([object]$ScaleText)

    $scale = Convert-AgentVectorText -Value $ScaleText
    if ($null -eq $scale) {
        return $false
    }

    $thinAxes = @($scale | Where-Object { $_ -le 0.09 }).Count
    $longAxes = @($scale | Where-Object { $_ -ge 1.5 }).Count
    return ($thinAxes -ge 1 -and $longAxes -ge 1)
}

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$sceneRelative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $sceneRelative "Scene file is missing." "Restore the scene before checking for retired blue blockout line markers."
}
else {
    try {
        $scene = Read-AgentJson -Path $fullScenePath
        $allObjects = @()
        foreach ($rootObject in @($scene.GameObjects)) {
            $allObjects += @(Get-AllObjects -Object $rootObject)
        }

        foreach ($object in $allObjects) {
            foreach ($component in @(Get-ObjectComponents -Object $object)) {
                $model = [string](Get-JsonPropertyValue -Object $component -Name "Model")
                $material = [string](Get-JsonPropertyValue -Object $component -Name "MaterialOverride")
                if ($model -ne "models/dev/box.vmdl") {
                    continue
                }
                if ($material -ne "materials/emp_glow.vmat") {
                    continue
                }
                if (-not (Test-LineLikeScale -ScaleText (Get-JsonPropertyValue -Object $object -Name "Scale"))) {
                    continue
                }

                $name = [string](Get-JsonPropertyValue -Object $object -Name "Name")
                Add-AgentIssue $issues "Error" "Blockout Line Marker" $sceneRelative "Retired line-like emp_glow blockout marker '$name' is still present." "Delete the line strip or replace it with non-line readability that is intentionally arted."
            }
        }

        if ($ShowInfo) {
            Add-AgentIssue $issues "Info" "Blockout Line Marker" $sceneRelative "Scanned $($allObjects.Count) scene object(s) for line-like emp_glow dev-box markers."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Scene JSON" $sceneRelative "Could not inspect scene JSON: $($_.Exception.Message)" "Fix scene JSON before relying on the blue-line guard."
    }
}

$fullGeneratorPath = if ([System.IO.Path]::IsPathRooted($GeneratorPath)) { $GeneratorPath } else { Join-Path $Root $GeneratorPath }
$generatorRelative = ConvertTo-AgentRelativePath -Path $fullGeneratorPath -Root $Root
if (-not (Test-Path -LiteralPath $fullGeneratorPath)) {
    Add-AgentIssue $issues "Warning" "Scene Generator" $generatorRelative "Scene generator file was not found." "If a new level generator replaced it, add this blue-line guard there too."
}
else {
    $generator = Get-Content -LiteralPath $fullGeneratorPath -Raw
    $retiredPatterns = @(
        @{ Pattern = "PaintedRoute"; Label = "painted route strip" },
        @{ Pattern = "ApproachPaint"; Label = "approach paint strip" },
        @{ Pattern = "BreachMarker"; Label = "breach marker strip" },
        @{ Pattern = "DangerStripe"; Label = "danger stripe strip" },
        @{ Pattern = "EscapeRead"; Label = "escape/read strip" },
        @{ Pattern = "lane_marker\s*\("; Label = "lane marker helper" },
        @{ Pattern = "LaunchPad_Glow_.*marker_scale\s*=\s*[""']\s*[0-9.]+\s*,\s*0\.0?8"; Label = "launch-pad glow strip marker" }
    )

    foreach ($entry in $retiredPatterns) {
        if ($generator -match $entry.Pattern) {
            Add-AgentIssue $issues "Error" "Scene Generator" $generatorRelative "Generator can recreate retired $($entry.Label)." "Keep future blockout generation free of glowing line strips."
        }
    }

    if ($ShowInfo) {
        Add-AgentIssue $issues "Info" "Scene Generator" $generatorRelative "Checked scene generator for retired glowing line marker families."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
