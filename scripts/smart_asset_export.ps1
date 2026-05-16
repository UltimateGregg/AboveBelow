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
$projectRoot = (Get-Location).Path
$normalizedBlendFile = [System.IO.Path]::GetFullPath($BlendFilePath)

function Resolve-ConfigSourceBlend {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }

    if (-not $config.source_blend) {
        return $null
    }

    $sourceBlend = [string]$config.source_blend
    if ($sourceBlend.Contains('$')) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($sourceBlend)) {
        return [System.IO.Path]::GetFullPath($sourceBlend)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $sourceBlend))
}

# Check for asset-specific config (e.g., drone_asset_pipeline.json)
$assetSpecificConfig = Join-Path $PSScriptRoot "${blendFileName}_asset_pipeline.json"
$genericConfig = Join-Path $PSScriptRoot "asset_pipeline_generic.json"

if (Test-Path $assetSpecificConfig) {
    Write-Host "Using asset-specific config: $assetSpecificConfig" -ForegroundColor Green
    $configPath = $assetSpecificConfig
} else {
    $sourceBlendConfigs = @(
        Get-ChildItem -Path $PSScriptRoot -Filter "*_asset_pipeline.json" |
            Where-Object { $_.FullName -ne $assetSpecificConfig } |
            Where-Object {
                $configSource = Resolve-ConfigSourceBlend -ConfigPath $_.FullName
                $configSource -and [string]::Equals($configSource, $normalizedBlendFile, [System.StringComparison]::OrdinalIgnoreCase)
            }
    )

    if ($sourceBlendConfigs.Count -eq 1) {
        $configPath = $sourceBlendConfigs[0].FullName
        Write-Host "Using source_blend config: $configPath" -ForegroundColor Green
    } elseif ($sourceBlendConfigs.Count -gt 1) {
        $matches = ($sourceBlendConfigs | ForEach-Object { $_.FullName }) -join "`n  - "
        Write-Error "Multiple asset configs point at ${BlendFilePath}:`n  - $matches"
        exit 1
    }
}

if (-not $configPath -and (Test-Path $genericConfig)) {
    Write-Host "Using generic config: $genericConfig" -ForegroundColor Yellow
    $configPath = $genericConfig
} elseif (-not $configPath) {
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

if (-not $DryRun) {
    $materialSlotAudit = Join-Path $PSScriptRoot "agents\fbx_material_slot_audit.ps1"
    if (Test-Path $materialSlotAudit) {
        Write-Host "Running changed-asset material slot audit: $blendFileName"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $materialSlotAudit -Root $projectRoot -Config $configPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Changed-asset material slot audit failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    }
}
