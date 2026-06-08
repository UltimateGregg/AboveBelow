# Animated Model Intake Agent

## Purpose

Route animated Blender, FBX, VMDL, ModelDoc, and AnimGraph work through an editor-first workflow before gameplay or prefab wiring is accepted.

Use this agent when:

- an imported model has animation clips that need to play in S&Box,
- a Blender/FBX/VMDL roundtrip includes skeleton, sequence, or root-motion data,
- a model needs an AnimGraph, state machine, 1D blendspace, direct sequence playback, or one-shot animation triggers,
- first-person viewmodel polish depends on imported or stock animation parameters.

## Primary Areas

- `*.blend`
- `Assets/models/**/*.fbx`
- `Assets/models/**/*.vmdl`
- `Assets/prefabs/**/*.prefab`
- `Code/**/*Animation*.cs`
- `Code/Player/FirstPersonViewmodel.cs`
- `scripts/*_asset_pipeline.json`
- `docs/automation.md`

## Editor-First Workflow

Start with `.agents/sbox/editor-first-workflow-agent.md`. Check `control_plane_status` or the MCP tool list before static edits, then inspect the live editor state when available.

1. Prove the source animation exists in Blender or the authored source file.
2. Export through the normal asset pipeline and confirm the FBX and VMDL are generated.
3. Open the model in S&Box ModelDoc / Model Editor / AnimGraph tooling and confirm the imported clips appear by name.
4. Play every imported clip in editor tooling before wiring gameplay. A Blender preview or generated VMDL is not playback proof.
5. Choose the smallest runtime path that fits the behavior:
   - Use `SkinnedModelRenderer.Sequence` with `UseAnimGraph` disabled for simple direct sequence playback.
   - Use an AnimGraph state machine or 1D blendspace for locomotion such as idle, walk, run, crouch, and directional movement.
   - Use `Parameters.Set` bool triggers, float parameters, or int parameters for attacks, reloads, death, deploys, and other one-shot transitions.
   - Use `AnimGraphDirectPlayback` when a Direct Playback Anim node should play a named sequence from code.
6. Verify runtime wiring on the owning component or prefab only after editor playback works.

## Local API Anchors

Verify exact symbols with `scripts/agents/sbox_api_lookup.ps1` before adding new animation calls. Current local API anchors include:

- `SkinnedModelRenderer.UseAnimGraph`
- `SkinnedModelRenderer.AnimationGraph`
- `SkinnedModelRenderer.Sequence`
- `SkinnedModelRenderer.PlaybackRate`
- `SkinnedModelRenderer.PlayAnimationsInEditorScene`
- `AnimationGraph.Load`
- `AnimGraphDirectPlayback`
- `SkinnedModelRenderer.Parameters`
- `SkinnedModelRenderer.SetIk`
- `SkinnedModelRenderer.SetLookDirection`

## First-Person Viewmodel Rules

`FirstPersonViewmodel` is the first owner to inspect for first-person weapon and hand animation. It already uses `UseAnimGraph`, `Parameters.Set`, custom visual copies, stock animation drivers, and hand IK. Extend that path before replacing it with a full-body animation helper.

Keep first-person and full-body animation proof separate:

- full-body locomotion usually belongs to `GroundPlayerController` and `CitizenAnimationHelper`,
- first-person weapon and hand polish usually belongs to `FirstPersonViewmodel`,
- shared held-item pose data should stay in existing weapon/prefab pose surfaces unless the user asks for a new animation system.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/animated_model_intake_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite animated-model -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production -ShowInfo
```

After static checks, complete the editor proof: open the VMDL/AnimGraph surface, play the imported clips, then run a targeted editor playtest for the owning object or character. Report when editor access is unavailable instead of treating static checks as animation playback proof.

## Output Shape

Report:

- editor/MCP availability and any fallback,
- imported clip names checked in ModelDoc or AnimGraph tooling,
- runtime path chosen: direct sequence, AnimGraph parameters, 1D blendspace/state machine, or direct playback node,
- owning component or prefab that drives the animation,
- static audit results,
- remaining editor playtest or multiplayer proof gaps.
