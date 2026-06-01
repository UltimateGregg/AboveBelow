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

Write-AgentSection "UI Flow Audit"
Write-Host "Root: $Root"

$uiRoot = Join-Path $Root "Code\UI"
if (-not (Test-Path -LiteralPath $uiRoot)) {
    Add-AgentIssue $issues "Info" "UI Flow" "Code/UI" "No UI folder found."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$interactiveClassTokens = @(
    "choice",
    "team-choice",
    "menu-button",
    "main-menu-button",
    "option-button",
    "action-button"
)

$passiveClassTokens = @(
    "passive",
    "info",
    "static",
    "readonly",
    "disabled"
)

function Test-HasClassToken {
    param(
        [string]$ClassText,
        [string[]]$Tokens
    )

    foreach ($token in $Tokens) {
        if ($ClassText -match "(^|[\s@-])$([regex]::Escape($token))($|[\s\(\)-])") {
            return $true
        }
    }

    return $false
}

function Get-ClassText {
    param([string]$TagText)

    $match = [regex]::Match($TagText, 'class\s*=\s*(?:"([^"]*)"|''([^'']*)'')', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return ""
    }

    if ($match.Groups[1].Success) {
        return $match.Groups[1].Value
    }

    return $match.Groups[2].Value
}

function Test-HasOnClick {
    param([string]$TagText)

    return $TagText -match '(?i)\bonclick\s*='
}

function Test-HasBuildHash {
    param([string]$Text)

    return $Text -match '(?m)\bprotected\s+override\s+int\s+BuildHash\s*\('
}

function Test-HasDynamicRazorOutput {
    param([string]$Text)

    $patterns = @(
        '>[ \t]*@(?:\(|[A-Za-z_])',
        '(?i)\b(?:class|style|id|value|title)\s*=\s*@',
        '(?i)\b[A-Za-z_][A-Za-z0-9_]*:bind\s*=\s*@',
        '(?s)<[A-Z][A-Za-z0-9_.]*[^>]*\s+(?!on)[A-Za-z_][A-Za-z0-9_]*(?::bind)?\s*=\s*@'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-CallsStateHasChangedFromTick {
    param([string]$Text)

    return $Text -match '(?s)\boverride\s+void\s+Tick\s*\(\s*\).*?\bStateHasChanged\s*\('
}

function Test-HasMenuClickSoundContract {
    param([string]$Text)

    return $Text -match 'const\s+string\s+MenuClickSoundPath\s*=\s*"sounds/ui_menu_click\.sound";' `
        -and $Text -match '(?s)\bvoid\s+ClickMenuOption\s*\(\s*Action\s+\w+\s*\).*?\bPlayMenuClickSound\s*\(\s*\).*?\w+\?\.\s*Invoke\s*\(\s*\)' `
        -and $Text -match '(?s)\bvoid\s+PlayMenuClickSound\s*\(\s*\).*?\bSound\.Play\s*\(\s*MenuClickSoundPath\s*\)'
}

function Test-HudRolePickerStagedTeamAndLoadouts {
    param(
        [string]$Text,
        [string]$Relative,
        [System.Collections.Generic.List[object]]$Issues
    )

    if ($Relative -ne "Code/UI/HudPanel.razor") {
        return
    }

    if ($Text -notmatch 'RolePickerTitle') {
        return
    }

    if ($Text -match 'class="team-option"' -or $Text -match 'class="choices nested"') {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Team picker loadout options are nested vertically under individual team cards." "Keep team choice and loadout choice as separate picker stages."
    }

    $titlePattern = '(?s)<div\s+class="title">@RolePickerTitle</div>.*?string\s+RolePickerTitle\s*=>\s*SelectedLoadoutTeam\s+switch.*?PlayerRole\.Pilot\s*=>\s*"Drone Pilot Loadout".*?PlayerRole\.Soldier\s*=>\s*"Hunters Loadout".*?_\s*=>\s*"Select team"'
    if ($Text -notmatch $titlePattern) {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Role picker title must match the active picker stage." "Render Select team for the team stage, Drone Pilot Loadout for the pilot loadout stage, and Hunters Loadout for the hunter loadout stage."
    }

    $teamPattern = '(?s)@if\s*\(\s*SelectedLoadoutTeam\s*==\s*PlayerRole\.Spectator\s*\).*?<div\s+class="team-choices">.*?(?:SelectLoadoutTeam\s*\(\s*PlayerRole\.Pilot\s*\)|ClickMenuOption\s*\(\s*SelectPilotTeam\s*\)).*?DRONE PILOTS.*?(?:SelectLoadoutTeam\s*\(\s*PlayerRole\.Soldier\s*\)|ClickMenuOption\s*\(\s*SelectSoldierTeam\s*\)).*?HUNTERS.*?ClickMenuOption\s*\(\s*BackToMainMenu\s*\).*?GO BACK'
    if ($Text -notmatch $teamPattern) {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Role picker must show a standalone team selection stage with its own Back button." "Render Drone Pilots/Hunters choices only while SelectedLoadoutTeam is Spectator, followed by a Back action to the main menu."
    }

    $pilotPattern = '(?s)@if\s*\(\s*SelectedLoadoutTeam\s*==\s*PlayerRole\.Pilot\s*\).*?<div\s+class="loadout-section">.*?<div\s+class="choices">.*?(GPS DRONE|DroneChoiceLabel\s*\(\s*DroneType\.Gps\s*\)).*?(FPV DRONE|DroneChoiceLabel\s*\(\s*DroneType\.Fpv\s*\)).*?(FIBER FPV|DroneChoiceLabel\s*\(\s*DroneType\.FiberOpticFpv\s*\)).*?ClickMenuOption\s*\(\s*ClearLoadoutTeam\s*\).*?GO BACK'
    if ($Text -notmatch $pilotPattern) {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Drone Pilot loadout options must render as the second-stage Pilot picker." "Render GPS, FPV, and Fiber FPV only after the Pilot team is selected, followed by a Back action to team selection."
    }

    $soldierPattern = '(?s)@if\s*\(\s*SelectedLoadoutTeam\s*==\s*PlayerRole\.Soldier\s*\).*?<div\s+class="loadout-section">.*?<div\s+class="choices">.*?(ASSAULT|SoldierChoiceLabel\s*\(\s*SoldierClass\.Assault\s*\)).*?(COUNTER-UAV|SoldierChoiceLabel\s*\(\s*SoldierClass\.CounterUav\s*\)).*?(HEAVY|SoldierChoiceLabel\s*\(\s*SoldierClass\.Heavy\s*\)).*?ClickMenuOption\s*\(\s*ClearLoadoutTeam\s*\).*?GO BACK'
    if ($Text -notmatch $soldierPattern) {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Soldier class options must render as the second-stage Soldier picker." "Render Assault, Counter-UAV, and Heavy only after the Soldier team is selected, followed by a Back action to team selection."
    }

    $backCount = [regex]::Matches($Text, 'GO BACK').Count
    if ($backCount -lt 3) {
        Add-AgentIssue $Issues "Error" "UI Flow" $Relative "Role picker needs Back buttons on team, pilot loadout, and soldier class stages." "Add one Back action to the main menu stage and one Back action for each selected-team loadout stage."
    }
}

function Test-HudMainMenuTransitionContract {
    param(
        [string]$Text,
        [string]$Relative,
        [System.Collections.Generic.List[object]]$Issues
    )

    if ($Relative -ne "Code/UI/HudPanel.razor") {
        return
    }

    $checks = @(
        @{
            Pattern = 'ShowMainMenuShell'
            Message = "Main menu should remain rendered while the Play transition exits."
            Recommendation = "Use a separate shell visibility property so the exit animation can finish before the role picker owns the screen."
        },
        @{
            Pattern = 'PlayTransitionActive'
            Message = "Main menu Play transition state is missing."
            Recommendation = "Track local transition state and include it in BuildHash() instead of forcing StateHasChanged() from Tick()."
        },
        @{
            Pattern = '(?:onclick=@StartMainMenuPlayTransition|ClickMenuOption\s*\(\s*StartMainMenuPlayTransition\s*\))'
            Message = "Play should start the animated main-menu transition."
            Recommendation = "Route the Play button through StartMainMenuPlayTransition instead of immediately hiding the main menu."
        },
        @{
            Pattern = 'main-menu-scanline'
            Message = "Play transition should render the upward drone scan overlay."
            Recommendation = "Render a scanline element only with the main menu Play transition shell."
        },
        @{
            Pattern = 'class="main-menu-title-text">ABOVE / BELOW</span>'
            Message = "Main menu title should be a centered child element."
            Recommendation = "Wrap the title text in a child span so the full-screen flex container can center it reliably in S&Box UI."
        },
        @{
            Pattern = 'MainMenuTransitionHashTick'
            Message = "BuildHash() should include a quantized main-menu transition tick."
            Recommendation = "Hash a short transition tick so Razor refreshes when the exit animation should be removed."
        },
        @{
            Pattern = 'bool\s+ShowRolePicker\s*=>\s*NeedsRoleChoice\s*&&\s*!MainMenuOpen\s*&&\s*!PlayTransitionActive;'
            Message = "Role picker should not render over the exiting main menu during the Play scan."
            Recommendation = "Keep the role picker unmounted until the Play transition completes so the old and new menu layouts cannot overlap or appear to shift."
        }
    )

    foreach ($check in $checks) {
        if ($Text -notmatch $check.Pattern) {
            Add-AgentIssue $Issues "Error" "UI Flow" $Relative $check.Message $check.Recommendation
        }
    }
}

function Test-HudMainMenuStylesheetContract {
    param(
        [string]$Root,
        [System.Collections.Generic.List[object]]$Issues
    )

    $relativePaths = @(
        "Code/UI/HudPanel.razor.scss",
        "Code/UI/HudPanel.cs.scss",
        "Assets/ui/hudpanel.cs.scss"
    )

    $texts = @{}
    foreach ($relative in $relativePaths) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path)) {
            Add-AgentIssue $Issues "Error" "UI Flow" $relative "HUD stylesheet alias is missing." "Keep the Razor stylesheet and S&Box alias stylesheets in sync."
            continue
        }

        $texts[$relative] = Get-Content -LiteralPath $path -Raw
    }

    if (-not $texts.ContainsKey("Code/UI/HudPanel.razor.scss")) {
        return
    }

    $canonical = $texts["Code/UI/HudPanel.razor.scss"]
    foreach ($relative in @("Code/UI/HudPanel.cs.scss", "Assets/ui/hudpanel.cs.scss")) {
        if ($texts.ContainsKey($relative) -and $texts[$relative] -ne $canonical) {
            Add-AgentIssue $Issues "Error" "UI Flow" $relative "HUD stylesheet alias is out of sync with HudPanel.razor.scss." "Copy the accepted HUD style changes to all S&Box stylesheet aliases."
        }
    }

    $styleChecks = @(
        @{
            Pattern = '(?s)\.team-choice\s*\{[^}]*flex:\s*1\s+1\s+0;[^}]*min-width:\s*0;'
            Message = "Team choice buttons must share equal width regardless of label length."
            Recommendation = "Use flex: 1 1 0 and min-width: 0 on .team-choice so Drone Pilots and Hunters cards divide the row evenly."
        },
        @{
            Pattern = '(?s)\.role-panel\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Role picker panel text must be centered."
            Recommendation = "Center text at the role-panel level so role picker headings and menu text align consistently."
        },
        @{
            Pattern = '(?s)\.team-choice\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Team choice button text must be centered."
            Recommendation = "Center the contents of each team-choice card so both team labels and descriptions align the same way."
        },
        @{
            Pattern = '(?s)\.section-title\s*\{[^}]*text-align:\s*center;'
            Message = "Menu section titles must be centered."
            Recommendation = "Center menu section-title text to match the rest of the picker."
        },
        @{
            Pattern = '(?s)\.options-panel\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Options menu panel text must be centered."
            Recommendation = "Center the options panel content and text instead of leaving settings copy left-aligned."
        },
        @{
            Pattern = '(?s)\.option-row\s*\{[^}]*flex-direction:\s*column;[^}]*align-items:\s*center;[^}]*justify-content:\s*center;[^}]*text-align:\s*center;'
            Message = "Options menu rows must center their text."
            Recommendation = "Stack each option row vertically and center its copy/control groups so all options menu text is centered."
        },
        @{
            Pattern = '(?s)\.option-copy\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Options menu copy must be centered."
            Recommendation = "Center option-copy text so option names and values align with the menu."
        },
        @{
            Pattern = '(?s)\.options-actions\s*\{[^}]*justify-content:\s*center;'
            Message = "Options menu action buttons must be centered."
            Recommendation = "Center the options action row so the bottom menu controls align with the rest of the panel."
        },
        @{
            Pattern = '\.main-menu-title\s*\{[^}]*top:\s*0;[^}]*right:\s*0;[^}]*bottom:\s*0;[^}]*left:\s*0;[^}]*justify-content:\s*center;[^}]*align-items:\s*center;'
            Message = "Main menu title must be flex-centered across the full viewport."
            Recommendation = "Use a full-screen absolute title overlay with centered flex alignment instead of percentage translate centering."
        },
        @{
            Pattern = '\.main-menu-panel\s*\{[^}]*position:\s*absolute;[^}]*top:\s*68%;'
            Message = "Main menu buttons must sit in the lower third."
            Recommendation = "Position the main menu panel absolutely near top: 68% with horizontal centering."
        },
        @{
            Pattern = '\.main-menu-scanline'
            Message = "Main menu upward scanline style is missing."
            Recommendation = "Style the Play-only scanline overlay in the main menu startup block."
        },
        @{
            Pattern = 'animation:\s*mainMenuScanUp\s+0\.5s\s+ease-in'
            Message = "Upward drone scan must last 0.5 seconds and accelerate."
            Recommendation = "Use a 0.5s accelerating timing curve for mainMenuScanUp."
        },
        @{
            Pattern = '(?s)@keyframes\s+mainMenuScanUp\s*\{\s*0%\s*\{\s*bottom:\s*0%;\s*opacity:\s*1;\s*\}\s*100%\s*\{\s*bottom:\s*104%;\s*opacity:\s*0;\s*\}\s*\}'
            Message = "Upward drone scan keyframes should be one smooth eased arc."
            Recommendation = "Use only start and end keyframes with ease-in timing; do not add intermediate scan positions that create stepped speed bands."
        },
        @{
            Pattern = '(?s)&\.play-transition-exit\s*\{.*?\.main-menu-title\s*\{[^}]*animation:\s*mainMenuTitleExit\s+0\.36s\s+ease-out\s+forwards;.*?\.main-menu-panel\s*\{[^}]*animation:\s*mainMenuPanelExit\s+0\.36s\s+ease-out\s+forwards;'
            Message = "Main menu exit transition should hold title and buttons hidden after the fade."
            Recommendation = "Use forwards fill-mode on the main-menu title and panel exit animations so the menu does not reappear during the scan."
        },
        @{
            Pattern = '(?s)@keyframes\s+mainMenuPanelExit\s*\{\s*0%\s*\{\s*opacity:\s*1;\s*\}\s*100%\s*\{\s*opacity:\s*0;\s*\}\s*\}'
            Message = "Main menu panel exit should not animate transform during the Play scan."
            Recommendation = "Fade the already-centered panel out without transform keyframes; S&Box can compose animated transforms with the centering transform and create a one-frame lateral jump."
        },
        @{
            Pattern = '\.main-menu-title-text\s*\{[^}]*font-size:\s*72px;[^}]*font-weight:\s*900;'
            Message = "Main menu title text style is missing."
            Recommendation = "Style the title text child directly so S&Box centers the child panel and applies the title typography to it."
        }
    )

    foreach ($check in $styleChecks) {
        if ($canonical -notmatch $check.Pattern) {
            Add-AgentIssue $Issues "Error" "UI Flow" "Code/UI/HudPanel.razor.scss" $check.Message $check.Recommendation
        }
    }
}

