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

Write-AgentSection "S&Box Code Search Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required Code Search intake surface is missing." "Restore the file or update sbox_code_search_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required Code Search marker '$pattern'." "Keep S&Box Code Search routed through dated docs, agents, hooks, suites, and audits."
        }
    }
}

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "Official S&Box Code Search reviewed on \d{4}-\d{2}-\d{2}",
    "https://sbox\.game/codesearch",
    "Search the source of every published package",
    "package type",
    "code type",
    "year",
    "sbox-code-search-agent\.md",
    "sbox_code_search_audit\.ps1"
) "Code Search Reference"

Test-FileHasPatterns ".agents/sbox/sbox-code-search-agent.md" @(
    "Purpose",
    "https://sbox\.game/codesearch",
    "published packages",
    "package type",
    "code type",
    "year",
    "sbox_api_lookup\.ps1",
    "sbox_code_search_audit\.ps1",
    "Do not vendor package source"
) "Code Search Agent"

Test-FileHasPatterns ".agents/sbox/sbox-engine-reference-agent.md" @(
    "https://sbox\.game/codesearch",
    "sbox-code-search-agent\.md"
) "Engine Reference Agent"

Test-FileHasPatterns "docs/known_sbox_patterns.md" @(
    "S&Box Code Search Intake",
    "https://sbox\.game/codesearch",
    "sbox-code-search-agent\.md",
    "sbox_code_search_audit\.ps1"
) "Known Patterns"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "S&Box Code Search Agent",
    "sbox-code-search-agent\.md",
    "sbox_code_search_audit\.ps1",
    "run_agent_checks\.ps1 -Suite code-search"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "sbox-code-search-agent\.md",
    "sbox_code_search_audit\.ps1",
    "Code Search"
) "Agent Routing"

Test-FileHasPatterns "AGENTS.md" @(
    "S&Box Code Search",
    "sbox-code-search-agent\.md",
    "run_agent_checks\.ps1 -Suite code-search"
) "Project Instructions"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"code-search"',
    "sbox_code_search_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    '"code-search"',
    "sbox_code_search_audit\.ps1",
    "S&Box Code Search Agent"
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "CodeSearchResearch",
    "sbox_code_search_audit\.ps1",
    "https://sbox\.game/codesearch"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-code-search-check"',
    "sbox_code_search_audit\.ps1",
    '"code-search"'
) "Claude Hook"

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Code Search" "" "S&Box Code Search docs, agent, hook, suite, self-test, and audit wiring passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
