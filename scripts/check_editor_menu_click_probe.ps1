param(
    [string]$Root = ""
)

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$errors = New-Object System.Collections.Generic.List[string]

function Add-Error {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
}

function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Error "Missing required file: $RelativePath"
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

$debugPath = "Code\UI\HudPanel.Debug.cs"
$debug = Read-Text $debugPath

if ($debug -notmatch '\[ConCmd\(\s*"dvp_menu_click"\s*\)\]') {
    Add-Error "$debugPath must expose a debug-only dvp_menu_click console command for editor menu automation."
}

foreach ($required in @(
    'MousePanelEvent',
    'CreateEvent',
    'FindMenuPanelByText',
    'PLAY',
    'HUNTERS',
    'ASSAULT',
    'StartFromMainMenu',
    'SelectLoadoutTeam\( PlayerRole\.Soldier \)',
    'SelectLocalSoldier\( SoldierClass\.Assault \)'
)) {
    if ($debug -notmatch $required) {
        Add-Error "$debugPath must include '$required' so menu automation dispatches real UI click events and has deterministic fallbacks."
    }
}

if ($debug -match '#if DEBUG[\s\S]*#endif') {
    # OK: keep the editor probe out of release builds.
}
else {
    Add-Error "$debugPath must wrap the menu click probe in #if DEBUG."
}

if ($errors.Count -gt 0) {
    Write-Host "Editor menu click probe guard failed:"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Editor menu click probe guard passed."
