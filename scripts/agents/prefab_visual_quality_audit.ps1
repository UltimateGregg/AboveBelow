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
        Add-AgentIssue $issues "Error" $Area $Path "Required prefab visual-quality file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $Path "Missing required visual-quality marker '$pattern'." $Recommendation
        }
    }
}

Write-AgentSection "Prefab Visual Quality Audit"

Test-RequiredText -Path ".agents/sbox/prefab-visual-quality-agent.md" -Area "Prefab Visual Quality Agent" -Patterns @(
    'Prefab Visual Quality Agent',
    'control_plane_status',
    'editor_take_screenshot',
    'underbaked',
    'silhouette',
    'material/tint variation',
    'static non-trigger colliders',
    'visual-only'
) -Recommendation "Keep a reusable agent card for primitive prefab visual review and editor proof."

Test-RequiredText -Path "docs/agent_toolkit.md" -Area "Agent Toolkit" -Patterns @(
    'Prefab Visual Quality Agent',
    'prefab_visual_quality_audit\.ps1',
    'valid-but-underbaked'
) -Recommendation "Document the prefab visual-quality route in the main toolkit."

Test-RequiredText -Path ".agents/sbox/README.md" -Area "Agent Routing" -Patterns @(
    'prefab-visual-quality-agent\.md',
    'prefab_visual_quality_audit\.ps1'
) -Recommendation "Make the prefab visual-quality agent discoverable from S&Box routing docs."

Test-RequiredText -Path "scripts/agents/run_agent_checks.ps1" -Area "Suite Wiring" -Patterns @(
    'prefab_visual_quality_audit\.ps1',
    '"prefab"',
    '"train"'
) -Recommendation "Wire the prefab visual-quality audit into focused prefab and training suites."

Test-RequiredText -Path "scripts/agents/destroyed_pickup_prefab_audit.ps1" -Area "Destroyed Pickup Contract" -Patterns @(
    'primitive child pieces',
    'tint variation',
    'near-black',
    'Cab roof',
    'visual-quality contract'
) -Recommendation "Keep the destroyed pickup audit guarding objective symptoms of the old underbaked blockout."

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Prefab Visual Quality" ".agents/sbox/prefab-visual-quality-agent.md" "Checked primitive-prefab visual-quality routing, suite wiring, and destroyed-pickup objective quality guards."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
