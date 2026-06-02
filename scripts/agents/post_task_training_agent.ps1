param(
    [string]$Root = "",
    [switch]$ShowFiles,
    [switch]$ShowInfo,
    [switch]$FailOnWarning,
    [switch]$WriteReport,
    [string]$RecentGoal = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]
$reportLines = New-Object System.Collections.Generic.List[string]

function Add-TrainingLine {
    param([string]$Line = "")

    Write-Host $Line
    $script:reportLines.Add($Line)
}

function Add-TrainingSection {
    param([string]$Title)

    Add-TrainingLine ""
    Add-TrainingLine "== $Title =="
}

function Test-TrainingPathMatch {
    param(
        [string]$Path,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-TrainingRecentGoal {
    param(
        [string]$Root,
        [string]$RecentGoal,
        [object[]]$ChangedFiles = @()
    )

    if (-not [string]::IsNullOrWhiteSpace($RecentGoal)) {
        return $RecentGoal
    }

    $candidateDirs = @(
        "docs/superpowers/plans",
        "docs/superpowers/specs",
        "docs/assets/briefs",
        "docs/marketing"
    )

    $changedGoalFiles = @($ChangedFiles | Where-Object {
        $path = $_.Path
        foreach ($dir in $candidateDirs) {
            if ($path -like "$dir/*") {
                return $true
            }
        }
        return $false
    })

    if ($changedGoalFiles.Count -gt 0) {
        return "Changed plan/spec/brief: $($changedGoalFiles[0].Path)"
    }

    $candidates = @()
    foreach ($dir in $candidateDirs) {
        $full = Join-Path $Root $dir
        if (Test-Path -LiteralPath $full) {
            $candidates += Get-ChildItem -LiteralPath $full -File -ErrorAction SilentlyContinue
        }
    }

    $latest = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($latest.Count -eq 0) {
        return "No recent plan/spec/brief file found."
    }

    return "No changed goal artifact found; latest plan/spec/brief: $(ConvertTo-AgentRelativePath -Path $latest[0].FullName -Root $Root)"
}

$changed = @(Get-AgentChangedFiles -Root $Root)
$recentGoalText = Get-TrainingRecentGoal -Root $Root -RecentGoal $RecentGoal -ChangedFiles $changed

$areaRules = @(
    [pscustomobject]@{
        Name = "Gameplay"
        Patterns = @("Code/Game/*", "Code/Player/*", "Code/Drone/*", "Code/Equipment/*")
        Checks = @(
            "scripts/agents/build_log_sentinel.ps1",
            "scripts/agents/gameplay_regression_guard.ps1",
            "scripts/agents/networking_review_audit.ps1"
        )
        Training = "If the task exposed a missed gameplay regression, add a focused guard under scripts/agents and wire it into run_agent_checks.ps1 plus test_full_automation_layer.ps1."
    },
    [pscustomobject]@{
        Name = "UI"
        Patterns = @("Code/UI/*", "Assets/ui/*")
        Checks = @(
            "scripts/agents/ui_flow_audit.ps1",
            "scripts/agents/playtest_checklist.ps1 -ChangeArea UI"
        )
        Training = "If a UI issue escaped static checks, add a concrete Razor or playtest checklist rule rather than relying on generic build success."
    },
    [pscustomobject]@{
        Name = "PrefabScene"
        Patterns = @("Assets/prefabs/*", "Assets/scenes/*")
        Checks = @(
            "scripts/agents/prefab_wiring_audit.ps1",
            "scripts/agents/prefab_graph_audit.ps1",
            "scripts/agents/scene_integrity_audit.ps1",
            "scripts/agents/collision_authoring_agent.ps1"
        )
        Training = "If scene or prefab authoring failed, capture the pattern in known_sbox_patterns.md and add a static fixture to the relevant audit."
    },
    [pscustomobject]@{
        Name = "Assets"
        Patterns = @("*.blend", "*.blend.blend", "*_model.blend/*", "Assets/models/*", "Assets/materials/*", "scripts/*_asset_pipeline.json", "scripts/asset_pipeline.*", "scripts/smart_asset_export.ps1")
        Checks = @(
            "scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo",
            "scripts/agents/asset_pipeline_audit.ps1",
            "scripts/agents/modeldoc_audit.ps1 -ShowInfo",
            "scripts/agents/fbx_material_slot_audit.ps1 -ShowInfo"
        )
        Training = "If an asset roundtrip or quality target failed, make the brief, reference requirements, config, ModelDoc, material-slot, and visual-review path reproducible before accepting the asset."
    },
    [pscustomobject]@{
        Name = "Tooling"
        Patterns = @(".agents/*", ".codex/*", ".claude/*", "scripts/agents/*", "docs/agent_toolkit.md", "AGENTS.md")
        Checks = @(
            "scripts/agents/test_full_automation_layer.ps1",
            "scripts/agents/run_agent_checks.ps1 -Suite train"
        )
        Training = "Tooling improvements should land in the runnable suite, the automation self-test, and the human-facing agent docs together."
    },
    [pscustomobject]@{
        Name = "Docs"
        Patterns = @("docs/*", "README.md", "TESTING_GUIDE.md", "ROADMAP.md")
        Checks = @(
            "scripts/agents/docs_roadmap_audit.ps1",
            "scripts/agents/sbox_engine_reference_audit.ps1 -ShowInfo",
            "scripts/agents/sbox_api_reference_audit.ps1 -ShowInfo",
            "scripts/agents/post_task_training_agent.ps1 -ShowFiles"
        )
        Training = "Docs should capture reusable workflow lessons, not just narrate the specific task."
    },
    [pscustomobject]@{
        Name = "EngineResearch"
        Patterns = @("docs/sbox_engine_llm_reference.md", ".agents/sbox/sbox-engine-reference-agent.md", ".agents/sbox/sbox-docs-source-agent.md", ".agents/sbox/sbox-release-notes-agent.md", "scripts/agents/sbox_docs_source_audit.ps1", "scripts/agents/sbox_engine_reference_audit.ps1", "scripts/agents/sbox_release_notes_audit.ps1", "scripts/agents/sbox_api_lookup.ps1", "scripts/agents/sbox_api_reference_audit.ps1", "API.json", "api.json")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite sbox-docs -ShowInfo",
            "scripts/agents/sbox_engine_reference_audit.ps1 -ShowInfo",
            "scripts/agents/run_agent_checks.ps1 -Suite docs"
        )
        Training = "External S&Box or Source 2 research should be verified against official docs/public source and local API.json when exact symbols matter, captured in the engine reference, routed through the reference agent, and protected by stale-guidance/API audits."
    },
    [pscustomobject]@{
        Name = "SboxDocsSource"
        Patterns = @(".agents/sbox/sbox-docs-source-agent.md", "scripts/agents/sbox_docs_source_audit.ps1", "docs/sbox_engine_llm_reference.md")
        Checks = @(
            "scripts/agents/sbox_docs_source_audit.ps1 -Refresh -ShowInfo",
            "scripts/agents/run_agent_checks.ps1 -Suite sbox-docs -ShowInfo"
        )
        Training = "Facepunch/sbox-docs training should refresh the official markdown source into .tmpbuild, record the reviewed commit/date, inspect toc.yml plus markdown locally, and promote only reusable lessons into docs, agents, hooks, or audits."
    },
    [pscustomobject]@{
        Name = "ReleaseNotesResearch"
        Patterns = @("docs/sbox_engine_llm_reference.md", ".agents/sbox/sbox-release-notes-agent.md", "scripts/agents/sbox_release_notes_audit.ps1", ".claude/settings.json")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite release-notes -ShowInfo",
            "scripts/agents/sbox_api_lookup.ps1 -Root . -Query SyncAttribute -Limit 5"
        )
        Training = "Official S&Box release-note training should start at https://sbox.game/release-notes and https://sbox.game/api/changes, record source/review dates, verify exact symbols through local API.json, and promote only reusable workflow lessons into docs, agents, hooks, or audits."
    },
    [pscustomobject]@{
        Name = "CodeSearchResearch"
        Patterns = @("docs/sbox_engine_llm_reference.md", ".agents/sbox/sbox-code-search-agent.md", "scripts/agents/sbox_code_search_audit.ps1", ".claude/settings.json")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite code-search -ShowInfo",
            "scripts/agents/sbox_api_lookup.ps1 -Root . -Query Component -Limit 5"
        )
        Training = "S&Box Code Search training should start at https://sbox.game/codesearch, use public package source for pattern discovery only, compare multiple recent examples, verify exact symbols through local API.json, and promote reusable lessons into docs, agents, hooks, or audits."
    },
    [pscustomobject]@{
        Name = "LearnResearch"
        Patterns = @("docs/sbox_engine_llm_reference.md", ".agents/sbox/sbox-learn-intake-agent.md", ".agents/sbox/ui-razor-reactivity-agent.md", ".agents/sbox/ui-flow-agent.md", ".agents/sbox/editor-node-tool-agent.md", "scripts/agents/sbox_learn_intake_audit.ps1", "scripts/agents/ui_flow_audit.ps1", "scripts/agents/editor_node_tool_audit.ps1")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite learn -ShowInfo",
            "scripts/agents/ui_flow_audit.ps1 -FailOnWarning -ShowInfo"
        )
        Training = "S&Box Learn tutorial lessons should become focused agents, subagents, docs, hooks, and audit fixtures before they become standing guidance."
    },
    [pscustomobject]@{
        Name = "EditorNodeTools"
        Patterns = @("Editor/*", "Libraries/*/Editor/*", ".agents/sbox/editor-node-tool-agent.md", "scripts/agents/editor_node_tool_audit.ps1")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite editor-node-tool -ShowInfo",
            "scripts/agents/sbox_engine_reference_audit.ps1 -ShowInfo"
        )
        Training = "Custom Node Editor tools should stay editor-only, use verified editor API shapes, clear tutorial placeholders, and keep manual editor-open verification in the handoff."
    },
    [pscustomobject]@{
        Name = "EditorFirstWorkflow"
        Patterns = @(".mcp.json", ".claude/*", ".agents/sbox/editor-first-workflow-agent.md", "docs/editor_control_plane.md", "docs/agent_toolkit.md", "AGENTS.md", "scripts/agents/editor_first_workflow_audit.ps1", "scripts/agents/run_agent_checks.ps1", "scripts/agents/test_full_automation_layer.ps1")
        Checks = @(
            "scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo",
            "scripts/agents/test_full_automation_layer.ps1"
        )
        Training = "When a task can be done through the S&Box editor, start with live MCP status/capability checks, mutate through native editor tools where available, and report static fallbacks as environment limits."
    }
)

