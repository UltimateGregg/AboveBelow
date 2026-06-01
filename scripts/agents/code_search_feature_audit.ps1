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

Write-AgentSection "Code Search Feature Audit"
Write-Host "Root: $Root"

function Get-Text {
    param([string]$Relative)

    $path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Code Search Features" $Relative "Required file is missing."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Pattern {
    param(
        [string]$Relative,
        [string]$Text,
        [string]$Pattern,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Code Search Features" $Relative $Message $Recommendation
    }
}

$hitscan = Get-Text "Code/Player/HitscanWeapon.cs"
$shotgun = Get-Text "Code/Player/ShotgunWeapon.cs"
$controller = Get-Text "Code/Player/GroundPlayerController.cs"
$tracer = Get-Text "Code/Player/BallisticTracerRenderer.cs"
$grenade = Get-Text "Code/Equipment/ThrowableGrenade.cs"
$projectile = Get-Text "Code/Equipment/ThrownGrenadeProjectile.cs"
$hud = Get-Text "Code/UI/HudPanel.razor"
$ammoHud = Get-Text "Code/UI/AmmoHudRenderer.cs"
$scoreboardOverlay = Get-Text "Code/UI/ScoreboardOverlayRenderer.cs"
$setup = Get-Text "Code/Game/GameSetup.cs"
$teamComms = Get-Text "Code/Game/TeamComms.cs"
$teamVoice = Get-Text "Code/Game/TeamVoice.cs"
$trainingDummy = Get-Text "Code/Game/TrainingDummy.cs"
$loadoutResource = Get-Text "Code/Game/LoadoutDefinitionResource.cs"
$interactionPrompt = Get-Text "Code/Game/WorldInteractionPrompt.cs"
$interactionPromptRenderer = Get-Text "Code/UI/InteractionPromptRenderer.cs"
$droneCamera = Get-Text "Code/Drone/DroneCamera.cs"
$editorPreview = Get-Text "Editor/LoadoutDefinitionAssetPreview.cs"
$runChecks = Get-Text "scripts/agents/run_agent_checks.ps1"

Assert-Pattern "Code/Player/HitscanWeapon.cs" $hitscan 'SpreadImpulseDegrees' "Rifle dynamic spread impulse is missing." "Add a per-shot aim bloom impulse inspired by Code Search weapon aim-cone examples."
Assert-Pattern "Code/Player/HitscanWeapon.cs" $hitscan 'SpreadRecoverySeconds' "Rifle dynamic spread recovery is missing." "Recover transient aim bloom over time instead of using only static hip/ADS spread."
Assert-Pattern "Code/Player/HitscanWeapon.cs" $hitscan 'CurrentAimBloom' "Rifle HUD aim-bloom surface is missing." "Expose current weapon bloom so the HUD crosshair can reflect recoil/spread state."
Assert-Pattern "Code/Player/HitscanWeapon.cs" $hitscan 'BallisticTracerRenderer\.Spawn' "Rifle does not use the renderer-backed tracer path." "Spawn a SceneLineObject-backed tracer when no explicit tracer prefab is configured."
Assert-Pattern "Code/Player/ShotgunWeapon.cs" $shotgun 'CurrentAimBloom' "Shotgun HUD aim-bloom surface is missing." "Expose shotgun spread/recoil bloom to the HUD."
Assert-Pattern "Code/Player/ShotgunWeapon.cs" $shotgun 'BallisticTracerRenderer\.Spawn' "Shotgun pellets do not use the renderer-backed tracer path." "Fall back to renderer tracers for pellet trails when no tracer prefab is configured."
Assert-Pattern "Code/Player/GroundPlayerController.cs" $controller 'AddShotNoise' "Camera shot-noise hook is missing." "Add a small local camera kick/roll noise path used by rifle and shotgun fire."

Assert-Pattern "Code/Player/BallisticTracerRenderer.cs" $tracer 'SceneLineObject' "Renderer tracer does not create a SceneLineObject." "Use S&Box scene-line rendering for lightweight ballistic trails."
Assert-Pattern "Code/Player/BallisticTracerRenderer.cs" $tracer 'Component\.ITemporaryEffect' "Renderer tracer lacks temporary-effect lifecycle support." "Implement ITemporaryEffect so tracer GameObjects can be cleaned up by existing effect flows."
Assert-Pattern "Code/Player/BallisticTracerRenderer.cs" $tracer 'DisableLooping' "Renderer tracer cannot be asked to stop." "Expose DisableLooping for temporary-effect compatibility."

