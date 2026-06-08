param(
    [string]$Root = "",
    [string[]]$Config = @(),
    [string]$BlenderExe = "",
    [int]$TimeoutSeconds = 180,
    [double]$AxisTolerance = 0.25,
    [double]$MaxOverallScaleRatio = 2.0,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$auditScript = Join-Path $Root "scripts\model_collision_scale_audit.py"
if (-not (Test-Path -LiteralPath $auditScript)) {
    Write-Host "[Error] Model Collision Scale [scripts/model_collision_scale_audit.py] - Audit helper is missing."
    exit 1
}

$pythonArgs = @(
    $auditScript,
    "--root", $Root,
    "--timeout-seconds", ([string]$TimeoutSeconds),
    "--axis-tolerance", ([string]$AxisTolerance),
    "--max-overall-scale-ratio", ([string]$MaxOverallScaleRatio)
)

if ($ShowInfo) {
    $pythonArgs += "--show-info"
}
if ($FailOnWarning) {
    $pythonArgs += "--fail-on-warning"
}
if (-not [string]::IsNullOrWhiteSpace($BlenderExe)) {
    $pythonArgs += @("--blender-exe", $BlenderExe)
}
foreach ($configPath in $Config) {
    if (-not [string]::IsNullOrWhiteSpace($configPath)) {
        $pythonArgs += @("--config", $configPath)
    }
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
    if ($line -match '^\[Info\]' -and -not $ShowInfo) {
        continue
    }
    if ($line -match '^\[Warning\]') {
        $hasWarning = $true
    }
    Write-Host $line
}

if ($pythonExit -ne 0) {
    exit 1
}

if ($FailOnWarning -and $hasWarning) {
    exit 1
}

exit 0
