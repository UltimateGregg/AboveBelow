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

Write-AgentSection "Team Label Copy Audit"
Write-Host "Root: $Root"

$forbiddenChecks = @(
    @{
        Path = "Code/UI/HudPanel.razor"
        Patterns = @(
            "ABOVE WINS",
            "BELOW WINS",
            "Take down above.",
            "Hunt below.",
            "Fly drones from above",
            "Fight from below",
            "Drone Pilots against Soldiers.",
            '"ABOVE" : "BELOW"',
            '"ABOVE" : LocalRole == PlayerRole.Soldier ? "BELOW"'
        )
    },
    @{
        Path = "Code/UI/HudPanel.cs"
        Patterns = @(
            '=> "ABOVE"',
            '=> "BELOW"'
        )
    },
    @{
        Path = "Code/UI/MainMenuPanel.razor"
        Patterns = @(
            ">ABOVE</",
            ">BELOW</",
            "pressure the battlefield from above",
            "ground hunters"
        )
    },
    @{
        Path = "Code/Game/RoundManager.cs"
        Patterns = @(
            '"ABOVE" : "BELOW"',
            "Above {PilotWins}",
            "Below {SoldierWins}"
        )
    },
    @{
        Path = "README.md"
        Patterns = @(
            "HUD labels still read **ABOVE**",
            "for pilots and **BELOW**"
        )
    },
    @{
        Path = "docs/architecture.md"
        Patterns = @(
            "Player-facing role names rebranded to ABOVE / BELOW"
        )
    },
    @{
        Path = "scripts/agents/playtest_checklist.ps1"
        Patterns = @(
            "Above/Below team choices"
        )
    }
)

$requiredCopy = @(
    @{
        Path = "Code/UI/HudPanel.razor"
        Values = @(
            "DRONE PILOTS WIN",
            "SOLDIERS WIN",
            "Hunt soldiers.",
            "Take down drone pilots.",
            "Fly drones as drone pilots",
            "Fight as soldiers",
            "main-menu-title"">ABOVE / BELOW"
        )
    },
    @{
        Path = "Code/UI/HudPanel.cs"
        Values = @(
            "DRONE PILOTS",
            "SOLDIERS"
        )
    },
    @{
        Path = "Code/UI/MainMenuPanel.razor"
        Values = @(
            "DRONE PILOTS",
            "SOLDIERS",
            "Drone Pilots and Soldiers",
            "pressure Soldiers across the battlefield"
        )
    },
    @{
        Path = "Code/Game/RoundManager.cs"
        Values = @(
            "Drone Pilots",
            "Soldiers"
        )
    }
)

function Get-CheckedFileText {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Team Labels" $RelativePath "Expected copy surface is missing." "Restore the file or update this audit if the UI surface moved."
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

foreach ($check in $forbiddenChecks) {
    $text = Get-CheckedFileText -RelativePath $check.Path
    if ($null -eq $text) {
        continue
    }

    foreach ($pattern in $check.Patterns) {
        if ($text.IndexOf($pattern, [System.StringComparison]::Ordinal) -ge 0) {
            Add-AgentIssue $issues "Error" "Team Labels" $check.Path "Found stale player-facing team label '$pattern'." "Use 'Drone Pilots' for the pilot side and 'Soldiers' for the soldier side. Keep the project title unchanged."
        }
    }
}

foreach ($check in $requiredCopy) {
    $text = Get-CheckedFileText -RelativePath $check.Path
    if ($null -eq $text) {
        continue
    }

    foreach ($value in $check.Values) {
        if ($text.IndexOf($value, [System.StringComparison]::Ordinal) -lt 0) {
            Add-AgentIssue $issues "Error" "Team Labels" $check.Path "Expected team copy '$value' was not found." "Keep the in-game role, objective, and round-end labels aligned with the requested terminology."
        }
    }
}

Add-AgentIssue $issues "Info" "Team Labels" "Code/UI" "Checked in-game team labels, round-end copy, menu copy, and related docs for stale Above/Below role naming."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
