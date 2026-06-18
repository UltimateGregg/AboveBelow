# Claude Code project guide

This is "ABOVE / BELOW" (`DroneVsPlayers`) — a vertical asymmetric s&box shooter. One player flies a drone from above, the rest fight on the ground. Roles rotate each round.

**Setting:** the whole game takes place in **Bouneurmaum National Park** — a rural, daytime national park (pine forest, grassland clearings, dirt roads, scattered rural structures + park infrastructure, a staged incident-response command tent). This is the canonical art direction for every model, light, and effect: if it wouldn't look at home in a real national park, it doesn't belong. Full guide in [`docs/setting.md`](docs/setting.md).

**This guide (`CLAUDE.md`) is the canonical practical reference for working in this repo** — it's auto-loaded each session and kept current. [`AGENTS.md`](AGENTS.md) holds the standing AI-workflow rules (small verifiable phases, compile + log checks after each, editor-first, don't invent APIs) and still applies; where the two overlap on project specifics, this file wins. The notes below are the practical, hard-won bits that aren't obvious from a fresh code read.

## Project layout (the short version)

```
Code/
  Common/    Shared enums (PlayerRole, SoldierClass, DroneType), PlayerSpawn
  Game/      RoundManager, GameRules, GameStats, GameSetup,
             TrainingDummy, AmbientSound, CollisionDebugViewer
  Drone/     DroneController (flight), DroneCamera, DroneWeapon,
             DroneBase + GpsDrone / FpvDrone / FiberOpticFpvDrone,
             JammingReceiver, PilotLink, FiberCable
  Player/    GroundPlayerController, PilotSoldier, RemoteController,
             SoldierBase + AssaultSoldier / CounterUavSoldier / HeavySoldier,
             HitscanWeapon, ShotgunWeapon, DroneJammerGun,
             WeaponPose (static utility), SoldierLoadout, FirstPersonViewmodel,
             TracerLifetime, ImpactEffects
  Equipment/ ThrowableGrenade + ChaffGrenade / EmpGrenade / FragGrenade
  UI/        HudPanel (Razor), MainMenuPanel, KillFeedTracker
  code/Wiring/AutoWire.cs   — runs at scene load to resolve prefab refs by name
```

Main scene: `Assets/scenes/main.scene`. Startup scene is the same.

## Asset pipeline (Blender → FBX → vmdl → prefab)

There's an auto-export hook (`blend-auto-export` in `.claude/settings.json`) that fires on any `.blend` save. It runs `scripts/smart_asset_export.ps1`, which selects a per-asset config (`scripts/<blendname>_asset_pipeline.json`) and calls `scripts/asset_pipeline.py`. **If no per-asset config exists, the wrapper auto-scaffolds one** from the `.blend` via `scripts/scaffold_asset_config.py` and then runs the pipeline — so a brand-new asset only needs a save to reach s&box.

### After you finish modeling in Blender — REQUIRED

A `.blend` change only reaches s&box once it's saved AND processed by the pipeline. The hook handles the export, but **you must save the .blend yourself** — saving is part of finishing a Blender modeling task, not something to hand off to the user with a "save it yourself" remark. The hook watches the disk, not your intent.

After any Blender modeling work that should land in-game:

1. **Save** the `.blend` to `<group>_model.blend/<assetname>.blend` (e.g., `environment_model.blend/watertower.blend`). Use the `mcp__blender_stdio__blender_save_file` tool, or call `bpy.ops.wm.save_as_mainfile(filepath="<absolute path>")` via `execute_blender_code`. Do not skip this step.
2. The hook fires on save. If `scripts/<assetname>_asset_pipeline.json` doesn't exist, it gets scaffolded automatically (axis -Y/Z, scale 0.0254, target paths under `Assets/models/`, material slots mapped to `materials/<lowercased_slot>.vmat` with a leading `M_` stripped).
3. **Verify** that `Assets/models/<assetname>.vmdl` and `Assets/models/<assetname>.fbx` exist after the hook completes. Read the hook's success/failure notification. On failure, run the pipeline manually and read the error:
   ```powershell
   python scripts/asset_pipeline.py --config scripts/<assetname>_asset_pipeline.json
   ```
4. If the scaffolded `material_remap` paths don't match the `.vmat` filenames you want, edit `scripts/<assetname>_asset_pipeline.json` and save the `.blend` again to re-export.
5. If the asset needs a prefab, edit the prefab JSON to point at the new vmdl, or add a `prefab` block to the config so the pipeline wires it on the next save.

The scaffolder refuses to overwrite an existing config without `--force`, so it only fires on first-time exports — subsequent saves re-use the existing (possibly hand-edited) config.

### Knowing what file gets exported where

The PS script strips the .blend extension twice from the filename. So `drone_model.blend/drone_fpv.blend` → asset key `drone_fpv` → looks for `scripts/drone_fpv_asset_pipeline.json`.

