param(
    [string]$BlendFile = "",
    [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 9876
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$BridgeScript = Join-Path $PSScriptRoot "start_blender_mcp_background.py"

if (-not (Test-Path -LiteralPath $BlenderExe)) {
    $Launcher = "C:\Program Files\Blender Foundation\Blender 5.1\blender-launcher.exe"
    if (Test-Path -LiteralPath $Launcher) {
        $BlenderExe = $Launcher
    } else {
        throw "Cannot find Blender executable at '$BlenderExe' or '$Launcher'."
    }
}

$env:SBOX_BLENDER_MCP_ADDON_DIR = Join-Path $ProjectRoot "mcp-1.0.0"
$env:BLENDER_MCP_HOST = $HostName
$env:BLENDER_MCP_PORT = [string]$Port

$ArgsList = @()
if ($BlendFile) {
    $ArgsList += (Resolve-Path -LiteralPath $BlendFile).Path
}
$ArgsList += @("--background", "--python", $BridgeScript)

& $BlenderExe @ArgsList
