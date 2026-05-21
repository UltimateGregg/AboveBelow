param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]

function Read-ProjectFile {
    param([string]$Path)

    $fullPath = Join-Path $Root $Path
    if (!(Test-Path -LiteralPath $fullPath)) {
        $failures.Add("Missing file: $Path")
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Require-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if (![regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

function Reject-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if ([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

$hud = Read-ProjectFile "Code/UI/HudPanel.razor"

Require-Match "HudPanel should render the sprint meter inside the existing reticle stack." `
    $hud "<div\s+class=""reticle-stack"">[\s\S]{0,2400}ShowSprintMeter[\s\S]{0,500}sprint-meter"

Require-Match "HudPanel should use a sprint meter class so cooldown/recovery can be styled." `
    $hud "class=""sprint-meter\s+@SprintMeterClass"""

Require-Match "HudPanel should read the local pilot drone-view state." `
    $hud "LocalDroneViewActive[\s\S]{0,220}DroneViewActive"

Require-Match "HudPanel should hide the ground sprint meter while the local pilot is in drone view." `
    $hud "ShowSprintMeter[\s\S]{0,260}LocalDroneViewActive"

Require-Match "HudPanel should expose the ground stamina percent to the reticle sprint meter." `
    $hud "SprintMeterPercent[\s\S]{0,220}LocalGroundController[\s\S]{0,220}Stamina"

Reject-Match "Sprint meter should not be limited to soldiers only." `
    $hud "ShowSprintMeter[\s\S]{0,220}LocalRole\s*==\s*PlayerRole\.Soldier"

Reject-Match "The old lower-left stamina bar markup should be removed." `
    $hud "<div\s+class=""bottom-left""[\s\S]{0,600}stamina-bar"

foreach ($stylePath in @(
    "Code/UI/HudPanel.razor.scss",
    "Code/UI/HudPanel.cs.scss",
    "Assets/ui/hudpanel.cs.scss"
)) {
    $style = Read-ProjectFile $stylePath

    Require-Match "$stylePath should style the reticle sprint meter." `
        $style "\.sprint-meter"

    Require-Match "$stylePath should style the sprint fill." `
        $style "\.sprint-fill"

    Require-Match "$stylePath should center the sprint meter between the reticle and bottom of the screen." `
        $style "top:\s*25vh"

    Require-Match "$stylePath should center the sprint meter on its vertical midpoint." `
        $style "transform:\s*translatey\(\s*-50%\s*\)"

    Require-Match "$stylePath should make the sprint meter double wide." `
        $style "width:\s*240px"

    Require-Match "$stylePath should make the sprint meter taller." `
        $style "height:\s*18px"

    Require-Match "$stylePath should render the sprint meter at 50 percent opacity." `
        $style "opacity:\s*0\.5"

    Require-Match "$stylePath should style the exhausted/locked sprint state." `
        $style "&\.locked"

    Require-Match "$stylePath should style the recovery sprint state." `
        $style "&\.recovering"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "HUD sprint meter check passed."
