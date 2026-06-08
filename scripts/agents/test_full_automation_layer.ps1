param(
    [string]$Root = "",
    [switch]$ProjectSmoke
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

function Invoke-AgentExpectedFailureFixture {
    param(
        [string]$ScriptPath,
        [string[]]$ScriptArgs,
        [string]$Label,
        [string]$SourcePath
    )

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $output | ForEach-Object { Write-Host $_ }
        return $exitCode
    }

    $blockingLines = @($output | Where-Object { $_ -match '^\[(Error|Warning)\]' })
    if ($blockingLines.Count -eq 0) {
        $output | ForEach-Object { Write-Host $_ }
        Add-AgentIssue $script:issues "Error" "Full Automation Tests" $SourcePath "Expected-failure fixture '$Label' exited with $exitCode but did not emit an audit issue line." "Keep red fixtures explicit so script crashes do not masquerade as expected audit failures."
        return $exitCode
    }

    Write-Host "[Info] Expected-failure fixture '$Label' produced $($blockingLines.Count) audit issue line(s)."
    return $exitCode
}

$requiredScripts = @(
    "scripts/agents/ui_flow_audit.ps1",
    "scripts/agents/prefab_wiring_audit.ps1",
    "scripts/agents/prefab_graph_audit.ps1",
    "scripts/agents/first_person_viewmodel_prefab_audit.ps1",
    "scripts/agents/grenade_effect_prefab_audit.ps1",
    "scripts/agents/migrate_scene_singletons_to_prefab_instances.ps1",
    "scripts/agents/muzzle_flash_prefab_audit.ps1",
    "scripts/agents/runtime_prefab_fallback_audit.ps1",
    "scripts/agents/scene_prefab_coverage_audit.ps1",
    "scripts/agents/scene_singleton_prefab_audit.ps1",
    "scripts/agents/team_comms_prefab_audit.ps1",
    "scripts/agents/team_voice_prefab_audit.ps1",
    "scripts/agents/terrain_scene_prefab_migration_audit.ps1",
    "scripts/agents/thrown_grenade_projectile_prefab_audit.ps1",
    "scripts/agents/training_dummy_prefab_audit.ps1",
    "scripts/agents/scene_integrity_audit.ps1",
    "scripts/agents/terrain_floor_audit.ps1",
    "scripts/agents/sandbag_cover_audit.ps1",
    "scripts/agents/road_cover_barrier_audit.ps1",
    "scripts/agents/road_lane_marking_audit.ps1",
    "scripts/agents/road_edge_wear_audit.ps1",
    "scripts/agents/burnt_vehicle_block_audit.ps1",
    "scripts/agents/collision_authoring_agent.ps1",
    "scripts/agents/tree_collision_audit.ps1",
    "scripts/agents/collision_agent_chain_audit.ps1",
    "scripts/agents/collision_chain_report.ps1",
    "scripts/agents/model_collision_scale_audit.ps1",
    "scripts/model_collision_scale_audit.py",
    "scripts/agents/current_log_audit.ps1",
    "scripts/agents/feature_readiness_report.ps1",
    "scripts/agents/post_task_training_agent.ps1",
    "scripts/agents/gameplay_regression_guard.ps1",
    "scripts/check_round_reprompt_flow.ps1",
    "scripts/agents/aaa_asset_quality_audit.ps1",
    "scripts/agents/blender_quality_audit.ps1",
    "scripts/agents/material_texture_audit.ps1",
    "scripts/agents/drone_variant_visual_audit.ps1",
    "scripts/agents/modeldoc_audit.ps1",
    "scripts/agents/fbx_material_slot_audit.ps1",
    "scripts/agents/sound_asset_audit.ps1",
    "scripts/agents/ambient_noise_audit.ps1",
    "scripts/agents/sound_playback_audit.ps1",
    "scripts/agents/team_label_copy_audit.ps1",
    "scripts/agents/mcp_screenshot_audit.ps1",
    "scripts/agents/sbox_docs_source_audit.ps1",
    "scripts/agents/sbox_engine_reference_audit.ps1",
    "scripts/agents/sbox_release_notes_audit.ps1",
    "scripts/agents/sbox_code_search_audit.ps1",
    "scripts/agents/sbox_api_lookup.ps1",
    "scripts/agents/sbox_api_reference_audit.ps1",
    "scripts/agents/sbox_learn_intake_audit.ps1",
    "scripts/agents/animated_model_intake_audit.ps1",
    "scripts/agents/editor_node_tool_audit.ps1",
    "scripts/agents/editor_first_workflow_audit.ps1",
    "scripts/agents/asset_visual_review.ps1",
    "scripts/agents/blender_live_toolkit_self_test.ps1"
)

