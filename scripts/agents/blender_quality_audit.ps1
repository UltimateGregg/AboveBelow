param(
    [string]$Root = "",
    [ValidateSet("", "weapon", "drone", "character", "environment")]
    [string]$Category = "",
    [string[]]$Blend = @(),
    [string]$BlenderExe = "",
    [int]$TimeoutSeconds = 120,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$auditScript = Join-Path $Root "scripts\blender_asset_audit.py"
$profiles = Join-Path $Root "scripts\asset_quality_profiles.json"

$pythonArgs = @(
    $auditScript,
    "--root", $Root,
    "--profiles", $profiles,
    "--timeout-seconds", $TimeoutSeconds
)

if (-not [string]::IsNullOrWhiteSpace($Category)) {
    $pythonArgs += @("--category", $Category)
}

if (-not [string]::IsNullOrWhiteSpace($BlenderExe)) {
    $pythonArgs += @("--blender-exe", $BlenderExe)
}

foreach ($blendPath in $Blend) {
    $pythonArgs += @("--blend", $blendPath)
}

Push-Location $Root
try {
    $output = @(& python @pythonArgs 2>&1)
    $pythonExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

$hasWarning = $false
foreach ($line in $output) {
    $text = [string]$line
    if ($text.StartsWith("[Warning]")) {
        $hasWarning = $true
    }

    if ($ShowInfo -or -not $text.StartsWith("[Info]")) {
        Write-Host $text
    }
}

if ($pythonExit -ne 0) {
    exit 1
}

if ($FailOnWarning -and $hasWarning) {
    exit 1
}

exit 0
