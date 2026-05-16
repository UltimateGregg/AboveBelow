param(
    [string]$Root = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

$requiredScripts = @(
    "scripts/agents/ui_flow_audit.ps1",
    "scripts/agents/prefab_graph_audit.ps1",
    "scripts/agents/scene_integrity_audit.ps1",
    "scripts/agents/current_log_audit.ps1",
    "scripts/agents/feature_readiness_report.ps1",
    "scripts/agents/gameplay_regression_guard.ps1",
    "scripts/agents/blender_quality_audit.ps1",
    "scripts/agents/material_texture_audit.ps1",
    "scripts/agents/modeldoc_audit.ps1",
    "scripts/agents/fbx_material_slot_audit.ps1",
    "scripts/agents/asset_visual_review.ps1",
    "scripts/agents/blender_live_toolkit_self_test.ps1"
)

foreach ($script in $requiredScripts) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $script))) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" $script "Required full-layer script is missing." "Create the script and wire it into run_agent_checks.ps1."
    }
}

$runner = Join-Path $Root "scripts/agents/run_agent_checks.ps1"
if (Test-Path -LiteralPath $runner) {
    $runnerText = Get-Content -LiteralPath $runner -Raw
    $validateSetMatch = [regex]::Match($runnerText, '\[ValidateSet\((?<values>[^\)]*)\)\]')
    if (-not $validateSetMatch.Success) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner does not declare a ValidateSet for suites." "Restore suite validation on the Suite parameter."
    }

    foreach ($suite in @("ui", "prefab-graph", "scene", "logs", "readiness", "asset-production", "modeldoc", "blender-live", "gameplay-regression")) {
        $quotedSuite = '"' + [regex]::Escape($suite) + '"'
        if ($validateSetMatch.Success -and $validateSetMatch.Groups["values"].Value -notmatch $quotedSuite) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner ValidateSet does not expose suite '$suite'." "Add the suite to the Suite parameter ValidateSet."
        }

        $switchCasePattern = '(?m)^\s*"' + [regex]::Escape($suite) + '"\s*\{'
        if ($runnerText -notmatch $switchCasePattern) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner does not wire switch case '$suite'." "Add the suite case to the switch block."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/run_agent_checks.ps1" "Runner script is missing." "Restore the runner."
}

foreach ($script in $requiredScripts) {
    if ($script -eq "scripts/agents/asset_visual_review.ps1") {
        continue
    }

    $full = Join-Path $Root $script
    if (-not (Test-Path -LiteralPath $full)) {
        continue
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $full -Root $Root | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" $script "Script exited with $LASTEXITCODE on the current project." "Fix the script or the issue it detected."
    }
}

$uiAudit = Join-Path $Root "scripts/agents/ui_flow_audit.ps1"
if (Test-Path -LiteralPath $uiAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-ui-flow-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\UI") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $fixturePath = Join-Path $tempRoot "Code\UI\Fixture.razor"
        '<root><div class="choice pilot">Dead Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit did not fail on a dead interactive-looking fixture." "Keep the fixture red/green test aligned with the audit rules."
        }

        '<root><div class="choice pilot" onclick=@DoThing>Live Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit failed on a fixture with an onclick handler." "Avoid false positives for valid clickable elements."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$prefabGraphAudit = Join-Path $Root "scripts/agents/prefab_graph_audit.ps1"
if (Test-Path -LiteralPath $prefabGraphAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-prefab-graph-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\models") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\materials") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\prefabs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\fixture.vmdl") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\fixture_a.vmat") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\fixture_b.vmat") | Out-Null

        @'
{
  "source_blend": "fixture.blend",
  "target_fbx": "Assets/models/fixture.fbx",
  "target_vmdl": "Assets/models/fixture.vmdl",
  "material_remap": {
    "FixtureA": "materials/fixture_a.vmat",
    "FixtureB": "materials/fixture_b.vmat"
  },
  "vmdl_material_source_suffix": "",
  "vmdl_use_global_default": false,
  "strict_vmdl_material_sources": true
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\fixture_asset_pipeline.json") -Encoding UTF8

        $prefabPath = Join-Path $tempRoot "Assets\prefabs\Fixture.prefab"
        @'
{
  "RootObject": {
    "__guid": "root-guid",
    "Name": "Fixture",
    "Components": [],
    "Children": [
      {
        "__guid": "visual-guid",
        "Name": "Visual",
        "Components": [
          {
            "__type": "Sandbox.ModelRenderer",
            "__guid": "renderer-guid",
            "Model": "models/fixture.vmdl",
            "MaterialOverride": "materials/fixture_a.vmat"
          }
        ],
        "Children": []
      }
    ]
  }
}
'@ | Set-Content -LiteralPath $prefabPath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $prefabGraphAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/prefab_graph_audit.ps1" "Prefab graph audit did not fail on a protected multi-material prefab MaterialOverride." "Keep the fixture red/green test aligned with the Blender-to-S&Box texture transfer regression."
        }

        (Get-Content -LiteralPath $prefabPath -Raw).Replace('"MaterialOverride": "materials/fixture_a.vmat"', '"MaterialOverride": null') | Set-Content -LiteralPath $prefabPath -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $prefabGraphAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/prefab_graph_audit.ps1" "Prefab graph audit failed after clearing the protected multi-material prefab MaterialOverride." "Avoid false positives when the VMDL owns material binding."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$modelDocAudit = Join-Path $Root "scripts/agents/modeldoc_audit.ps1"
if (Test-Path -LiteralPath $modelDocAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-modeldoc-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\models") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\materials") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $vmdlPath = Join-Path $tempRoot "Assets\models\fixture.vmdl"
        @'
