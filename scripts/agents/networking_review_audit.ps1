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

Write-AgentSection "Networking Review Audit"
Write-Host "Root: $Root"

$codeRoot = Join-Path $Root "Code"
if (-not (Test-Path -LiteralPath $codeRoot)) {
    Add-AgentIssue $issues "Error" "Code" "Code" "Code directory is missing." "Restore Code/ before running networking review."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit 1
}

$files = @(Get-ChildItem -LiteralPath $codeRoot -Recurse -File -Include "*.cs", "*.razor" -ErrorAction SilentlyContinue)

foreach ($file in $files) {
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    if ($null -eq $raw) {
        $raw = ""
    }
    $lines = Get-Content -LiteralPath $file.FullName

    if ($raw -match "GameObject\.Find\s*\(") {
        Add-AgentIssue $issues "Warning" "Scene Query" $relative "Uses GameObject.Find()." "Prefer cached component references, AutoWire, or scoped Scene queries."
    }

    if ($raw -match "OnFixedUpdate\s*\([^)]*\)\s*\{[\s\S]*GameObject\.Find\s*\(") {
        Add-AgentIssue $issues "Error" "Scene Query" $relative "GameObject.Find appears inside OnFixedUpdate." "Move lookup to OnStart or cache it outside the fixed tick."
    }

    $subscriptions = [regex]::Matches($raw, "([A-Za-z_][\w\.]*\.On[A-Za-z_]\w*|On[A-Za-z_]\w*)\s*\+=")
    foreach ($match in $subscriptions) {
        $eventName = $match.Groups[1].Value.Split(".")[-1]
        if ($eventName -match "^(On|[A-Z]).*" -and $raw -notmatch [regex]::Escape($eventName) + "\s*-=") {
            Add-AgentIssue $issues "Warning" "Events" $relative "Subscribes to '$eventName' without an obvious unsubscribe in the same file." "Unsubscribe in OnDestroy unless the event source is definitely shorter-lived."
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "\[Rpc\.(Broadcast|Host)\]") {
            $attributeLine = $i + 1
            $windowEnd = [Math]::Min($lines.Count - 1, $i + 45)
            $window = ($lines[$i..$windowEnd] -join "`n")
            $mutatingPatterns = @(
                "TakeDamage\s*\(",
                "NetworkSpawn\s*\(",
                "\.Add\s*\(",
                "\.Remove\s*\(",
                "CurrentHealth\s*=",
                "IsDead\s*=",
                "IsJammed\s*=",
                "IncomingStrength\s*=",
                "IsCrashing\s*=",
                "SelectedSlot\s*=",
                "AmmoInMagazine\s*=",
                "AmmoReserve\s*="
            )
            $looksMutating = $false
            foreach ($pattern in $mutatingPatterns) {
                if ($window -match $pattern) {
                    $looksMutating = $true
                    break
                }
            }

            if ($looksMutating -and $window -notmatch "Networking\.IsHost|CanMutateState\s*\(") {
                Add-AgentIssue $issues "Warning" "RPC Authority" "${relative}:$attributeLine" "RPC block appears to mutate state without an obvious host-authority guard." "Add a host guard or document why the mutation is visual-only/client-local."
            }
        }

        if ($line -match "NetworkSpawn\s*\(") {
            $start = [Math]::Max(0, $i - 60)
            $end = [Math]::Min($lines.Count - 1, $i + 8)
            $nearby = ($lines[$start..$end] -join "`n")
            if ($nearby -notmatch "Networking\.IsHost|CanMutateState\s*\(|NetworkSpawn\s*\(\s*channel|NetworkSpawn\s*\(\s*conn") {
                Add-AgentIssue $issues "Warning" "Network Spawn" "${relative}:$($i + 1)" "NetworkSpawn call has no nearby ownership or host-authority cue." "Confirm only the host spawns networked gameplay objects and owner is set when needed."
            }
        }
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Networking" "" "Static networking audit found no blocking patterns."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
