param(
    [string]$PrefabDir = "Assets/prefabs"
)

$ErrorActionPreference = "Stop"

$rules = @{
    "soldier_assault.prefab" = @(
        @{ Pattern = "^DroneVsPlayers\.HitscanWeapon$"; Slot = 1; Label = "assault primary" },
        @{ Pattern = "^DroneVsPlayers\.ChaffGrenade$"; Slot = 2; Label = "assault equipment" }
    )
    "soldier_counter_uav.prefab" = @(
        @{ Pattern = "^DroneVsPlayers\.DroneJammerGun$"; Slot = 1; Label = "counter-UAV primary" },
        @{ Pattern = "^DroneVsPlayers\.FragGrenade$"; Slot = 2; Label = "counter-UAV equipment" }
    )
    "soldier_heavy.prefab" = @(
        @{ Pattern = "^DroneVsPlayers\.ShotgunWeapon$"; Slot = 1; Label = "heavy primary" },
        @{ Pattern = "^DroneVsPlayers\.EmpGrenade$"; Slot = 2; Label = "heavy equipment" }
    )
    "pilot_ground.prefab" = @(
        @{ Pattern = "^DroneVsPlayers\.DroneDeployer$"; Slot = 1; Label = "pilot drone controller" },
        @{ Pattern = "^DroneVsPlayers\.HitscanWeapon$"; Slot = 2; Label = "pilot MP7" }
    )
}

$failures = New-Object System.Collections.Generic.List[string]

function Get-DefaultLoadoutSlot {
    param([string]$Type)

    if ($Type -match "^DroneVsPlayers\.(FragGrenade|ChaffGrenade|EmpGrenade)$") {
        return 2
    }

    if ($Type -match "^DroneVsPlayers\.(HitscanWeapon|ShotgunWeapon|DroneJammerGun|DroneDeployer)$") {
        return 1
    }

    return -1
}

foreach ($entry in $rules.GetEnumerator()) {
    $path = Join-Path $PrefabDir $entry.Key
    if (!(Test-Path -LiteralPath $path)) {
        $failures.Add("Missing prefab: $path")
        continue
    }

    $raw = Get-Content -LiteralPath $path -Raw
    $typeMatches = @([regex]::Matches($raw, '"__type"\s*:\s*"(?<type>DroneVsPlayers\.[^"]+)"'))
    $components = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $typeMatches.Count; $i++) {
        $match = $typeMatches[$i]
        $nextIndex = if ($i + 1 -lt $typeMatches.Count) { $typeMatches[$i + 1].Index } else { $raw.Length }
        $segment = $raw.Substring($match.Index, $nextIndex - $match.Index)
        $slotMatch = [regex]::Match($segment, '"Slot"\s*:\s*(?<slot>-?\d+)')
        $type = $match.Groups["type"].Value
        $slot = if ($slotMatch.Success) { [int]$slotMatch.Groups["slot"].Value } else { Get-DefaultLoadoutSlot -Type $type }
        $components.Add([pscustomobject]@{
            Type = $type
            Slot = $slot
        })
    }

    $slotClaims = @{}

    foreach ($rule in $entry.Value) {
        $matches = @($components | Where-Object { $_.Type -match $rule.Pattern })
        if ($matches.Count -eq 0) {
            $failures.Add("$($entry.Key): missing $($rule.Label)")
            continue
        }

        foreach ($component in $matches) {
            $slot = [int]$component.Slot
            if ($slot -ne [int]$rule.Slot) {
                $failures.Add("$($entry.Key): $($rule.Label) expected slot $($rule.Slot), found $slot")
            }

            if ($slot -gt 0) {
                if (!$slotClaims.ContainsKey($slot)) {
                    $slotClaims[$slot] = New-Object System.Collections.Generic.List[string]
                }
                $slotClaims[$slot].Add($rule.Label)
            }
        }
    }

    foreach ($slot in $slotClaims.Keys) {
        if ($slotClaims[$slot].Count -gt 1) {
            $failures.Add("$($entry.Key): multiple held items claim slot ${slot}: $($slotClaims[$slot] -join ', ')")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Loadout slot check passed for $($rules.Count) prefabs."
