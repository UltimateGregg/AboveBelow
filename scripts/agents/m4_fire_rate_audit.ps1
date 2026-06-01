param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

function Find-PrefabChildPath {
    param(
        [object]$Node,
        [string[]]$Path
    )

    $current = $Node
    foreach ($part in $Path) {
        $children = @($current.Children)
        $current = $children | Where-Object { $_.Name -eq $part } | Select-Object -First 1
        if ($null -eq $current) {
            return $null
        }
    }

    return $current
}

function Get-FireIntervalComponent {
    param(
        [object]$Node
    )

    return @($Node.Components) | Where-Object {
        $null -ne $_.PSObject.Properties["FireInterval"]
    } | Select-Object -First 1
}

function Test-HitscanFireInterval {
    param(
        [string]$Path,
        [string]$Label,
        [string[]]$NodePath,
        [double]$ExpectedInterval,
        [string]$Area = "M4 Fire Rate"
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $Path "$Label prefab is missing." "Restore the prefab or update the M4 fire-rate contract intentionally."
        return
    }

    try {
        $prefab = Read-AgentJson -Path $fullPath
    }
    catch {
        Add-AgentIssue $issues "Error" $Area $Path $_.Exception.Message "Fix invalid prefab JSON before tuning weapon balance."
        return
    }

    $node = $prefab.RootObject
    if ($NodePath.Count -gt 0) {
        $node = Find-PrefabChildPath -Node $node -Path $NodePath
    }

    if ($null -eq $node) {
        Add-AgentIssue $issues "Error" $Area $Path "$Label is missing path '$($NodePath -join "/")'." "Keep the weapon child path stable or update this focused balance guard."
        return
    }

    $weapon = Get-FireIntervalComponent -Node $node
    if ($null -eq $weapon) {
        Add-AgentIssue $issues "Error" $Area $Path "$Label has no component with FireInterval at the checked path." "Keep the fire-rate check tied to the actual weapon component."
        return
    }

    $actual = [double]$weapon.FireInterval
    if ([math]::Abs($actual - $ExpectedInterval) -gt 0.0001) {
        Add-AgentIssue $issues "Error" $Area $Path "$Label FireInterval is $actual; expected $ExpectedInterval." "A 1.5x M4 fire-rate increase from 0.12 seconds per shot should use FireInterval 0.08."
        return
    }

    Add-AgentIssue $issues "Info" $Area $Path "$Label FireInterval is $actual."
}

function Test-RequiredDocText {
    param(
        [string]$Path,
        [string]$Pattern
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "M4 Fire Rate Docs" $Path "Balance documentation is missing." "Keep current-value docs aligned with tuned prefab data."
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    if ($text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "M4 Fire Rate Docs" $Path "Balance docs do not mention the current M4 0.08 s fire interval." "Update the assault current-value row when tuning the M4 prefab fire interval."
        return
    }

    Add-AgentIssue $issues "Info" "M4 Fire Rate Docs" $Path "Balance docs mention the current M4 fire interval."
}

Write-AgentSection "M4 Fire Rate Audit"

Test-HitscanFireInterval -Path "Assets/prefabs/soldier_assault.prefab" -Label "Assault M4" -NodePath @("Body", "Weapon") -ExpectedInterval 0.08
Test-HitscanFireInterval -Path "Assets/prefabs/soldier.prefab" -Label "Legacy assault M4 fallback" -NodePath @("Body", "Weapon") -ExpectedInterval 0.08
Test-HitscanFireInterval -Path "Assets/prefabs/items/assault_rifle_m4_held.prefab" -Label "Reusable held-item M4 template" -NodePath @() -ExpectedInterval 0.08
Test-HitscanFireInterval -Path "Assets/prefabs/pilot_ground.prefab" -Label "Pilot MP7" -NodePath @("Body", "Weapon") -ExpectedInterval 0.07 -Area "Non-M4 Fire Rate Regression"
Test-RequiredDocText -Path "docs/balance_rps.md" -Pattern 'rifle 18 damage every 0\.08 s'

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
