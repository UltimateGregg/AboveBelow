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

Write-AgentSection "S&Box API Reference Audit"
Write-Host "Root: $Root"

function Resolve-SboxApiJsonPath {
    param([string]$ProjectRoot)

    foreach ($candidate in @("API.json", "api.json")) {
        $path = Join-Path $ProjectRoot $candidate
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $null
}

function Test-TextMarkers {
    param(
        [string]$Path,
        [string[]]$Patterns,
        [string]$Area,
        [string]$Recommendation
    )

    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" $Area $Path "Required API reference integration file is missing." $Recommendation
        return
    }

    $text = Get-Content -LiteralPath $full -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" $Area $Path "Missing required API reference marker '$pattern'." $Recommendation
        }
    }
}

function Find-ApiType {
    param(
        [object[]]$Types,
        [string]$FullName
    )

    return @($Types | Where-Object { $_.FullName -eq $FullName } | Select-Object -First 1)
}

Test-TextMarkers -Path "docs/sbox_engine_llm_reference.md" -Area "API Reference Docs" -Patterns @(
    "API\.json",
    "sbox_api_lookup\.ps1",
    "local API dump"
) -Recommendation "Document the local official API dump and lookup command in the engine reference."

Test-TextMarkers -Path ".agents/sbox/sbox-engine-reference-agent.md" -Area "API Reference Agent" -Patterns @(
    "API\.json",
    "sbox_api_lookup\.ps1"
) -Recommendation "Route exact API-shape questions through the local lookup command."

Test-TextMarkers -Path "docs/agent_toolkit.md" -Area "API Reference Routing" -Patterns @(
    "S&Box API Lookup",
    "sbox_api_lookup\.ps1"
) -Recommendation "Expose the lookup helper in the agent toolkit routing table."

Test-TextMarkers -Path ".agents/sbox/README.md" -Area "API Reference Routing" -Patterns @(
    "S&Box API Lookup",
    "sbox_api_lookup\.ps1"
) -Recommendation "Expose the lookup helper in the agent routing README."

Test-TextMarkers -Path "AGENTS.md" -Area "API Reference Instructions" -Patterns @(
    "API\.json",
    "sbox_api_lookup\.ps1"
) -Recommendation "Tell agents to query the local API dump before making exact S&Box API claims."

Test-TextMarkers -Path ".claude/settings.json" -Area "API Reference Hook" -Patterns @(
    "sbox_api_reference_audit\.ps1",
    "sbox_api_lookup\.ps1",
    "API\.json"
) -Recommendation "Keep docs and API-reference hooks aware of the new API tooling."

Test-TextMarkers -Path "scripts/agents/run_agent_checks.ps1" -Area "API Reference Suite" -Patterns @(
    '"api"',
    "sbox_api_reference_audit\.ps1",
    "sbox_api_lookup\.ps1"
) -Recommendation "Wire the API audit into a named suite and recurring docs/train suites."

Test-TextMarkers -Path "scripts/agents/test_full_automation_layer.ps1" -Area "API Reference Self-Test" -Patterns @(
    "sbox_api_lookup\.ps1",
    "sbox_api_reference_audit\.ps1"
) -Recommendation "Protect the API lookup and audit wiring in the automation self-test."

$lookupPath = Join-Path $Root "scripts/agents/sbox_api_lookup.ps1"
if (-not (Test-Path -LiteralPath $lookupPath)) {
    Add-AgentIssue $issues "Error" "API Lookup Tool" "scripts/agents/sbox_api_lookup.ps1" "The local API lookup helper is missing." "Restore the lookup helper so agents can query exact S&Box signatures."
}

$apiPath = Resolve-SboxApiJsonPath -ProjectRoot $Root
if ([string]::IsNullOrWhiteSpace($apiPath)) {
    Add-AgentIssue $issues "Warning" "API Dump" "API.json" "Local official S&Box API dump was not found at the project root." "Download or copy the official API.json into the root when exact engine API shape matters."
}
else {
    try {
        $api = Read-AgentJson -Path $apiPath
        $types = @($api.Types)
        if ($types.Count -lt 100) {
            Add-AgentIssue $issues "Error" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "API dump has only $($types.Count) types, which is too small for the official S&Box API surface." "Replace the file with the official API.json dump."
        }

        foreach ($requiredType in @(
            "Sandbox.Component",
            "Sandbox.GameObject",
            "Sandbox.Networking",
            "Sandbox.SyncAttribute",
            "Sandbox.RpcAttribute",
            "Sandbox.Rpc.BroadcastAttribute",
            "Sandbox.Rpc.HostAttribute",
            "Sandbox.Rpc.OwnerAttribute",
            "Sandbox.ClientEditableAttribute",
            "Sandbox.TimeSince"
        )) {
            if (@(Find-ApiType -Types $types -FullName $requiredType).Count -eq 0) {
                Add-AgentIssue $issues "Error" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "API dump is missing required type '$requiredType'." "Refresh API.json from the official S&Box API export."
            }
        }

        if (@(Find-ApiType -Types $types -FullName "NetAttribute").Count -gt 0 -or @(Find-ApiType -Types $types -FullName "Sandbox.NetAttribute").Count -gt 0) {
            Add-AgentIssue $issues "Warning" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "API dump contains a NetAttribute symbol; stale networking guidance audits may need review." "Verify current networking docs before changing project guidance."
        }

        $networking = Find-ApiType -Types $types -FullName "Sandbox.Networking"
        if ($networking.Count -gt 0 -and @(@($networking[0].Properties) | Where-Object { $_.Name -eq "IsHost" }).Count -eq 0) {
            Add-AgentIssue $issues "Error" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "Sandbox.Networking does not expose IsHost in the local API dump." "Refresh API.json or update host-authority guidance after source verification."
        }

        $gameObject = Find-ApiType -Types $types -FullName "Sandbox.GameObject"
        if ($gameObject.Count -gt 0 -and @(@($gameObject[0].Methods) | Where-Object { $_.Name -eq "NetworkSpawn" }).Count -eq 0) {
            Add-AgentIssue $issues "Error" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "Sandbox.GameObject does not expose NetworkSpawn in the local API dump." "Refresh API.json or update network-spawn guidance after source verification."
        }

        Add-AgentIssue $issues "Info" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "Validated local S&Box API dump with $($types.Count) reflected types."
    }
    catch {
        Add-AgentIssue $issues "Error" "API Dump" (ConvertTo-AgentRelativePath -Path $apiPath -Root $Root) "Failed to parse local API dump: $($_.Exception.Message)" "Replace API.json with valid official JSON."
    }
}

if (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "API Reference" "" "S&Box API lookup, docs routing, suite wiring, and local dump checks passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