# Release-notes audit coverage marker: S&Box Release Notes Intake Agent
# https://sbox.game/release-notes is protected by the "release-notes" suite and sbox_release_notes_audit.ps1.
# Code Search audit coverage marker: S&Box Code Search Agent
# https://sbox.game/codesearch is protected by the "code-search" suite and sbox_code_search_audit.ps1.
# Animated model import coverage marker: S&Box Animated Model Intake Agent
# Editor-first AnimGraph and sequence proof is protected by the "animated-model" suite and animated_model_intake_audit.ps1.

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

    foreach ($suite in @("ui", "prefab-graph", "scene", "terrain", "logs", "readiness", "train", "asset-production", "modeldoc", "animated-model", "blender-live", "gameplay-regression", "sound", "collision", "collision-chain", "api", "sbox-docs", "release-notes", "code-search", "learn", "editor-node-tool", "editor-first")) {
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

$aaaAssetQualityAudit = Join-Path $Root "scripts/agents/aaa_asset_quality_audit.ps1"
if (Test-Path -LiteralPath $aaaAssetQualityAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-aaa-asset-quality-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        @'
{
  "weapon": {
    "required_material_roles": ["metal"],
    "optional_texture_maps": ["TextureNormal"],
    "required_name_hints": ["muzzle"],
    "quality_targets": ["Readable silhouette"],
    "visual_review_checks": ["Preview render"],
    "acceptance_checks": ["Socket documented"]
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\asset_quality_profiles.json") -Encoding UTF8
        "Reference Requirements Production Quality Targets Visual Review Plan reference_requirements quality_targets visual_review_checks" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\new_asset_brief.ps1") -Encoding UTF8
        "blender-quality-agent.md material-texture-agent.md visual-review-agent.md asset-pipeline-agent.md modeldoc-agent.md aaa_asset_quality_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\aaa-asset-quality-agent.md") -Encoding UTF8
        "AAA Asset Quality Agent aaa_asset_quality_audit.ps1 Production Quality Targets" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "aaa-asset-quality-agent.md aaa_asset_quality_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        '"asset-production" aaa_asset_quality_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "aaa_asset_quality_audit.ps1 reference_requirements Production Quality Targets" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $aaaAssetQualityAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete AAA asset quality profile" -SourcePath "scripts/agents/aaa_asset_quality_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/aaa_asset_quality_audit.ps1" "AAA asset quality audit did not fail on an incomplete profile fixture." "Keep reference requirements, quality targets, visual review checks, and category coverage protected."
        }

        @'
{
  "weapon": {
    "required_material_roles": ["metal"],
    "optional_texture_maps": ["TextureNormal"],
    "required_name_hints": ["muzzle"],
    "reference_requirements": ["Reference sheet"],
    "quality_targets": ["Readable silhouette"],
    "visual_review_checks": ["Preview render"],
    "acceptance_checks": ["Socket documented"]
  },
  "drone": {
    "required_material_roles": ["frame"],
    "optional_texture_maps": ["TextureNormal"],
    "required_name_hints": ["prop"],
    "reference_requirements": ["Drone reference"],
    "quality_targets": ["Distance readability"],
    "visual_review_checks": ["Chase-camera preview"],
    "acceptance_checks": ["Variant identity documented"]
  },
  "character": {
    "required_material_roles": ["body"],
    "optional_texture_maps": ["TextureNormal"],
    "required_name_hints": ["root"],
    "reference_requirements": ["Character reference"],
    "quality_targets": ["Gear breakup"],
    "visual_review_checks": ["Prefab preview"],
    "acceptance_checks": ["Rig assumptions documented"]
  },
  "environment": {
    "required_material_roles": ["surface"],
    "optional_texture_maps": ["TextureNormal"],
    "required_name_hints": ["root"],
    "reference_requirements": ["Environment reference"],
    "quality_targets": ["Ground and drone readability"],
    "visual_review_checks": ["S&Box lighting screenshot"],
    "acceptance_checks": ["Collision expectations documented"]
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\asset_quality_profiles.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $aaaAssetQualityAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/aaa_asset_quality_audit.ps1" "AAA asset quality audit failed on complete routing fixtures." "Avoid false positives for complete production asset quality wiring."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$gameplayRegressionGuard = Join-Path $Root "scripts/agents/gameplay_regression_guard.ps1"
if (Test-Path -LiteralPath $gameplayRegressionGuard) {
    $gameplayRegressionText = Get-Content -LiteralPath $gameplayRegressionGuard -Raw
    if ($gameplayRegressionText -notmatch [regex]::Escape("scripts\check_round_reprompt_flow.ps1")) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/gameplay_regression_guard.ps1" "Gameplay regression suite does not run the round re-prompt guard." "Wire scripts/check_round_reprompt_flow.ps1 into gameplay_regression_guard.ps1."
    }
}

$modelCollisionScaleAudit = Join-Path $Root "scripts/agents/model_collision_scale_audit.ps1"
if (Test-Path -LiteralPath $modelCollisionScaleAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-model-collision-scale-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\models") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null
        Copy-Item -LiteralPath (Join-Path $Root "scripts\agents\agent_common.ps1") -Destination (Join-Path $tempRoot "scripts\agents\agent_common.ps1") -Force
        Copy-Item -LiteralPath (Join-Path $Root "scripts\model_collision_scale_audit.py") -Destination (Join-Path $tempRoot "scripts\model_collision_scale_audit.py") -Force

        @'
{
  "source_blend": "environment_model.blend/bad_sign.blend",
  "target_fbx": "Assets/models/bad_sign.fbx",
  "target_vmdl": "Assets/models/bad_sign.vmdl",
  "audit_render_bounds": { "size": [31, 418, 231] },
  "physics_shapes": [
    {
      "type": "box",
      "origin": [0, 0, 0],
      "dimensions": [4.35, 0.18, 2.35],
      "surface_prop": "wood",
      "collision_tags": "solid"
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\bad_sign_asset_pipeline.json") -Encoding UTF8
        @'
<!-- kv3 encoding:text:version{fixture} format:modeldoc29:version{fixture} -->
{
    rootNode =
    {
        _class = "RootNode"
        children =
        [
            {
                _class = "RenderMeshFile"
                filename = "models/bad_sign.fbx"
                import_scale = 1.0
            },
            {
                _class = "PhysicsShapeList"
                children =
                [
                    {
                        _class = "PhysicsShapeBox"
                        parent_bone = ""
                        surface_prop = "wood"
                        collision_tags = "solid"
                        origin = [ 0.0, 0.0, 0.0 ]
                        dimensions = [ 4.35, 0.18, 2.35 ]
                    },
                ]
            },
        ]
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\models\bad_sign.vmdl") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $modelCollisionScaleAudit -ScriptArgs @("-Root", $tempRoot) -Label "primitive collider uses Blender-meter dimensions instead of source-unit mesh bounds" -SourcePath "scripts/agents/model_collision_scale_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/model_collision_scale_audit.ps1" "Collision-scale audit did not fail on a deliberately 100x-small primitive collider fixture." "Compare ModelCollider/physics bounds against ModelRenderer/source mesh bounds so Blender-meter primitive dimensions cannot ship."
        }

        Remove-Item -LiteralPath (Join-Path $tempRoot "scripts\bad_sign_asset_pipeline.json") -Force
        Remove-Item -LiteralPath (Join-Path $tempRoot "Assets\models\bad_sign.vmdl") -Force

        @'
{
  "source_blend": "environment_model.blend/good_sign.blend",
  "target_fbx": "Assets/models/good_sign.fbx",
  "target_vmdl": "Assets/models/good_sign.vmdl",
  "audit_render_bounds": { "size": [31, 418, 231] },
  "collision": {
    "mode": "render_mesh",
    "surface_prop": "wood",
    "collision_tags": "solid"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\good_sign_asset_pipeline.json") -Encoding UTF8
        @'
<!-- kv3 encoding:text:version{fixture} format:modeldoc29:version{fixture} -->
{
    rootNode =
    {
        _class = "RootNode"
        children =
        [
            {
                _class = "RenderMeshFile"
                filename = "models/good_sign.fbx"
                import_scale = 1.0
            },
            {
                _class = "PhysicsShapeList"
                children =
                [
                    {
                        _class = "PhysicsMeshFile"
                        name = "collision"
                        parent_bone = ""
                        surface_prop = "wood"
                        collision_tags = "solid"
                        filename = "models/good_sign.fbx"
                        import_scale = 1.0
                    },
                ]
            },
        ]
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\models\good_sign.vmdl") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $modelCollisionScaleAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/model_collision_scale_audit.ps1" "Collision-scale audit failed on a render_mesh fixture with matching render and collision mesh bounds." "Avoid false positives for solid props using render_mesh collision."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$collisionChainAudit = Join-Path $Root "scripts/agents/collision_agent_chain_audit.ps1"
if (Test-Path -LiteralPath $collisionChainAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-collision-agent-chain-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        "# Incomplete" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-chain-agent.md") -Encoding UTF8
        @'
param(
    [ValidateSet("collision-chain")]
    [string]$Suite = "collision-chain"
)
switch ($Suite) {
    "collision-chain" {
        $scripts = @(
            @{ Name = "collision_agent_chain_audit.ps1" },
            @{ Name = "collision_chain_report.ps1" }
        )
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "collision-chain-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "Collision Agent Chain" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionChainAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete collision chain role docs" -SourcePath "scripts/agents/collision_agent_chain_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_agent_chain_audit.ps1" "Collision chain audit did not fail on incomplete role docs." "Keep the chain audit strict enough to catch missing subagent prompts."
        }

        @'
# Collision Chain Agent

## Purpose

Fixture chain doc.

## Role Stack

Default flow: Coordinator -> Explorer -> Implementer -> Verifier -> Critic.

### Coordinator
Coordinates.

### Explorer
Explores.

### Implementer
Implements.

### Verifier
Verifies.

### Critic
Critiques.

## Handoff Protocol

- `Status`: `PASS`, `REWORK`, `BLOCKED`, or `OUT_OF_SCOPE`.

## Rework Loop

Do not run an endless loop.

## Collision Acceptance Rules

Rules exist.

## Evidence Commands

Commands exist.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-chain-agent.md") -Encoding UTF8
        @'
# Collision Explorer Agent

## Purpose
Explore.

## Role
You are a read-only Codex explorer.

## Inputs
Inputs.

## Work
Do not edit files.

## Output Shape
Collision Contract Hotspots Suggested Next Handoff
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-explorer-agent.md") -Encoding UTF8
        @'
# Collision Implementer Agent

## Purpose
Implement.

## Role
Do not revert edits made by others.

## Inputs
owned file paths

## Work
Work.

## Output Shape
Changed Files Verification Next Handoff
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-implementer-agent.md") -Encoding UTF8
        @'
# Collision Verifier Agent

## Purpose
Verify.

## Role
Verify.

## Inputs
Inputs.

## Work
Run collision-chain and send to collision-critic-agent.md. Treat stale or unrelated logs as limits.

## Output Shape
Evidence Runtime Gaps
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-verifier-agent.md") -Encoding UTF8
        @'
# Collision Critic Agent

## Purpose
Critique.

## Role
Use defect-first review.

## Inputs
Inputs.

## Review Rules
Distinguish confirmed defects from untested runtime gaps.

## Output Shape
Findings Evidence Gaps Next Handoff
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-critic-agent.md") -Encoding UTF8
        @'
# Collision Authoring Agent

## Purpose
Authoring.

## Primary Areas
Areas.

## Review Rules
Collision_* LadderVolume water tower building root

## Evidence Command
Command.

## Runtime Proof
Static checks prove the authored collision exists.

## Output Shape
Output.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\collision-authoring-agent.md") -Encoding UTF8
        "collision-chain-agent.md collision-explorer-agent.md collision-implementer-agent.md collision-verifier-agent.md collision-critic-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "Collision Agent Chain Collision Explorer Agent Collision Implementer Agent Collision Verifier Agent Collision Critic Agent collision_chain_report.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "Authored Prop Collision Alignment collision-chain-agent.md Codex explorer defines the collision contract" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionChainAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_agent_chain_audit.ps1" "Collision chain audit failed on complete role docs." "Avoid false positives for valid subagent-chain documentation."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$requiredMcpSources = @(
    "Libraries/jtc.mcp-server/Editor/Handlers/SoundHandler.cs",
    "Libraries/jtc.mcp-server/Editor/Handlers/ControlPlaneHandler.cs",
    "Libraries/jtc.mcp-server/Editor/Mcp/Tools/SoundTools.cs",
    "Libraries/jtc.mcp-server/Editor/Mcp/Tools/ControlPlaneTools.cs"
)

foreach ($source in $requiredMcpSources) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $source))) {
        Add-AgentIssue $issues "Error" "Full Automation Tests" $source "Required native editor control-plane source is missing." "Add the MCP handler/tool source file."
    }
}

$editorFirstAudit = Join-Path $Root "scripts/agents/editor_first_workflow_audit.ps1"
if (Test-Path -LiteralPath $editorFirstAudit) {
    $editorFirstAuditText = Get-Content -LiteralPath $editorFirstAudit -Raw
    foreach ($marker in @("Editor-First Workflow Audit", "editor-first-workflow-agent.md", "control_plane_status", "tools/list", "editor_save_scene", "sbox-editor-first-workflow-check")) {
        if ($editorFirstAuditText -notmatch [regex]::Escape($marker)) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/editor_first_workflow_audit.ps1" "Editor-first workflow audit is missing marker '$marker'." "Keep the audit strict enough to protect live-editor-first routing, capability checks, save proof, and hook wiring."
        }
    }
}

$droneVariantVisualAudit = Join-Path $Root "scripts/agents/drone_variant_visual_audit.ps1"
if (Test-Path -LiteralPath $droneVariantVisualAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-drone-variant-visual-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\prefabs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\models") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\materials") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\Player") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "drone_model.blend") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        @'
{
  "RootObject": {
    "Name": "Drone (FPV)",
    "Children": [
      {
        "Name": "Visual",
        "Components": [
          {
            "__type": "Sandbox.ModelRenderer",
            "Model": "models/drone_high.vmdl"
          }
        ]
      }
    ]
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\prefabs\drone_fpv.prefab") -Encoding UTF8
        'public string FpvHeldDroneModelPath { get; set; } = "models/drone_high.vmdl";' | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Player\DroneDeployer.cs") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $droneVariantVisualAudit -ScriptArgs @("-Root", $tempRoot) -Label "FPV reuses shared GPS visual model" -SourcePath "scripts/agents/drone_variant_visual_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/drone_variant_visual_audit.ps1" "Drone variant visual audit did not fail when the FPV prefab reused the shared GPS body." "Keep the fixture red/green test aligned with the separate-variant model contract."
        }

        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "drone_model.blend\drone_fpv.blend") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\drone_fpv.fbx") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\drone_fpv.vmdl") | Out-Null
        '"Layer0" { "TextureColor" "materials/drone_fpv_motor_color.png" }' | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\materials\drone_fpv_motor.vmat") -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\drone_fpv_motor_color.png") | Out-Null

        @'
{
  "RootObject": {
    "Name": "Drone (FPV)",
    "Children": [
      {
        "Name": "Visual",
        "Components": [
          {
            "__type": "Sandbox.ModelRenderer",
            "Model": "models/drone_fpv.vmdl"
          }
        ]
      }
    ]
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\prefabs\drone_fpv.prefab") -Encoding UTF8
        @'
public string FpvHeldDroneModelPath { get; set; } = "models/drone_fpv.vmdl";
public string FiberHeldDroneModelPath { get; set; } = "models/drone_fpv_fiber.vmdl";
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Player\DroneDeployer.cs") -Encoding UTF8
        @'
{
  "source_blend": "drone_model.blend/drone_fpv.blend",
  "target_fbx": "Assets/models/drone_fpv.fbx",
  "target_vmdl": "Assets/models/drone_fpv.vmdl",
  "model_resource_path": "models/drone_fpv.vmdl",
  "material_remap": {
    "Motor_Aluminum": "materials/drone_fpv_motor.vmat"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\drone_fpv_asset_pipeline.json") -Encoding UTF8

        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "drone_model.blend\drone_fpv_fiber.blend") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\drone_fpv_fiber.fbx") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\models\drone_fpv_fiber.vmdl") | Out-Null
        '"Layer0" { "TextureColor" "materials/drone_fpv_fiber_motor_color.png" }' | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\materials\drone_fpv_fiber_motor.vmat") -Encoding UTF8
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\materials\drone_fpv_fiber_motor_color.png") | Out-Null

        @'
{
  "RootObject": {
    "Name": "Drone (Fiber-Optic FPV)",
    "Children": [
      {
        "Name": "Visual",
        "Components": [
          {
            "__type": "Sandbox.ModelRenderer",
            "Model": "models/drone_fpv_fiber.vmdl"
          }
        ]
      }
    ]
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\prefabs\drone_fpv_fiber.prefab") -Encoding UTF8
        @'
{
  "source_blend": "drone_model.blend/drone_fpv_fiber.blend",
  "target_fbx": "Assets/models/drone_fpv_fiber.fbx",
  "target_vmdl": "Assets/models/drone_fpv_fiber.vmdl",
  "model_resource_path": "models/drone_fpv_fiber.vmdl",
  "material_remap": {
    "Motor_Aluminum": "materials/drone_fpv_fiber_motor.vmat"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\drone_fpv_fiber_asset_pipeline.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $droneVariantVisualAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/drone_variant_visual_audit.ps1" "Drone variant visual audit failed on a valid FPV visual-contract fixture." "Avoid false positives for a distinct source blend, VMDL, prefab body model, motor material, and held preview path."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

if ($ProjectSmoke) {
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
}
else {
    Write-Host "[Info] Project smoke pass skipped; run test_full_automation_layer.ps1 -ProjectSmoke or run_agent_checks.ps1 -Suite full for current-project audit execution."
}

$soundAudit = Join-Path $Root "scripts/agents/sound_asset_audit.ps1"
if (Test-Path -LiteralPath $soundAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-sound-asset-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\sounds") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $soundPath = Join-Path $tempRoot "Assets\sounds\bad_missing_source.sound"
        @'
{
  "UI": false,
  "Volume": "1",
  "Pitch": "1",
  "Decibels": 58,
  "SelectionMode": "Random",
  "Sounds": [ "sounds/missing_source.wav" ],
  "DistanceAttenuation": true,
  "Distance": 1200,
  "__version": 1
}
'@ | Set-Content -LiteralPath $soundPath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $soundAudit -ScriptArgs @("-Root", $tempRoot) -Label "missing SoundEvent source" -SourcePath "scripts/agents/sound_asset_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sound_asset_audit.ps1" "Sound asset audit did not fail on a .sound file with a missing WAV source." "Keep the fixture red/green test aligned with the raw-audio wrapper regression."
        }

        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "Assets\sounds\missing_source.wav") | Out-Null
        & powershell -NoProfile -ExecutionPolicy Bypass -File $soundAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sound_asset_audit.ps1" "Sound asset audit failed on a .sound file with an existing WAV source." "Avoid false positives for valid SoundEvent wrappers."
        }

        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code") | Out-Null
        $fakeSboxRoot = Join-Path $tempRoot "FakeSbox"
        $mountedSoundDir = Join-Path $fakeSboxRoot "download\assets\gameplay\equipment\weapons\m4a1\sounds"
        New-Item -ItemType Directory -Force -Path $mountedSoundDir | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $mountedSoundDir "m4_shot.abc123.sound_c") | Out-Null
        @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputPath>$($fakeSboxRoot.Replace("\", "/"))/.vs/output/</OutputPath>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\dronevsplayers.csproj") -Encoding UTF8
        'class UsesMountedSound { const string Shot = "gameplay/equipment/weapons/m4a1/sounds/m4_shot.sound"; }' | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UsesMountedSound.cs") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $soundAudit -ScriptArgs @("-Root", $tempRoot) -Label "direct mounted SoundEvent reference" -SourcePath "scripts/agents/sound_asset_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sound_asset_audit.ps1" "Sound asset audit did not fail on a direct mounted SoundEvent fixture." "Keep gameplay code, prefabs, and scenes pointed at local Assets/sounds wrappers; import stock audio into local wrappers instead of committing mounted package paths."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$uiAudit = Join-Path $Root "scripts/agents/ui_flow_audit.ps1"
if (Test-Path -LiteralPath $uiAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-ui-flow-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\UI") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\ui") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $hudStyles = @'
.team-choice { flex: 1 1 0; min-width: 0; align-items: center; text-align: center; }
.role-panel { align-items: center; text-align: center; }
.section-title { text-align: center; }
.options-panel { align-items: center; text-align: center; }
.option-row { flex-direction: column; align-items: center; justify-content: center; text-align: center; }
.option-copy { align-items: center; text-align: center; }
.options-actions { justify-content: center; }
.main-menu-title { top: 0; right: 0; bottom: 0; left: 0; justify-content: center; align-items: center; }
.main-menu-panel { position: absolute; top: 68%; }
.main-menu-scanline { animation: mainMenuScanUp 0.5s ease-in; }
@keyframes mainMenuScanUp { 0% { bottom: 0%; opacity: 1; } 100% { bottom: 104%; opacity: 0; } }
&.play-transition-exit { .main-menu-title { animation: mainMenuTitleExit 0.36s ease-out forwards; } .main-menu-panel { animation: mainMenuPanelExit 0.36s ease-out forwards; } }
@keyframes mainMenuPanelExit { 0% { opacity: 1; } 100% { opacity: 0; } }
.main-menu-title-text { font-size: 72px; font-weight: 900; }
'@
        $hudStyles | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.razor.scss") -Encoding UTF8
        $hudStyles | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.cs.scss") -Encoding UTF8
        $hudStyles | Set-Content -LiteralPath (Join-Path $tempRoot "Assets\ui\hudpanel.cs.scss") -Encoding UTF8

        $fixturePath = Join-Path $tempRoot "Code\UI\Fixture.razor"
        '<root><div class="choice pilot">Dead Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $uiAudit -ScriptArgs @("-Root", $tempRoot, "-FailOnWarning") -Label "dead interactive-looking Razor choice" -SourcePath "scripts/agents/ui_flow_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit did not fail on a dead interactive-looking fixture." "Keep the fixture red/green test aligned with the audit rules."
        }

        '<root><div class="choice pilot" onclick=@DoThing>Live Choice</div></root>' | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit failed on a fixture with an onclick handler." "Avoid false positives for valid clickable elements."
        }

        @'
@using Sandbox.UI;
@inherits Panel
<root><label>@Count</label></root>
@code {
    public int Count { get; set; }
}
'@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $uiAudit -ScriptArgs @("-Root", $tempRoot, "-FailOnWarning") -Label "dynamic Razor output without BuildHash" -SourcePath "scripts/agents/ui_flow_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit did not fail on dynamic Razor output without BuildHash." "Keep dynamic HUD and menu values tied to BuildHash so Razor refreshes intentionally."
        }

        @'
@using System;
@using Sandbox.UI;
@inherits Panel
<root><label>@Count</label></root>
@code {
    public int Count { get; set; }

    protected override int BuildHash() => HashCode.Combine( Count );
}
'@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $uiAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit failed on a dynamic Razor fixture with BuildHash." "Avoid false positives for correctly hashed Razor state."
        }

        @'
@using System;
@using Sandbox.UI;
@inherits Panel
<root><label>@Count</label></root>
@code {
    public int Count { get; set; }

    public override void Tick()
    {
        StateHasChanged();
    }

    protected override int BuildHash() => HashCode.Combine( Count );
}
'@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $uiAudit -ScriptArgs @("-Root", $tempRoot, "-FailOnWarning") -Label "StateHasChanged from Tick" -SourcePath "scripts/agents/ui_flow_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/ui_flow_audit.ps1" "UI flow audit did not fail on StateHasChanged() in Tick()." "Keep per-frame Razor rebuilds out of routine HUD and menu work."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$teamLabelAudit = Join-Path $Root "scripts/agents/team_label_copy_audit.ps1"
if (Test-Path -LiteralPath $teamLabelAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-team-label-copy-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\UI") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\Game") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        @'
<root>
    <div>ABOVE WINS</div>
    <div>BELOW WINS</div>
    <div>Take down above.</div>
    <div>Hunt below.</div>
    <span>Fly drones from above</span>
    <span>Fight from below</span>
    <div>@(LocalRole == PlayerRole.Pilot ? "ABOVE" : "BELOW")</div>
    <div>@(LocalRole == PlayerRole.Pilot ? "ABOVE" : LocalRole == PlayerRole.Soldier ? "BELOW" : "SPECTATOR")</div>
</root>
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.razor") -Encoding UTF8

        @'
public partial class HudPanel
{
    string LocalRoleLabel => LocalRole switch
    {
        PlayerRole.Pilot => "ABOVE",
        PlayerRole.Soldier => "BELOW",
        _ => "SPECTATOR",
    };
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.cs") -Encoding UTF8

        @'
<root>
    <div class="feature-title pilot">ABOVE</div>
    <div class="feature-title soldier">BELOW</div>
</root>
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\MainMenuPanel.razor") -Encoding UTF8

        @'
public sealed class RoundManager
{
    void BroadcastRoundEnd()
    {
        var label = winner == WinningSide.Pilot ? "ABOVE" : "BELOW";
        Log.Info($"[Round] {label} wins. Above {PilotWins} / Below {SoldierWins}");
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Game\RoundManager.cs") -Encoding UTF8

        "HUD labels still read **ABOVE** for pilots and **BELOW** for soldiers." | Set-Content -LiteralPath (Join-Path $tempRoot "README.md") -Encoding UTF8
        "Player-facing role names rebranded to ABOVE / BELOW." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\architecture.md") -Encoding UTF8
        "Above/Below team choices appear only after Play." | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\playtest_checklist.ps1") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $teamLabelAudit -ScriptArgs @("-Root", $tempRoot) -Label "stale Above/Below role copy" -SourcePath "scripts/agents/team_label_copy_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/team_label_copy_audit.ps1" "Team label audit did not fail on stale Above/Below role-copy fixtures." "Keep the fixture red/green test aligned with the player-facing label policy."
        }

        @'
<root>
    <span class="main-menu-title-text">ABOVE / BELOW</span>
    <div class="title">@RolePickerTitle</div>
    <div>DRONE PILOTS WIN</div>
    <div>HUNTERS WIN</div>
    <div>Find the hunters.</div>
    <div>Take down drone pilots.</div>
    <span>Fly drones as drone pilots</span>
    <span>Fight as hunters</span>
    <div>Select team</div>
    <div>Drone Pilot Loadout</div>
    <div>Hunters Loadout</div>
</root>
@code {
    string RolePickerTitle => "Select team";
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.razor") -Encoding UTF8

        @'
public partial class HudPanel
{
    string PilotRoleLabel => "DRONE PILOTS";
    string SoldierRoleLabel => "HUNTERS";
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.cs") -Encoding UTF8

        @'
<root>
    <div>A vertical asymmetric shooter about Drone Pilots and Hunters.</div>
    <div>Drone Pilots launch drones, swap into the camera, and pressure Hunters across the battlefield.</div>
    <div class="feature-title pilot">DRONE PILOTS</div>
    <div class="feature-title soldier">HUNTERS</div>
</root>
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\MainMenuPanel.razor") -Encoding UTF8

        @'
public sealed class RoundManager
{
    void BroadcastRoundEnd()
    {
        var label = winner == WinningSide.Pilot ? "Drone Pilots" : "Hunters";
        Log.Info($"[Round] {label} win. Drone Pilots {PilotWins} / Hunters {SoldierWins}");
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Game\RoundManager.cs") -Encoding UTF8

        "Player-facing team labels read **Drone Pilots** and **Hunters**; keep **ABOVE / BELOW** as the project title." | Set-Content -LiteralPath (Join-Path $tempRoot "README.md") -Encoding UTF8
        "Player-facing team labels use Drone Pilots and Hunters." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\architecture.md") -Encoding UTF8
        "Drone Pilots/Hunters team choices appear only after Play." | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\playtest_checklist.ps1") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $teamLabelAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/team_label_copy_audit.ps1" "Team label audit failed on valid Drone Pilots/Hunters fixtures." "Avoid false positives for the current player-facing label policy."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$prefabWiringAudit = Join-Path $Root "scripts/agents/prefab_wiring_audit.ps1"
if (Test-Path -LiteralPath $prefabWiringAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-prefab-wiring-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\prefabs") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $prefabPath = Join-Path $tempRoot "Assets\prefabs\BadLineRenderer.prefab"
        @'
{
  "RootObject": {
    "Name": "BadLineRenderer",
    "Components": [
      {
        "__type": "Sandbox.LineRenderer",
        "Color": {
          "color": "1,0.9,0.28,0.95",
          "useColor": true,
          "useGradient": false
        }
      }
    ],
    "Children": []
  }
}
'@ | Set-Content -LiteralPath $prefabPath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $prefabWiringAudit -ScriptArgs @("-Root", $tempRoot, "-OnlyLineRendererSerialization") -Label "legacy LineRenderer.Color serialization" -SourcePath "scripts/agents/prefab_wiring_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/prefab_wiring_audit.ps1" "Prefab wiring audit did not fail on a legacy LineRenderer.Color fixture." "Keep the fixture red/green test aligned with current S&Box LineRenderer serialization."
        }

        @'
{
  "RootObject": {
    "Name": "GoodLineRenderer",
    "Components": [
      {
        "__type": "Sandbox.LineRenderer",
        "UseVectorPoints": true,
        "Lighting": false
      }
    ],
    "Children": []
  }
}
'@ | Set-Content -LiteralPath $prefabPath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $prefabWiringAudit -Root $tempRoot -OnlyLineRendererSerialization | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/prefab_wiring_audit.ps1" "Prefab wiring audit failed on a LineRenderer fixture without legacy Color serialization." "Avoid false positives for valid LineRenderer prefab data."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$sceneAudit = Join-Path $Root "scripts/agents/scene_integrity_audit.ps1"
if (Test-Path -LiteralPath $sceneAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-scene-integrity-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\scenes") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $scenePath = Join-Path $tempRoot "Assets\scenes\main.scene"
        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" },
        { "__type": "DroneVsPlayers.HudPanel" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" }
      ],
      "Children": [
        {
          "Name": "WaterTower",
          "Components": [],
          "Children": [
            {
              "Name": "Visual",
              "Components": [
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" },
                { "__type": "Sandbox.ModelCollider", "Model": "models/watertower.vmdl", "IsTrigger": false, "Static": true }
              ],
              "Children": []
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "water tower without LadderVolume" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a water tower fixture without a LadderVolume." "Keep the fixture red/green test aligned with the water tower traversal regression."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" },
        { "__type": "DroneVsPlayers.HudPanel" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" }
      ],
      "Children": [
        {
          "Name": "WaterTower",
          "Components": [],
          "Children": [
            {
              "Name": "Visual",
              "Components": [
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Ladder",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": true, "Scale": "110,80,600" },
                { "__type": "DroneVsPlayers.LadderVolume", "AutoConfigureCollider": true, "TopExitLocalOffset": "0,60,272" }
              ],
              "Children": []
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "water tower without Visual ModelCollider" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a water tower fixture without a Visual ModelCollider." "Keep the fixture red/green test aligned with the water tower mesh-collision regression."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" },
        { "__type": "DroneVsPlayers.HudPanel" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" }
      ],
      "Children": [
        {
          "Name": "WaterTower",
          "Components": [],
          "Children": [
            { "Name": "Visual", "Rotation": "0,0,0,1", "Components": [ { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" }, { "__type": "Sandbox.ModelCollider", "Model": "models/watertower.vmdl", "IsTrigger": false, "Static": true } ], "Children": [] },
            { "Name": "Collision_Tank", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "660,660,230" } ], "Children": [] },
            { "Name": "Collision_Roof", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "600,600,80" } ], "Children": [] },
            { "Name": "Collision_Platform", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "760,760,34" } ], "Children": [] },
            { "Name": "Collision_Frame_North", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "560,48,420" } ], "Children": [] },
            { "Name": "Collision_Leg_NorthWest", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" } ], "Children": [] },
            { "Name": "Collision_Leg_NorthEast", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" } ], "Children": [] },
            { "Name": "Collision_Leg_SouthWest", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" } ], "Children": [] },
            { "Name": "Collision_Leg_SouthEast", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" } ], "Children": [] },
            { "Name": "Collision_Ladder", "Components": [ { "__type": "Sandbox.BoxCollider", "IsTrigger": true, "Scale": "110,80,600" }, { "__type": "DroneVsPlayers.LadderVolume", "AutoConfigureCollider": true, "TopExitLocalOffset": "0,60,272" } ], "Children": [] }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "broad lower-frame water tower collider" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a broad lower-frame water tower collider." "Keep the fixture red/green test aligned with the water tower invisible-collision regression."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" },
        { "__type": "DroneVsPlayers.HudPanel" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" }
      ],
      "Children": [
        {
          "Name": "WaterTower",
          "Components": [],
          "Children": [
            {
              "Name": "Visual",
              "Rotation": "0,0,0.131218359,0.991353512",
              "Components": [
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" },
                { "__type": "Sandbox.ModelCollider", "Model": "models/watertower.vmdl", "IsTrigger": false, "Static": true }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Tank",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "660,660,230" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Roof",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "600,600,80" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Platform",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "760,760,34" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_NorthWest",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_NorthEast",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_SouthWest",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_SouthEast",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Ladder",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": true, "Scale": "110,80,600" },
                { "__type": "DroneVsPlayers.LadderVolume", "AutoConfigureCollider": true, "TopExitLocalOffset": "0,60,272" }
              ],
              "Children": []
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "locally rotated water tower visual" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a water tower fixture with locally rotated visuals and unrotated collision." "Keep the fixture red/green test aligned with the water tower visual/collision alignment regression."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" },
        { "__type": "DroneVsPlayers.HudPanel" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" },
        { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" }
      ],
      "Children": [
        {
          "Name": "WaterTower",
          "Components": [],
          "Children": [
            {
              "Name": "Visual",
              "Rotation": "0,0,0,1",
              "Components": [
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" },
                { "__type": "Sandbox.ModelCollider", "Model": "models/watertower.vmdl", "IsTrigger": false, "Static": true }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Tank",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "660,660,230" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Roof",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "600,600,80" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Platform",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "760,760,34" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_NorthWest",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_NorthEast",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_SouthWest",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Leg_SouthEast",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": false, "Scale": "36,36,520" }
              ],
              "Children": []
            },
            {
              "Name": "Collision_Ladder",
              "Components": [
                { "__type": "Sandbox.BoxCollider", "IsTrigger": true, "Scale": "110,80,600" },
                { "__type": "DroneVsPlayers.LadderVolume", "AutoConfigureCollider": true, "TopExitLocalOffset": "0,60,272" }
              ],
              "Children": []
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sceneAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit failed on a water tower fixture with a trigger LadderVolume." "Avoid false positives for valid water tower ladder authoring."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "GameManager",
      "Components": [
        { "__type": "DroneVsPlayers.GameRules" },
        { "__type": "DroneVsPlayers.GameStats" },
        { "__type": "DroneVsPlayers.GameSetup" },
        { "__type": "DroneVsPlayers.RoundManager" },
        { "__type": "DroneVsPlayers.AutoWireHelper" }
      ],
      "Children": []
    },
    {
      "Name": "HUD",
      "Components": [
        { "__type": "DroneVsPlayers.HudPanel" }
      ],
      "Children": []
    },
    {
      "Name": "Spawns",
      "Components": [],
      "Children": [
        { "Name": "PilotSpawn", "Components": [ { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Pilot" } ], "Children": [] },
        { "Name": "SoldierSpawn", "Components": [ { "__type": "DroneVsPlayers.PlayerSpawn", "Role": "Soldier" } ], "Children": [] }
      ]
    },
    {
      "Name": "BlockoutMap",
      "Components": [],
      "Children": [
        {
          "Name": "NorthBoundary",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/dev/box.vmdl", "RenderType": "On" },
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" }
          ],
          "Children": []
        },
        {
          "Name": "SouthBoundary",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/dev/box.vmdl", "RenderType": "Off" },
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" },
            { "__type": "DroneVsPlayers.SelectedHierarchyColliderViewer", "AlwaysDraw": true, "IncludeTriggers": true }
          ],
          "Children": []
        },
        {
          "Name": "EastBoundary",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/dev/box.vmdl", "RenderType": "Off" },
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" },
            { "__type": "DroneVsPlayers.SelectedHierarchyColliderViewer", "AlwaysDraw": true, "IncludeTriggers": true }
          ],
          "Children": []
        },
        {
          "Name": "WestBoundary",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/dev/box.vmdl", "RenderType": "Off" },
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" },
            { "__type": "DroneVsPlayers.SelectedHierarchyColliderViewer", "AlwaysDraw": true, "IncludeTriggers": true }
          ],
          "Children": []
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "solid-rendered invisible boundary wall" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a boundary wall with RenderType On." "Keep boundary walls collider-backed and editor-wireframed, not solid-rendered in play."
        }

        $alwaysDrawFixture = (Get-Content -LiteralPath $scenePath -Raw).Replace('"RenderType": "On"', '"RenderType": "Off"')
        $alwaysDrawFixture | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sceneAudit -ScriptArgs @("-Root", $tempRoot) -Label "always-drawn invisible boundary wall" -SourcePath "scripts/agents/scene_integrity_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a boundary wall that always draws its collision viewer." "Keep invisible boundary walls fully hidden unless selected."
        }

        $validBoundaryFixture = (Get-Content -LiteralPath $scenePath -Raw).Replace('"AlwaysDraw": true', '"AlwaysDraw": false')
        $validBoundaryFixture = [regex]::Replace(
            $validBoundaryFixture,
            '"Sandbox\.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" \}',
            '"Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "50,50,50" }, { "__type": "DroneVsPlayers.SelectedHierarchyColliderViewer", "AlwaysDraw": false, "IncludeTriggers": true }',
            1
        )
        $validBoundaryFixture | Set-Content -LiteralPath $scenePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sceneAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit failed on a valid fully invisible boundary fixture." "Avoid false positives when boundary walls are hidden as renderers and collision viewers only draw on selection."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$collisionAudit = Join-Path $Root "scripts/agents/collision_authoring_agent.ps1"
if (Test-Path -LiteralPath $collisionAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-collision-authoring-agent-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Assets\scenes") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        $scenePath = Join-Path $tempRoot "Assets\scenes\main.scene"
        @'
{
  "GameObjects": [
    {
      "Name": "TestProp",
      "Children": [
        {
          "Name": "Collision_Block",
          "Components": [],
          "Children": []
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionAudit -ScriptArgs @("-Root", $tempRoot) -Label "Collision_* object without collider" -SourcePath "scripts/agents/collision_authoring_agent.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent did not fail on a Collision_* object without a BoxCollider." "Keep collision helper naming tied to actual collider authoring."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "TestProp",
      "Children": [
        {
          "Name": "Visual",
          "Rotation": "0,0,0.131218359,0.991353512",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/test.vmdl", "RenderType": "On" }
          ],
          "Children": []
        },
        {
          "Name": "Collision_Block",
          "Components": [
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "100,100,100" }
          ],
          "Children": []
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionAudit -ScriptArgs @("-Root", $tempRoot, "-FailOnWarning") -Label "locally rotated Visual beside collision helpers" -SourcePath "scripts/agents/collision_authoring_agent.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent did not flag a locally rotated Visual beside Collision_* children." "Keep the regression guard aligned with visual/collision transform drift."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "WaterTower",
      "Children": [
        { "Name": "Visual", "Rotation": "0,0,0,1", "Components": [ { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl", "RenderType": "On" } ], "Children": [] },
        { "Name": "Collision_Tank", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "660,660,230" } ], "Children": [] },
        { "Name": "Collision_Roof", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "600,600,80" } ], "Children": [] },
        { "Name": "Collision_Platform", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "760,760,34" } ], "Children": [] },
        { "Name": "Collision_Frame_North", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "560,48,420" } ], "Children": [] },
        { "Name": "Collision_Leg_NorthWest", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "36,36,520" } ], "Children": [] },
        { "Name": "Collision_Leg_NorthEast", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "36,36,520" } ], "Children": [] },
        { "Name": "Collision_Leg_SouthWest", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "36,36,520" } ], "Children": [] },
        { "Name": "Collision_Leg_SouthEast", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "36,36,520" } ], "Children": [] },
        { "Name": "Collision_Ladder", "Components": [ { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": true, "Static": true, "Scale": "110,80,600" }, { "__type": "DroneVsPlayers.LadderVolume", "AutoConfigureCollider": true, "TopExitLocalOffset": "0,60,272" } ], "Children": [] }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionAudit -ScriptArgs @("-Root", $tempRoot) -Label "broad lower-frame water tower collision" -SourcePath "scripts/agents/collision_authoring_agent.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent did not fail on a broad lower-frame water tower collider." "Keep the collision agent aligned with the water tower open-base regression."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "TestProp",
      "Children": [
        {
          "Name": "Visual",
          "Rotation": "0,0,0,1",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/test.vmdl", "RenderType": "On" }
          ],
          "Children": []
        },
        {
          "Name": "Collision_Block",
          "Components": [
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "100,100,100" }
          ],
          "Children": []
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent failed on a valid prop with identity Visual rotation and solid collision." "Avoid false positives for normal scene collision authoring."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "BlockoutMap",
      "Children": [
        {
          "Name": "Buildings",
          "Children": [
            {
              "Name": "House_Large_01",
              "Children": [
                {
                  "Name": "Model_Visual",
                  "Components": [
                    { "__type": "Sandbox.ModelRenderer", "Model": "models/house_large.vmdl", "RenderType": "On" }
                  ],
                  "Children": []
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionAudit -ScriptArgs @("-Root", $tempRoot) -Label "building renderer without authored collision" -SourcePath "scripts/agents/collision_authoring_agent.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent did not fail on a rendered building without authored collision coverage." "Keep building collision checks rooted at the building object, not the selected visual child."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "BlockoutMap",
      "Children": [
        {
          "Name": "Buildings",
          "Children": [
            {
              "Name": "House_Large_01",
              "Children": [
                {
                  "Name": "Model_Visual",
                  "Components": [
                    { "__type": "Sandbox.ModelRenderer", "Model": "models/house_large.vmdl", "RenderType": "On" }
                  ],
                  "Children": []
                },
                {
                  "Name": "Collision_Floor",
                  "Components": [
                    { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "100,100,24" }
                  ],
                  "Children": []
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent failed on a rendered building with sibling Collision_* coverage." "Allow Model_Visual children to remain renderer-only when the building root owns collision helpers."
        }

        @'
{
  "source_blend": "environment_model.blend/fixture.blend",
  "model_resource_path": "models/fixture_environment.vmdl",
  "target_vmdl": "Assets/models/fixture_environment.vmdl"
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\fixture_environment_asset_pipeline.json") -Encoding UTF8

        @'
{
  "GameObjects": [
    {
      "Name": "UncoveredEnvironmentModel",
      "Components": [
        { "__type": "Sandbox.ModelRenderer", "Model": "models/fixture_environment.vmdl", "RenderType": "On" }
      ],
      "Children": []
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $collisionAudit -ScriptArgs @("-Root", $tempRoot) -Label "Blender environment model without collision" -SourcePath "scripts/agents/collision_authoring_agent.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent did not fail on an environment Blender model without authored collision." "Keep direct scene Blender models covered by a BoxCollider or Collision_* helper."
        }

        @'
{
  "GameObjects": [
    {
      "Name": "CoveredEnvironmentModel",
      "Children": [
        {
          "Name": "Visual",
          "Components": [
            { "__type": "Sandbox.ModelRenderer", "Model": "models/fixture_environment.vmdl", "RenderType": "On" }
          ],
          "Children": []
        },
        {
          "Name": "Collision_Body",
          "Components": [
            { "__type": "Sandbox.BoxCollider", "Center": "0,0,0", "IsTrigger": false, "Static": true, "Scale": "100,100,100" }
          ],
          "Children": []
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $scenePath -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/collision_authoring_agent.ps1" "Collision authoring agent failed on an environment Blender model with sibling Collision_* coverage." "Allow normal Visual plus Collision_* prop authoring for Blender environment models."
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

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $prefabGraphAudit -ScriptArgs @("-Root", $tempRoot) -Label "protected multi-material prefab MaterialOverride" -SourcePath "scripts/agents/prefab_graph_audit.ps1"
        if ($fixtureExitCode -eq 0) {
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

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $modelDocAudit -ScriptArgs @("-Root", $tempRoot) -Label "missing VMDL source mesh" -SourcePath "scripts/agents/modeldoc_audit.ps1"
        if ($fixtureExitCode -eq 0) {
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

            $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $fbxMaterialSlotAudit -ScriptArgs @("-Root", $tempRoot, "-Config", $configPath) -Label "VMDL remap source with .vmat suffix" -SourcePath "scripts/agents/fbx_material_slot_audit.ps1"
            if ($fixtureExitCode -eq 0) {
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

$sboxEngineReferenceAudit = Join-Path $Root "scripts/agents/sbox_engine_reference_audit.ps1"
if (Test-Path -LiteralPath $sboxEngineReferenceAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-engine-reference-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        @'
# S&Box Engine LLM Reference

Verified against official sources on 2026-05-20:

- https://sbox.game/dev/doc
- https://github.com/Facepunch/sbox-docs
- https://github.com/Facepunch/sbox-public
- https://sbox.game/learn/facepunch/creating-an-entity-for-sandbox

Official docs source repo reviewed on 2026-05-27:
- https://github.com/Facepunch/sbox-docs
- sbox_docs_source_audit.ps1

Valve Developer Community Source 2 docs reviewed on 2026-05-27:
- Resourcecompiler
- MaterialGroups
- Postprocessing_Editor
- Nav_Mesh_Editing legacy Source/Counter-Strike context

Use `[Sync]` for replicated state.
Use ModelDoc for VMDL work.
Sandbox Entity `.sent` resources point at prefabs. Use ClientEditable and TimeSince when appropriate.

## Avoid Source 1 Habits

Do not use `.qc` model scripts as active S&Box guidance.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8

        @'
# S&Box Engine Reference Agent

## Purpose

Verify S&Box engine research.

Sources:
- https://sbox.game/dev/doc
- https://github.com/Facepunch/sbox-docs
- https://github.com/Facepunch/sbox-public
- Valve Developer Community Source 2
- Nav_Mesh_Editing legacy Source/Counter-Strike context
- sbox-docs-source-agent.md

Evidence:
scripts/agents/sbox_engine_reference_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8

        "S&Box Engine Reference Agent S&Box Docs Source Agent sbox_docs_source_audit.ps1 sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "Valve Source 2 Asset Pipeline Intake; Valve Nav Mesh Docs Are Legacy For S&Box" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "sbox-engine-reference-agent.md sbox-docs-source-agent.md sbox_docs_source_audit.ps1 sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "sbox_docs_source_audit.ps1 sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_docs_source_audit.ps1 sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "sbox_docs_source_audit.ps1 sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8

        "Use [Net] for replicated S&Box gameplay state." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxEngineReferenceAudit -ScriptArgs @("-Root", $tempRoot) -Label "stale [Net] engine guidance" -SourcePath "scripts/agents/sbox_engine_reference_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit did not fail on active stale [Net] guidance." "Keep the fixture red/green test aligned with current S&Box [Sync] guidance."
        }

        "Use [Sync] for replicated S&Box gameplay state." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxEngineReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit failed on valid [Sync] guidance and complete routing docs." "Avoid false positives for current, sourced S&Box reference guidance."
        }

        "Run nav_generate and nav_edit to build S&Box bot navigation." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxEngineReferenceAudit -ScriptArgs @("-Root", $tempRoot, "-FailOnWarning") -Label "active legacy nav mesh guidance" -SourcePath "scripts/agents/sbox_engine_reference_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit did not fail on active nav_generate/nav_edit S&Box guidance." "Keep Valve nav mesh docs marked as legacy Source/Counter-Strike context for this project."
        }

        "Use S&Box navigation through Recast and Scene.NavMesh." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxEngineReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit failed on valid Scene.NavMesh guidance after the nav fixture." "Avoid false positives for current S&Box Recast navigation guidance."
        }

        "Create a .qc file for this S&Box model." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxEngineReferenceAudit -ScriptArgs @("-Root", $tempRoot) -Label "active .qc model guidance" -SourcePath "scripts/agents/sbox_engine_reference_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit did not fail on active .qc model guidance." "Keep Source 1 model workflow references marked as historical or avoided."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$sboxLearnIntakeAudit = Join-Path $Root "scripts/agents/sbox_learn_intake_audit.ps1"
if (Test-Path -LiteralPath $sboxLearnIntakeAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-learn-intake-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".claude") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        "S&Box Learn was reviewed." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "S&Box Engine Reference Agent" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-learn-intake-agent.md") -Encoding UTF8
        "UI Flow Agent" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\ui-razor-reactivity-agent.md") -Encoding UTF8
        "BuildHash" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\ui-flow-agent.md") -Encoding UTF8
        "scripts/agents/ui_flow_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\ui_flow_audit.ps1") -Encoding UTF8
        "S&Box Learn Intake Agent" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-learn-intake-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        '"learn"' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_learn_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "sbox_learn_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxLearnIntakeAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete Learn intake routing" -SourcePath "scripts/agents/sbox_learn_intake_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_learn_intake_audit.ps1" "Learn intake audit did not fail on incomplete routing fixtures." "Keep the fixture strict enough to catch missing Learn agents, subagent, hook, and UI audit wiring."
        }

        @'
# S&Box Engine LLM Reference

Secondary community tutorial context reviewed on 2026-05-23:

- https://sbox.game/learn
- https://sbox.game/learn/tesa/ui-buildhash
- https://sbox.game/learn/gibbard/networked-variable-ui

Official editor docs reviewed on 2026-05-25:

- https://sbox.game/dev/doc/editor/

## Editor Tooling And Inspector Workflows

Use UndoScope, EditorEvent, AssetPreview, and TextureGenerator guidance for editor workflow training.

Use BuildHash() for dynamic Razor UI and do not call StateHasChanged() from Tick().
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8

        @'
# S&Box Learn Intake Agent

## Purpose

Route S&Box Learn tutorial context and official editor-doc sweeps.

Sources:
- https://sbox.game/learn
- https://sbox.game/dev/doc/editor/

Evidence:
scripts/agents/sbox_learn_intake_audit.ps1
ui-razor-reactivity-agent.md
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-learn-intake-agent.md") -Encoding UTF8

        @'
# UI Razor Reactivity Agent

## Purpose

Review [Sync] UI values for BuildHash() coverage and avoid StateHasChanged() in Tick().

Evidence:
scripts/agents/ui_flow_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\ui-razor-reactivity-agent.md") -Encoding UTF8

        @'
# Editor Node Tool Agent

## Purpose

Review S&Box Learn Node Editor examples.

Sources:
- https://sbox.game/learn/aqua/node-editor-01

Evidence:
GraphView
IPlug
scripts/agents/editor_node_tool_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\editor-node-tool-agent.md") -Encoding UTF8

        "BuildHash() StateHasChanged()" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\ui-flow-agent.md") -Encoding UTF8
        "Test-InheritsRazorPanel Test-HasDynamicRazorOutput Test-HasBuildHash Test-CallsStateHasChangedFromTick Dynamic Razor output has no BuildHash Razor Tick() calls StateHasChanged()" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\ui_flow_audit.ps1") -Encoding UTF8
        "S&Box Learn Intake Agent UI Razor Reactivity Agent Editor Node Tool Agent sbox_learn_intake_audit.ps1 ui-razor-reactivity-agent.md editor-node-tool-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-learn-intake-agent.md ui-razor-reactivity-agent.md editor-node-tool-agent.md sbox_learn_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        '"learn" sbox_learn_intake_audit.ps1 editor_node_tool_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_learn_intake_audit.ps1 S&Box Learn Intake Agent https://sbox.game/dev/doc/editor/ UI Razor Reactivity Agent editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "LearnResearch EditorNodeTools sbox_learn_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[{"id":"sbox-learn-intake-check","action":{"args":["-Suite","learn",".\\scripts\\agents\\sbox_learn_intake_audit.ps1"]}}]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxLearnIntakeAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_learn_intake_audit.ps1" "Learn intake audit failed on complete routing fixtures." "Avoid false positives for valid Learn intake workflow wiring."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$sboxReleaseNotesAudit = Join-Path $Root "scripts/agents/sbox_release_notes_audit.ps1"
if (Test-Path -LiteralPath $sboxReleaseNotesAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-release-notes-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".claude") | Out-Null

        "https://sbox.game/release-notes" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "S&Box Release Notes Intake Agent" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-release-notes-agent.md") -Encoding UTF8
        "https://sbox.game/release-notes" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8
        "Official S&Box Release Notes Intake" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "S&Box Release Notes Intake Agent" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-release-notes-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "S&Box release notes" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        '"release-notes"' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_release_notes_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "ReleaseNotesResearch" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxReleaseNotesAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete release-notes intake routing" -SourcePath "scripts/agents/sbox_release_notes_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_release_notes_audit.ps1" "Release-notes audit did not fail on incomplete routing fixtures." "Keep the fixture strict enough to catch missing release-note docs, agent, hook, suite, and self-test wiring."
        }

        @'
# S&Box Engine LLM Reference

Official S&Box release notes reviewed on 2026-06-04:

- https://sbox.game/release-notes
- https://sbox.game/news/update-26-06-03
- https://sbox.game/api/changes
- 26.06.03
- Mesh.AddMorph
- Mesh.AddSubMesh
- MorphDelta
- CreateModelFromMeshDialog
- ResourceWriter.AddExternalReference
- Connection.Name
- Connection.DisplayName

Use HasTag() on trace results. Route chat through IChatEvent. Custom panel drawing can use IPanelDraw. Voice Mixer owns voice transmission. TerrainStorage.SetResolution() is the terrain resolution workflow. Scene.Trace.Cone and Rigidbody.SleepThreshold are available after API verification. VMDL writer now also saves the PHYS block. Physical sound simulation changes sound proof expectations. UI mixer routing matters for 2D cues. Modern UI CSS features such as clamp() and :has() are available. Mesh.AddSubMesh stays pending when the local API dump does not expose the exact member.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8

        @'
# S&Box Release Notes Intake Agent

## Purpose

Review official release notes.

Sources:
- https://sbox.game/release-notes
- https://sbox.game/api/changes

If the local dump does not expose a named symbol, keep it pending.

Evidence:
- sbox_api_lookup.ps1
- sbox_release_notes_audit.ps1
- sbox-learn-intake-agent.md
- sbox-engine-reference-agent.md
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-release-notes-agent.md") -Encoding UTF8

        "https://sbox.game/release-notes https://sbox.game/api/changes sbox-release-notes-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8
        "Official S&Box Release Notes Intake sbox-release-notes-agent.md sbox_release_notes_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "S&Box Release Notes Intake Agent sbox_release_notes_audit.ps1 Suite release-notes" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-release-notes-agent.md sbox_release_notes_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "S&Box release notes sbox-release-notes-agent.md run_agent_checks.ps1 -Suite release-notes" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        '"release-notes" sbox_release_notes_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        'sbox_release_notes_audit.ps1 S&Box Release Notes Intake Agent https://sbox.game/release-notes "release-notes"' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "ReleaseNotesResearch sbox_release_notes_audit.ps1 https://sbox.game/release-notes" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[{"id":"sbox-release-notes-check","action":{"args":["-Suite","release-notes",".\\scripts\\agents\\sbox_release_notes_audit.ps1"]}}]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxReleaseNotesAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_release_notes_audit.ps1" "Release-notes audit failed on complete routing fixtures." "Avoid false positives for valid official release-note workflow wiring."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$sboxCodeSearchAudit = Join-Path $Root "scripts/agents/sbox_code_search_audit.ps1"
if (Test-Path -LiteralPath $sboxCodeSearchAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-code-search-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".claude") | Out-Null

        "https://sbox.game/codesearch" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "S&Box Code Search Agent" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-code-search-agent.md") -Encoding UTF8
        "https://sbox.game/codesearch" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8
        "S&Box Code Search Intake" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "S&Box Code Search Agent" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-code-search-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "S&Box Code Search" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        '"code-search"' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_code_search_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "CodeSearchResearch" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxCodeSearchAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete Code Search intake routing" -SourcePath "scripts/agents/sbox_code_search_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_code_search_audit.ps1" "Code Search audit did not fail on incomplete routing fixtures." "Keep the fixture strict enough to catch missing Code Search docs, agent, hook, suite, and self-test wiring."
        }

        @'
# S&Box Engine LLM Reference

Official S&Box Code Search reviewed on 2026-05-30:

- https://sbox.game/codesearch
- Search the source of every published package.
- package type
- code type
- year
- sbox-code-search-agent.md
- sbox_code_search_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8

        @'
# S&Box Code Search Agent

## Purpose

Review published packages at https://sbox.game/codesearch.

Sources:
- published packages
- package type
- code type
- year
- sbox_api_lookup.ps1

Evidence:
- sbox_code_search_audit.ps1

Do not vendor package source.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-code-search-agent.md") -Encoding UTF8

        "https://sbox.game/codesearch sbox-code-search-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8
        "S&Box Code Search Intake https://sbox.game/codesearch sbox-code-search-agent.md sbox_code_search_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "S&Box Code Search Agent sbox-code-search-agent.md sbox_code_search_audit.ps1 run_agent_checks.ps1 -Suite code-search" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "Code Search sbox-code-search-agent.md sbox_code_search_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "S&Box Code Search sbox-code-search-agent.md run_agent_checks.ps1 -Suite code-search" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        '"code-search" sbox_code_search_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        'S&Box Code Search Agent "code-search" sbox_code_search_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "CodeSearchResearch sbox_code_search_audit.ps1 https://sbox.game/codesearch" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[{"id":"sbox-code-search-check","action":{"args":["-Suite","code-search",".\\scripts\\agents\\sbox_code_search_audit.ps1"]}}]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxCodeSearchAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_code_search_audit.ps1" "Code Search audit failed on complete routing fixtures." "Avoid false positives for valid Code Search workflow wiring."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$animatedModelAudit = Join-Path $Root "scripts/agents/animated_model_intake_audit.ps1"
if (Test-Path -LiteralPath $animatedModelAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-animated-model-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".claude") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Code\Player") | Out-Null

        "Animated Model Intake Agent" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\animated-model-intake-agent.md") -Encoding UTF8
        "Animated Model Intake Agent" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        '"animated-model"' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "animated_model_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "AnimatedAssets" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        '{"hooks":[]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $animatedModelAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete animated model intake routing" -SourcePath "scripts/agents/animated_model_intake_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/animated_model_intake_audit.ps1" "Animated model audit did not fail on incomplete routing fixtures." "Keep the fixture strict enough to catch missing editor-first docs, hook, suite, self-test, training, and API-symbol guidance."
        }

        @'
# Animated Model Intake Agent

## Purpose

Use editor-first-workflow-agent.md for animated Blender/FBX/VMDL imports.

## Editor-First Workflow

- control_plane_status
- ModelDoc
- AnimGraph
- imported clips
- AnimationGraph
- SkinnedModelRenderer.Sequence
- AnimGraphDirectPlayback
- Parameters.Set
- 1D blendspace
- state machine
- bool triggers
- FirstPersonViewmodel
- sbox_api_lookup.ps1
- animated_model_intake_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\animated-model-intake-agent.md") -Encoding UTF8

        "Animated Model Intake animated-model-intake-agent.md animated_model_intake_audit.ps1 run_agent_checks.ps1 -Suite animated-model editor-first-workflow-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "Animated Model animated-model-intake-agent.md animated_model_intake_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "Animated Model Import AnimGraph ModelDoc editor-first-workflow-agent.md animated-model-intake-agent.md animated_model_intake_audit.ps1 SkinnedModelRenderer.Sequence AnimGraphDirectPlayback Parameters.Set" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\known_sbox_patterns.md") -Encoding UTF8
        "Animated model import reviewed on 2026-06-06 SkinnedModelRenderer.UseAnimGraph SkinnedModelRenderer.AnimationGraph SkinnedModelRenderer.Sequence SkinnedModelRenderer.PlaybackRate SkinnedModelRenderer.PlayAnimationsInEditorScene AnimationGraph.Load AnimGraphDirectPlayback Parameters.Set sbox_api_lookup.ps1 animated_model_intake_audit.ps1 editor-first-workflow-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "Animated model imports need editor-first AnimGraph playback proof before gameplay wiring. animated-model-intake-agent.md run_agent_checks.ps1 -Suite animated-model" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\automation.md") -Encoding UTF8
        "S&Box Animated Model Intake Hook sbox-animated-model-check run_agent_checks.ps1 -Suite animated-model animated-model-intake-agent.md editor-first-workflow-agent.md" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        '"animated-model" animated_model_intake_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        'Animated Model Intake Agent "animated-model" animated_model_intake_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "AnimatedAssets animated_model_intake_audit.ps1 AnimGraph" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        'UseAnimGraph Parameters.Set SetIk' | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Player\FirstPersonViewmodel.cs") -Encoding UTF8
        '{"hooks":[{"id":"sbox-animated-model-check","action":{"args":["-Suite","animated-model",".\\scripts\\agents\\animated_model_intake_audit.ps1"]}}]}' | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $animatedModelAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/animated_model_intake_audit.ps1" "Animated model audit failed on complete routing fixtures." "Avoid false positives for valid editor-first animated model workflow wiring."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$sboxApiReferenceAudit = Join-Path $Root "scripts/agents/sbox_api_reference_audit.ps1"
if (Test-Path -LiteralPath $sboxApiReferenceAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-api-reference-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".claude") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "scripts\agents\sbox_api_lookup.ps1") | Out-Null

        "API.json local API dump sbox_api_lookup.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "API.json sbox_api_lookup.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8
        "S&Box API Lookup sbox_api_lookup.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "S&Box API Lookup sbox_api_lookup.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "API.json sbox_api_lookup.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "AGENTS.md") -Encoding UTF8
        "API.json sbox_api_lookup.ps1 sbox_api_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".claude\settings.json") -Encoding UTF8
        '"api" sbox_api_reference_audit.ps1 sbox_api_lookup.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_api_lookup.ps1 sbox_api_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8

        $badTypes = @(
            [pscustomobject]@{ FullName = "Sandbox.Component"; Name = "Component" },
            [pscustomobject]@{ FullName = "Sandbox.GameObject"; Name = "GameObject"; Methods = @([pscustomobject]@{ Name = "NetworkSpawn" }) },
            [pscustomobject]@{ FullName = "Sandbox.Networking"; Name = "Networking"; Properties = @([pscustomobject]@{ Name = "IsHost" }) }
        )
        @{ Types = $badTypes } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempRoot "API.json") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $sboxApiReferenceAudit -ScriptArgs @("-Root", $tempRoot) -Label "incomplete local API dump" -SourcePath "scripts/agents/sbox_api_reference_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_api_reference_audit.ps1" "API reference audit did not fail on an incomplete local API dump." "Keep API dump validation strict enough to catch missing core S&Box symbols."
        }

        $validTypes = New-Object System.Collections.Generic.List[object]
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.Component"; Name = "Component" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.GameObject"; Name = "GameObject"; Methods = @([pscustomobject]@{ Name = "NetworkSpawn" }) })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.Networking"; Name = "Networking"; Properties = @([pscustomobject]@{ Name = "IsHost" }) })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.SyncAttribute"; Name = "SyncAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.RpcAttribute"; Name = "RpcAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.Rpc.BroadcastAttribute"; Name = "BroadcastAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.Rpc.HostAttribute"; Name = "HostAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.Rpc.OwnerAttribute"; Name = "OwnerAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.ClientEditableAttribute"; Name = "ClientEditableAttribute" })
        $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.TimeSince"; Name = "TimeSince" })
        for ($i = 0; $i -lt 100; $i++) {
            $validTypes.Add([pscustomobject]@{ FullName = "Sandbox.FixtureType$i"; Name = "FixtureType$i" })
        }
        @{ Types = $validTypes.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempRoot "API.json") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxApiReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_api_reference_audit.ps1" "API reference audit failed on complete lookup docs, suite wiring, and required API symbols." "Avoid false positives for valid local API-reference setup."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

$editorNodeToolAudit = Join-Path $Root "scripts/agents/editor_node_tool_audit.ps1"
if (Test-Path -LiteralPath $editorNodeToolAudit) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sbox-editor-node-tool-audit-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "docs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot ".agents\sbox") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "scripts\agents") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "Editor") | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $tempRoot "dronevsplayers.sbproj") | Out-Null

        "Editor Node Tools https://sbox.game/learn/aqua/node-editor-01" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8
        "Editor Node Tool Agent Node Editor GraphView editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\editor-node-tool-agent.md") -Encoding UTF8
        "Editor Node Tool Agent editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "editor-node-tool-agent.md editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        '"editor-node-tool" editor_node_tool_audit.ps1' | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "EditorNodeTools editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8
        "editor_node_tool_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8

        @'
using System;
using Editor.NodeEditor;

public class BadNodeToolView : GraphView
{
    public BadNodeToolView( Editor.Widget parent ) : base( parent )
    {
    }

    public void OnPaintSomething()
    {
        throw new NotImplementedException();
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Editor\BadNodeToolView.cs") -Encoding UTF8

        $fixtureExitCode = Invoke-AgentExpectedFailureFixture -ScriptPath $editorNodeToolAudit -ScriptArgs @("-Root", $tempRoot) -Label "node-editor NotImplementedException placeholder" -SourcePath "scripts/agents/editor_node_tool_audit.ps1"
        if ($fixtureExitCode -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/editor_node_tool_audit.ps1" "Editor node-tool audit did not fail on copied NotImplementedException scaffolding." "Keep the fixture red/green test aligned with the node-editor tutorial placeholder rule."
        }

        @'
using Editor.NodeEditor;

public class GoodNodeToolView : GraphView
{
    public GoodNodeToolView( Editor.Widget parent ) : base( parent )
    {
    }

    public void OnPaintSomething()
    {
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Editor\BadNodeToolView.cs") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $editorNodeToolAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/editor_node_tool_audit.ps1" "Editor node-tool audit failed on valid editor-only scaffolding." "Avoid false positives for editor-contained GraphView code with safe callback bodies."
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($tempRoot)) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
