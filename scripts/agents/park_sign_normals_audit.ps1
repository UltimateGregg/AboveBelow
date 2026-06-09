param(
    [string]$Root = "",
    [string]$BlendPath = "environment_model.blend\bouneurmaum_park_sign.blend",
    [string]$BlenderExe = "",
    [int]$TimeoutSeconds = 180,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$auditScript = Join-Path $Root "scripts\bouneurmaum_park_sign_normals_audit.py"
if (-not (Test-Path -LiteralPath $auditScript)) {
    Write-Host "[Error] Park Sign Normals [scripts/bouneurmaum_park_sign_normals_audit.py] - Audit helper is missing."
    exit 1
}

$pythonArgs = @(
    $auditScript,
    "--root", $Root,
    "--blend", $BlendPath,
    "--timeout-seconds", ([string]$TimeoutSeconds)
)

if (-not [string]::IsNullOrWhiteSpace($BlenderExe)) {
    $pythonArgs += @("--blender-exe", $BlenderExe)
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
