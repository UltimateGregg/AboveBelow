<#
.SYNOPSIS
  PostToolUse hook: auto-export a .blend after it is saved through the Blender MCP.

.DESCRIPTION
  The project's blend-auto-export watcher (.claude/settings.json, file_pattern_change)
  only sees .blend changes made by Claude's own file tools. When a .blend is saved by
  the *Blender process* via the MCP tool `mcp__blender_stdio__blender_save_file`, the
  watcher never fires, so the asset pipeline does not run.

  This hook closes that gap. Claude Code invokes it as a PostToolUse hook for the
  Blender save tool, passing the tool call as JSON on stdin. We pull the saved .blend
  path out of that JSON and run scripts/smart_asset_export.ps1 for it -- the same
  script the file watcher would have run -- so an MCP save exports exactly like a
  Ctrl+S save.

  Wired in .claude/settings.local.json under hooks.PostToolUse with matcher
  "mcp__blender_stdio__blender_save_file". Safe to run by hand: pipe a JSON blob or
  pass -BlendFilePath directly.
#>
[CmdletBinding()]
param(
  # Optional explicit path (manual runs / testing). Normally the path comes from stdin.
  [string]$BlendFilePath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # scripts/hooks -> repo root

function Resolve-BlendPath {
  param([string]$ExplicitPath)

  if ($ExplicitPath) { return $ExplicitPath }

  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

  try { $data = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $data = $null }

  if ($data) {
    # 1. Save As path passed to the tool (our normal workflow always sets this).
    if ($data.tool_input -and $data.tool_input.PSObject.Properties['path'] -and $data.tool_input.path) {
      return [string]$data.tool_input.path
    }

    # 2. The tool's own result -> { "saved": "<abs path>" }.
    $resp = $data.tool_response
    if ($resp) {
      if ($resp.PSObject.Properties['saved'] -and $resp.saved) { return [string]$resp.saved }
      # MCP results may arrive as a content envelope: { content: [ { text: "{...json...}" } ] }
      if ($resp.PSObject.Properties['content'] -and $resp.content) {
        foreach ($block in $resp.content) {
          if ($block.PSObject.Properties['text'] -and $block.text) {
            try {
              $inner = $block.text | ConvertFrom-Json -ErrorAction Stop
              if ($inner.saved) { return [string]$inner.saved }
            } catch { }
          }
        }
      }
    }
  }

  # 3. Last resort: greedy match of an absolute .blend FILE path in the raw payload
  #    (greedy so it reaches the final .blend, not a directory named *.blend).
  if ($raw -match '([A-Za-z]:(?:\\\\|\\)[^"]*\.blend)') { return ($Matches[1] -replace '\\\\', '\') }
  return $null
}

$blend = Resolve-BlendPath -ExplicitPath $BlendFilePath

if (-not $blend) {
  Write-Output "blend-save-export: no .blend path found in tool payload; nothing to export."
  exit 0
}
if ($blend -notmatch '\.blend$') {
  Write-Output "blend-save-export: saved path is not a .blend ($blend); skipping export."
  exit 0
}
if (-not (Test-Path -LiteralPath $blend -PathType Leaf)) {
  Write-Output "blend-save-export: .blend file not found on disk ($blend); skipping export."
  exit 0
}

Write-Output "blend-save-export: exporting $blend"
$exporter = Join-Path $repoRoot 'scripts\smart_asset_export.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $exporter -BlendFilePath $blend
$code = $LASTEXITCODE
if ($code -ne 0) {
  Write-Output "blend-save-export: smart_asset_export.ps1 exited with code $code"
  exit $code
}
Write-Output "blend-save-export: export complete for $blend"
exit 0
