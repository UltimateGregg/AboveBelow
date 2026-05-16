param(
    [string]$Root = "",
    [switch]$NoBuild,
    [int]$LogMinutes = 240,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "S&Box Build and Log Sentinel"
Write-Host "Root: $Root"

if (-not $NoBuild) {
    $project = Join-Path $Root "Code\dronevsplayers.csproj"
    if (-not (Test-Path -LiteralPath $project)) {
        Add-AgentIssue $issues "Error" "Build" "Code/dronevsplayers.csproj" "Project file is missing." "Restore the project file or update this sentinel."
    }
    else {
        Write-Host "Running: dotnet build Code\dronevsplayers.csproj --no-restore"
        Push-Location $Root
        try {
            $buildOutput = & dotnet build "Code\dronevsplayers.csproj" --no-restore 2>&1
            $buildExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $buildText = ($buildOutput | Out-String)
        $buildLog = Join-Path $Root ".tmpbuild\agent-build.log"
        New-Item -ItemType Directory -Force -Path (Split-Path $buildLog -Parent) | Out-Null
        $buildText | Set-Content -LiteralPath $buildLog -Encoding UTF8

        if ($buildExitCode -ne 0) {
            Add-AgentIssue $issues "Error" "Build" ".tmpbuild/agent-build.log" "dotnet build failed with exit code $buildExitCode." "Open the build log and fix the first compiler error before continuing."
        }
        elseif ($buildText -match "\bwarning\s+[A-Z]*\d{3,5}\b") {
            Add-AgentIssue $issues "Warning" "Build" ".tmpbuild/agent-build.log" "Build succeeded but emitted compiler warnings." "Review warnings before claiming a clean handoff."
        }
        else {
            Add-AgentIssue $issues "Info" "Build" ".tmpbuild/agent-build.log" "Build succeeded without compiler warnings."
        }
    }
}
else {
    Add-AgentIssue $issues "Info" "Build" "" "Build skipped because -NoBuild was supplied."
}

$freshAfter = (Get-Date).AddMinutes(-1 * [Math]::Abs($LogMinutes))
$candidateLogs = New-Object System.Collections.Generic.List[string]

$knownLogs = @(
    (Join-Path $Root "mcp-editor-build.log")
)

foreach ($path in $knownLogs) {
    if (Test-Path -LiteralPath $path) {
        $candidateLogs.Add($path)
    }
}

$possibleLogDirs = @(
    (Join-Path $Root ".sbox\logs"),
    (Join-Path $Root ".tmpbuild"),
    (Join-Path $env:LOCALAPPDATA "sbox\logs"),
    (Join-Path $env:LOCALAPPDATA "s&box\logs")
)
$possibleLogDirs += @(Get-AgentSboxLogDirectories -Root $Root)

foreach ($dir in $possibleLogDirs) {
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        continue
    }
    Get-ChildItem -LiteralPath $dir -File -Filter "*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "agent-build.log" } |
        ForEach-Object { $candidateLogs.Add($_.FullName) }
}

$candidateLogs = [System.Collections.Generic.List[string]]@($candidateLogs | Select-Object -Unique)

if ($candidateLogs.Count -eq 0) {
    Add-AgentIssue $issues "Warning" "Editor Logs" "" "No S&Box or editor log files were found." "Run the editor playtest when runtime validation matters."
}
else {
    foreach ($path in $candidateLogs) {
        $item = Get-Item -LiteralPath $path
        $relative = ConvertTo-AgentRelativePath -Path $item.FullName -Root $Root
        if ($item.LastWriteTime -lt $freshAfter) {
            Add-AgentIssue $issues "Info" "Editor Logs" $relative "Log is stale: last modified $($item.LastWriteTime)." "Do not treat this as current runtime validation."
            continue
        }

        $tail = Get-Content -LiteralPath $item.FullName -Tail 250 -ErrorAction SilentlyContinue | Out-String
        $errorMatches = [regex]::Matches($tail, "(?im)(NullReferenceException|ArgumentNullException|InvalidOperationException|MissingMethodException|^\s*error\b|Exception:|CS\d{4})")
        $warningMatches = [regex]::Matches($tail, "(?im)(^\s*warning\b|WARN|Warning:)")

        if ($errorMatches.Count -gt 0) {
            Add-AgentIssue $issues "Warning" "Editor Logs" $relative "Fresh log contains $($errorMatches.Count) error/exception-looking line(s)." "Inspect the fresh log; runtime errors may not be caught by build."
        }
        elseif ($warningMatches.Count -gt 0) {
            Add-AgentIssue $issues "Warning" "Editor Logs" $relative "Fresh log contains $($warningMatches.Count) warning-looking line(s)." "Confirm these warnings are expected or pre-existing."
        }
        else {
            Add-AgentIssue $issues "Info" "Editor Logs" $relative "Fresh log tail has no obvious error or warning lines."
        }
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
