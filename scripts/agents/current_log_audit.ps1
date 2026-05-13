param(
    [string]$Root = "",
    [int]$FreshMinutes = 240,
    [switch]$RequireFresh,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Current Log Audit"
Write-Host "Root: $Root"

$cutoff = (Get-Date).AddMinutes(-1 * [Math]::Abs($FreshMinutes))
$logPaths = New-Object System.Collections.Generic.List[string]

$candidateFiles = @(
    (Join-Path $Root "mcp-editor-build.log")
)
foreach ($file in $candidateFiles) {
    if (Test-Path -LiteralPath $file) {
        $logPaths.Add((Resolve-Path -LiteralPath $file).Path)
    }
}

$candidateDirs = @(
    (Join-Path $Root ".sbox\logs"),
    (Join-Path $env:LOCALAPPDATA "sbox"),
    (Join-Path $env:LOCALAPPDATA "s&box"),
    (Join-Path $env:LOCALAPPDATA "Sandbox"),
    (Join-Path $env:LOCALAPPDATA "Facepunch")
)

foreach ($dir in $candidateDirs) {
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        continue
    }

    Get-ChildItem -LiteralPath $dir -Recurse -File -Include "*.log", "*.txt" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "agent-build.log" -and $_.LastWriteTime -ge $cutoff } |
        ForEach-Object { $logPaths.Add($_.FullName) }
}

$logPaths = [System.Collections.Generic.List[string]]@($logPaths | Select-Object -Unique)
$freshCount = 0

foreach ($path in $logPaths) {
    $item = Get-Item -LiteralPath $path
    $relative = ConvertTo-AgentRelativePath -Path $item.FullName -Root $Root
    if ($item.LastWriteTime -lt $cutoff) {
        Add-AgentIssue $issues "Info" "Logs" $relative "Stale log ignored: last modified $($item.LastWriteTime)."
        continue
    }

    $freshCount += 1
    $tail = Get-Content -LiteralPath $item.FullName -Tail 300 -ErrorAction SilentlyContinue | Out-String
    $errorMatches = [regex]::Matches($tail, "(?im)(NullReferenceException|ArgumentNullException|InvalidOperationException|MissingMethodException|^\s*error\b|Exception:|Unhandled exception|CS\d{4})")
    $warningMatches = [regex]::Matches($tail, "(?im)(^\s*warning\b|WARN|Warning:)")

    if ($errorMatches.Count -gt 0) {
        Add-AgentIssue $issues "Warning" "Logs" $relative "Fresh log contains $($errorMatches.Count) error/exception-looking line(s)." "Inspect the log before claiming current editor/runtime health."
    }
    elseif ($warningMatches.Count -gt 0) {
        Add-AgentIssue $issues "Warning" "Logs" $relative "Fresh log contains $($warningMatches.Count) warning-looking line(s)." "Confirm warnings are expected or pre-existing."
    }
    else {
        Add-AgentIssue $issues "Info" "Logs" $relative "Fresh log tail has no obvious error/warning lines."
    }
}

if ($freshCount -eq 0) {
    $severity = if ($RequireFresh) { "Warning" } else { "Info" }
    Add-AgentIssue $issues $severity "Logs" "" "No fresh editor/runtime logs found in the last $FreshMinutes minute(s)." "Run an editor playtest when runtime validation matters."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
