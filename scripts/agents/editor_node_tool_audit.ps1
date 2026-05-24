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

Write-AgentSection "Editor Node Tool Audit"
Write-Host "Root: $Root"

$requiredMarkers = @(
    [pscustomobject]@{ Path = ".agents/sbox/editor-node-tool-agent.md"; Patterns = @("Node Editor", "GraphView", "editor_node_tool_audit\.ps1") },
    [pscustomobject]@{ Path = "docs/sbox_engine_llm_reference.md"; Patterns = @("Editor Node Tools", "https://sbox.game/learn/aqua/node-editor-01") },
    [pscustomobject]@{ Path = "docs/agent_toolkit.md"; Patterns = @("Editor Node Tool Agent", "editor_node_tool_audit\.ps1") },
    [pscustomobject]@{ Path = ".agents/sbox/README.md"; Patterns = @("editor-node-tool-agent\.md", "editor_node_tool_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/run_agent_checks.ps1"; Patterns = @("editor-node-tool", "editor_node_tool_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/post_task_training_agent.ps1"; Patterns = @("EditorNodeTools", "editor_node_tool_audit\.ps1") },
    [pscustomobject]@{ Path = "scripts/agents/test_full_automation_layer.ps1"; Patterns = @("editor_node_tool_audit\.ps1") }
)

foreach ($check in $requiredMarkers) {
    $full = Join-Path $Root $check.Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" "Editor Node Tool Integration" $check.Path "Required node-tool workflow file is missing." "Restore the file or update editor_node_tool_audit.ps1 intentionally."
        continue
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $check.Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Editor Node Tool Integration" $check.Path "Missing required integration marker '$pattern'." "Keep node-editor research wired through docs, routing, training, and self-test."
        }
    }
}

$nodeToolPattern = "\b(GraphView|NodeUI|IPlug(In|Out)?|INodeType)\b|Editor\.NodeEditor"
$nodeToolFiles = @(Get-AgentFiles -Root $Root -Include @("*.cs") | Where-Object {
    $relative = ConvertTo-AgentRelativePath -Path $_.FullName -Root $Root
    if ($relative -like "obj/*" -or $relative -like "bin/*") {
        return $false
    }

    $text = Get-Content -LiteralPath $_.FullName -Raw
    return $text -match $nodeToolPattern
})

foreach ($file in $nodeToolFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $isEditorAssemblyPath = $relative -match "(^Editor/|/Editor/)"

    if (-not $isEditorAssemblyPath) {
        Add-AgentIssue $issues "Error" "Editor Node Tool Code" $relative "Node editor UI symbols appear outside an Editor assembly path." "Keep custom GraphView, NodeUI, INodeType, and IPlug tooling under Editor/ or a library Editor/ folder."
    }

    if ($text -match "throw\s+new\s+NotImplementedException\s*\(") {
        Add-AgentIssue $issues "Error" "Editor Node Tool Code" $relative "Tutorial placeholder NotImplementedException remains in node-editor scaffolding." "Replace interface placeholder bodies with safe defaults before handoff; these callbacks are hit by hover, paint, menus, or graph actions."
    }
}

if ($nodeToolFiles.Count -eq 0) {
    Add-AgentIssue $issues "Info" "Editor Node Tool Code" "" "No custom editor node-tool C# files were detected."
}
elseif (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Editor Node Tool Code" "" "Custom editor node-tool C# files passed placement and placeholder checks."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
