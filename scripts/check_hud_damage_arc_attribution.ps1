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

$hud = Read-ProjectFile "Code/UI/HudPanel.razor"
foreach ($childPanel in Get-ChildItem -Path (Join-Path $Root "Code/UI/Hud/*.razor") -ErrorAction SilentlyContinue) {
    $hud += "`n" + (Get-Content -LiteralPath $childPanel.FullName -Raw)
}

Require-Match "HUD damage arcs should require a real non-local attacker before treating local-owned damage as hostile." `
    $hud "if\s*\([^\r\n]*victim\.GameObject\.Network\.Owner\?\.Id\s*==\s*localId[^\r\n]*&&[^\r\n]*info\.AttackerId\s*!=\s*default[^\r\n]*&&[^\r\n]*info\.AttackerId\s*!=\s*localId[^\r\n]*\)[\s\S]{0,1200}_damageArcs\.Add"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "HUD damage arc attribution check passed."
