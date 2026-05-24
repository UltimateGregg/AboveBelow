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

Write-AgentSection "S&Box Engine Reference Audit"
Write-Host "Root: $Root"

function Add-LineIssue {
    param(
        [ValidateSet("Error", "Warning", "Info")]
        [string]$Severity,
        [string]$Area,
        [string]$Path,
        [int]$LineNumber,
        [string]$Message,
        [string]$Recommendation
    )

    $location = if ($LineNumber -gt 0) { "$Path`:$LineNumber" } else { $Path }
    Add-AgentIssue $issues $Severity $Area $location $Message $Recommendation
}

function Test-ExemptLine {
    param(
        [string]$Line,
        [string]$Pattern
    )

    return $Line -match $Pattern
}

$requiredFiles = @(
    "docs/sbox_engine_llm_reference.md",
    ".agents/sbox/sbox-engine-reference-agent.md"
)

foreach ($required in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $required))) {
        Add-AgentIssue $issues "Error" "Engine Reference" $required "Required S&Box engine reference surface is missing." "Create the file and keep it dated against official sources."
    }
}

$referencePath = Join-Path $Root "docs/sbox_engine_llm_reference.md"
if (Test-Path -LiteralPath $referencePath) {
    $referenceText = Get-Content -LiteralPath $referencePath -Raw
    foreach ($pattern in @(
        "Verified against official sources on \d{4}-\d{2}-\d{2}",
        "https://sbox.game/dev/doc",
        "https://github.com/Facepunch/sbox-public",
        "https://sbox.game/learn/facepunch/creating-an-entity-for-sandbox",
        "\.sent",
        "ClientEditable",
        "TimeSince",
        "\[Sync\]",
        "ModelDoc",
        "Avoid Source 1 Habits"
    )) {
        if ($referenceText -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Engine Reference" "docs/sbox_engine_llm_reference.md" "Reference doc is missing required marker '$pattern'." "Keep the reference short, sourced, dated, and project-specific."
        }
    }
}

$agentPath = Join-Path $Root ".agents/sbox/sbox-engine-reference-agent.md"
if (Test-Path -LiteralPath $agentPath) {
    $agentText = Get-Content -LiteralPath $agentPath -Raw
    foreach ($pattern in @(
        "Purpose",
        "https://sbox.game/dev/doc",
        "https://github.com/Facepunch/sbox-public",
        "sbox_engine_reference_audit\.ps1"
    )) {
        if ($agentText -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Engine Reference Agent" ".agents/sbox/sbox-engine-reference-agent.md" "Agent doc is missing required marker '$pattern'." "Keep research intake discoverable and evidence-backed."
        }
    }
}

$integrationChecks = @(
    [pscustomobject]@{ Path = "docs/agent_toolkit.md"; Patterns = @("S&Box Engine Reference Agent", "sbox_engine_reference_audit\.ps1") },
    [pscustomobject]@{ Path = ".agents/sbox/README.md"; Patterns = @("sbox-engine-reference-agent\.md", "sbox_engine_reference_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/run_agent_checks.ps1"; Patterns = @("sbox_engine_reference_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/test_full_automation_layer.ps1"; Patterns = @("sbox_engine_reference_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/post_task_training_agent.ps1"; Patterns = @("sbox_engine_reference_audit\.ps1") }
)

foreach ($check in $integrationChecks) {
    $full = Join-Path $Root $check.Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" "Engine Reference Integration" $check.Path "Integration file is missing." "Restore the file or update this audit intentionally."
        continue
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $check.Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Engine Reference Integration" $check.Path "Missing required integration marker '$pattern'." "Wire engine-reference intake through docs, routing, training, and self-test."
        }
    }
}

$scanFiles = @(Get-AgentFiles -Root $Root -Include @("*.md") | Where-Object {
    $relative = ConvertTo-AgentRelativePath -Path $_.FullName -Root $Root
    if ($relative -like "docs/superpowers/*" -or $relative -like "docs/marketing/*") {
        return $false
    }

    return $relative -like "docs/*" -or
        $relative -like ".agents/sbox/*" -or
        $relative -eq "AGENTS.md" -or
        $relative -eq "README.md" -or
        $relative -eq "TESTING_GUIDE.md" -or
        $relative -eq "WIRING.md" -or
        $relative -eq "ROADMAP.md"
})

$netExempt = "(?i)obsolete|legacy|stale|avoid|do not|don't|deprecated|instead|rather than|old|replaced|translate"
$qcExempt = "(?i)Source 1|legacy|avoid|do not|don't|obsolete|equivalent|migration|not use|not implementation"
$vmdlExempt = "(?i)avoid|do not|don't|not|instead|blind|manual VMDL edits|manual \.vmdl|not hand"
$volatileClaim = "(?i)\b(latest|current)\b.*\b(S&Box engine|S&Box API|sbox engine|sbox API|Source 2|\.NET|SDK|ModelDoc|RPC|Sync|Blender Source Tools|Blender exporter)\b|\b(S&Box engine|S&Box API|sbox engine|sbox API|Source 2|\.NET|SDK|ModelDoc|RPC|Sync|Blender Source Tools|Blender exporter)\b.*\b(latest|current)\b"
$volatileExempt = "(?i)as of \d{4}-\d{2}-\d{2}|verified against|source:|https?://|current_log|current runtime|current editor|current project|this repo|this checkout|current file|current map|current scene|current target|currently keep|current open|current change|current authoring|current local"

foreach ($file in $scanFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $hasFileSourceMarker = $text -match "Verified against official sources on \d{4}-\d{2}-\d{2}" -or
        ($text -match "https://sbox.game" -and $text -match "https://github.com/Facepunch/sbox-public")
    $lines = $text -split "\r?\n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNumber = $i + 1

        if ($line -match "\[Net\]" -and -not (Test-ExemptLine -Line $line -Pattern $netExempt)) {
            Add-LineIssue "Error" "Stale Networking Guidance" $relative $lineNumber "Line appears to recommend stale '[Net]' networking guidance." "Use current S&Box '[Sync]' guidance or mark the reference as obsolete migration context."
        }

        if ($line -match "(?i)\.qc\b" -and -not (Test-ExemptLine -Line $line -Pattern $qcExempt)) {
            Add-LineIssue "Error" "Source 1 Model Guidance" $relative $lineNumber "Line appears to recommend Source 1 '.qc' model workflow for S&Box." "Use ModelDoc / Model Editor and the project asset-pipeline audits instead."
        }

        if ($line -match "(?i)vmdl" -and $line -match "(?i)hand[- ]?(write|edit|author)|text[- ]?edit|edit .*text" -and -not (Test-ExemptLine -Line $line -Pattern $vmdlExempt)) {
            Add-LineIssue "Error" "Manual VMDL Guidance" $relative $lineNumber "Line appears to recommend hand-editing VMDL text as active guidance." "Use ModelDoc, asset-pipeline generation, or source-controlled VMDL audits as the durable path."
        }

        if (-not $hasFileSourceMarker -and $line -match $volatileClaim -and -not (Test-ExemptLine -Line $line -Pattern $volatileExempt)) {
            Add-LineIssue "Warning" "Unverified Volatile Claim" $relative $lineNumber "Line contains a latest/current S&Box or tooling claim without an obvious source/date marker." "Add an 'as of YYYY-MM-DD' marker, a source link, or rewrite the claim as project-local guidance."
        }
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Engine Reference" "" "S&Box engine reference docs, routing, and stale-guidance checks passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
