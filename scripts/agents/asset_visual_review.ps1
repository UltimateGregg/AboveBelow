param(
    [string]$Root = "",
    [string[]]$Blend = @(),
    [string]$OutDir = "screenshots/asset_previews",
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

$issues = New-Object 'System.Collections.Generic.List[object]'

if ($Blend.Count -eq 0) {
    Add-AgentIssue -Issues $issues -Severity Warning -Area "Asset Visual Review" -Path "" -Message "No -Blend inputs were provided." -Recommendation "Pass one or more .blend files with -Blend."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit 0
}

$renderScript = Join-Path $Root "scripts\render_asset_preview.py"
$pythonArgs = @(
    $renderScript,
    "--out-dir", $OutDir,
    "--timeout-seconds", $TimeoutSeconds
)

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

$resolvedOutDir = $OutDir
if (-not [System.IO.Path]::IsPathRooted($resolvedOutDir)) {
    $resolvedOutDir = Join-Path $Root $resolvedOutDir
}

foreach ($blendPath in $Blend) {
    Push-Location $Root
    try {
        $previewNameOutput = @(& python -c "from pathlib import Path; import sys; sys.path.insert(0, str(Path('scripts').resolve())); import render_asset_preview; print(render_asset_preview.build_preview_paths(Path(sys.argv[1]), Path.cwd(), Path(sys.argv[2]))[0])" $blendPath $resolvedOutDir 2>&1)
        $previewNameExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($previewNameExit -ne 0 -or $previewNameOutput.Count -eq 0) {
        Add-AgentIssue -Issues $issues -Severity Error -Area "Asset Visual Review" -Path $blendPath -Message "Could not calculate expected preview path." -Recommendation "Check scripts/render_asset_preview.py for import or naming errors."
        continue
    }

    $expectedPreview = [string]$previewNameOutput[-1]
    $relativePreview = ConvertTo-AgentRelativePath -Path $expectedPreview -Root $Root

    if (Test-Path -LiteralPath $expectedPreview) {
        Write-Host $relativePreview
    }
    else {
        Add-AgentIssue -Issues $issues -Severity Error -Area "Asset Visual Review" -Path $relativePreview -Message "Expected preview PNG was not created." -Recommendation "Check Blender output and rerun the visual review."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo

if ($pythonExit -ne 0) {
    exit 1
}

$exitCode = Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning
if ($exitCode -ne 0) {
    exit $exitCode
}

if ($FailOnWarning -and $hasWarning) {
    exit 1
}

exit 0