Assert-Pattern "Code/Equipment/ThrowableGrenade.cs" $grenade 'StartCookingThrow' "Grenade cooking is missing." "Start cooking on throw-button press and release the throw with remaining fuse time."
Assert-Pattern "Code/Equipment/ThrowableGrenade.cs" $grenade 'ReleaseCookedThrow' "Cooked grenade release is missing." "Release on throw-button up and pass cooked fuse time to the projectile."
Assert-Pattern "Code/Equipment/ThrowableGrenade.cs" $grenade 'AltThrowSpeedScale' "Alternate short throw mode is missing." "Use Attack2 as a near/far throw modifier."
Assert-Pattern "Code/Equipment/ThrowableGrenade.cs" $grenade 'DropOnOwnerDeath' "Drop-on-death grenade behavior is missing." "If the owner dies while cooking, drop the armed grenade instead of silently clearing it."
Assert-Pattern "Code/Equipment/ThrowableGrenade.cs" $grenade 'ProjectileSleepThreshold' "Projectile sleep-threshold pass-through is missing." "Expose Rigidbody.SleepThreshold from the grenade thrower."
Assert-Pattern "Code/Equipment/ThrownGrenadeProjectile.cs" $projectile 'SleepThreshold' "Thrown projectile sleep threshold is missing." "Configure Rigidbody.SleepThreshold so grenade bodies settle predictably."
Assert-Pattern "Code/Equipment/ThrownGrenadeProjectile.cs" $projectile 'Body\.SleepThreshold\s*=\s*SleepThreshold' "Thrown projectile does not apply SleepThreshold to the Rigidbody." "Set Body.SleepThreshold inside ConfigurePhysics()."

Assert-Pattern "Code/Game/TeamComms.cs" $teamComms 'IChatEvent' "Team chat handler is missing." "Implement IChatEvent and route /team or /t messages through per-team RecipientFilter."
Assert-Pattern "Code/Game/TeamComms.cs" $teamComms 'RecipientFilter' "Team chat does not filter recipients." "Use ChatMessageEvent.RecipientFilter to keep team chat team-scoped."
Assert-Pattern "Code/Game/TeamComms.cs" $teamComms 'Platform\.Chat\.AddText' "Team chat lacks local system feedback." "Use Platform.Chat.AddText for local command feedback and round/team notifications."
Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice ':\s*Voice' "Team voice component is missing." "Subclass Sandbox.Voice so team membership controls who can hear local voice."
Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice 'ShouldHearVoice' "Team voice does not filter heard speakers." "Override ShouldHearVoice and compare speaker/listener teams through GameSetup."
Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice 'ExcludeFilter' "Team voice does not expose sender-side exclusion." "Override ExcludeFilter so non-teammates are excluded from transmitted voice."
Assert-Pattern "Code/Game/GameSetup.cs" $setup 'GetConnectionRole' "GameSetup does not expose connection role lookup." "Add a stable team lookup helper shared by chat, voice, and future team systems."
Assert-Pattern "Code/Game/GameSetup.cs" $setup 'AreSameTeam' "GameSetup does not expose team comparison." "Add a helper for team-scoped routing."
Assert-Pattern "Code/Game/GameSetup.cs" $setup 'LoadoutDefinitions' "GameSetup does not expose loadout definition resources." "Add optional GameResource-backed loadout definitions with local fallback definitions."
Assert-Pattern "Code/Game/GameSetup.cs" $setup 'GetSoldierLoadoutDefinition' "GameSetup lacks soldier loadout definition lookup." "Expose resource/fallback lookup for HUD previews and future balance audits."
Assert-Pattern "Code/Game/GameSetup.cs" $setup 'GetDroneLoadoutDefinition' "GameSetup lacks drone loadout definition lookup." "Expose resource/fallback lookup for HUD previews and future balance audits."

Assert-Pattern "Code/Game/TrainingDummy.cs" $trainingDummy 'NavMeshAgent' "Training dummy navigation is not backed by NavMeshAgent." "Use NavMeshAgent.WishVelocity so solo targets follow S&Box navmesh paths when available."
Assert-Pattern "Code/Game/TrainingDummy.cs" $trainingDummy 'UseNavMeshNavigation' "Training dummy lacks an opt-in NavMesh mode." "Add a property-gated NavMesh pathing mode that falls back to local wander movement."
Assert-Pattern "Code/Game/TrainingDummy.cs" $trainingDummy 'Scene\.NavMesh\.GetRandomPoint' "Training dummy does not sample navmesh wander points." "Pick patrol targets through Scene.NavMesh.GetRandomPoint when possible."
Assert-Pattern "Code/Game/TrainingDummy.cs" $trainingDummy 'PressureNearestEnemy' "Training dummy lacks enemy-pressure behavior." "Add a practice-bot mode that pressures the nearest opposing local pawn inside an engagement radius."

Assert-Pattern "Code/Game/LoadoutDefinitionResource.cs" $loadoutResource 'GameResource' "Loadout definition resource is missing." "Create a custom GameResource for class/drone loadout metadata."
Assert-Pattern "Code/Game/LoadoutDefinitionResource.cs" $loadoutResource 'LoadoutCatalog' "Fallback loadout catalog is missing." "Keep resource-driven UI usable before authored .dvploadout assets exist."
Assert-Pattern "Code/Game/LoadoutDefinitionResource.cs" $loadoutResource 'FindSoldier' "Soldier loadout resource lookup is missing." "Provide soldier-class lookup by resource or fallback catalog."
Assert-Pattern "Code/Game/LoadoutDefinitionResource.cs" $loadoutResource 'FindDrone' "Drone loadout resource lookup is missing." "Provide drone-variant lookup by resource or fallback catalog."