function Test-MainMenuPanelStylesheetContract {
    param(
        [string]$Root,
        [System.Collections.Generic.List[object]]$Issues
    )

    $razorPath = Join-Path $Root "Code/UI/MainMenuPanel.razor"
    $relativePaths = @(
        "Code/UI/MainMenuPanel.razor.scss",
        "Code/UI/MainMenuPanel.cs.scss",
        "Assets/ui/mainmenupanel.cs.scss"
    )

    if (-not (Test-Path -LiteralPath $razorPath) -and -not ($relativePaths | ForEach-Object { Test-Path -LiteralPath (Join-Path $Root $_) } | Where-Object { $_ })) {
        return
    }

    $texts = @{}
    foreach ($relative in $relativePaths) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path)) {
            Add-AgentIssue $Issues "Error" "UI Flow" $relative "Main menu stylesheet alias is missing." "Keep the Razor stylesheet and S&Box alias stylesheets in sync."
            continue
        }

        $texts[$relative] = Get-Content -LiteralPath $path -Raw
    }

    if (-not $texts.ContainsKey("Code/UI/MainMenuPanel.razor.scss")) {
        return
    }

    $canonical = $texts["Code/UI/MainMenuPanel.razor.scss"]
    foreach ($relative in @("Code/UI/MainMenuPanel.cs.scss", "Assets/ui/mainmenupanel.cs.scss")) {
        if ($texts.ContainsKey($relative) -and $texts[$relative] -ne $canonical) {
            Add-AgentIssue $Issues "Error" "UI Flow" $relative "Main menu stylesheet alias is out of sync with MainMenuPanel.razor.scss." "Copy accepted main-menu style changes to all S&Box stylesheet aliases."
        }
    }

    $styleChecks = @(
        @{
            Pattern = '(?s)\.copy-column\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Main menu copy column text must be centered."
            Recommendation = "Center the copy column so title, description, status, and action text align consistently."
        },
        @{
            Pattern = '(?s)\.brand,\s*\.description,\s*\.actions\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Main menu text groups must be centered."
            Recommendation = "Center brand, description, and action groups instead of leaving menu copy left-aligned."
        },
        @{
            Pattern = '(?s)\.feature\s*\{[^}]*align-items:\s*center;[^}]*text-align:\s*center;'
            Message = "Main menu feature card text must be centered."
            Recommendation = "Center feature card contents so team feature text matches the rest of the menu."
        },
        @{
            Pattern = '(?s)\.menu-button\s*\{[^}]*text-align:\s*center;'
            Message = "Main menu button text must be centered."
            Recommendation = "Set text-align: center on menu-button so all standalone menu actions align the same way."
        },
        @{
            Pattern = '(?s)\.status\s*\{[^}]*text-align:\s*center;'
            Message = "Main menu status text must be centered."
            Recommendation = "Center the status line to match the rest of the menu."
        },
        @{
            Pattern = '(?s)\.sky-label,\s*\.ground-label\s*\{[^}]*left:\s*0;[^}]*right:\s*0;[^}]*text-align:\s*center;'
            Message = "Main menu visual labels must be centered."
            Recommendation = "Center the sky and ground labels inside the visual panel so no menu text remains left-aligned."
        }
    )

    foreach ($check in $styleChecks) {
        if ($canonical -notmatch $check.Pattern) {
            Add-AgentIssue $Issues "Error" "UI Flow" "Code/UI/MainMenuPanel.razor.scss" $check.Message $check.Recommendation
        }
    }
}

