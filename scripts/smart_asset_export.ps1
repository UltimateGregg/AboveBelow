param(
    [string]$BlendFilePath,
    [switch]$DryRun,
    [switch]$SkipExport,
    [switch]$SkipPrefab
)

$ErrorActionPreference = "Stop"

# Resolve the .blend file path
if (-not [System.IO.Path]::IsPathRooted($BlendFilePath)) {
    $BlendFilePath = Join-Path (Get-Location) $BlendFilePath
}

if (-not (Test-Path $BlendFilePath)) {
    Write-Error "Blend file not found: $BlendFilePath"
    exit 1
}

# Extract asset name from blend file (e.g., drone.blend → drone)
$blendFileName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($BlendFilePath))
$blendDir = Split-Path $BlendFilePath -Parent

# Check for asset-specific config (e.g., drone_asset_pipeline.json)
$assetSpecificConfig = Join-Path $PSScriptRoot "${blendFileName}_asset_pipeline.json"
$genericConfig = Join-Path $PSScriptRoot "asset_pipeline_generic.json"

if (Test-Path $assetSpecificConfig) {
    Write-Host "Using asset-specific config: $assetSpecificConfig" -ForegroundColor Green
    $configPath = $assetSpecificConfig
} elseif (Test-Path $genericConfig) {
    Write-Host "Using generic config: $genericConfig" -ForegroundColor Yellow
    $configPath = $genericConfig
} else {
    # No per-asset config and no generic fallback. Auto-scaffold a config
    # from the .blend so newly modeled assets reach s&box without a manual
    # bootstrap step. The scaffolder refuses to overwrite an existing config,
    # so this branch only triggers on genuinely first-time exports.
    $scaffolder = Join-Path $PSScriptRoot "scaffold_asset_config.py"
    if (-not (Test-Path $scaffolder)) {
        Write-Error "No config found and scaffolder is missing:`n  - $assetSpecificConfig`n  - $scaffolder"
        exit 1
    }
    Write-Host "No config for '$blendFileName' - scaffolding from .blend ..." -ForegroundColor Yellow
    & python $scaffolder $BlendFilePath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Scaffolder failed for $blendFileName (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
    if (-not (Test-Path $assetSpecificConfig)) {
        Write-Error "Scaffolder did not produce expected config: $assetSpecificConfig"
        exit 1
    }
    Write-Host "Scaffolded $assetSpecificConfig - review material_remap if needed." -ForegroundColor Cyan
    $configPath = $assetSpecificConfig
}

# Build asset pipeline command
$argsList = @(
    (Join-Path $PSScriptRoot "asset_pipeline.py"),
    "--config", $configPath,
    "--source-blend", $BlendFilePath
)

if ($DryRun) {
    $argsList += "--dry-run"
}
if ($SkipExport) {
    $argsList += "--skip-export"
}
if ($SkipPrefab) {
    $argsList += "--skip-prefab"
}

# Run Python asset pipeline
Write-Host "Running asset pipeline for: $blendFileName"
Write-Host "Command: python $($argsList -join ' ')"

& python $argsList

if ($LASTEXITCODE -ne 0) {
    Write-Error "Asset pipeline failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Asset export completed successfully: $blendFileName" -ForegroundColor Green
