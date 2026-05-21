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

function Get-DefaultFloat {
    param(
        [string]$Text,
        [string]$Property
    )

    $match = [regex]::Match($Text, "$Property\s*\{\s*get;\s*set;\s*\}\s*=\s*(?<value>[0-9]+(?:\.[0-9]+)?)f")
    if (!$match.Success) {
        $failures.Add("Missing numeric default for $Property.")
        return 0.0
    }

    return [double]::Parse($match.Groups["value"].Value, [Globalization.CultureInfo]::InvariantCulture)
}

$controller = Read-ProjectFile "Code/Player/GroundPlayerController.cs"

Require-Match "GroundPlayerController should expose sprint footstep stride tuning." `
    $controller "SprintFootstepStrideMultiplier\s*\{\s*get;\s*set;\s*\}\s*=\s*[0-9]+(?:\.[0-9]+)?f"

Require-Match "GroundPlayerController should use sprint footstep stride tuning while sprinting." `
    $controller "if\s*\(\s*IsSprinting\s*\)\s*stride\s*\*=\s*SprintFootstepStrideMultiplier"

Reject-Match "Sprinting footsteps should not use the old short-stride cadence multiplier." `
    $controller "if\s*\(\s*IsSprinting\s*\)\s*stride\s*\*=\s*0\.75f"

$walkSpeed = Get-DefaultFloat $controller "WalkSpeed"
$sprintSpeed = Get-DefaultFloat $controller "SprintSpeed"
$footstepDistance = Get-DefaultFloat $controller "FootstepDistance"
$sprintStrideMultiplier = Get-DefaultFloat $controller "SprintFootstepStrideMultiplier"

if ($footstepDistance -gt 0 -and $sprintStrideMultiplier -gt 0) {
    $walkCadence = $walkSpeed / $footstepDistance
    $sprintCadence = $sprintSpeed / ($footstepDistance * $sprintStrideMultiplier)

    if ($sprintCadence -gt 5.5) {
        $failures.Add(("Default sprint footstep cadence is too fast: {0:N2}/sec. Keep it at or below 5.50/sec." -f $sprintCadence))
    }

    if ($sprintCadence -lt ($walkCadence * 1.1)) {
        $failures.Add(("Default sprint footstep cadence is too slow versus walk: sprint {0:N2}/sec, walk {1:N2}/sec." -f $sprintCadence, $walkCadence))
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Sprint footstep cadence check passed."
