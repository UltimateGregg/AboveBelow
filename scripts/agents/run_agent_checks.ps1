param(
    [string]$Root = "",
    [ValidateSet("quick", "full", "build", "ui", "prefab", "prefab-graph", "scene", "asset", "asset-production", "networking", "docs", "balance", "playtest", "logs", "readiness", "self-test")]
    [string]$Suite = "quick",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Invoke-AgentScript {
    param(
        [string]$Name,
        [string[]]$ScriptArgs = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $Name
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "[Error] Missing script: $scriptPath"
        return 1
    }

    Write-Host ""
    Write-Host "---- Running $Name ----"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ScriptArgs 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    return $exitCode
}

$commonArgs = @("-Root", $Root)
if ($ShowInfo) {
    $commonArgs += "-ShowInfo"
}
if ($FailOnWarning) {
    $commonArgs += "-FailOnWarning"
}

$scripts = @()
switch ($Suite) {
    "quick" {
        $scripts = @(
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "networking_review_audit.ps1"; Args = $commonArgs },
            @{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs },
            @{ Name = "current_log_audit.ps1"; Args = ($commonArgs + "-ShowInfo") },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root) }
        )
    }
    "full" {
        $scripts = @(
            @{ Name = "test_full_automation_layer.ps1"; Args = @("-Root", $Root) },
            @{ Name = "build_log_sentinel.ps1"; Args = $commonArgs },
            @{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "networking_review_audit.ps1"; Args = $commonArgs },
            @{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs },
            @{ Name = "current_log_audit.ps1"; Args = $commonArgs },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") },
            @{ Name = "balance_tuning_report.ps1"; Args = @("-Root", $Root) },
            @{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "All") }
        )
    }
    "build" { $scripts = @(@{ Name = "build_log_sentinel.ps1"; Args = $commonArgs }) }
    "ui" {
        $scripts = @(
            @{ Name = "ui_flow_audit.ps1"; Args = $commonArgs },
            @{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "UI") },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
        )
    }
    "prefab" { $scripts = @(@{ Name = "prefab_wiring_audit.ps1"; Args = $commonArgs }) }
    "prefab-graph" { $scripts = @(@{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs }) }
    "scene" { $scripts = @(@{ Name = "scene_integrity_audit.ps1"; Args = $commonArgs }) }
    "asset" { $scripts = @(@{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs }) }
    "asset-production" {
        $scripts = @(
            @{ Name = "blender_quality_audit.ps1"; Args = $commonArgs },
            @{ Name = "material_texture_audit.ps1"; Args = $commonArgs },
            @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
            @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
            @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
        )
    }
    "networking" { $scripts = @(@{ Name = "networking_review_audit.ps1"; Args = $commonArgs }) }
    "docs" { $scripts = @(@{ Name = "docs_roadmap_audit.ps1"; Args = $commonArgs }) }
    "balance" { $scripts = @(@{ Name = "balance_tuning_report.ps1"; Args = @("-Root", $Root) }) }
    "playtest" { $scripts = @(@{ Name = "playtest_checklist.ps1"; Args = @("-Root", $Root, "-ChangeArea", "All") }) }
    "logs" { $scripts = @(@{ Name = "current_log_audit.ps1"; Args = $commonArgs }) }
    "readiness" { $scripts = @(@{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }) }
    "self-test" { $scripts = @(@{ Name = "test_full_automation_layer.ps1"; Args = @("-Root", $Root) }) }
}

$failed = New-Object System.Collections.Generic.List[string]
foreach ($script in $scripts) {
    $exitCode = Invoke-AgentScript -Name $script.Name -ScriptArgs $script.Args
    if ($exitCode -ne 0) {
        $failed.Add("$($script.Name) exited $exitCode")
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "Agent check suite '$Suite' failed:"
    $failed | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Agent check suite '$Suite' completed."
