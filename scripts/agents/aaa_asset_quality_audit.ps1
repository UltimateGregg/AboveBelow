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
        [string]$Text,
        [string[]]$Needles,
        [string]$Area,
        [string]$Recommendation
    )

    foreach ($needle in $Needles) {
        if ($Text -notmatch [regex]::Escape($needle)) {
            Add-AgentIssue $issues "Error" $Area $Path "Missing required routing text '$needle'." $Recommendation
        }
    }
}

Write-AgentSection "AAA Asset Quality Audit"
Write-Host "Root: $Root"

$profilePath = Join-Path $Root "scripts\asset_quality_profiles.json"
if (-not (Test-Path -LiteralPath $profilePath)) {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/asset_quality_profiles.json" "Asset quality profiles file is missing." "Restore category profiles before creating new production asset briefs."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $profiles = Read-AgentJson -Path $profilePath
}
catch {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/asset_quality_profiles.json" $_.Exception.Message "Fix invalid JSON."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$requiredCategories = @("weapon", "drone", "character", "environment")
$requiredProfileLists = @(
    "required_material_roles",
    "optional_texture_maps",
    "required_name_hints",
    "reference_requirements",
    "quality_targets",
    "visual_review_checks",
    "acceptance_checks"
)

foreach ($category in $requiredCategories) {
    if (-not ($profiles.PSObject.Properties.Name -contains $category)) {
        Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/asset_quality_profiles.json" "Missing '$category' quality profile." "Keep all supported asset categories available to new_asset_brief.ps1."
        continue
    }

    $profile = $profiles.$category
    foreach ($field in $requiredProfileLists) {
        if (-not ($profile.PSObject.Properties.Name -contains $field)) {
            Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/asset_quality_profiles.json" "Profile '$category' is missing '$field'." "Add concrete reference, quality, visual-review, and acceptance guidance for this category."
            continue
        }

        $values = @($profile.$field | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($values.Count -eq 0) {
            Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/asset_quality_profiles.json" "Profile '$category' has no entries for '$field'." "Keep each profile useful enough to generate a production-ready asset brief."
        }
    }
}

$briefScriptPath = Join-Path $Root "scripts\agents\new_asset_brief.ps1"
if (-not (Test-Path -LiteralPath $briefScriptPath)) {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/agents/new_asset_brief.ps1" "Asset brief generator is missing." "Restore the brief generator so new high-polish assets start from an explicit quality target."
}
else {
    $briefScriptText = Get-Content -LiteralPath $briefScriptPath -Raw
    Test-RequiredText "scripts/agents/new_asset_brief.ps1" $briefScriptText @(
        "Reference Requirements",
        "Production Quality Targets",
        "Visual Review Plan",
        "reference_requirements",
        "quality_targets",
        "visual_review_checks"
    ) "AAA Asset Quality" "Keep generated briefs tied to reference, art-quality, and visual-review expectations."
}

$agentDocPath = Join-Path $Root ".agents\sbox\aaa-asset-quality-agent.md"
if (-not (Test-Path -LiteralPath $agentDocPath)) {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" ".agents/sbox/aaa-asset-quality-agent.md" "AAA asset quality routing agent is missing." "Add the routing card so Codex can coordinate brief, Blender, material, visual, and import proof."
}
else {
    $agentDocText = Get-Content -LiteralPath $agentDocPath -Raw
    Test-RequiredText ".agents/sbox/aaa-asset-quality-agent.md" $agentDocText @(
        "blender-quality-agent.md",
        "material-texture-agent.md",
        "visual-review-agent.md",
        "asset-pipeline-agent.md",
        "modeldoc-agent.md",
        "aaa_asset_quality_audit.ps1"
    ) "AAA Asset Quality" "Keep the quality agent connected to the specialist checks that prove Blender-to-S&Box readiness."
}

$toolkitPath = Join-Path $Root "docs\agent_toolkit.md"
if (Test-Path -LiteralPath $toolkitPath) {
    $toolkitText = Get-Content -LiteralPath $toolkitPath -Raw
    Test-RequiredText "docs/agent_toolkit.md" $toolkitText @(
        "AAA Asset Quality Agent",
        "aaa_asset_quality_audit.ps1",
        "Production Quality Targets"
    ) "AAA Asset Quality" "Document the quality gate in the human-facing toolkit."
}
else {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "docs/agent_toolkit.md" "Agent toolkit docs are missing." "Restore the docs that explain asset-production routing."
}

$readmePath = Join-Path $Root ".agents\sbox\README.md"
if (Test-Path -LiteralPath $readmePath) {
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    Test-RequiredText ".agents/sbox/README.md" $readmeText @(
        "aaa-asset-quality-agent.md",
        "aaa_asset_quality_audit.ps1"
    ) "AAA Asset Quality" "Expose the quality agent in the S&Box agent routing table."
}
else {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" ".agents/sbox/README.md" "Agent routing README is missing." "Restore the agent routing table."
}

$runnerPath = Join-Path $Root "scripts\agents\run_agent_checks.ps1"
if (Test-Path -LiteralPath $runnerPath) {
    $runnerText = Get-Content -LiteralPath $runnerPath -Raw
    Test-RequiredText "scripts/agents/run_agent_checks.ps1" $runnerText @(
        "aaa_asset_quality_audit.ps1",
        "asset-production"
    ) "AAA Asset Quality" "Wire the quality gate into the asset-production suite."
}
else {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/agents/run_agent_checks.ps1" "Agent runner is missing." "Restore suite routing."
}

$selfTestPath = Join-Path $Root "scripts\agents\test_full_automation_layer.ps1"
if (Test-Path -LiteralPath $selfTestPath) {
    $selfTestText = Get-Content -LiteralPath $selfTestPath -Raw
    Test-RequiredText "scripts/agents/test_full_automation_layer.ps1" $selfTestText @(
        "aaa_asset_quality_audit.ps1",
        "reference_requirements",
        "Production Quality Targets"
    ) "AAA Asset Quality" "Protect this workflow with a self-test fixture so the gate cannot quietly disappear."
}
else {
    Add-AgentIssue $issues "Error" "AAA Asset Quality" "scripts/agents/test_full_automation_layer.ps1" "Automation self-test is missing." "Restore self-test coverage for agent wiring."
}

Add-AgentIssue $issues "Info" "AAA Asset Quality" "" "Checked $($requiredCategories.Count) profile(s), brief generation, agent routing, suite wiring, and self-test coverage."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