$razorFiles = @(Get-ChildItem -LiteralPath $uiRoot -Recurse -File -Filter "*.razor" -ErrorAction SilentlyContinue)
foreach ($file in $razorFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $lines = @(Get-Content -LiteralPath $file.FullName)
    $text = Get-Content -LiteralPath $file.FullName -Raw

    Test-HudRolePickerStagedTeamAndLoadouts -Text $text -Relative $relative -Issues $issues
    Test-HudMainMenuTransitionContract -Text $text -Relative $relative -Issues $issues

    $requiresMenuClickSound = $relative -in @("Code/UI/HudPanel.razor", "Code/UI/MainMenuPanel.razor")
    if ($requiresMenuClickSound -and -not (Test-HasMenuClickSoundContract -Text $text)) {
        Add-AgentIssue $issues "Error" "UI Flow" $relative "Menu panel does not route clicks through the shared UI click sound wrapper." "Add MenuClickSoundPath, ClickMenuOption(Action), and PlayMenuClickSound() using sounds/ui_menu_click.sound."
    }

    if (($text -match '@inherits\s+PanelComponent') -and (Test-HasDynamicRazorOutput -Text $text) -and -not (Test-HasBuildHash -Text $text)) {
        Add-AgentIssue $issues "Warning" "UI Flow" $relative "Dynamic Razor output has no BuildHash override." "Override BuildHash() and include every value that can change rendered markup, especially [Sync] values shown in the HUD."
    }

    if (Test-CallsStateHasChangedFromTick -Text $text) {
        Add-AgentIssue $issues "Warning" "UI Flow" $relative "Razor Tick() calls StateHasChanged()." "Use BuildHash(), event-driven state changes, or a narrower invalidation path instead of rebuilding the panel every frame."
    }

    $capturing = $false
    $tagText = ""
    $startLine = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if (-not $capturing) {
            $divIndex = $line.IndexOf("<div", [System.StringComparison]::OrdinalIgnoreCase)
            if ($divIndex -lt 0) {
                continue
            }

            $capturing = $true
            $tagText = $line.Substring($divIndex)
            $startLine = $i + 1
        }
        else {
            $tagText += " " + $line.Trim()
        }

        $tagEnd = [regex]::Match($tagText, '(?<!=)>')
        if (-not $tagEnd.Success) {
            continue
        }

        $capturing = $false
        $openTag = $tagText.Substring(0, $tagEnd.Index + 1)
        $classText = Get-ClassText -TagText $openTag
        if ([string]::IsNullOrWhiteSpace($classText)) {
            $tagText = ""
            continue
        }

        $looksInteractive = Test-HasClassToken -ClassText $classText -Tokens $interactiveClassTokens
        $isExplicitlyPassive = Test-HasClassToken -ClassText $classText -Tokens $passiveClassTokens
        if ($looksInteractive -and -not $isExplicitlyPassive -and -not (Test-HasOnClick -TagText $openTag)) {
            Add-AgentIssue $issues "Warning" "UI Flow" "${relative}:$startLine" "Interactive-looking div has class '$classText' but no onclick handler." "Add onclick behavior, rename the class, or mark the element with a passive/info/static class."
        }
        elseif ($requiresMenuClickSound -and $looksInteractive -and -not $isExplicitlyPassive -and (Test-HasOnClick -TagText $openTag) -and $openTag -notmatch 'ClickMenuOption') {
            Add-AgentIssue $issues "Error" "UI Flow" "${relative}:$startLine" "Interactive menu div with class '$classText' does not play the shared click sound." "Wrap menu onclick handlers with ClickMenuOption(...) so every menu click triggers sounds/ui_menu_click.sound."
        }

        $tagText = ""
    }
}

Test-HudMainMenuStylesheetContract -Root $Root -Issues $issues
Test-MainMenuPanelStylesheetContract -Root $Root -Issues $issues

if ($razorFiles.Count -eq 0) {
    Add-AgentIssue $issues "Info" "UI Flow" "Code/UI" "No Razor files found."
}
else {
    Add-AgentIssue $issues "Info" "UI Flow" "Code/UI" "Scanned $($razorFiles.Count) Razor UI file(s) for dead-looking interactive elements and Razor refresh hazards."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
