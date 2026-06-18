param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning,
    [switch]$RequireLocalCheckout,
    [switch]$RequireLatest
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "S&Box Public Source Audit"
Write-Host "Root: $Root"

function Test-FileHasPatterns {
    param(
        [string]$RelativePath,
        [string[]]$Patterns,
        [string]$Area
    )

    $full = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required S&Box public-source workflow surface is missing." "Restore the file or update sbox_public_source_audit.ps1 intentionally."
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $RelativePath "Missing required public-source marker '$pattern'." "Keep Facepunch/sbox-public intake routed through agents, docs, suite wiring, hooks, and MCP proof."
        }
    }
}

function Invoke-GitCapture {
    param([string[]]$GitArgs)

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & git @GitArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Text = (($output | Select-Object -First 1) -join "").Trim()
        Details = (($output | Out-String).Trim())
    }
}

Test-FileHasPatterns "docs/sbox_engine_llm_reference.md" @(
    "Official S&Box public source reviewed on \d{4}-\d{2}-\d{2}",
    "https://github\.com/Facepunch/sbox-public",
    "tools/sbox-public",
    "sbox_public_source_audit\.ps1",
    "MCP",
    "Bootstrap\.bat"
) "Public Source Reference"

Test-FileHasPatterns ".agents/sbox/sbox-public-source-agent.md" @(
    "Purpose",
    "https://github\.com/Facepunch/sbox-public",
    "tools/sbox-public",
    "Bootstrap\.bat",
    "sbox_public_source_audit\.ps1",
    "control_plane_status",
    "Libraries/jtc\.mcp-server/Editor/mcp-server\.editor\.csproj"
) "Public Source Agent"

Test-FileHasPatterns ".agents/sbox/sbox-engine-reference-agent.md" @(
    "Facepunch/sbox-public"
) "Engine Reference Agent"

Test-FileHasPatterns "docs/known_sbox_patterns.md" @(
    "Official S&Box Public Source Intake",
    "sbox-public-source-agent\.md",
    "sbox_public_source_audit\.ps1"
) "Known Patterns"

Test-FileHasPatterns "docs/agent_toolkit.md" @(
    "S&Box Public Source Agent",
    "sbox-public-source-agent\.md",
    "sbox_public_source_audit\.ps1",
    "run_agent_checks\.ps1 -Suite sbox-public"
) "Agent Toolkit"

Test-FileHasPatterns ".agents/sbox/README.md" @(
    "sbox-public-source-agent\.md",
    "sbox_public_source_audit\.ps1",
    "Facepunch/sbox-public"
) "Agent Routing"

Test-FileHasPatterns "AGENTS.md" @(
    "Facepunch/sbox-public",
    "sbox-public-source-agent\.md",
    "run_agent_checks\.ps1 -Suite sbox-public"
) "Project Instructions"

Test-FileHasPatterns "scripts/agents/run_agent_checks.ps1" @(
    '"sbox-public"',
    "sbox_public_source_audit\.ps1"
) "Suite Wiring"

Test-FileHasPatterns "scripts/agents/test_full_automation_layer.ps1" @(
    '"sbox-public"',
    "sbox_public_source_audit\.ps1",
    "S&Box Public Source Agent"
) "Self Test"

Test-FileHasPatterns "scripts/agents/post_task_training_agent.ps1" @(
    "SboxPublicSource",
    "sbox_public_source_audit\.ps1",
    "Facepunch/sbox-public"
) "Training Agent"

Test-FileHasPatterns ".claude/settings.json" @(
    '"id"\s*:\s*"sbox-public-source-check"',
    "sbox_public_source_audit\.ps1",
    '"sbox-public"'
) "Claude Hook"

