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

function Test-RequiredText {
    param(
        [string]$Path,
        [string]$Area,
        [string[]]$Patterns,
        [string]$Recommendation
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $Path "Required editor-first workflow file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $Path "Missing required editor-first marker '$pattern'." $Recommendation
        }
    }
}

Write-AgentSection "Editor-First Workflow Audit"

Test-RequiredText -Path ".mcp.json" -Area "MCP Manifest" -Patterns @(
    '"sbox"',
    'http://localhost:29015/mcp'
) -Recommendation "Keep the native S&Box MCP endpoint advertised for clients that load project MCP manifests."

Test-RequiredText -Path ".agents/sbox/editor-first-workflow-agent.md" -Area "Editor-First Agent" -Patterns @(
    'Editor-First Workflow Agent',
    'control_plane_status',
    'tools/list',
    'control_plane_capabilities',
    'editor_scene_info',
    'component_list',
    'component_set',
    'scene_create_object',
    'editor_save_scene',
    'editor_take_screenshot',
    'editor_play',
    'editor_console_output',
    'CoworkBridge',
    'fallback'
) -Recommendation "Document the live-editor-first workflow, capability discovery, mutation tools, proof tools, and fallback boundary."

Test-RequiredText -Path "docs/editor_control_plane.md" -Area "Editor Control Plane Docs" -Patterns @(
    'Editor-First Command Workflow',
    'control_plane_status',
    'tools/list',
    'control_plane_capabilities',
    'editor_scene_info',
    'component_list',
    'component_get',
    'component_set',
    'editor_save_scene',
    'editor_take_screenshot',
    'editor_play',
    'editor_console_output',
    'CoworkBridge'
) -Recommendation "Keep the control-plane docs explicit enough that future agents start in the editor and know when fallback is honest."

Test-RequiredText -Path ".agents/sbox/README.md" -Area "Agent Routing" -Patterns @(
    'editor-first-workflow-agent\.md',
    'run_agent_checks\.ps1 -Suite editor-first',
    'Prefer the native S&Box MCP server'
) -Recommendation "Make the editor-first agent discoverable from the agent routing table and operating rules."

Test-RequiredText -Path "docs/agent_toolkit.md" -Area "Agent Toolkit" -Patterns @(
    'Editor-First Workflow Agent',
    'editor-first-workflow-agent\.md',
    'run_agent_checks\.ps1 -Suite editor-first',
    'Native S&Box editor control-plane'
) -Recommendation "Keep the toolkit routing future editor-capable tasks through the native MCP workflow."

Test-RequiredText -Path "AGENTS.md" -Area "Project Instructions" -Patterns @(
    'editor-first-workflow-agent\.md',
    'control_plane_status',
    'tools/list',
    'editor_save_scene'
) -Recommendation "Project-level instructions should tell future agents to begin editor-capable tasks in the live S&Box editor."

Test-RequiredText -Path "scripts/agents/run_agent_checks.ps1" -Area "Suite Wiring" -Patterns @(
    '"editor-first"',
    'editor_first_workflow_audit\.ps1',
    'cowork_bridge_autostart_audit\.ps1'
) -Recommendation "Expose a focused editor-first suite and wire the audit into recurring checks."

Test-RequiredText -Path "scripts/agents/post_task_training_agent.ps1" -Area "Training Wiring" -Patterns @(
    'EditorFirstWorkflow',
    'editor_first_workflow_audit\.ps1',
    'editor-first-workflow-agent\.md'
) -Recommendation "Training mode should recognize editor-first workflow changes and point future passes at the focused suite."

Test-RequiredText -Path "scripts/agents/test_full_automation_layer.ps1" -Area "Self-Test Wiring" -Patterns @(
    'editor_first_workflow_audit\.ps1',
    '"editor-first"',
    'Editor-First Workflow'
) -Recommendation "Protect the editor-first suite and audit with the automation self-test."

$settingsPath = Join-Path $Root ".claude/settings.json"
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $hook = @($settings.hooks | Where-Object { $_.id -eq "sbox-editor-first-workflow-check" })
        if ($hook.Count -eq 0) {
            Add-AgentIssue $issues "Error" "Claude Hook" ".claude/settings.json" "Missing sbox-editor-first-workflow-check hook." "Add a hook that runs the editor-first suite when editor workflow docs, agent routing, or audit wiring changes."
        }
        else {
            $hookText = $hook[0] | ConvertTo-Json -Depth 20
            foreach ($pattern in @('editor_first_workflow_audit\.ps1', 'editor-first', 'docs/editor_control_plane\.md', 'editor-first-workflow-agent\.md')) {
                if ($hookText -notmatch $pattern) {
                    Add-AgentIssue $issues "Error" "Claude Hook" ".claude/settings.json" "Editor-first hook is missing marker '$pattern'." "Keep the hook focused on editor-first workflow drift."
                }
            }
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Claude Hook" ".claude/settings.json" "Failed to parse Claude hook settings: $($_.Exception.Message)" "Fix the hook JSON before relying on automatic editor-first workflow checks."
    }
}
else {
    Add-AgentIssue $issues "Warning" "Claude Hook" ".claude/settings.json" "Claude hook settings are missing." "Add the editor-first hook if this workspace uses Claude Code hooks."
}

Add-AgentIssue $issues "Info" "Editor-First Workflow" "" "Checked editor-first agent routing, docs, suite wiring, training wiring, self-test coverage, MCP manifest, and Claude hook." ""

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