Assert-Pattern "Code/Game/WorldInteractionPrompt.cs" $interactionPrompt 'WorldInteractionPrompt' "World interaction prompt component is missing." "Add a reusable component that can drive HUD prompts from world objects."
Assert-Pattern "Code/UI/InteractionPromptRenderer.cs" $interactionPromptRenderer 'RenderFragment' "Interaction prompt renderer is missing." "Centralize prompt markup instead of one-off HUD prompt blocks."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'InteractionPromptRenderer\.Render' "HUD does not use the shared interaction prompt renderer." "Route drone and world prompts through a single renderer."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'CurrentWorldPrompt' "HUD does not surface world interaction prompts." "Find the nearest usable WorldInteractionPrompt and include it in BuildHash."

Assert-Pattern "Code/Drone/DroneCamera.cs" $droneCamera 'OpticZoomFovDegrees' "Drone camera lacks optic zoom tuning." "Add right-click optic zoom/FOV behavior inspired by scope examples."
Assert-Pattern "Code/Drone/DroneCamera.cs" $droneCamera 'IsOpticZoomActive' "Drone camera does not expose optic zoom state to the HUD." "Expose local optic state for the drone overlay."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'ShowDroneOpticOverlay' "HUD lacks drone optic overlay state." "Add an optic overlay layer when the local drone camera is zoomed."

Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice 'ApplyVoiceRoutingProfile' "TeamVoice lacks role-aware radio/proximity routing." "Configure pilot voice as radio and hunter voice as worldspace proximity."
Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice 'HunterProximityDistance' "TeamVoice lacks hunter proximity distance tuning." "Expose proximity distance for hunter voice playback."
Assert-Pattern "Code/Game/TeamVoice.cs" $teamVoice 'VoiceRouteLabel' "TeamVoice does not expose a route label for diagnostics/UI." "Expose route labels for HUD/debug and future sound audits."

Assert-Pattern "Editor/LoadoutDefinitionAssetPreview.cs" $editorPreview 'AssetPreview\("dvploadout"\)' "Loadout definition asset preview metadata is missing." "Register editor-only preview metadata for .dvploadout resources."
Assert-Pattern "scripts/agents/run_agent_checks.ps1" $runChecks 'nav_collision_qa_audit\.ps1' "Navigation/collision QA audit is not wired into agent checks." "Run the nav/collision QA audit from the Code Search suite."

Assert-Pattern "Code/UI/HudPanel.razor" $hud 'CurrentWeaponBloom' "HUD does not read weapon bloom." "Read selected weapon bloom from rifle or shotgun and include it in the crosshair class."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'weapon-bloom-' "HUD crosshair bloom class is missing." "Add stable bloom buckets so styles and BuildHash can refresh without per-frame StateHasChanged()."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'CurrentWeaponBloomBucket' "HUD does not bucket weapon bloom for BuildHash." "Hash a quantized weapon-bloom bucket instead of raw per-frame values."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'CurrentWeaponBloomBucket' "HUD BuildHash does not track weapon bloom." "Include CurrentWeaponBloomBucket in BuildHash()."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'AmmoHudRenderer\.Render' "Ammo HUD remains inline in HudPanel." "Extract ammo markup into a focused renderer component."
Assert-Pattern "Code/UI/HudPanel.razor" $hud 'ScoreboardOverlayRenderer\.Render' "Scoreboard overlay remains inline in HudPanel." "Extract scoreboard markup into a focused renderer component."
Assert-Pattern "Code/UI/AmmoHudRenderer.cs" $ammoHud 'RenderFragment' "AmmoHud renderer component does not expose RenderFragment output." "Move the ammo label/value markup into AmmoHudRenderer."
Assert-Pattern "Code/UI/AmmoHudRenderer.cs" $ammoHud 'bottom-right-ammo' "AmmoHud renderer component does not render the ammo HUD markup." "Move the ammo label/value markup into AmmoHudRenderer."
Assert-Pattern "Code/UI/ScoreboardOverlayRenderer.cs" $scoreboardOverlay 'RenderFragment' "Scoreboard renderer component does not expose RenderFragment output." "Move scoreboard markup into ScoreboardOverlayRenderer."
Assert-Pattern "Code/UI/ScoreboardOverlayRenderer.cs" $scoreboardOverlay 'scoreboard-overlay' "Scoreboard renderer component does not render the scoreboard markup." "Move scoreboard rows into ScoreboardOverlayRenderer."

if ($issues.Count -eq 0) {
    Add-AgentIssue $issues "Info" "Code Search Features" "Code" "Selected Code Search-derived feature surfaces are present."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