$areaCounts = @{}
foreach ($rule in $areaRules) {
    $areaCounts[$rule.Name] = 0
}

foreach ($file in $changed) {
    foreach ($rule in $areaRules) {
        if (Test-TrainingPathMatch -Path $file.Path -Patterns $rule.Patterns) {
            $areaCounts[$rule.Name] = $areaCounts[$rule.Name] + 1
        }
    }
}

Add-TrainingLine "# Post-Task Training Agent"
Add-TrainingLine ""
Add-TrainingLine "Root: $Root"
Add-TrainingLine "Recent goal source: $recentGoalText"
Add-TrainingLine "Changed paths: $($changed.Count)"

if ($ShowFiles -and $changed.Count -gt 0) {
    Add-TrainingSection "Changed Files"
    foreach ($file in $changed) {
        Add-TrainingLine "- $($file.Status) $($file.Path)"
    }
}

Add-TrainingSection "Training Focus"
if ($changed.Count -eq 0) {
    Add-AgentIssue $issues "Info" "Post-Task Training" "" "No changed files were detected, so the training pass has no task evidence to inspect." "Run this after a completed task or pass -RecentGoal with a concise goal summary."
}
else {
    foreach ($rule in $areaRules) {
        $count = $areaCounts[$rule.Name]
        if ($count -le 0) {
            continue
        }

        Add-TrainingLine "- $($rule.Name): $count changed path(s)"
        foreach ($check in $rule.Checks) {
            Add-TrainingLine "  check: powershell -ExecutionPolicy Bypass -File $check"
        }
        Add-TrainingLine "  training: $($rule.Training)"
    }
}