$cloneDir = Join-Path $Root "tools\sbox-public"
$checkoutSeverity = if ($RequireLocalCheckout -or $RequireLatest) { "Error" } else { "Info" }
if (-not (Test-Path -LiteralPath (Join-Path $cloneDir ".git"))) {
    Add-AgentIssue $issues $checkoutSeverity "S&Box Public Source" "tools/sbox-public" "The project-local Facepunch/sbox-public checkout is missing." "Clone https://github.com/Facepunch/sbox-public.git to tools/sbox-public, then run Bootstrap.bat there."
}
else {
    $remote = Invoke-GitCapture -GitArgs @("-C", $cloneDir, "remote", "get-url", "origin")
    if ($remote.ExitCode -ne 0 -or $remote.Text -notmatch "github\.com[:/]Facepunch/sbox-public(\.git)?$") {
        Add-AgentIssue $issues "Error" "S&Box Public Source" "tools/sbox-public" "The public-source checkout origin is not Facepunch/sbox-public." "Keep tools/sbox-public pointed at https://github.com/Facepunch/sbox-public.git."
    }

    $branch = Invoke-GitCapture -GitArgs @("-C", $cloneDir, "branch", "--show-current")
    if ($branch.ExitCode -ne 0 -or $branch.Text -ne "master") {
        Add-AgentIssue $issues "Warning" "S&Box Public Source" "tools/sbox-public" "The public-source checkout is not on master." "Use master for latest Facepunch/sbox-public intake unless a task explicitly pins another ref."
    }

    $head = Invoke-GitCapture -GitArgs @("-C", $cloneDir, "rev-parse", "HEAD")
    if ($head.ExitCode -eq 0) {
        Add-AgentIssue $issues "Info" "S&Box Public Source" "tools/sbox-public" "Local public-source checkout is at $($head.Text)." "Compare with upstream using -RequireLatest when freshness matters."
    }
    else {
        Add-AgentIssue $issues "Error" "S&Box Public Source" "tools/sbox-public" "Could not read the local public-source commit." $head.Details
    }

    if ($RequireLatest) {
        $upstream = Invoke-GitCapture -GitArgs @("ls-remote", "https://github.com/Facepunch/sbox-public.git", "refs/heads/master")
        if ($upstream.ExitCode -ne 0) {
            Add-AgentIssue $issues "Error" "S&Box Public Source" "https://github.com/Facepunch/sbox-public" "Could not query upstream master." $upstream.Details
        }
        else {
            $upstreamSha = (($upstream.Text -split "\s+")[0]).Trim()
            if ($head.ExitCode -eq 0 -and $head.Text -ne $upstreamSha) {
                Add-AgentIssue $issues "Error" "S&Box Public Source" "tools/sbox-public" "Local checkout is not at the latest upstream master commit." "Update tools/sbox-public to $upstreamSha and rerun Bootstrap.bat before using it as latest public-source context."
            }
            else {
                Add-AgentIssue $issues "Info" "S&Box Public Source" "tools/sbox-public" "Local checkout matches upstream master $upstreamSha." ""
            }
        }
    }

    foreach ($requiredPath in @(
        "Bootstrap.bat",
        "game/sbox-dev.exe",
        "game/bin/managed/Sandbox.Engine.dll",
        "game/bin/managed/Sandbox.Tools.dll",
        "engine/Tools/SboxBuild/SboxBuild.csproj"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $cloneDir $requiredPath))) {
            Add-AgentIssue $issues $checkoutSeverity "S&Box Public Source" "tools/sbox-public/$requiredPath" "Required public-source/bootstrap artifact is missing." "Run cmd /c Bootstrap.bat inside tools/sbox-public and recheck."
        }
    }
}

$mcpManifest = Join-Path $Root ".mcp.json"
if (Test-Path -LiteralPath $mcpManifest) {
    try {
        $manifest = Get-Content -LiteralPath $mcpManifest -Raw | ConvertFrom-Json
        if (-not $manifest.mcpServers.sbox -or $manifest.mcpServers.sbox.url -ne "http://localhost:29015/mcp") {
            Add-AgentIssue $issues "Error" "MCP Manifest" ".mcp.json" "The native S&Box MCP endpoint is missing or changed." "Keep the editor MCP server advertised at http://localhost:29015/mcp."
        }
        if (-not $manifest.mcpServers.blender -or $manifest.mcpServers.blender.url -ne "http://localhost:9876") {
            Add-AgentIssue $issues "Warning" "MCP Manifest" ".mcp.json" "The Blender MCP endpoint is missing or changed." "Keep Blender MCP routing unless the bridge is intentionally replaced."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "MCP Manifest" ".mcp.json" "Failed to parse MCP manifest: $($_.Exception.Message)" "Fix .mcp.json before relying on MCP clients."
    }
}
else {
    Add-AgentIssue $issues "Error" "MCP Manifest" ".mcp.json" "The MCP manifest is missing." "Restore .mcp.json with sbox, blender, and blender_stdio servers."
}

foreach ($mcpPath in @(
    "mcp/dist/blender.js",
    "Libraries/jtc.mcp-server/Editor/mcp-server.editor.csproj",
    "tools/dashboard/mcp_proxy.py"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $mcpPath))) {
        Add-AgentIssue $issues "Error" "MCP Wiring" $mcpPath "Required MCP wiring file is missing." "Restore the MCP server/proxy file before claiming MCPs are functional."
    }
}

$mcpProject = Join-Path $Root "Libraries\jtc.mcp-server\Editor\mcp-server.editor.csproj"
if (Test-Path -LiteralPath $mcpProject) {
    $mcpProjectText = Get-Content -LiteralPath $mcpProject -Raw
    if ($mcpProjectText -match "\.\./\.\./\.\./\.\./sbox-public") {
        Add-AgentIssue $issues "Info" "MCP Build Source" "Libraries/jtc.mcp-server/Editor/mcp-server.editor.csproj" "The MCP editor project still compiles against the sibling sbox-public checkout, not tools/sbox-public." "Do not reroute to tools/sbox-public unless its public distribution has compatible project references or the csproj is intentionally changed to DLL references and rebuilt."
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "S&Box Public Source" "" "Public source checkout, bootstrap artifacts, MCP manifest, routing docs, suite, self-test, and hook wiring passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
