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

Write-AgentSection "Docs and Roadmap Audit"
Write-Host "Root: $Root"

$requiredDocs = @(
    "README.md",
    "ROADMAP.md",
    "TESTING_GUIDE.md",
    "WIRING.md",
    "docs/architecture.md",
    "docs/automation.md",
    "docs/balance_rps.md",
    "docs/gameplay_loop.md",
    "docs/known_sbox_patterns.md"
)

foreach ($path in $requiredDocs) {
    $full = Join-Path $Root $path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" "Docs" $path "Required project documentation is missing." "Restore the doc or update the project documentation index intentionally."
    }
    elseif ((Get-Item -LiteralPath $full).Length -eq 0) {
        Add-AgentIssue $issues "Warning" "Docs" $path "Documentation file is empty." "Fill in the expected guidance or remove it from the required list."
    }
}

Push-Location $Root
try {
    $status = @(git status --short 2>$null)
}
finally {
    Pop-Location
}

if ($LASTEXITCODE -eq 0 -and $status.Count -gt 0) {
    $codeChanges = @($status | Where-Object { $_ -match "^\s*(M|A|\?\?)\s+Code/" })
    $prefabChanges = @($status | Where-Object { $_ -match "^\s*(M|A|\?\?)\s+Assets/(prefabs|scenes)/" })
    $scriptChanges = @($status | Where-Object { $_ -match "^\s*(M|A|\?\?)\s+scripts/" })
    $docChanges = @($status | Where-Object { $_ -match "^\s*(M|A|\?\?)\s+(docs/|README\.md|ROADMAP\.md|TESTING_GUIDE\.md|WIRING\.md)" })

    if (($codeChanges.Count -gt 0 -or $prefabChanges.Count -gt 0) -and $docChanges.Count -eq 0) {
        Add-AgentIssue $issues "Warning" "Docs Drift" "" "Code or prefab files changed but no docs changed." "If the behavior, public setup, or known S&Box pattern changed, update docs before handoff."
    }

    if ($scriptChanges.Count -gt 0 -and $docChanges.Count -eq 0) {
        Add-AgentIssue $issues "Warning" "Docs Drift" "" "Tooling scripts changed but no docs changed." "Document new commands in docs/automation.md or docs/agent_toolkit.md."
    }
}

$roadmap = Join-Path $Root "ROADMAP.md"
if (Test-Path -LiteralPath $roadmap) {
    $roadmapText = Get-Content -LiteralPath $roadmap -Raw
    if ($roadmapText -notmatch "Phase 0\.5" -or $roadmapText -notmatch "Phase 6") {
        Add-AgentIssue $issues "Warning" "Roadmap" "ROADMAP.md" "Roadmap does not include the expected phase markers." "Keep roadmap structure stable or update this audit."
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Docs" "" "Documentation presence and drift checks passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
