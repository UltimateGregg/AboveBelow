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

$razorFiles = @(Get-ChildItem -LiteralPath $uiRoot -Recurse -File -Filter "*.razor" -ErrorAction SilentlyContinue)
foreach ($file in $razorFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $lines = @(Get-Content -LiteralPath $file.FullName)
    $text = Get-Content -LiteralPath $file.FullName -Raw

    if ((Test-HasDynamicRazorOutput -Text $text) -and -not (Test-HasBuildHash -Text $text)) {
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

        if ($tagText -notmatch ">") {
            continue
        }

        $capturing = $false
        $openTag = ($tagText -split ">", 2)[0] + ">"
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

        $tagText = ""
    }
}

if ($razorFiles.Count -eq 0) {
    Add-AgentIssue $issues "Info" "UI Flow" "Code/UI" "No Razor files found."
}
else {
    Add-AgentIssue $issues "Info" "UI Flow" "Code/UI" "Scanned $($razorFiles.Count) Razor UI file(s) for dead-looking interactive elements and Razor refresh hazards."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
