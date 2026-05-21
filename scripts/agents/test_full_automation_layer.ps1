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
    "scripts/agents/prefab_wiring_audit.ps1",
    "scripts/agents/prefab_graph_audit.ps1",
    "scripts/agents/scene_integrity_audit.ps1",
    "scripts/agents/collision_authoring_agent.ps1",
    "scripts/agents/collision_agent_chain_audit.ps1",
    "scripts/agents/collision_chain_report.ps1",
    "scripts/agents/current_log_audit.ps1",
    "scripts/agents/feature_readiness_report.ps1",
    "scripts/agents/post_task_training_agent.ps1",
    "scripts/agents/gameplay_regression_guard.ps1",
    "scripts/agents/blender_quality_audit.ps1",
    "scripts/agents/material_texture_audit.ps1",
    "scripts/agents/modeldoc_audit.ps1",
    "scripts/agents/fbx_material_slot_audit.ps1",
    "scripts/agents/sound_asset_audit.ps1",
    "scripts/agents/ambient_noise_audit.ps1",
    "scripts/agents/sound_playback_audit.ps1",
    "scripts/agents/team_label_copy_audit.ps1",
    "scripts/agents/mcp_screenshot_audit.ps1",
    "scripts/agents/sbox_engine_reference_audit.ps1",
    "scripts/agents/sbox_api_lookup.ps1",
    "scripts/agents/sbox_api_reference_audit.ps1",
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

    foreach ($suite in @("ui", "prefab-graph", "scene", "logs", "readiness", "train", "asset-production", "modeldoc", "blender-live", "gameplay-regression", "sound", "collision", "collision-chain", "api")) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionChainAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $soundAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $soundAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $teamLabelAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/team_label_copy_audit.ps1" "Team label audit did not fail on stale Above/Below role-copy fixtures." "Keep the fixture red/green test aligned with the player-facing label policy."
        }

        @'
<root>
    <div class="main-menu-title">ABOVE / BELOW</div>
    <div>DRONE PILOTS WIN</div>
    <div>SOLDIERS WIN</div>
    <div>Hunt soldiers.</div>
    <div>Take down drone pilots.</div>
    <span>Fly drones as drone pilots</span>
    <span>Fight as soldiers</span>
</root>
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.razor") -Encoding UTF8

        @'
public partial class HudPanel
{
    string PilotRoleLabel => "DRONE PILOTS";
    string SoldierRoleLabel => "SOLDIERS";
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\HudPanel.cs") -Encoding UTF8

        @'
<root>
    <div>A vertical asymmetric shooter about Drone Pilots and Soldiers.</div>
    <div>Drone Pilots launch drones, swap into the camera, and pressure Soldiers across the battlefield.</div>
    <div class="feature-title pilot">DRONE PILOTS</div>
    <div class="feature-title soldier">SOLDIERS</div>
</root>
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\UI\MainMenuPanel.razor") -Encoding UTF8

        @'
public sealed class RoundManager
{
    void BroadcastRoundEnd()
    {
        var label = winner == WinningSide.Pilot ? "Drone Pilots" : "Soldiers";
        Log.Info($"[Round] {label} win. Drone Pilots {PilotWins} / Soldiers {SoldierWins}");
    }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "Code\Game\RoundManager.cs") -Encoding UTF8

        "Player-facing team labels read **Drone Pilots** and **Soldiers**; keep **ABOVE / BELOW** as the project title." | Set-Content -LiteralPath (Join-Path $tempRoot "README.md") -Encoding UTF8
        "Player-facing team labels use Drone Pilots and Soldiers." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\architecture.md") -Encoding UTF8
        "Drone Pilots/Soldiers team choices appear only after Play." | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\playtest_checklist.ps1") -Encoding UTF8

        & powershell -NoProfile -ExecutionPolicy Bypass -File $teamLabelAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/team_label_copy_audit.ps1" "Team label audit failed on valid Drone Pilots/Soldiers fixtures." "Avoid false positives for the current player-facing label policy."
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $prefabWiringAudit -Root $tempRoot -OnlyLineRendererSerialization | Out-Host
        if ($LASTEXITCODE -eq 0) {
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
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" }
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
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sceneAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/scene_integrity_audit.ps1" "Scene integrity audit did not fail on a water tower fixture without solid collision children." "Keep the fixture red/green test aligned with the water tower collision regression."
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
            { "Name": "Visual", "Rotation": "0,0,0,1", "Components": [ { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" } ], "Children": [] },
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sceneAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" }
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
        if ($LASTEXITCODE -eq 0) {
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
                { "__type": "Sandbox.ModelRenderer", "Model": "models/watertower.vmdl" }
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot -FailOnWarning | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $collisionAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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
- https://github.com/Facepunch/sbox-public

Use `[Sync]` for replicated state.
Use ModelDoc for VMDL work.

## Avoid Source 1 Habits

Do not use `.qc` model scripts as active S&Box guidance.
'@ | Set-Content -LiteralPath (Join-Path $tempRoot "docs\sbox_engine_llm_reference.md") -Encoding UTF8

        @'
# S&Box Engine Reference Agent

## Purpose

Verify S&Box engine research.

Sources:
- https://sbox.game/dev/doc
- https://github.com/Facepunch/sbox-public

Evidence:
scripts/agents/sbox_engine_reference_audit.ps1
'@ | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\sbox-engine-reference-agent.md") -Encoding UTF8

        "S&Box Engine Reference Agent sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "docs\agent_toolkit.md") -Encoding UTF8
        "sbox-engine-reference-agent.md sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot ".agents\sbox\README.md") -Encoding UTF8
        "sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\run_agent_checks.ps1") -Encoding UTF8
        "sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\test_full_automation_layer.ps1") -Encoding UTF8
        "sbox_engine_reference_audit.ps1" | Set-Content -LiteralPath (Join-Path $tempRoot "scripts\agents\post_task_training_agent.ps1") -Encoding UTF8

        "Use [Net] for replicated S&Box gameplay state." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxEngineReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit did not fail on active stale [Net] guidance." "Keep the fixture red/green test aligned with current S&Box [Sync] guidance."
        }

        "Use [Sync] for replicated S&Box gameplay state." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxEngineReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit failed on valid [Sync] guidance and complete routing docs." "Avoid false positives for current, sourced S&Box reference guidance."
        }

        "Create a .qc file for this S&Box model." | Set-Content -LiteralPath (Join-Path $tempRoot "docs\bad_engine_guidance.md") -Encoding UTF8
        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxEngineReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Add-AgentIssue $issues "Error" "Full Automation Tests" "scripts/agents/sbox_engine_reference_audit.ps1" "Engine reference audit did not fail on active .qc model guidance." "Keep Source 1 model workflow references marked as historical or avoided."
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

        & powershell -NoProfile -ExecutionPolicy Bypass -File $sboxApiReferenceAudit -Root $tempRoot | Out-Host
        if ($LASTEXITCODE -eq 0) {
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

Write-AgentIssues -Issues $issues -ShowInfo
exit (Get-AgentExitCode -Issues $issues)
