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

Write-AgentSection "S&Box Whitelist Audit"
Write-Host "Root: $Root"

$codeRoot = Join-Path $Root "Code"
if (-not (Test-Path -LiteralPath $codeRoot)) {
    Add-AgentIssue $issues "Error" "Whitelist" "Code" "Project Code directory is missing." "Restore the game code directory or update this audit."
}
else {
    $blockedPatterns = @(
        @{ Pattern = "System\.Reflection"; Reason = "System.Reflection calls are blocked by the S&Box whitelist." },
        @{ Pattern = "\bBindingFlags\b"; Reason = "Reflection BindingFlags usage is blocked by the S&Box whitelist." },
        @{ Pattern = "\.Get(Method|Field|Property)\s*\("; Reason = "Runtime member lookup can trip S&Box whitelist violations." },
        @{ Pattern = "\bMethodBase\b"; Reason = "MethodBase APIs are blocked by the S&Box whitelist." },
        @{ Pattern = "\bDynamicInvoke\s*\("; Reason = "DynamicInvoke is blocked by the S&Box whitelist." }
    )

    foreach ($entry in $blockedPatterns) {
        $matches = @(Get-ChildItem -LiteralPath $codeRoot -Recurse -File -Filter "*.cs" |
            Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" } |
            Select-String -Pattern $entry.Pattern -AllMatches)

        foreach ($match in $matches) {
            $relative = ConvertTo-AgentRelativePath -Path $match.Path -Root $Root
            Add-AgentIssue $issues "Error" "Whitelist" "$relative`:$($match.LineNumber)" $entry.Reason "Use direct typed calls or DEBUG-only helper methods instead of reflection."
        }
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Whitelist" "Code" "No S&Box whitelist-risky reflection markers were found in game code."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
