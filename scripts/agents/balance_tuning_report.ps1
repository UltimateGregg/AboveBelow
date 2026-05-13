param(
    [string]$Root = "",
    [string]$OutFile = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Text = ""
    )
    $Lines.Add($Text)
}

$lines = New-Object System.Collections.Generic.List[string]
Add-Line $lines "# Balance and Tuning Report"
Add-Line $lines ""
Add-Line $lines "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Line $lines ""

$gameRulesPath = Join-Path $Root "Code\Game\GameRules.cs"
if (Test-Path -LiteralPath $gameRulesPath) {
    Add-Line $lines "## GameRules Defaults"
    Add-Line $lines ""
    Add-Line $lines "| Property | Type | Default |"
    Add-Line $lines "|---|---:|---:|"

    $raw = Get-Content -LiteralPath $gameRulesPath -Raw
    $matches = [regex]::Matches($raw, "\[Property,\s*Sync\]\s+public\s+(?<type>int|float|bool)\s+(?<name>\w+)\s*\{\s*get;\s*set;\s*\}\s*=\s*(?<value>[^;]+);")
    foreach ($match in $matches) {
        Add-Line $lines "| $($match.Groups['name'].Value) | $($match.Groups['type'].Value) | $($match.Groups['value'].Value.Trim()) |"
    }
    Add-Line $lines ""
}

$prefabValues = @(
    @{ Path = "Assets/prefabs/soldier_assault.prefab"; Label = "Assault Soldier"; Fields = @("MaxHealth", "Damage", "FireInterval", "MagazineSize", "ReloadSeconds") },
    @{ Path = "Assets/prefabs/soldier_counter_uav.prefab"; Label = "Counter-UAV Soldier"; Fields = @("MaxHealth", "Range", "ConeHalfAngle", "TickInterval") },
    @{ Path = "Assets/prefabs/soldier_heavy.prefab"; Label = "Heavy Soldier"; Fields = @("MaxHealth", "DamagePerPellet", "PelletCount", "FireInterval", "ReloadSeconds") },
    @{ Path = "Assets/prefabs/pilot_ground.prefab"; Label = "Pilot Ground"; Fields = @("MaxHealth", "LaunchCooldownSeconds") },
    @{ Path = "Assets/prefabs/drone_gps.prefab"; Label = "GPS Drone"; Fields = @("MaxHealth", "MaxSpeed", "Acceleration", "JamSusceptibility", "EnableHitscan", "EnableKamikaze", "KamikazeDamage") },
    @{ Path = "Assets/prefabs/drone_fpv.prefab"; Label = "FPV Drone"; Fields = @("MaxHealth", "MaxSpeed", "Acceleration", "JamSusceptibility", "EnableHitscan", "EnableKamikaze", "KamikazeDamage") },
    @{ Path = "Assets/prefabs/drone_fpv_fiber.prefab"; Label = "Fiber FPV Drone"; Fields = @("MaxHealth", "MaxSpeed", "Acceleration", "JamSusceptibility", "EnableHitscan", "EnableKamikaze", "KamikazeDamage") }
)

Add-Line $lines "## Prefab Tuning Snapshot"
Add-Line $lines ""

foreach ($entry in $prefabValues) {
    $full = Join-Path $Root $entry.Path
    Add-Line $lines "### $($entry.Label)"
    Add-Line $lines ""
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Line $lines ("Missing prefab: ``{0}``" -f $entry.Path)
        Add-Line $lines ""
        continue
    }

    $raw = Get-Content -LiteralPath $full -Raw
    Add-Line $lines "| Field | Value |"
    Add-Line $lines "|---|---:|"
    foreach ($field in $entry.Fields) {
        $pattern = '"' + [regex]::Escape($field) + '"\s*:\s*(?<value>"[^"]+"|true|false|-?\d+(?:\.\d+)?)'
        $match = [regex]::Match($raw, $pattern)
        if ($match.Success) {
            Add-Line $lines "| $field | $($match.Groups['value'].Value) |"
        }
    }
    Add-Line $lines ""
}

Add-Line $lines "## Review Prompts"
Add-Line $lines ""
Add-Line $lines "- Counter-UAV should remain the clearest answer to GPS."
Add-Line $lines "- Heavy should remain the clearest answer to normal FPV dive pressure."
Add-Line $lines "- Assault rifle/chaff should remain the practical answer to fiber FPV."
Add-Line $lines '- Fiber FPV `JamSusceptibility` should stay `0` unless the balance spec changes.'
Add-Line $lines "- Any weapon or health tuning change needs a solo smoke test plus a 2-client combat test."

$text = $lines -join [Environment]::NewLine
if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $target = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $Root $OutFile }
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    $text | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Host "Wrote balance report: $(ConvertTo-AgentRelativePath -Path $target -Root $Root)"
}
else {
    Write-Host $text
}
