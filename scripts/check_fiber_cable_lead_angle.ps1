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

$fiberCable = Read-ProjectFile "Code/Drone/FiberCable.cs"
$fiberPrefab = Read-ProjectFile "Assets/prefabs/drone_fpv_fiber.prefab"

Require-Match "FiberCable should expose a 45-degree live lead angle target." `
    $fiberCable "\[Property,\s*Range\(\s*10f,\s*85f\s*\)\]\s*public\s+float\s+DroneLeadAngleDegrees\s*\{\s*get;\s*set;\s*\}\s*=\s*45f;"

Require-Match "FiberCable should cap the live lead projection distance." `
    $fiberCable "\[Property,\s*Range\(\s*0f,\s*1200f\s*\)\]\s*public\s+float\s+DroneLeadMaxHorizontalDistance\s*\{\s*get;\s*set;\s*\}\s*=\s*600f;"

Require-Match "FiberCable should build a shifted drone lead point before adding drone trail points." `
    $fiberCable "var\s+droneLeadPoint\s*=\s*BuildDroneLeadPoint\(\s*dronePos,\s*groundUnderDrone,\s*groundUnderPilot\s*\);[\s\S]{0,260}AddTrailPoint\(\s*_droneTrail,\s*droneLeadPoint"

Require-Match "FiberCable should render the current shifted lead point before the live drone endpoint." `
    $fiberCable "for\s*\(\s*int\s+i\s*=\s*0;\s*i\s*<\s*_droneTrail\.Count;\s*i\+\+\s*\)[\s\S]{0,180}AddRenderPoint\(\s*droneLeadPoint\s*\);[\s\S]{0,120}AddRenderPoint\(\s*dronePos\s*\);"

Require-Match "FiberCable should calculate horizontal lead distance from the target angle." `
    $fiberCable "var\s+angleRadians\s*=\s*DroneLeadAngleDegrees\.Clamp\(\s*10f,\s*85f\s*\)\s*\*\s*\(MathF\.PI\s*/\s*180f\);[\s\S]{0,220}MathF\.Tan\(\s*angleRadians\s*\)"

Require-Match "FiberCable should prefer the existing cable trail or pilot direction for the live lead direction." `
    $fiberCable "_hasLastDroneTrailPoint[\s\S]{0,260}_lastDroneTrailPoint[\s\S]{0,260}groundUnderPilot"

Require-Match "FiberCable should freeze detached cable endpoints using the shifted lead point instead of the vertical drone projection." `
    $fiberCable "BuildGroundedRenderPoints\(\)[\s\S]*BuildDroneLeadPoint\(\s*WorldPosition,\s*groundUnderDrone,\s*leadDirectionReference\s*\)"

Require-Match "Fiber FPV prefab should serialize the 45-degree lead angle." `
    $fiberPrefab '"DroneLeadAngleDegrees"\s*:\s*45'

Require-Match "Fiber FPV prefab should serialize the live lead projection cap." `
    $fiberPrefab '"DroneLeadMaxHorizontalDistance"\s*:\s*600'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "ERROR: $_" }
    exit 1
}

Write-Host "Fiber cable lead angle check passed."
