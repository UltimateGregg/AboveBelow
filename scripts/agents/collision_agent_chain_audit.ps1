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

function Test-AgentChainDocument {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Root,
        [string]$Path,
        [string]$Title,
        [string[]]$RequiredHeadings = @(),
        [string[]]$RequiredPhrases = @()
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $Issues "Error" "Collision Agent Chain" $Path "$Title document is missing." "Create the persistent Codex agent prompt."
        return
    }

    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($heading in $RequiredHeadings) {
        $pattern = "(?m)^#{1,6}\s+" + [regex]::Escape($heading) + "\s*$"
        if ($text -notmatch $pattern) {
            Add-AgentIssue $Issues "Error" "Collision Agent Chain" $Path "$Title document is missing section heading '$heading'." "Keep role contracts structured, not keyword-only."
        }
    }

    foreach ($phrase in $RequiredPhrases) {
        if ($text -notmatch [regex]::Escape($phrase)) {
            Add-AgentIssue $Issues "Error" "Collision Agent Chain" $Path "$Title document is missing required contract phrase '$phrase'." "Keep the chain protocol explicit enough for future Codex agents to follow."
        }
    }
}

$documents = @(
    @{
        Path = ".agents/sbox/collision-chain-agent.md"
        Title = "Collision Chain Agent"
        Headings = @("Purpose", "Role Stack", "Coordinator", "Explorer", "Implementer", "Verifier", "Critic", "Handoff Protocol", "Rework Loop", "Collision Acceptance Rules", "Evidence Commands")
        Phrases = @('Coordinator -> Explorer -> Implementer -> Verifier -> Critic', '`Status`: `PASS`, `REWORK`, `BLOCKED`, or `OUT_OF_SCOPE`.', 'Do not run an endless loop.')
    },
    @{
        Path = ".agents/sbox/collision-explorer-agent.md"
        Title = "Collision Explorer Agent"
        Headings = @("Purpose", "Role", "Inputs", "Work", "Output Shape")
        Phrases = @('read-only Codex explorer', 'Collision Contract', 'Hotspots', 'Suggested Next Handoff', 'Do not edit files.')
    },
    @{
        Path = ".agents/sbox/collision-implementer-agent.md"
        Title = "Collision Implementer Agent"
        Headings = @("Purpose", "Role", "Inputs", "Work", "Output Shape")
        Phrases = @('owned file paths', 'Changed Files', 'Verification', 'Next Handoff', 'Do not revert edits made by others')
    },
    @{
        Path = ".agents/sbox/collision-verifier-agent.md"
        Title = "Collision Verifier Agent"
        Headings = @("Purpose", "Role", "Inputs", "Work", "Output Shape")
        Phrases = @('Evidence', 'Runtime Gaps', 'collision-chain', 'collision-critic-agent.md', 'Treat stale or unrelated logs as limits')
    },
    @{
        Path = ".agents/sbox/collision-critic-agent.md"
        Title = "Collision Critic Agent"
        Headings = @("Purpose", "Role", "Inputs", "Review Rules", "Output Shape")
        Phrases = @('defect-first', 'Findings', 'Evidence Gaps', 'Next Handoff', 'Distinguish confirmed defects from untested runtime gaps')
    },
    @{
        Path = ".agents/sbox/collision-authoring-agent.md"
        Title = "Collision Authoring Agent"
        Headings = @("Purpose", "Primary Areas", "Review Rules", "Evidence Command", "Runtime Proof", "Output Shape")
        Phrases = @('Collision_*', 'LadderVolume', 'water tower', 'building root', 'Static checks prove the authored collision exists')
    }
)

foreach ($document in $documents) {
    Test-AgentChainDocument -Issues $issues -Root $Root -Path $document.Path -Title $document.Title -RequiredHeadings $document.Headings -RequiredPhrases $document.Phrases
}

