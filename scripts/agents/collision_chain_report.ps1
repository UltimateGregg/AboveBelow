param(
    [string]$Root = "",
    [string]$Goal = "Collision workflow review",
    [string]$OutFile = ".tmpbuild/collision-chain-report.md",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]

function Invoke-CollisionChainStep {
    param(
        [string]$Role,
        [string]$Description,
        [string]$ScriptName,
        [string[]]$ExtraArgs = @(),
        [switch]$AllowFailure
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $args = @("-Root", $Root) + $ExtraArgs
    if ($ShowInfo -and $ScriptName -in @("collision_agent_chain_audit.ps1", "collision_authoring_agent.ps1", "scene_integrity_audit.ps1")) {
        $args += "-ShowInfo"
    }
    if ($FailOnWarning -and $ScriptName -in @("collision_agent_chain_audit.ps1", "collision_authoring_agent.ps1", "scene_integrity_audit.ps1")) {
        $args += "-FailOnWarning"
    }

    $command = "powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptName " + ($args -join " ")
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Add-AgentIssue $issues "Error" "Collision Chain Report" "scripts/agents/$ScriptName" "$Description script is missing." "Restore the script before relying on the collision chain."
        $results.Add([pscustomobject]@{
            Role = $Role
            Description = $Description
            Command = $command
            ExitCode = 1
            Output = "Missing script."
        })
        return
    }

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args 2>&1
    $exitCode = $LASTEXITCODE
    $results.Add([pscustomobject]@{
        Role = $Role
        Description = $Description
        Command = $command
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    })

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        Add-AgentIssue $issues "Error" "Collision Chain Report" "scripts/agents/$ScriptName" "$Description exited $exitCode." "Fix the failing evidence before handing collision work to the critic."
    }
}

Invoke-CollisionChainStep -Role "Coordinator" -Description "Validate persistent role prompts, handoff protocol, and docs wiring" -ScriptName "collision_agent_chain_audit.ps1"
Invoke-CollisionChainStep -Role "Verifier" -Description "Validate authored Collision_* helpers and ladder trigger rules" -ScriptName "collision_authoring_agent.ps1"
Invoke-CollisionChainStep -Role "Verifier" -Description "Validate scene-level collision and water-tower traversal rules" -ScriptName "scene_integrity_audit.ps1"
Invoke-CollisionChainStep -Role "Verifier" -Description "Generate manual prefab/collision playtest checklist" -ScriptName "playtest_checklist.ps1" -ExtraArgs @("-ChangeArea", "Prefab")

$target = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $Root $OutFile }
New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Collision Chain Report")
$lines.Add("")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Goal: $Goal")
$lines.Add("")
$lines.Add("## Role Flow")
$lines.Add("")
$lines.Add("1. Coordinator defines scope, dirty-worktree limits, and the next role.")
$lines.Add("2. Explorer maps visible geometry, Collision_* helpers, triggers, and hotspots without editing.")
$lines.Add("3. Implementer edits only owned files against the explorer collision contract.")
$lines.Add("4. Verifier runs static evidence, records runtime gaps, and asks for rework when evidence fails.")
$lines.Add("5. Critic reviews defects first and returns PASS, REWORK, BLOCKED, or OUT_OF_SCOPE.")
$lines.Add("")
$lines.Add("## Handoff Packet")
$lines.Add("")
$lines.Add("- Goal: $Goal")
$lines.Add("- Scope: authored scene and prefab collision, ladder triggers, and collision workflow checks.")
$lines.Add("- Do Not Touch: unrelated dirty gameplay, UI, sound, model, or editor-control-plane files.")
$lines.Add("- Current Evidence: see Evidence Results below.")
$lines.Add("- Known Risks: stale editor hierarchy, stale logs, broad invisible blockers, trigger-vs-solid mistakes, and untested runtime traversal.")
$lines.Add("- Expected Output: role status plus findings, changed files when applicable, evidence, runtime gaps, and next handoff.")
$lines.Add("")
$lines.Add("## Evidence Results")
$lines.Add("")
foreach ($result in $results) {
    $lines.Add("### $($result.Role): $($result.Description)")
    $lines.Add("")
    $lines.Add(('Command: `{0}`' -f $result.Command))
    $lines.Add(('Exit code: `{0}`' -f $result.ExitCode))
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        $lines.Add("")
        $lines.Add('```text')
        $lines.Add($result.Output)
        $lines.Add('```')
    }
    $lines.Add("")
}

$lines.Add("## Next Handoff")
$lines.Add("")
if (@($issues | Where-Object { $_.Severity -eq "Error" }).Count -gt 0) {
    $lines.Add("Status: REWORK")
    $lines.Add('Next: send the failing evidence to `collision-implementer-agent.md` or fix the workflow script/doc named by the error.')
}
else {
    $lines.Add("Status: PASS")
    $lines.Add('Next: send this report plus the current diff to `collision-critic-agent.md` for findings-first review before final handoff.')
}

($lines -join [Environment]::NewLine) | Set-Content -LiteralPath $target -Encoding UTF8

Add-AgentIssue $issues "Info" "Collision Chain Report" (ConvertTo-AgentRelativePath -Path $target -Root $Root) "Wrote collision chain report for Codex role handoff."

Write-AgentSection "Collision Chain Report"
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
Write-Host "Wrote collision chain report: $(ConvertTo-AgentRelativePath -Path $target -Root $Root)"
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
