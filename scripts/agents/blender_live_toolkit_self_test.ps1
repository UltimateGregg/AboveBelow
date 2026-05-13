param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Blender Live Toolkit Self-Test"
Write-Host "Root: $Root"

$requiredFiles = @(
    "blender_addons/sbox_asset_toolkit/__init__.py",
    "scripts/install_blender_asset_toolkit.ps1",
    "scripts/start_visible_blender_asset_toolkit.ps1",
    "mcp/src/blender.ts",
    "docs/blender_mcp.md",
    "docs/agent_toolkit.md"
)

foreach ($path in $requiredFiles) {
    $full = Join-Path $Root $path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" "Blender Live Toolkit" $path "Required file is missing." "Create the visible Blender toolkit file."
    }
}

$addonPath = Join-Path $Root "blender_addons/sbox_asset_toolkit/__init__.py"
if (Test-Path -LiteralPath $addonPath) {
    $addonText = Get-Content -LiteralPath $addonPath -Raw
    $requiredClasses = @(
        "SBOX_PT_asset_toolkit",
        "SBOX_OT_start_bridge",
        "SBOX_OT_setup_asset_scene",
        "SBOX_OT_create_asset_brief",
        "SBOX_OT_run_quality_audit",
        "SBOX_OT_render_preview",
        "SBOX_OT_export_to_sbox",
        "SBOX_OT_run_production_checks"
    )
    foreach ($className in $requiredClasses) {
        if ($addonText -notmatch [regex]::Escape($className)) {
            Add-AgentIssue $issues "Error" "Blender Add-on" "blender_addons/sbox_asset_toolkit/__init__.py" "Missing add-on class '$className'." "Expose the expected UI/operator surface."
        }
    }
}

$mcpPath = Join-Path $Root "mcp/src/blender.ts"
if (Test-Path -LiteralPath $mcpPath) {
    $mcpText = Get-Content -LiteralPath $mcpPath -Raw
    $requiredTools = @(
        "blender_sbox_scene_status",
        "blender_sbox_setup_asset_scene",
        "blender_sbox_add_socket",
        "blender_sbox_create_material",
        "blender_sbox_render_current_preview",
        "blender_sbox_export_current_asset"
    )
    foreach ($toolName in $requiredTools) {
        if ($mcpText -notmatch [regex]::Escape($toolName)) {
            Add-AgentIssue $issues "Error" "Blender MCP" "mcp/src/blender.ts" "Missing MCP tool '$toolName'." "Register the S&Box high-level Blender MCP tool."
        }
    }
}

$docs = @(
    @{ Path = "docs/blender_mcp.md"; Patterns = @("S&Box Asset Toolkit", "start_visible_blender_asset_toolkit.ps1", "blender_sbox_setup_asset_scene") },
    @{ Path = "docs/agent_toolkit.md"; Patterns = @("Blender visible MCP", "S&Box Asset Toolkit") }
)

foreach ($doc in $docs) {
    $full = Join-Path $Root $doc.Path
    if (-not (Test-Path -LiteralPath $full)) {
        continue
    }
    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $doc.Patterns) {
        if ($text -notmatch [regex]::Escape($pattern)) {
            Add-AgentIssue $issues "Error" "Docs" $doc.Path "Missing documentation phrase '$pattern'." "Document the visible Blender MCP workflow."
        }
    }
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