$runnerPath = "scripts/agents/run_agent_checks.ps1"
$runnerFullPath = Join-Path $Root $runnerPath
if (Test-Path -LiteralPath $runnerFullPath) {
    $runnerText = Get-Content -LiteralPath $runnerFullPath -Raw
    if ($runnerText -notmatch '"collision-chain"') {
        Add-AgentIssue $issues "Error" "Collision Agent Chain" $runnerPath "run_agent_checks.ps1 does not expose the collision-chain suite." "Add collision-chain to the ValidateSet and switch block."
    }
    $collisionChainCase = [regex]::Match($runnerText, '(?ms)^\s*"collision-chain"\s*\{(?<body>.*?)^\s*\}')
    if (-not $collisionChainCase.Success) {
        Add-AgentIssue $issues "Error" "Collision Agent Chain" $runnerPath "run_agent_checks.ps1 does not define a collision-chain switch case." "Wire the chain audit and report generator into the collision-chain suite."
    }
    else {
        $caseBody = $collisionChainCase.Groups["body"].Value
        if ($caseBody -notmatch "collision_agent_chain_audit\.ps1") {
            Add-AgentIssue $issues "Error" "Collision Agent Chain" $runnerPath "The collision-chain suite does not run collision_agent_chain_audit.ps1." "Run the structured role-doc audit inside the collision-chain suite."
        }
        if ($caseBody -notmatch "collision_chain_report\.ps1") {
            Add-AgentIssue $issues "Error" "Collision Agent Chain" $runnerPath "The collision-chain suite does not run collision_chain_report.ps1." "Run the report generator inside the collision-chain suite."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Collision Agent Chain" $runnerPath "run_agent_checks.ps1 is missing." "Restore the suite runner."
}

$readmePath = ".agents/sbox/README.md"
$readmeFullPath = Join-Path $Root $readmePath
if (Test-Path -LiteralPath $readmeFullPath) {
    $readmeText = Get-Content -LiteralPath $readmeFullPath -Raw
    foreach ($agentDoc in @("collision-chain-agent.md", "collision-explorer-agent.md", "collision-implementer-agent.md", "collision-verifier-agent.md", "collision-critic-agent.md")) {
        if ($readmeText -notmatch [regex]::Escape($agentDoc)) {
            Add-AgentIssue $issues "Error" "Collision Agent Chain" $readmePath "Agent README does not route $agentDoc." "Add a routing row for every collision chain role."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Collision Agent Chain" $readmePath "Agent README is missing." "Restore the agent routing doc."
}

$toolkitPath = "docs/agent_toolkit.md"
$toolkitFullPath = Join-Path $Root $toolkitPath
if (Test-Path -LiteralPath $toolkitFullPath) {
    $toolkitText = Get-Content -LiteralPath $toolkitFullPath -Raw
    foreach ($required in @("Collision Agent Chain", "Collision Explorer Agent", "Collision Implementer Agent", "Collision Verifier Agent", "Collision Critic Agent", "collision_chain_report.ps1")) {
        if ($toolkitText -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Collision Agent Chain" $toolkitPath "Agent toolkit docs do not mention '$required'." "Document the chain roles and evidence command."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Collision Agent Chain" $toolkitPath "Agent toolkit docs are missing." "Restore docs/agent_toolkit.md."
}

$patternsPath = "docs/known_sbox_patterns.md"
$patternsFullPath = Join-Path $Root $patternsPath
if (Test-Path -LiteralPath $patternsFullPath) {
    $patternsText = Get-Content -LiteralPath $patternsFullPath -Raw
    foreach ($required in @("Authored Prop Collision Alignment", "collision-chain-agent.md", "Codex explorer defines the collision contract")) {
        if ($patternsText -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Collision Agent Chain" $patternsPath "Known S&Box patterns do not preserve '$required'." "Keep the durable collision-chain lesson documented."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Collision Agent Chain" $patternsPath "Known S&Box patterns doc is missing." "Restore docs/known_sbox_patterns.md."
}

Add-AgentIssue $issues "Info" "Collision Agent Chain" "" "Validated $($documents.Count) structured collision chain document(s), suite wiring, and docs coverage."

Write-AgentSection "Collision Agent Chain Audit"
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
