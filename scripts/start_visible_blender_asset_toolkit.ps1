param(
    [string]$BlendFile = "",
    [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 9876,
    [switch]$NoInstall
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$StartupScript = Join-Path $PSScriptRoot "start_visible_blender_asset_toolkit.py"

if (-not (Test-Path -LiteralPath $BlenderExe)) {
    $Launcher = "C:\Program Files\Blender Foundation\Blender 5.1\blender-launcher.exe"
    if (Test-Path -LiteralPath $Launcher) {
        $BlenderExe = $Launcher
    } else {
        throw "Cannot find Blender executable at '$BlenderExe' or '$Launcher'."
    }
}

if (-not $NoInstall) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install_blender_asset_toolkit.ps1") -ProjectRoot $ProjectRoot
}

$env:SBOX_PROJECT_ROOT = [string]$ProjectRoot
$env:SBOX_BLENDER_MCP_ADDON_DIR = Join-Path $ProjectRoot "mcp-1.0.0"
$env:BLENDER_MCP_HOST = $HostName
$env:BLENDER_MCP_PORT = [string]$Port

$ArgsList = @()
if ($BlendFile) {
    $ArgsList += (Resolve-Path -LiteralPath $BlendFile).Path
}
$ArgsList += @("--python", $StartupScript)

Write-Host "Starting visible Blender with S&Box Asset Toolkit..."
Write-Host "Blender: $BlenderExe"
Write-Host "Bridge: ${HostName}:$Port"
Start-Process -FilePath $BlenderExe -ArgumentList $ArgsList -WorkingDirectory $ProjectRoot