<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc29:version{3cec427c-1b0e-4d48-a90a-0436f33a6041} -->
{
    rootNode =
    {
        _class = "RootNode"
        children =
        [
            {
                _class = "RenderMeshList"
                children =
                [
                    {
                        _class = "RenderMeshFile"
                        filename = "models/missing_source.fbx"
                    },
                ]
            },
        ]
    }
}
'@ | Set-Content -LiteralPath $vmdlPath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $modelDocAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/modeldoc_audit.ps1" "ModelDoc audit did not fail on a missing source mesh fixture." "Keep the fixture red/green test aligned with the audit rules."
        }

        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\source.fbx") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\fixture.vmat") | Out-Null
        @'
{
  "source_blend": "fixture.blend",
  "target_fbx": "Assets/models/source.fbx",
  "target_vmdl": "Assets/models/fixture.vmdl",
  "material_remap": {
    "FixtureMaterial": "materials/fixture.vmat"
  },
  "vmdl_material_source_suffix": "",
  "vmdl_use_global_default": false,
  "strict_vmdl_material_sources": true
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\fixture_asset_pipeline.json") -Encoding UTF8

        @'
<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc29:version{3cec427c-1b0e-4d48-a90a-0436f33a6041} -->
{
    rootNode =
    {
        _class = "RootNode"
        children =
        [
            {
                _class = "MaterialGroupList"
                children =
                [
                    {
                        _class = "DefaultMaterialGroup"
                        remaps =
                        [
                            {
                                from = "FixtureMaterial"
                                to = "materials/fixture.vmat"
                            },
                        ]
                        use_global_default = false
                    },
                ]
            },
            {
                _class = "RenderMeshList"
                children =
                [
                    {
                        _class = "RenderMeshFile"
                        filename = "models/source.fbx"
                    },
                ]
            },
        ]
    }
}
'@ | Set-Content -LiteralPath $vmdlPath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $modelDocAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/modeldoc_audit.ps1" "ModelDoc audit failed on a valid fixture." "Avoid false positives for valid VMDL source and material paths."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$fbxMaterialSlotAudit = Join-Path $Root "scripts/agents/fbx_material_slot_audit.ps1"
if (Test-Path -LiteralPath $fbxMaterialSlotAudit) {
    $defaultBlender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
    $sourceFbx = Join-Path $Root "Assets\models\terrain_assets.fbx"
    if ((Test-Path -LiteralPath $defaultBlender) -and (Test-Path -LiteralPath $sourceFbx)) {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-fbx-material-slot-audit-" + [System.Guid]::NewGuid().ToString("N"))
        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\models") | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\materials") | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null
            New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null
            Copy-Item -LiteralPath $sourceFbx -Destination (Join-Path $tempRoot "Assets\models\source.fbx")
            Copy-Item -LiteralPath (Join-Path $Root "scripts\fbx_material_slot_audit.py") -Destination (Join-Path $tempRoot "scripts\fbx_material_slot_audit.py")
            New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\fixture.vmat") | Out-Null

            $configPath = Join-Path $tempRoot "scripts\fixture_asset_pipeline.json"
            $vmdlPath = Join-Path $tempRoot "Assets\models\fixture.vmdl"
            @'
{
  "source_blend": "fixture.blend",
  "target_fbx": "Assets/models/source.fbx",
  "target_vmdl": "Assets/models/fixture.vmdl",
  "material_remap": {
    "TerrainPineBark": "materials/fixture.vmat"
  },
  "vmdl_material_source_suffix": "",
  "vmdl_use_global_default": false,
  "strict_vmdl_material_sources": true
}
'@ | Set-Content -LiteralPath $configPath -Encoding UTF8

            @'
<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc29:version{3cec427c-1b0e-4d48-a90a-0436f33a6041} -->
{
    rootNode =
    {
        _class = "RootNode"
        children =
        [
            {
                _class = "MaterialGroupList"
                children =
                [
                    {
                        _class = "DefaultMaterialGroup"
                        remaps =
                        [
                            {
                                from = "TerrainPineBark.vmat"
                                to = "materials/fixture.vmat"
                            },
                        ]
                        use_global_default = false
                    },
                ]
            },
            {
                _class = "RenderMeshList"
                children =
                [
                    {
                        _class = "RenderMeshFile"
                        filename = "models/source.fbx"
                    },
                ]
            },
        ]
    }
}
'@ | Set-Content -LiteralPath $vmdlPath -Encoding UTF8

            & powershell -NoProfile -ExecutionPolicy Bypass -File $fbxMaterialSlotAudit -Root $tempRoot -Config $configPath | Out-Host
            if ($LASTEXITCODE -eq 0) {
                Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/fbx_material_slot_audit.ps1" "FBX material slot audit did not fail on a .vmat-suffixed VMDL source against raw FBX slots." "Keep the fixture red/green test aligned with the terrain texture regression."
            }

            (Get-Content -LiteralPath $vmdlPath -Raw).Replace('from = "TerrainPineBark.vmat"', 'from = "TerrainPineBark"') | Set-Content -LiteralPath $vmdlPath -Encoding UTF8
            & powershell -NoProfile -ExecutionPolicy Bypass -File $fbxMaterialSlotAudit -Root $tempRoot -Config $configPath | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/fbx_material_slot_audit.ps1" "FBX material slot audit failed on a raw VMDL source matching the exported FBX slot." "Avoid false positives for valid terrain-style raw material remaps."
            }
        }
        finally {
            if ([System.IO.Directory]::Exists($tempRoot)) {
                [System.IO.Directory]::Delete($tempRoot, $true)
            }
        }
    }
    else {
        Add-AgentIssue $issues "Info" "Full Automation Tests" "scripts/agents/fbx_material_slot_audit.ps1" "Skipped FBX material-slot fixture because Blender or terrain_assets.fbx is unavailable."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