$runnerPath = Join-Path $Root "scripts/agents/run_agent_checks.ps1"
$selfTestPath = Join-Path $Root "scripts/agents/test_full_automation_layer.ps1"
$toolkitPath = Join-Path $Root "docs/agent_toolkit.md"
$agentReadmePath = Join-Path $Root ".agents/sbox/README.md"
$agentsPath = Join-Path $Root "AGENTS.md"

$runnerText = if (Test-Path -LiteralPath $runnerPath) { Get-Content -LiteralPath $runnerPath -Raw } else { "" }
$selfTestText = if (Test-Path -LiteralPath $selfTestPath) { Get-Content -LiteralPath $selfTestPath -Raw } else { "" }
$toolkitText = if (Test-Path -LiteralPath $toolkitPath) { Get-Content -LiteralPath $toolkitPath -Raw } else { "" }
$agentReadmeText = if (Test-Path -LiteralPath $agentReadmePath) { Get-Content -LiteralPath $agentReadmePath -Raw } else { "" }
$agentsText = if (Test-Path -LiteralPath $agentsPath) { Get-Content -LiteralPath $agentsPath -Raw } else { "" }

if ($runnerText -notmatch 'post_task_training_agent\.ps1') {
    Add-AgentIssue $issues "Error" "Post-Task Training" "scripts/agents/run_agent_checks.ps1" "The runner does not invoke post_task_training_agent.ps1." "Add a train suite that runs the post-task training agent."
}

