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

Write-AgentSection "S&Box Learn Intake Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required Learn intake surface is missing." "Restore the file or update sbox_learn_intake_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required Learn intake marker '$pattern'." "Keep S&Box Learn lessons routed through docs, agents, hooks, and audits."
        }
    }
}

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "https://sbox\.game/learn",
    "https://sbox\.game/learn/tesa/ui-buildhash",
    "https://sbox\.game/learn/gibbard/networked-variable-ui",
    "https://sbox\.game/dev/doc/editor/",
    "Editor Tooling And Inspector Workflows",
    "UndoScope",
    "EditorEvent",
    "AssetPreview",
    "TextureGenerator",
    "BuildHash\(\)",
    "StateHasChanged\(\)"
) "Learn Reference"

Test-FileHasPatterns ".agents/sbox/sbox-learn-intake-agent.md" @(
    "Purpose",
    "https://sbox\.game/learn",
    "https://sbox\.game/dev/doc/editor/",
    "official editor-doc",
    "S&Box Learn",
    "sbox_learn_intake_audit\.ps1",
    "ui-razor-reactivity-agent\.md"
) "Learn Intake Agent"

Test-FileHasPatterns ".agents/sbox/ui-razor-reactivity-agent.md" @(
    "Purpose",
    "BuildHash\(\)",
    "StateHasChanged\(\)",
    "ui_flow_audit\.ps1",
    "\[Sync\]"
) "Razor Reactivity Subagent"

Test-FileHasPatterns ".agents/sbox/editor-node-tool-agent.md" @(
    "Purpose",
    "GraphView",
    "IPlug",
    "editor_node_tool_audit\.ps1",
    "https://sbox\.game/learn/aqua/node-editor-01"
) "Editor Node Tool Subagent"

Test-FileHasPatterns ".agents/sbox/ui-flow-agent.md" @(
    "BuildHash\(\)",
    "StateHasChanged\(\)"
) "UI Flow Agent"

Test-FileHasPatterns "scripts/agents/ui_flow_audit.ps1" @(
    "Test-InheritsRazorPanel",
    "Test-HasDynamicRazorOutput",
    "Test-HasBuildHash",
    "Test-CallsStateHasChangedFromTick",
    "Dynamic Razor output has no BuildHash",
    "Razor Tick\(\) calls StateHasChanged\(\)"
) "UI Audit"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "S&Box Learn Intake Agent",
    "UI Razor Reactivity Agent",
    "Editor Node Tool Agent",
    "sbox_learn_intake_audit\.ps1",
    "ui-razor-reactivity-agent\.md",
    "editor-node-tool-agent\.md"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "sbox-learn-intake-agent\.md",
    "ui-razor-reactivity-agent\.md",
    "editor-node-tool-agent\.md",
    "sbox_learn_intake_audit\.ps1"
) "Agent Routing"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"learn"',
    "sbox_learn_intake_audit\.ps1",
    "editor_node_tool_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    "sbox_learn_intake_audit\.ps1",
    "S&Box Learn Intake Agent",
    "https://sbox\.game/dev/doc/editor/",
    "UI Razor Reactivity Agent",
    "editor_node_tool_audit\.ps1"
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "LearnResearch",
    "sbox_learn_intake_audit\.ps1",
    "EditorNodeTools"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-learn-intake-check"',
    "sbox_learn_intake_audit\.ps1",
    '"-Suite"',
    '"learn"'
) "Claude Hook"

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Learn Intake" "" "S&Box Learn intake agents, subagent, hook, suite, and audit wiring passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
