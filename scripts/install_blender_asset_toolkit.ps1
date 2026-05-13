param(
    [string]$ProjectRoot = "",
    [string]$BlenderVersion = "",
    [string]$AddonsRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
} else {
    $ProjectRoot = Resolve-Path -LiteralPath $ProjectRoot
}

$Source = Join-Path $ProjectRoot "blender_addons\sbox_asset_toolkit"
if (-not (Test-Path -LiteralPath $Source)) {
    throw "Cannot find add-on source at '$Source'."
}

if ([string]::IsNullOrWhiteSpace($AddonsRoot)) {
    $BlenderBase = Join-Path $env:APPDATA "Blender Foundation\Blender"
    if ([string]::IsNullOrWhiteSpace($BlenderVersion)) {
        $VersionDir = Get-ChildItem -LiteralPath $BlenderBase -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($null -eq $VersionDir) {
            $BlenderVersion = "5.1"
        } else {
            $BlenderVersion = $VersionDir.Name
        }
    }
    $AddonsRoot = Join-Path $BlenderBase "$BlenderVersion\scripts\addons"
}

$Target = Join-Path $AddonsRoot "sbox_asset_toolkit"
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item -LiteralPath (Join-Path $Source "__init__.py") -Destination (Join-Path $Target "__init__.py") -Force

Write-Host "Installed S&Box Asset Toolkit add-on to: $Target"
Write-Host "Enable it in Blender Preferences, or run scripts/start_visible_blender_asset_toolkit.ps1."