if ($runnerText -notmatch '"train"') {
    Add-AgentIssue $issues "Error" "Post-Task Training" "scripts/agents/run_agent_checks.ps1" "The runner does not expose a train suite." "Add train to the Suite ValidateSet and switch block."
}

if ($selfTestText -notmatch 'post_task_training_agent\.ps1' -or $selfTestText -notmatch '"train"') {
    Add-AgentIssue $issues "Error" "Post-Task Training" "scripts/agents/test_full_automation_layer.ps1" "The automation self-test does not protect the training agent and suite." "Keep training automation in the full-layer self-test."
}

if ($toolkitText -notmatch 'Post-Task Training Agent') {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "docs/agent_toolkit.md" "Agent toolkit docs do not mention the Post-Task Training Agent." "Document the train suite and expected use after task handoff."
}

if ($agentReadmeText -notmatch 'post-task-training-agent\.md') {
    Add-AgentIssue $issues "Warning" "Post-Task Training" ".agents/sbox/README.md" "Agent routing docs do not mention post-task-training-agent.md." "Add a routing row for post-task training."
}

if ($agentsText -notmatch 'just the word "train"' -or $agentsText -notmatch 'run_agent_checks\.ps1 -Suite train') {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "AGENTS.md" "Project instructions do not clearly define the train trigger and train suite." "Document that a bare train request should run the post-task training workflow."
}

$engineReferencePath = Join-Path $Root "docs/sbox_engine_llm_reference.md"
$engineAgentPath = Join-Path $Root ".agents/sbox/sbox-engine-reference-agent.md"
$engineAuditPath = Join-Path $Root "scripts/agents/sbox_engine_reference_audit.ps1"
$docsSourceAgentPath = Join-Path $Root ".agents/sbox/sbox-docs-source-agent.md"
$docsSourceAuditPath = Join-Path $Root "scripts/agents/sbox_docs_source_audit.ps1"
$apiLookupPath = Join-Path $Root "scripts/agents/sbox_api_lookup.ps1"
$apiAuditPath = Join-Path $Root "scripts/agents/sbox_api_reference_audit.ps1"

