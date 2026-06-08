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

Write-AgentSection "Animated Model Intake Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required animated model intake surface is missing." "Restore the file or update animated_model_intake_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required animated model marker '$pattern'." "Keep animated imports routed through editor-first proof, AnimGraph/sequence guidance, hooks, suites, and self-tests."
        }
    }
}

Test-FileHasPatterns ".agents/sbox/animated-model-intake-agent.md" @(
    "Purpose",
    "editor-first-workflow-agent\.md",
    "control_plane_status",
    "ModelDoc",
    "AnimGraph",
    "imported clips",
    "SkinnedModelRenderer\.Sequence",
    "AnimGraphDirectPlayback",
    "Parameters\.Set",
    "1D blendspace",
    "state machine",
    "bool triggers",
    "FirstPersonViewmodel",
    "sbox_api_lookup\.ps1",
    "animated_model_intake_audit\.ps1"
) "Animated Model Agent"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "Animated Model Intake",
    "animated-model-intake-agent\.md",
    "animated_model_intake_audit\.ps1",
    "run_agent_checks\.ps1 -Suite animated-model",
    "editor-first-workflow-agent\.md"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "Animated Model",
    "animated-model-intake-agent\.md",
    "animated_model_intake_audit\.ps1"
) "Agent Routing"

Test-FileHasPatterns "docs/known_sbox_patterns.md" @(
    "Animated Model Import",
    "AnimGraph",
    "ModelDoc",
    "editor-first-workflow-agent\.md",
    "SkinnedModelRenderer\.Sequence",
    "AnimGraphDirectPlayback",
    "Parameters\.Set",
    "animated_model_intake_audit\.ps1"
) "Known Patterns"

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "Animated model import reviewed on \d{4}-\d{2}-\d{2}",
    "SkinnedModelRenderer\.UseAnimGraph",
    "SkinnedModelRenderer\.AnimationGraph",
    "SkinnedModelRenderer\.Sequence",
    "SkinnedModelRenderer\.PlaybackRate",
    "SkinnedModelRenderer\.PlayAnimationsInEditorScene",
    "AnimationGraph\.Load",
    "AnimGraphDirectPlayback",
    "Parameters\.Set",
    "sbox_api_lookup\.ps1",
    "animated_model_intake_audit\.ps1"
) "Engine Reference"

Test-FileHasPatterns "docs/automation.md" @(
    "Animated model imports",
    "editor-first",
    "AnimGraph",
    "playback proof",
    "animated-model-intake-agent\.md",
    "run_agent_checks\.ps1 -Suite animated-model"
) "Automation Docs"

Test-FileHasPatterns "AGENTS.md" @(
    "S&Box Animated Model Intake Hook",
    "sbox-animated-model-check",
    "run_agent_checks\.ps1 -Suite animated-model",
    "animated-model-intake-agent\.md",
    "editor-first-workflow-agent\.md"
) "Project Instructions"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"animated-model"',
    "animated_model_intake_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    '"animated-model"',
    "Animated Model Intake Agent",
    "animated_model_intake_audit\.ps1"
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "AnimatedAssets",
    "animated_model_intake_audit\.ps1",
    "AnimGraph"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-animated-model-check"',
    "animated_model_intake_audit\.ps1",
    '"animated-model"'
) "Claude Hook"

Test-FileHasPatterns "Code/Player/FirstPersonViewmodel.cs" @(
    "UseAnimGraph",
    "Parameters\.Set",
    "SetIk"
) "First-Person Animation Owner"

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Animated Model Intake" "" "Animated model docs, agent, hook, suite, self-test, training, and first-person owner markers passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
