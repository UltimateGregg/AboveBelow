param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]

function Read-ProjectFile {
    param([string]$Path)

    $fullPath = Join-Path $Root $Path
    if (!(Test-Path -LiteralPath $fullPath)) {
        $failures.Add("Missing file: $Path")
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Require-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if (![regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

$options = Read-ProjectFile "Code/UI/LocalOptionsState.cs"

Require-Match "LocalOptionsState should declare 120% as the default UI scale." `
    $options "internal\s+const\s+float\s+DefaultUiScale\s*=\s*1\.2f\s*;"

Require-Match "LocalOptionsState should initialize UI scale from the default value." `
    $options "static\s+float\s+_uiScale\s*=\s*DefaultUiScale\s*;"

Require-Match "LocalOptionsState should fall back to the default value when no UI scale cookie exists." `
    $options "Game\.Cookies\.Get\(\s*UiScaleCookieKey\s*,\s*DefaultUiScale\s*\)"

Require-Match "Reset UI should restore the default UI scale." `
    $options "ResetUiScale\(\)[\s\S]{0,120}SetUiScale\(\s*DefaultUiScale\s*\)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "UI scale default check passed."
