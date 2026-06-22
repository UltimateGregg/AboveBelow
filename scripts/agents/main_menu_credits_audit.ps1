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

Write-AgentSection "Main Menu Credits Audit"
Write-Host "Root: $Root"

function Read-RequiredText {
    param([string]$Relative)

    $path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Main Menu Credits" $Relative "Required file is missing."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Test-RequiredPattern {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Path,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Main Menu Credits" $Path $Message $Recommendation
    }
}

$hudText = Read-RequiredText "Code/UI/HudPanel.razor"
$menuText = Read-RequiredText "Code/UI/Hud/MainMenuShellPanel.razor"
$creditsDataText = Read-RequiredText "Code/UI/CreditsData.cs"

$combinedText = "$hudText`n$menuText"

Test-RequiredPattern `
    -Text $menuText `
    -Pattern 'class="choice\s+main-menu-credits"[\s\S]*?Hud\.ClickMenuOption\s*\(\s*Hud\.OpenCredits\s*\)' `
    -Path "Code/UI/Hud/MainMenuShellPanel.razor" `
    -Message "Active main menu does not show a clickable Credits option." `
    -Recommendation "Render Credits in MainMenuShellPanel and route it through Hud.ClickMenuOption(Hud.OpenCredits)."

Test-RequiredPattern `
    -Text $menuText `
    -Pattern 'Hud\.ShowCredits[\s\S]*class="credits-overlay"[\s\S]*CreditsData\.Sections' `
    -Path "Code/UI/Hud/MainMenuShellPanel.razor" `
    -Message "Active main menu does not render the credits overlay from CreditsData." `
    -Recommendation "Render a credits overlay in the active HUD menu, not only in the legacy MainMenuPanel."

Test-RequiredPattern `
    -Text $menuText `
    -Pattern 'Hud\.ClickMenuOption\s*\(\s*Hud\.CloseCredits\s*\)' `
    -Path "Code/UI/Hud/MainMenuShellPanel.razor" `
    -Message "Credits overlay close controls do not use the shared menu click path." `
    -Recommendation "Close the overlay through Hud.ClickMenuOption(Hud.CloseCredits) so Credits follows the menu sound contract."

Test-RequiredPattern `
    -Text $hudText `
    -Pattern 'internal\s+bool\s+ShowCredits\s*\{\s*get;\s*(?:private\s+)?set;\s*\}' `
    -Path "Code/UI/HudPanel.razor" `
    -Message "HudPanel does not own Credits visibility state for the active menu." `
    -Recommendation "Add ShowCredits state to HudPanel so MainMenuShellPanel can render it."

Test-RequiredPattern `
    -Text $hudText `
    -Pattern 'internal\s+void\s+OpenCredits\s*\([\s\S]*?ShowCredits\s*=\s*true;' `
    -Path "Code/UI/HudPanel.razor" `
    -Message "HudPanel does not expose an OpenCredits action." `
    -Recommendation "Add OpenCredits() and set ShowCredits to true."

Test-RequiredPattern `
    -Text $hudText `
    -Pattern 'internal\s+void\s+CloseCredits\s*\([\s\S]*?ShowCredits\s*=\s*false;' `
    -Path "Code/UI/HudPanel.razor" `
    -Message "HudPanel does not expose a CloseCredits action." `
    -Recommendation "Add CloseCredits() and set ShowCredits to false."

Test-RequiredPattern `
    -Text $combinedText `
    -Pattern 'BuildHash\s*\([\s\S]*ShowCredits' `
    -Path "Code/UI/HudPanel.razor" `
    -Message "Credits visibility is not included in Razor BuildHash coverage." `
    -Recommendation "Include ShowCredits in the active HUD/menu BuildHash so the overlay appears and disappears reliably."

Test-RequiredPattern `
    -Text $creditsDataText `
    -Pattern 'CreditsData[\s\S]*Sections' `
    -Path "Code/UI/CreditsData.cs" `
    -Message "CreditsData source list is missing or not shaped as sections." `
    -Recommendation "Keep credits attribution in CreditsData.Sections so the active menu renders one source of truth."

$styleRelatives = @(
    "Code/UI/HudPanel.razor.scss",
    "Code/UI/HudPanel.cs.scss",
    "Assets/ui/hudpanel.cs.scss"
)

$styleTexts = @{}
foreach ($relative in $styleRelatives) {
    $styleTexts[$relative] = Read-RequiredText $relative
}

if ($styleTexts.ContainsKey("Code/UI/HudPanel.razor.scss")) {
    $canonical = $styleTexts["Code/UI/HudPanel.razor.scss"]
    foreach ($relative in @("Code/UI/HudPanel.cs.scss", "Assets/ui/hudpanel.cs.scss")) {
        if ($styleTexts.ContainsKey($relative) -and $styleTexts[$relative] -ne $canonical) {
            Add-AgentIssue $issues "Error" "Main Menu Credits" $relative "HUD stylesheet alias is out of sync with HudPanel.razor.scss." "Copy accepted HUD style changes to every S&Box stylesheet alias."
        }
    }

    foreach ($styleCheck in @(
        @{ Pattern = '\.main-menu-credits'; Message = "Credits menu button style is missing." },
        @{ Pattern = '\.credits-overlay'; Message = "Credits overlay style is missing." },
        @{ Pattern = '\.credits-card'; Message = "Credits card style is missing." },
        @{ Pattern = '\.credits-close'; Message = "Credits close button style is missing." },
        @{ Pattern = '\.credits-body'; Message = "Credits scroll body style is missing." }
    )) {
        if ($canonical -notmatch $styleCheck.Pattern) {
            Add-AgentIssue $issues "Error" "Main Menu Credits" "Code/UI/HudPanel.razor.scss" $styleCheck.Message "Style the active HUD credits UI in HudPanel.razor.scss and sync aliases."
        }
    }
}

Add-AgentIssue $issues "Info" "Main Menu Credits" "Code/UI/Hud/MainMenuShellPanel.razor" "Checked active startup menu credits rendering, state, BuildHash coverage, and stylesheet aliases."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