A per-asset config tells the pipeline:
- `source_blend`, `target_fbx`, `target_vmdl`, `model_resource_path`
- `root_object`, `combined_object_name`, `combine_meshes`
- `material_remap` — maps Blender material-slot names → `.vmat` paths in the generated VMDL
- `axis_forward`, `axis_up`, `global_scale` (always 0.0254 here)
- Optional: `prefab` to auto-wire a prefab's Visual ModelRenderer (skip if you'll edit the prefab by hand)

To scaffold a config manually (e.g., for an asset you've created outside the hook):

```powershell
python scripts/scaffold_asset_config.py path/to/asset.blend
```

To re-run the pipeline manually (useful when iterating on the config without modifying the .blend):

```powershell
python scripts/asset_pipeline.py --config scripts/<name>_asset_pipeline.json
```

### Conventions baked into existing tooling

- **Axis**: Blender's `-Y forward, +Z up`. Build models with the nose along Blender `-Y`. The drone_fpv model was rebuilt mid-session because it was originally built along `+X` — the export came out 90° rotated. Don't repeat that.
- **Blender → source scale factor**: With `global_scale: 0.0254`, 1 Blender unit ends up as ~2.54 source units after s&box import. Useful for sizing prefab Position values.
- **Material slot names round-trip literally** through FBX. Set `mat.name = "Frame_Carbon"` etc. explicitly in your Blender script and re-check after assignment — Blender silently appends `.001` on collision.
- **Sub-objects that need to be controlled separately at runtime** (e.g. spinning propellers) should be a *separate Blender file* with its own pipeline config. The pipeline force-combines all meshes in a single `.blend` into one mesh; you can't selectively exclude. This is by design and works fine — two source files, two vmdls, references at the prefab level.

### Imported / external model gotcha — `import_scale` and axis rotation

Models that were imported from elsewhere (not generated via our pipeline) can have wildly wrong proportions. The pre-existing `models/weapons/assault_rifle_m4.vmdl` had `import_scale: 1.0` producing **3200-unit bounds** — a 32-meter rifle. Fix is either:

1. **Edit the vmdl's `RenderMeshFile.import_scale`** to bring the mesh down to game-scale (M4 needed 0.013).
2. **Apply `Rotation` on the prefab's WeaponVisual GameObject** if the model's natural barrel axis isn't s&box's +X. The M4 model's barrel is along its local +Y; `WeaponVisual.Rotation = "0,-90,0"` (yaw −90°) maps that onto world forward so the MuzzleSocket lines up with the visible barrel tip.

If you import a new weapon model and bullets fire from the wrong place, suspect one of these two before tweaking offsets.

## Held-item viewmodel architecture (weapons + grenades)

All held items — rifle, shotgun, drone-jammer, every grenade — share a single FPS-viewmodel pattern via the static `WeaponPose` utility in `Code/Player/WeaponPose.cs`. Each item component declares:

```csharp
[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;  // or EquipmentSlot
[Property] public Vector3 FirstPersonOffset { get; set; }    // forward, right, up — from camera
[Property] public Angles FirstPersonRotationOffset { get; set; }
[Property] public Vector3 ThirdPersonLocalPosition { get; set; }    // body-local fallback
[Property] public Angles ThirdPersonLocalAngles { get; set; }
[Property] public GameObject WeaponVisual { get; set; }   // optional — for nested model child
```

…and in `OnUpdate` calls:

```csharp
WeaponPose.SetVisibility( GameObject, WeaponVisual, IsSelected );
if ( IsSelected )
    WeaponPose.UpdateViewmodel( this, IsProxy, FirstPersonOffset, FirstPersonRotationOffset,
                                ThirdPersonLocalPosition, ThirdPersonLocalAngles );
```

`WeaponPose.UpdateViewmodel` sets `WorldPosition` and `WorldRotation` each frame for the local first-person player (using `pc.Eye.WorldPosition` + camera basis vectors), and falls back to `LocalPosition`/`LocalRotation` for everyone else / third-person. **Don't compose the parent GameObject's transform into the held item's position** — the utility positions in world space, overriding any inherited transform.

### Slot system (number-key weapon switching)

`SoldierLoadout` lives on each soldier prefab and tracks `[Sync] SelectedSlot`. It listens for `Slot1`/`Slot2` input actions (bound to keys `1` and `2`) and broadcasts the change. Each held item's `IsSelected` is `WeaponPose.IsSlotSelected(this, Slot)`. Default slots:

- `SoldierLoadout.PrimarySlot = 1` — rifle / shotgun / jammer
- `SoldierLoadout.EquipmentSlot = 2` — grenades

When a slot isn't selected the item's `ModelRenderer.RenderType` is set to `ShadowsOnly` (visible to other players, invisible to the local player) and its input is gated off. Sounds owned by the item (jammer loop, etc.) force-stop on deselect.

## First-person viewmodel (`FirstPersonViewmodel`)

> Earlier docs described an `FpvArms` "two cylinders + two boxes that float into view" stub.
> **That component is gone** — `FirstPersonViewmodel` replaced it. There is no standalone
> `fps_arms` floating-arms component anymore; `models/first_person/first_person_arms_preview.vmdl`
> survives only as the `ArmsFallbackModelPath`.

`FirstPersonViewmodel` (partial class: `FirstPersonViewmodel.cs` / `.Build.cs` / `.Pose.cs`) is the local-only held-item renderer that sits on the soldier/pilot beside `GroundPlayerController`. It is `NetworkMode.Never`, hidden for proxies, and only runs when `pc.UseLocalFirstPersonViewmodel && pc.FirstPerson && !IsProxy`. Each time the selected held item changes it rebuilds a viewmodel root in one of three render modes:

1. **StockVisible** — shows a Facepunch stock weapon viewmodel (`facepunch/v_m4a1`, `v_mp5`, the grenades, …) with `UseAnimGraph`, driven by `UpdateStockAnimParameters` (deploy / attack / reload / ADS / sprint / empty). Facepunch first-person arms (`facepunch/v_first_person_arms_human`) are **bone-merged** onto the weapon via `BoneMergeTarget`, so the hands ride the weapon animation.
2. **CustomVisibleStockAnimated** — shows the *project's* custom weapon model (`models/weapons/assault_rifle_m4.vmdl`, etc.) while a **hidden** stock weapon plays as the animation driver. After two frames it bone-attaches the visible custom model to the stock weapon's grip bone (`CreateBoneObjects` + `GetBoneObject`), so the custom gun rides the exact stock skeleton and never drifts from the bone-merged arms on fast camera turns.
3. **StaticFallback** — if no stock/custom model loads, it copies the held item's `ModelRenderer`s into the root, floats them at the eye, and runs explicit `SetIk` hand IK on the arms to the item's left/right hand targets.

Conventions:
- **Local-only, proxy-hidden.** Remote players see the third-person **Citizen** body (`models/citizen_human/citizen_human_male.vmdl` + `CitizenAnimationHelper`) holding the *world* item — not these arms. `GroundPlayerController` hides the local body's hands while the viewmodel is active so there are no double-arms.
- `FirstPersonViewmodel.ShouldHideWorldHeldItem(...)` tells each held item to hide its world model locally while the viewmodel is showing.
- Model paths and per-weapon alignment are all `[Property]` fields on the component (`ArmsModelPath`, `AssaultRifleViewmodelPath`, `AssaultRifleCustomModelPath`, `CustomM4ViewmodelOffset/Rotation/Scale`, `CustomSmg…`, `CustomShotgun…`, `CustomJammer…`, `StockViewmodelOffset`). Tune offsets there; don't hardcode new model paths in code.
- Bone resolution is currently **heuristic** — `FindStockWeaponBoneObject` / `TryGetStockHandAnchor` / `TryGetStockWeaponAnchor` each try several bone/attachment names. Pinning these to the real Facepunch bone names is open viewmodel polish (drift/desync risk lives here).

Third-person grip is a separate path: `WeaponPose.ApplyHandPose` seats the *world* weapon in the Citizen's hands via `CitizenAnimationHelper` `HoldTypes` + `IkLeftHand` / `IkRightHand`.

For the full first-person weapon-rig anatomy (skeletal mesh, bone hierarchy, anim clips, anim graph, attachment points, IK, anim events, camera offsets, weapon-part rig) and a per-part status/gap table for this project, see [`docs/first_person_weapon_rig.md`](docs/first_person_weapon_rig.md).

## Collision authoring (mesh-based) — the default for props/buildings

> **STANDING RULE — collision + physics are part of "making a model," always.**
> Whenever you create or export *any* model (prop, building, weapon, door, decor —
> anything that becomes a `.vmdl`), you own its collision and physics by default.
> Do not wait to be asked and do not hand it back "visual only." Every new model
> ships with: (1) a `collision` block in its `scripts/<name>_asset_pipeline.json`
> (`render_mesh` for solid non-deforming props; `collision_mesh`/`primitives` only
> for the documented exceptions), and (2) a prefab whose Visual carries a
> `ModelCollider` (`Static = true` for things that never move; `Static = false` for
> script/physics-driven movers like doors). Verify `ModelCollider.LocalBounds` is
> non-zero and matches the renderer before calling the model done. The only time
> you skip collision is when the user explicitly says the model is decoration with
> no collision — and you call that out in your summary. If a model is genuinely a
> physics body (it moves, falls, or is pushed), give it the matching `Rigidbody` /
> joint setup too; a static keyframed mover (door) needs a non-static collider, not
> a `Rigidbody`.

Give a model **exact 1:1 collision** that can't drift: bake a triangle mesh into
the `.vmdl` and reference it with a `ModelCollider`. Full guide:
[`docs/collision_authoring.md`](docs/collision_authoring.md). The `WaterTower`
asset is the reference example.

Two parts:
1. **Model** — add a `collision` block to the asset's
   `scripts/<name>_asset_pipeline.json`; the pipeline writes a `PhysicsMeshFile`
   node for you:
   ```json
   "collision": { "mode": "render_mesh", "surface_prop": "metal", "collision_tags": "solid" }
   ```
   `mode`: `render_mesh` (default for solid non-deforming props) · `collision_mesh` (separate
   FBX to make a part hollow — generate it with `scripts/export_collision_mesh.py
   <blend> <out.fbx> --exclude-prefix Ladder_`) · `primitives` (documented
   exception only; dimensions come from exported source-unit mesh bounds, not
   Blender meter guesses) · `none`.
2. **Prefab** — one `ModelCollider` (`Model` = the `.vmdl`, `Static = true`) on the
   **same GameObject as the `ModelRenderer`** (the `Visual` child). It rides the
   exact visual transform, so it stays aligned under non-uniform instance scale +
   rotation. Don't add per-part `Collision_*` body boxes — the `ModelCollider`
   replaces them. Trigger volumes (ladders, zones) stay separate children.
   Place solid props through their prefab with this static `ModelCollider`, never
   by dragging the raw `.vmdl`, because raw model placement can create a dynamic
   Prop that falls on play.

**The gotcha:** `PhysicsMeshFile`/`PhysicsHullFile` MUST be nested inside a
`PhysicsShapeList`. Directly under `RootNode` the compiler **silently ignores it**
(zero collision, no error). The pipeline nests it correctly; the collision agent
audits for it. Verify with `ModelCollider.LocalBounds` (must be non-zero and
approximately match `ModelRenderer.LocalBounds`), the in-editor gizmo, and a play
test where the prefab renders, stays put, and collides. Run
`scripts/agents/model_collision_scale_audit.ps1 -ShowInfo` for generated assets.
Why this beats hand-placed boxes: those are authored in the wrong space and shear
under the instance's non-uniform scale — exactly why the water tower failed
repeatedly before this.

## Collider visualisation (`CollisionDebugViewer`)

Sits on the GameManager in `main.scene` as a `Component.ExecuteInEditor`. When `AlwaysDraw = true`, it walks every `BoxCollider` / `SphereCollider` / `CapsuleCollider` in the scene each frame and draws a wireframe via `Gizmo.Draw.LineBBox` / `LineSphere` / `Line`. Toggle the component on/off in the inspector when chasing "what invisible wall is blocking me here?" bugs.

`Gizmo.Scope` is keyed by the collider's `Id` so each shape gets its own gizmo bucket. Box gizmos are orange, spheres/capsules are green by default — properties on the component if you want to recolour.

## Recoil (`GroundPlayerController.AddRecoil`)

Weapons call `pc.AddRecoil(pitch, yaw)` on fire. The controller accumulates the kick into `_recoilOffset` and decays it back to zero each frame at `RecoilReturnRate` (default 12/sec). **The kick is applied to the rendered camera rotation only — `EyeAngles` (the aim source) stays untouched**, so the player's aim returns to where they pointed once the recoil settles. This is the CoD-style "no aim drift" feel. Don't mix recoil into EyeAngles.

`Eye.WorldRotation` is also set to the displayed (kicked) rotation so any GameObject parented to `Eye` (none today, but room for future viewmodel rigs) tracks the camera kick.

## Health and damage events

`Health` is host-authoritative with two networked events that fire on every peer:

- `OnDamaged(DamageInfo)` — fires for every damage application, fatal or not. HUD feedback (damage-direction arc, hitmarker) subscribes here.
- `OnKilled(DamageInfo)` — fires when HP hits zero. Kill feed and kill-chime hang off this.

`DamageInfo` carries `Amount`, `AttackerId`, `Position`, and `WeaponName`. Use `Health.RequestDamageNamed(amount, attackerId, position, weaponName)` from weapons so the kill feed gets proper attribution. `RequestDamage` (no weapon name) is still supported but feeds `"Unknown"` into the UI.

Each weapon should declare `[Property] string WeaponDisplayName` and pass it on RequestDamageNamed calls (HitscanWeapon, ShotgunWeapon, FragGrenade all do).

## HUD feedback layers (`HudPanel.razor`)

The HUD is one big Razor panel that includes role picker, jam warning, crosshair, hitmarker, damage arcs, kill feed, round state, top-right score, bottom-left health, loadout HUD, pilot controls, scoreboard, and low-HP vignette. Layered behaviour:

- **Crosshair**: only for `LocalRole == Soldier`. CSS-only, four ticks + center dot. `.firing` class spreads the ticks briefly after a hit.
- **Hitmarker**: when the local player damages another `Health`, white X flashes (`ui_hitmarker.sound`). On kill, larger red X (`ui_hitmarker_kill.sound`).
- **Damage-direction arc**: when the local player takes damage, a red arc rotates to point toward the source. Fades over 2 s; up to 8 stack.
- **Low-HP vignette**: `.low-hp` class on root applies a pulsing red radial gradient when HP < 25%.
- **Kill feed**: top-right, fed by `KillFeedTracker` on the GameManager. Each entry colored by local-attacker (blue) / local-victim (red) / neutral.
- **Scoreboard**: hold Tab. Reads `GameStats.GetScoreboard()`.

`KillFeedTracker` auto-subscribes to every `Health.OnKilled` in the scene and prunes entries older than `EntryLifetimeSeconds` (5.5 default). When adding new soldier/drone variants you don't need to do anything to participate in the feed — just make sure your weapon calls `RequestDamageNamed` so it gets named correctly.

## Drone prefab conventions

- `DroneController` finds propellers by walking the prefab's `GameObject.Children` for names that **start with "Propeller"**. Not bones, not FBX sub-meshes. New drone variants must include named `Propeller_*` child GameObjects with their own `ModelRenderer`, or no blades will spin.
- `AutoWireHelper` (`Code/code/Wiring/AutoWire.cs`) resolves `Visual`, `CameraSocket`, `MuzzleSocket` by *name* at the prefab root. Don't rename these without updating that file.
- The collider on the drone should match the visible body; the FPV drone's `BoxCollider` is `Center "0,0,1.4", Scale "16,16,4"` so the bottom of the collider sits at the bottom of the visible body, not 2 units below it.

## Pilot / drone control flow

Pilots spawn as a ground avatar (`pilot_ground.prefab` with `PilotSoldier` + `RemoteController` + `GroundPlayerController`) holding a `DroneDeployer`. Launching the deployer creates the selected drone variant and writes `PilotSoldier.LinkedDroneId`. The `RemoteController.DroneViewActive` flag toggles which pawn the local player drives after a drone is airborne:

- `false` (default at spawn): ground avatar takes input and the scene camera follows the pilot's `Eye`
- `true`: ground controller is disabled, `DroneCamera` drives the scene camera, and `DroneController` reads input

`DroneCamera` and `DroneController` both gate on `RemoteController.IsLocalDroneViewActive(Scene)` — a static helper. If no `RemoteController` exists in the scene (editor playtest with a hand-placed drone), it returns true so the drone is testable in isolation.

The toggle key is `TogglePilotControl`, defined in `ProjectSettings/Input.config` (currently bound to **F**, was Flashlight before).

## s&box editor MCP server (when present)

The project has a local MCP server (`jtc.mcp-server`) at `http://localhost:29015`. When Claude Code's binding to it drops, you can still call its tools by hitting the HTTP endpoint directly with a JSON-RPC body:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_scene_info","arguments":{}}}'
Invoke-WebRequest -Uri 'http://localhost:29015/mcp' -Method POST -Body $body -ContentType 'application/json' -UseBasicParsing
```

Notable quirks (also in `~/.claude/projects/.../memory/tooling_sbox_mcp.md`):
- `execute_csharp` errors with "Roslyn scripting not loaded" — don't use it. Spawn a test `ModelRenderer` to verify a model loaded.
- `editor_take_screenshot` errors with "RenderToPixmap method not available" — fall back to rendering a preview in Blender.
- `scene_open` on a `.prefab` errors "Ambiguous match" if a prefab editor session is open alongside `main.scene`. Re-open `Assets/scenes/main.scene` first.
- Avoid `editor_save_scene` while in play-mode or while a prefab editor session is the active tab — s&box has saved an `untitled.scene` next to main.scene at least once. Always `scene_open Assets/scenes/main.scene` first if unsure.

## Agent Infrastructure & Editor-First Workflow

This project uses an **editor-first** development philosophy: use the live S&Box editor and its MCP (Model Context Protocol) server as the primary authoring surface, especially for scene, prefab, component, asset, and sound work. Only fall back to hand-editing JSON when the editor surface is unavailable.

### Core Principle: Inspect → Mutate → Save → Verify

1. **Inspect** the live scene/prefab with `editor_scene_info`, `scene_get_hierarchy`, `scene_find_objects`, `component_list`, `component_get`
2. **Mutate** through editor commands: `scene_create_object`, `component_set`, `asset_*`, `sound_*` (prefer these over hand-editing JSON)
3. **Save** through the editor with `editor_save_scene` (only when you know the editor wasn't pre-dirty and edits are agent-owned)
4. **Verify** both live editor state and saved files; take proof screenshots with `editor_take_screenshot` when behavior changed

### Startup Checks

Before any editor-capable task:

1. Confirm S&Box editor is the intended surface for the work
2. Check live control-plane status: call `control_plane_status` MCP tool or query JSON-RPC directly:
   ```powershell
   $body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
   Invoke-WebRequest -Uri 'http://localhost:29015/mcp' -Method POST -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
   ```
3. If the native MCP is unavailable, record it explicitly and use the safest file/script fallback — don't pretend work was editor-native
4. Track `hasUnsavedChanges` from `control_plane_status` / `editor_scene_info`. If the editor was already dirty before your change, do not call `editor_save_scene` or reload commands unless explicitly approved — that would force a user-facing save prompt

### Agent Routing

**For different task types, use the corresponding agent** (listed in `.agents/sbox/`):

| Need | Agent | Evidence Command |
|------|-------|------------------|
| **Editor-capable work (scenes, prefabs, assets, sound)** | `editor-first-workflow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo` |
| **Final sanity pass after code changes** | `pre-handoff-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick` |
| **Build compile and editor/runtime log review** | `build-log-sentinel.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1` |
| **Gameplay regression (drone control, slots, HUD)** | `gameplay-systems-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1` |
| **Prefab structure, wiring, scene integrity** | `prefab-wiring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1` |
| **Collision/visual alignment, building/prop review** | `collision-authoring-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision -ShowInfo` |
| **Collision-heavy multi-agent work** | `collision-chain-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite collision-chain -ShowInfo` |
| **Blender/asset quality review** | `asset-pipeline-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1` |
| **AAA-quality Blender assets** | `aaa-asset-quality-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo` |
| **ModelDoc/VMDL validation** | `modeldoc-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo` |
| **Prefab visual quality** | `prefab-visual-quality-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_visual_quality_audit.ps1` |
| **UI/Razor refresh behavior** | `ui-flow-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning` |
| **Sound wiring and preview** | `sound-control-plane-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sound -ShowInfo` |
| **S&Box API/engine research** | `sbox-engine-reference-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Type Sandbox.GameObject -Member NetworkSpawn` |
| **Official S&Box docs intake** | `sbox-docs-source-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_docs_source_audit.ps1 -Refresh -ShowInfo` |
| **S&Box Learn tutorial intake** | `sbox-learn-intake-agent.md` | `powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_learn_intake_audit.ps1 -ShowInfo` |
| **Post-task training & improvement** | `post-task-training-agent.md` | Type `train` to trigger; runs `scripts/agents/run_agent_checks.ps1 -Suite train` |

Full routing table: see `.agents/sbox/README.md` (38 agents listed with commands).

### Automated Hooks

Eleven hooks in `.claude/settings.json` validate and prevent regressions:

1. **`blend-auto-export`** — Triggers asset pipeline on any `.blend` save
2. **`drone-control-regression-check`** — Validates drone input/pilot/HUD on file changes
3. **`sbox-editor-first-workflow-check`** — Routes editor-first work validation
4. **`sbox-blue-line-check`** — Prevents blockout line strips in playable level
5. **`sbox-engine-reference-check`** — Guards stale API/engine guidance
6. **`sbox-docs-source-check`** — Ensures docs sources stay current
7. **`sbox-learn-intake-check`** — Validates Learn tutorial lessons
8. **`sbox-release-notes-check`** — Routes release/API-change sweeps
9. **`sbox-code-search-check`** — Validates public package adoption
10. **`sbox-animated-model-check`** — Validates animated-model intake work
11. **`sbox-collision-authoring-check`** — Routes collision authoring validation

Hooks emit success/failure notifications. Check the output to confirm validation passed.

### Key Reference Files

| File | Purpose |
|------|---------|
| `.claude/settings.json` | 11 automated hooks and their triggers |
| `.agents/sbox/README.md` | Master routing table (38 agents with commands) |
| `.agents/sbox/editor-first-workflow-agent.md` | Default entry point for editor-capable work |
| `docs/editor_control_plane.md` | MCP endpoint, tool domains, editor control flow |
| `docs/agent_toolkit.md` | Comprehensive agent listing and quick-start |
| `AGENTS.md` | Project rules, post-task training workflow, agent discipline |
| `scripts/agents/run_agent_checks.ps1` | Master audit harness; use `-Suite` to select checks |

### Post-Task Training

**When a task is complete**, type just the word `train` to trigger the post-task training workflow. This:

1. Runs `scripts/agents/run_agent_checks.ps1 -Suite train`
2. Audits the recent goal, changed files, documentation, hooks, agents, subagents, pipelines, and workflows
3. Auto-applies durable improvements to `.agents/` files, hooks, audit scripts, and documentation
4. Outputs a summary of what changed and what still needs human/editor verification

**Example:** After finishing a collision-heavy task, training might detect a new collision pattern and add a focused audit to prevent future regressions.

### When Editor-First Does NOT Apply

- Pure C# refactors (no need to open editor)
- Documentation-only work
- Adding new audit scripts or agent guides
- Investigating code without changing scenes/prefabs

Still use the editor for **final runtime proof** when behavior changed (e.g., take a screenshot or test in play mode).

---

## Building Architecture (Multi-Level Design)

Arena buildings are now designed with gameplay depth: multiple floors, interior spaces, and vertical progression. The House_Large redesign establishes the pattern.

### Structure & Gameplay Levels

Each building supports three gameplay contexts:

- **Ground/Interior** (0–350 units): Main entry, living spaces. Semi-protected from drone sightlines.
- **Elevated/Loft** (350–500 units): Secondary vantage point. Visible to drone but harder to defend.
- **Roof** (500+ units): Highest exposure, best sight-lines. Fully visible to drone, tactical risk/reward.
- **Basement** (optional, −350 to 0): Underground shelter, completely hidden from drone view.

### File Structure

Building models live in `environment_model.blend/<buildingname>.blend` with organized sub-objects:

```
Blender File Structure:
├── Floor_Ground       (walkable surface, 0 height)
├── Floor_Basement     (walkable surface, negative height)
├── Floor_Loft         (partial platform, mid-height)
├── Roof_Sloped        (pitched roof surface)
├── Wall_Exterior_*    (north, south, east, west)
├── Wall_Interior_*    (room dividers)
├── Ladder_To_Loft     (climbable access)
├── Ladder_To_Roof     (continuation to roof)
├── Parapet_*          (low walls around roof edges)
└── Window_Frame_*     (door/window openings)
```

Separate objects per walkable surface are still nice for editing clarity, but no longer required for collision — the exported mesh IS the collision (see below). Visual-only geometry can share objects freely.

### Collision & Gameplay Zones in Prefabs

Buildings use **exact mesh collision** like every other prop (see the standing rule
under [Collision authoring](#collision-authoring-mesh-based--the-default-for-propsbuildings)):
the pipeline bakes a `PhysicsMeshFile` (inside `PhysicsShapeList`) into the
building's `.vmdl` via the `collision` block in its
`scripts/<name>_asset_pipeline.json`, and the prefab puts **one `ModelCollider`
(`Model` = the vmdl, `Static: true`) on the same GameObject as the
`ModelRenderer`**. Floors, walls, roofs, and stairs are all solid with exact
doorway/window openings — no per-part boxes to author or drift.

```json
House_Large (root)
├── Model_Visual (ModelRenderer → house_large.vmdl, ModelCollider → house_large.vmdl)
├── Ladder_To_Loft (LadderVolume + trigger BoxCollider)
├── Ladder_To_Roof (LadderVolume + trigger BoxCollider)
└── Zone_* (trigger-only BoxColliders for gameplay logic)
```

**Collision Rules**:
- Solid collision: ONE `ModelCollider` on the visual GameObject (`Static: true`, `IsTrigger: false`)
- All ladder volumes: `Static: true` (for trigger), `IsTrigger: true`
- All zones (Foyer, LivingArea, Basement, etc.): `IsTrigger: true` (detect player presence, not physical barrier)
- Hand-placed `Collision_*` BoxColliders are the **legacy** pattern (removed from House_Small/Large/house_rural in June 2026). The only remaining legacy holdout is `terrain_pine.prefab`, which has no source `.blend` to re-export from.

### LadderVolume Configuration

Two-ladder pattern (ground→loft, loft→roof):

```json
{
  "__type": "Sandbox.LadderVolume",
  "GrabPadding": 18,           // How far player can reach to grab ladder
  "TopExit": "0,0,185"         // Offset where player exits (relative to ladder position)
}
```

**Calculation**: `Ladder Position + TopExit = Exit Height`
- Ladder_To_Loft at (−50, −100, 0) with TopExit (0, 0, 185) → exits at height 185
- Ladder_To_Roof at (−50, −50, 350) with TopExit (0, 0, 150) → exits at height 500

Verify offsets match floor heights after export (Blender units scale by 0.0254 in game).

### Material Mapping

Reuse arena materials (don't create new ones):

```json
"material_remap": {
  "Material_Brick": "materials/arena/concrete_wall.vmat",
  "Material_Concrete": "materials/arena/concrete_wall.vmat",
  "Material_Wood": "materials/arena/asphalt_cover.vmat",
  "Material_Metal": "materials/arena/metal_pad.vmat",
  "Material_Glass": "materials/arena/asphalt_cover.vmat"
}
```

Available arena materials:
- `concrete_wall.vmat` — walls, floors
- `grass_ground.vmat` — terrain, berms
- `asphalt_cover.vmat` — interior, platforms
- `metal_pad.vmat` — roof, metal structures

### Blender Export & Alignment

**Before saving**:
1. Set each material slot name explicitly (Blender silently appends `.001` on collision)
2. Verify object hierarchy: separate objects for each walkable surface
3. Apply all transforms (Ctrl+A → All Transforms)
4. Orient all geometry with `-Y forward, +Z up` (per pipeline convention)

**After export** (asset pipeline auto-runs on save):
- Verify `Assets/models/<buildingname>.vmdl` created
- Verify `scripts/<buildingname>_asset_pipeline.json` scaffolded
- Check material_remap paths match actual .vmat files in `Assets/materials/arena/`

**Collision alignment** (critical for gameplay):
- Verify `ModelCollider.LocalBounds` is non-zero and ≈ matches `ModelRenderer.LocalBounds`
- Use CollisionDebugViewer (`GameManager` in `main.scene`, set `AlwaysDraw = true`) for the trigger volumes
- Test in-game: walk on all surfaces, climb ladders, verify no clipping

### Debugging Building Issues

**Model won't load**:
- Check `Assets/models/<buildingname>.vmdl` exists
- Verify prefab ModelRenderer.Model points to correct vmdl path
- Confirm material_remap points to existing .vmat files (run pipeline if error)

**Players fall through floors**:
- Check the prefab's `ModelCollider.LocalBounds` — zero bounds means the vmdl has no physics mesh
- Open the vmdl: `PhysicsMeshFile` MUST be nested inside `PhysicsShapeList` (directly under RootNode it is silently ignored)
- Confirm the asset's pipeline config has a `"collision"` block and the pipeline was re-run after adding it

**Can't climb ladder**:
- Ladder position must match visual ladder geometry in model
- LadderVolume.TopExit offset must be non-zero (e.g., not 0,0,0)
- Trigger collider must overlap ladder (use CollisionDebugViewer to verify)

**Ladder clips into geometry on exit**:
- Recalculate TopExit offset: should place player at the adjacent floor height
- Example: if loft floor is at height 360 and ladder is at height 185, TopExit should be (0, 0, 175) to exit at height 185+175=360

### Replicating the Pattern (House_Small, Water Tower, etc.)

For each new building:

1. **Create Blender file** in `environment_model.blend/<buildingname>.blend`
   - Use same axis/scale conventions (-Y forward, +Z up, 0.0254 global scale)
   - Organize by floor: separate objects for each walkable surface
   - Assign material slot names explicitly

2. **Save to trigger pipeline**
   - Pipeline auto-scaffolds `scripts/<buildingname>_asset_pipeline.json`
   - Verify material_remap points to existing arena materials
   - Re-run pipeline if material paths need updating

3. **Update/create prefab** (`Assets/prefabs/environment/<BuildingName>.prefab`)
   - Single Model_Visual child with ModelRenderer → new vmdl
   - Collision children matching walkable surfaces
   - LadderVolume components for vertical access (if applicable)
   - Zone triggers for each gameplay area

4. **Test in-game**
   - Load main.scene
   - Use CollisionDebugViewer to verify collision alignment
   - Walk/climb/jump to validate gameplay feel
   - Verify drone can see intended surfaces, not others

### References in Code

- **LadderVolume** (`Code/Game/LadderVolume.cs`): Configure entry/exit only; do not modify logic
- **CollisionDebugViewer** (`Code/Game/CollisionDebugViewer.cs`): Set `AlwaysDraw = true` for debugging
- **AutoWire** (`Code/code/Wiring/AutoWire.cs`): Resolves prefab references by name; don't use for buildings

---

## What not to do

- Don't rename public components, prefabs, or assets unless the user asks.
- Don't bake new asset paths into code; use prefab references or `[Property]` strings.
- Don't reach for `GameObject.Find()` inside fixed update.
- Don't ship a hand-rolled instantiation of a prefab when you can just edit the prefab JSON and let `GameSetup.SpawnPilotPawn` / `SpawnSoldierPawn` do its job at runtime.
- Don't change `AGENTS.md` content without flagging it — it's the standing AI-workflow rules doc (this file, CLAUDE.md, is canonical for project specifics).
- Don't mix recoil into `EyeAngles` — that's the aim source. Use `_recoilOffset` for camera display only (see `GroundPlayerController.AddRecoil`).
- Don't subscribe to `Health.OnDamaged` / `OnKilled` from a `Component` without storing the handler reference if you ever need to unsubscribe (`KillFeedTracker` and `HudPanel` both manage this — copy their pattern).
- Don't ship a new/exported model "visual only." Collision + physics are part of making a model — see the **STANDING RULE** under [Collision authoring](#collision-authoring-mesh-based--the-default-for-propsbuildings). Skip collision only when the user explicitly says it's decoration, and flag it in your summary.
