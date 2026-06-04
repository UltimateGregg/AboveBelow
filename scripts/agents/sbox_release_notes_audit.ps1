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

Write-AgentSection "S&Box Release Notes Intake Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required release-notes intake surface is missing." "Restore the file or update sbox_release_notes_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required release-notes marker '$pattern'." "Keep official patch-note lessons routed through dated docs, agents, hooks, suites, and audits."
        }
    }
}

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "Official S&Box release notes reviewed on \d{4}-\d{2}-\d{2}",
    "https://sbox\.game/release-notes",
    "https://sbox\.game/news/update-26-06-03",
    "https://sbox\.game/api/changes",
    "26\.06\.03",
    "Mesh\.AddMorph",
    "Mesh\.AddSubMesh",
    "MorphDelta",
    "CreateModelFromMeshDialog",
    "ResourceWriter\.AddExternalReference",
    "Connection\.Name",
    "Connection\.DisplayName",
    "physical sound simulation",
    "UI mixer",
    "clamp\(\)",
    ":has\(\)",
    "VMDL writer now also saves the PHYS block",
    "HasTag\(\)",
    "IChatEvent",
    "IPanelDraw",
    "Voice Mixer",
    "TerrainStorage\.SetResolution\(\)",
    "Scene\.Trace\.Cone",
    "Rigidbody\.SleepThreshold"
) "Release Notes Reference"

Test-FileHasPatterns ".agents/sbox/sbox-release-notes-agent.md" @(
    "Purpose",
    "https://sbox\.game/release-notes",
    "https://sbox\.game/api/changes",
    "sbox_api_lookup\.ps1",
    "local dump does not expose",
    "sbox_release_notes_audit\.ps1",
    "sbox-learn-intake-agent\.md",
    "sbox-engine-reference-agent\.md"
) "Release Notes Agent"

Test-FileHasPatterns ".agents/sbox/sbox-engine-reference-agent.md" @(
    "https://sbox\.game/release-notes",
    "https://sbox\.game/api/changes",
    "sbox-release-notes-agent\.md"
) "Engine Reference Agent"

Test-FileHasPatterns "docs/known_sbox_patterns.md" @(
    "Official S&Box Release Notes Intake",
    "sbox-release-notes-agent\.md",
    "sbox_release_notes_audit\.ps1"
) "Known Patterns"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "S&Box Release Notes Intake Agent",
    "sbox_release_notes_audit\.ps1",
    "Suite release-notes"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "sbox-release-notes-agent\.md",
    "sbox_release_notes_audit\.ps1"
) "Agent Routing"

Test-FileHasPatterns "AGENTS.md" @(
    "S&Box release notes",
    "sbox-release-notes-agent\.md",
    "run_agent_checks\.ps1 -Suite release-notes"
) "Project Instructions"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"release-notes"',
    "sbox_release_notes_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    "sbox_release_notes_audit\.ps1",
    "S&Box Release Notes Intake Agent",
    "https://sbox\.game/release-notes",
    '"release-notes"'
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "ReleaseNotesResearch",
    "sbox_release_notes_audit\.ps1",
    "https://sbox\.game/release-notes"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-release-notes-check"',
    "sbox_release_notes_audit\.ps1",
    '"-Suite"',
    '"release-notes"'
) "Claude Hook"

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Release Notes" "" "S&Box release-notes intake docs, agent, hook, suite, and audit wiring passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