if (-not (Test-Path -LiteralPath $engineReferencePath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "docs/sbox_engine_llm_reference.md" "Engine research reference doc is missing." "Capture verified S&Box/Source 2 research in a dated project reference instead of leaving it only in chat history."
}

if (-not (Test-Path -LiteralPath $engineAgentPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" ".agents/sbox/sbox-engine-reference-agent.md" "Engine research routing agent is missing." "Add an agent card that explains how to verify and route external engine research."
}

if (-not (Test-Path -LiteralPath $engineAuditPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine research audit script is missing." "Add a stale-guidance guard for [Net], .qc, manual VMDL advice, and unsourced volatile engine claims."
}

if (-not (Test-Path -LiteralPath $docsSourceAgentPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" ".agents/sbox/sbox-docs-source-agent.md" "Official docs source routing agent is missing." "Add an agent card for Facepunch/sbox-docs clone, inventory, and commit/date review workflow."
}

if (-not (Test-Path -LiteralPath $docsSourceAuditPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "scripts/agents/sbox_docs_source_audit.ps1" "Official docs source audit script is missing." "Add a refreshable audit for Facepunch/sbox-docs routing, suite, hook, and snapshot checks."
}

if (-not (Test-Path -LiteralPath $apiLookupPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "scripts/agents/sbox_api_lookup.ps1" "S&Box API lookup helper is missing." "Add a local API.json query helper so future agents can verify exact symbols before editing C#."
}

if (-not (Test-Path -LiteralPath $apiAuditPath)) {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "scripts/agents/sbox_api_reference_audit.ps1" "S&Box API reference audit is missing." "Protect local API lookup docs, hook, and suite wiring with an audit."
}

if ($toolkitText -notmatch 'S&Box Engine Reference Agent' -or $toolkitText -notmatch 'S&Box Docs Source Agent' -or $toolkitText -notmatch 'sbox_docs_source_audit\.ps1' -or $toolkitText -notmatch 'sbox_engine_reference_audit\.ps1' -or $toolkitText -notmatch 'sbox_api_lookup\.ps1') {
    Add-AgentIssue $issues "Warning" "Post-Task Training" "docs/agent_toolkit.md" "Agent toolkit docs do not route external S&Box engine research." "Document the engine reference agent and its evidence command."
}

if ($agentReadmeText -notmatch 'sbox-engine-reference-agent\.md' -or $agentReadmeText -notmatch 'sbox-docs-source-agent\.md' -or $agentReadmeText -notmatch 'sbox_docs_source_audit\.ps1' -or $agentReadmeText -notmatch 'sbox_engine_reference_audit\.ps1' -or $agentReadmeText -notmatch 'sbox_api_lookup\.ps1') {
    Add-AgentIssue $issues "Warning" "Post-Task Training" ".agents/sbox/README.md" "Agent routing docs do not mention the S&Box engine reference agent." "Add a routing row for verified engine/API research intake."
}

$newAgentScripts = @($changed | Where-Object { $_.Status -eq "??" -and $_.Path -like "scripts/agents/*.ps1" })
foreach ($script in $newAgentScripts) {
    $leaf = Split-Path $script.Path -Leaf
    $isOneShotMigrationHelper = $leaf -like "migrate_*"
    if (-not $isOneShotMigrationHelper -and $runnerText -notmatch [regex]::Escape($leaf)) {
        Add-AgentIssue $issues "Warning" "Post-Task Training" $script.Path "New agent script is not referenced by run_agent_checks.ps1." "Wire recurring checks into a named suite."
    }

    if ($selfTestText -notmatch [regex]::Escape($leaf)) {
        $recommendation = if ($isOneShotMigrationHelper) {
            "Protect one-shot migration helpers in the full-layer self-test, but do not run mutating helpers from recurring suites."
        }
        else {
            "Add a required-script entry or a focused red/green fixture."
        }
        Add-AgentIssue $issues "Warning" "Post-Task Training" $script.Path "New agent script is not protected by test_full_automation_layer.ps1." $recommendation
    }
}

$newAgentDocs = @($changed | Where-Object { $_.Status -eq "??" -and $_.Path -like ".agents/sbox/*.md" -and $_.Path -notlike "*/README.md" })
foreach ($doc in $newAgentDocs) {
    $leaf = Split-Path $doc.Path -Leaf
    if ($agentReadmeText -notmatch [regex]::Escape($leaf)) {
        Add-AgentIssue $issues "Warning" "Post-Task Training" $doc.Path "New agent doc is not discoverable from .agents/sbox/README.md." "Add a routing row that names when to use the agent."
    }
}

Add-TrainingSection "Findings"
$visibleIssues = @($issues | Where-Object { $ShowInfo -or $_.Severity -ne "Info" })
if ($visibleIssues.Count -eq 0) {
    Add-TrainingLine "No blocking issues found."
}
else {
    foreach ($issue in $visibleIssues) {
        $location = if ([string]::IsNullOrWhiteSpace($issue.Path)) { "" } else { " [$($issue.Path)]" }
        Add-TrainingLine "[$($issue.Severity)] $($issue.Area)$location - $($issue.Message)"
        if (-not [string]::IsNullOrWhiteSpace($issue.Recommendation)) {
            Add-TrainingLine "  Recommendation: $($issue.Recommendation)"
        }
    }
}

if ($WriteReport) {
    $reportDir = Join-Path $Root ".tmpbuild"
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    }

    $reportPath = Join-Path $reportDir "post-task-training-report.md"
    $reportLines | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host ""
    Write-Host "Training report written: $reportPath"
}

exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
