# Claude Code project guide

This is "ABOVE / BELOW" (`DroneVsPlayers`) — a vertical asymmetric s&box shooter. One player flies a drone from above, the rest fight on the ground. Roles rotate each round.

**The detailed rules of the road for changing this project live in [`AGENTS.md`](AGENTS.md).** Read it first. The notes below are the practical, hard-won bits that aren't obvious from a fresh code read.

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
             WeaponPose (static utility), SoldierLoadout, FpvArms,
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

1. **Save** the `.blend` to `<group>_model.blend/<assetname>.blend` (e.g., `weapons_model.blend/watertower.blend`). Use the `mcp__blender_stdio__blender_save_file` tool, or call `bpy.ops.wm.save_as_mainfile(filepath="<absolute path>")` via `execute_blender_code`. Do not skip this step.
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

## First-person arms (`FpvArms` — Phase 7)

Every soldier prefab has an `FpvArms` GameObject as a child of `Eye`. It renders `models/fps_arms.vmdl` (forearm cylinders + boxy hands, tinted per class) and follows the camera every frame — same hip ↔ ADS blend and view-inertia smoothing as `WeaponPose`, just inlined into the component because the arms aren't slot-gated.

Key conventions:
- `IsProxy` hides the renderer entirely for remote players (they see the third-person citizen body's arms instead — no double-arms in the world).
- `FirstPerson == false` (third-person debug mode) also hides the arms.
- Default offsets are tuned for the mesh's natural forward extent (`bounds.x ≈ 4 → 32`): `HipOffset = (0,-2,-4)`, `AdsOffset = (-6,-2,2)`. The mesh sits in front of the camera at hip, pulls back + up on ADS.
- Each soldier prefab tints the arms differently via `ModelRenderer.Tint` to match class colors (assault white, counter-UAV cyan, heavy red-brown, pilot grey-blue).
- The held weapon and the arms are *separate GameObjects* — there's no bone-attach. The arms are purely visual flair behind/around the weapon. A proper rigged setup (Phase 7.B in the roadmap) would parent the weapon to a `hand_R` bone, but the stub version is "two cylinders + two boxes that float into view."

If you swap the arms model, keep the mesh extending in the +X direction with origin near the wrists; adjust offsets only if the new mesh's `bounds.x` minimum is meaningfully different from `~4`.

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

## What not to do

- Don't rename public components, prefabs, or assets unless the user asks.
- Don't bake new asset paths into code; use prefab references or `[Property]` strings.
- Don't reach for `GameObject.Find()` inside fixed update.
- Don't ship a hand-rolled instantiation of a prefab when you can just edit the prefab JSON and let `GameSetup.SpawnPilotPawn` / `SpawnSoldierPawn` do its job at runtime.
- Don't change `AGENTS.md` content without flagging it — that's the legacy source of truth.
- Don't mix recoil into `EyeAngles` — that's the aim source. Use `_recoilOffset` for camera display only (see `GroundPlayerController.AddRecoil`).
- Don't subscribe to `Health.OnDamaged` / `OnKilled` from a `Component` without storing the handler reference if you ever need to unsubscribe (`KillFeedTracker` and `HudPanel` both manage this — copy their pattern).
