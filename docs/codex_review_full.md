# Codex review: Full FPS polish pass + asset pipeline work

You are auditing roughly two weeks of work on an s&box (Source 2 based) game project called "ABOVE / BELOW" (`DroneVsPlayers`). The previous agent shipped a comprehensive FPS polish roadmap covering seven phases of player-feel, weapon-feel, HUD, audio, and asset pipeline work. Your job is to verify *everything* — find bugs, missing wiring, broken JSON, scope drift, anything that would fail to compile, anything that violates the project's conventions, and anything that would not behave correctly at runtime.

**Do not just summarise what was changed.** Read the actual files and report concrete defects. If something is correct, say so briefly and move on. If you cannot verify something without running the editor (e.g. "does the recoil *feel* right"), say so explicitly rather than speculating.

---

## Project context you need before reviewing

- Repo root: `C:\Programming\S&Box\`
- Engine: s&box (Source 2). Components inherit from `Sandbox.Component`. `[Property]` exposes to the inspector. `[Sync]` networks a value. `[Rpc.Broadcast]`, `[Rpc.Owner]`, etc. for networked methods. `IsProxy == true` on remote clients. `Component.ExecuteInEditor` runs in the editor without play mode.
- Game-specific architecture lives in **`CLAUDE.md`** (project root) and the deeper legacy notes in `AGENTS.md`. **Read CLAUDE.md first** — it documents the WeaponPose pattern, the SoldierLoadout slot system, the `GroundPlayerController.Eye` GameObject convention, the recoil rules, the Health event model, the asset pipeline, the HUD layers, the drone prefab conventions, and the `import_scale` gotcha.
- Main scene: `Assets/scenes/main.scene`. Startup scene is the same.
- Asset pipeline is Blender → FBX → vmdl → prefab, driven by `scripts/asset_pipeline.py` with per-asset configs in `scripts/<name>_asset_pipeline.json`. Convention is `axis_forward: "-Y"`, `axis_up: "Z"`, `global_scale: 0.0254`. Material slot names round-trip literally through FBX. There's a known bug in `scripts/smart_asset_export.ps1` where it passes an unrecognised `--blend-file` flag; the workaround is to invoke `asset_pipeline.py` directly.

---

## What was changed (the manifest, grouped by phase)

### Phase 1 — Visible HUD wins

1. **Recoil wired to camera** — `Code/Player/GroundPlayerController.cs` gained `AddRecoil(float pitch, float yaw)`, `RecoilReturnRate`, `_recoilOffset`. Weapons call this on fire. Recoil is applied to the *displayed* camera rotation only; `EyeAngles` (the aim source) is *not* mutated, so aim returns to where the player pointed. `Eye.WorldRotation` is also set to the kicked rotation so anything parented to Eye tracks the kick.
2. **Crosshair** — `Code/UI/HudPanel.razor` + `.razor.scss` got a centered crosshair (4 ticks + dot, `.firing` class spreads ticks after a hit).
3. **Hitmarker** — when the local player damages another `Health`, white X flashes; on kill, larger red X. Sounds: `Assets/sounds/ui_hitmarker.sound`, `Assets/sounds/ui_hitmarker_kill.sound`.
4. **Damage direction indicator** — red arc rotates to point toward the damage source, fades over 2 seconds, stacks up to 8.
5. **Low-HP vignette** — `.low-hp` body class triggers pulsing red radial gradient when HP < 25%.
6. **Empty-magazine click** — pressing fire with `AmmoInMagazine == 0` and not reloading plays `Assets/sounds/empty_click.sound`; reload doesn't auto-trigger.
7. **Kill feed** — `Code/UI/KillFeedTracker.cs` (a `Component`) lives on `GameManager`, auto-subscribes to every `Health.OnKilled`, prunes entries older than `EntryLifetimeSeconds` (5.5 default). HudPanel renders them top-right.
8. **Tab scoreboard** — held `Score` input shows centered two-team table reading `GameStats.GetScoreboard()`.

### Phase 2 — Weapon FX polish

1. **Tracers** — `Assets/prefabs/tracer_default.prefab` exists. New `Code/Player/TracerLifetime.cs` destroys the tracer GameObject after `Lifetime`. `HitscanWeapon.Fire` spawns a tracer with `VectorPoints` set to origin + hit position, broadcast via `BroadcastBulletPath`.
2. **Impact effects** — `Code/Player/ImpactEffects.cs` plays surface-aware sounds (`impact_concrete.sound`, `impact_metal.sound`, `impact_flesh.sound`, `impact_wood.sound`) based on `tr.Surface?.ResourceName`. Decal/particle spawning is *deferred* (no decal prefabs created).
3. **Bullet whip-by** — when a trace passes within ~50 source units of the local player without hitting them, plays `bullet_whip.sound` at the closest point on the trace, and feeds suppression into `GroundPlayerController.AddSuppression`.
4. **Muzzle flash** — still the existing `PointLight` (no new particle sprite added).
5. **Spent casings** — *deferred*.

### Phase 3 — Camera & movement feel

1. **View bob** — `GroundPlayerController` has `ViewBobAmplitude`, `ViewBobFrequency`, `_bobPhase`. Procedural sine offset scales with speed fraction.
2. **Weapon sway/inertia** — implemented inside `WeaponPose.UpdateViewmodel` as a lerp toward the target each frame (rate from `swayLerpRate` parameter, default 18). All held items (rifle, shotgun, jammer, three grenades) inherit this.
3. **ADS** — `GroundPlayerController.SetAdsTarget(bool, float adsFov)`, `_adsT`, `AdsT`, `IsAds`. Weapons call `SetAdsTarget(Input.Down("Attack2"), AdsFovDegrees)` each frame when selected. `WeaponPose.UpdateViewmodel` blends `firstPersonOffset` → `adsOffset` by `pc.AdsT`. Camera FOV interpolates between `BaseFovDegrees` and the requested ADS FOV at `FovLerpRate`. Movement speed scales by `AdsMovementMultiplier` (0.55) while ADS.
4. **Sprint FOV** — `BaseFovDegrees + SprintFovBoost` while sprinting.
5. **Landing dip** — `_landingDipPitch`, `_wasOnGround`, applied as camera pitch on landing.
6. **Footsteps** — `_stepAccumulator` accumulates while on ground; plays `FootstepSound` at intervals. Sound files: `footstep_0.sound` through `footstep_3.sound` (4 randomised samples).
7. **Jump/land sounds** — `OnJump` broadcast plays `jump_grunt.sound`; landing plays `land_thud.sound` scaled by fall speed.

### Phase 4 — Tactical movement

1. **Crouch** — `_crouchT`, `StandingHeight=72` / `CrouchHeight=40`, `StandingEyeZ=64` / `CrouchEyeZ=40`. Held on `Duck` input (or while sliding). Lerps via `CrouchLerpRate`. Movement speed scales by `CrouchMovementMultiplier`.
2. **Lean** — *deferred* (needs new input bindings).
3. **Slide** — `IsSliding`, `_slideTimeLeft`, `_slideDirection`. Pressing crouch while sprinting commits to a directional slide for `SlideDuration` seconds; velocity decays; camera tilts toward slide direction.
4. **Stamina** — `Stamina` (`[Sync]`), `StaminaMaxSeconds`, `StaminaRefillSeconds`. Sprint allowed only above a small dead zone. Rendered as a bar under the HP bar in HudPanel.

### Phase 5 — Audio depth

1. **FP fire layer** — `HitscanWeapon.FireSoundFirstPerson` plays a UI-mode (no distance attenuation) close-mic sound for the local shooter, while the world sound plays for everyone. Files: `m4_fire_fp.sound` for the rifle.
2. **Reload step sounds** — `HitscanWeapon.MagDropSound`, `MagInsertSound`, `BoltRackSound` scheduled at staggered offsets in `BeginReload`. Files: `mag_drop.sound`, `mag_insert.sound`, `bolt_rack.sound`.
3. **Distance attenuation tuning** — `.sound` files' falloff curves audited for BF-style distant gunfights audibility.
4. **Ambient battlefield** — `Code/Game/AmbientSound.cs` loops a single sound from a GameObject. `Assets/sounds/ambient_battlefield.sound` and `AmbientBattlefield` GameObject in `main.scene`.

### Phase 6 — Kill notifications + suppression

1. **"ELIMINATED" popup** — HudPanel shows a center-top "ELIMINATED PlayerName" briefly when `Health.OnKilled` fires with the local player as attacker.
2. **Round transition** — `Assets/sounds/round_start_swell.sound`, played on countdown → active.
3. **Suppression** — when the whip-by fires, `GroundPlayerController.AddSuppression()` adds to `SuppressionT`; HudPanel applies a grey vignette and look sensitivity dampens.

### Phase 7 — First-person arms (stub)

1. **Blender model**: `weapons_model.blend/fps_arms.blend` — root empty `Fps_Arms` parents two forearm cylinders + two hand boxes. Materials `Arms_Sleeve` and `Arms_Glove`.
2. **Pipeline config**: `scripts/fps_arms_asset_pipeline.json`.
3. **Materials**: `Assets/materials/fps_arms_sleeve.vmat`, `Assets/materials/fps_arms_glove.vmat`, both `shaders/complex.shader`.
4. **Exported**: `Assets/models/fps_arms.vmdl` + `.fbx` with material remaps. Bounds reported by editor: `mins(4.5,-12,-19), maxs(32.3,15.7,-7.2)`.
5. **Component**: `Code/Player/FpvArms.cs` — camera-tracking viewmodel with hip↔ADS blend and view inertia, hides on `IsProxy` or `!FirstPerson` by setting `RenderType = Off`. Default offsets `HipOffset=(0,-2,-4)`, `AdsOffset=(-6,-2,2)`.
6. **Prefab wiring**: `FpvArms` GameObject under `Eye` in all four soldier/pilot prefabs (`soldier_assault`, `soldier_counter_uav`, `soldier_heavy`, `pilot_ground`), each with a per-class `ModelRenderer.Tint`.

### Cross-cutting infrastructure work

1. **WeaponPose static utility** — `Code/Player/WeaponPose.cs`. All held items use it: rifle, shotgun, drone jammer, three grenade types. Provides `IsSlotSelected`, `UpdateViewmodel` (with ADS overload), and `SetVisibility`.
2. **Slot system** — `Code/Player/SoldierLoadout.cs`. `[Sync] SelectedSlot`. Listens for `Slot1`/`Slot2` input. `SoldierLoadout.PrimarySlot = 1` (rifle/shotgun/jammer), `EquipmentSlot = 2` (grenades). When a slot isn't selected: `ModelRenderer.RenderType = ShadowsOnly`, input gated off.
3. **Health events** — `Code/Player/Health.cs`. `OnDamaged(DamageInfo)` and `OnKilled(DamageInfo)` fire on every peer. `DamageInfo` has `Amount`, `AttackerId`, `Position`, `WeaponName`. `RequestDamageNamed(amount, attackerId, position, weaponName)` is the canonical entry point for weapons. Each weapon declares `[Property] string WeaponDisplayName`.
4. **Training dummies for solo play** — `Code/Game/TrainingDummy.cs`. Citizens with `Health` + `CharacterController` that respawn after `RespawnSeconds`. Don't use `PilotSoldier` / `SoldierBase` so `RoundManager` win conditions ignore them. Four placed in `main.scene` (`TrainingDummy_NearSpawn`, `Mid_North`, `Mid_South`, `Far_East`). Prefab at `Assets/prefabs/training_dummy.prefab`.
5. **Solo playtest fixes** — `RoundManager.MinPlayers` defaults to 1; the scene-saved value was patched 2→1. Soldier spawn positions moved from `(-1420, ±180, 32)` to `(-880, ±180, 32)` (bunker back wall at `x=-1320` was blocking spawn).
6. **CollisionDebugViewer** — `Code/Game/CollisionDebugViewer.cs`. `Component.ExecuteInEditor` that draws Gizmo wireframes for all `BoxCollider` / `SphereCollider` / `CapsuleCollider` in the scene. Wired onto `GameManager` with `AlwaysDraw = true, __enabled: true`.
7. **M4 import_scale fix** — `Assets/models/weapons/assault_rifle_m4.vmdl` had `import_scale: 1.0` producing 3200-unit bounds (32-meter rifle). Fixed to `0.013`. The prefab's `WeaponVisual.Rotation = "0,-90,0"` maps the model's local +Y barrel onto world forward.
8. **FPV drone pipeline** — new drone variant built procedurally in Blender, exported via pipeline. Drone collider tuned (`BoxCollider.Center = "0,0,1.4"`, `Scale = "16,16,4"`).
9. **Weapon models** — drone jammer gun, frag/chaff/emp grenade models, shotgun all built procedurally in Blender with material slot names matching the vmdl remaps.
10. **30+ procedural WAVs** — generated via Python `wave` module: footsteps×4, impacts×4, jump, land, click, hitmarker, kill_chime, mag_drop, mag_insert, bolt_rack, jammer_loop, grenade_throw, grenade_explosion, shotgun_fire, m4_fire_fp, bullet_whip, ambient_battlefield, round_start_swell. Each has a matching `.sound` JSON file with falloff curves.

---

## What I want you to verify, by area

Work through each area. For each defect: file path, line number, exact problem, recommended fix.

### A. `GroundPlayerController.cs` polish layers

- **Recoil**: `AddRecoil` accumulates into `_recoilOffset`, decays at `RecoilReturnRate`. Verify `EyeAngles` is never touched by recoil. Verify the *displayed* camera rotation (and `Eye.WorldRotation` if used) includes `_recoilOffset` but the aim direction the weapons use for tracing does *not*. Trace which rotation `HitscanWeapon.RequestFire` uses for its trace.
- **View bob, landing dip, footsteps, jump/land sounds**: verify the math doesn't double-apply with the recoil offset or the ADS offset. Look for variable-naming confusion between displayed and aim rotations.
- **ADS state machine**: `_adsT` lerps 0↔1 at `AdsLerpRate`. `IsAds` should be true above some threshold. Verify the FOV target uses the per-weapon requested FOV (passed into `SetAdsTarget`) and falls back to `DefaultAdsFovDegrees`.
- **Crouch / slide**: `_crouchT` lerps; `CharacterController.Height` should follow. While sliding, input should be locked out and movement direction frozen. Verify slide exits cleanly when `_slideTimeLeft` hits zero or velocity drops below walk speed. Look for any state where the player gets stuck in slide.
- **Stamina**: verify `Stamina` ([Sync]) is server-authoritative so cheaters can't fake-sprint. Verify the deadzone prevents flicker between sprint and walk at exactly 0 stamina.
- **Suppression**: `AddSuppression` decays over ~1 second. Verify the look-sensitivity damping applies *only* to displayed rotation, not to actual `EyeAngles` deltas (otherwise getting shot at would mess up your aim).

### B. `WeaponPose.cs` correctness

- Verify the two overloads of `UpdateViewmodel`. The 7-arg version (no ADS offsets) should delegate to the 9-arg version with `adsOffset = firstPersonOffset` (which it does), so grenades behave as if ADS does nothing.
- The "first frame" detection is `current.LengthSquared < 0.01f` — if a held item GameObject is parented under `Body` (which moves with the soldier), its world position is *never* near the origin in normal play. Is this check ever true? Does it matter? Trace through a fresh spawn carefully.
- `SetVisibility` toggles between `On` and `ShadowsOnly`. Verify that's the right choice — the comment claims shadows-only "stays valid for colliders / sound parents."

### C. Every held-item component

The five+ classes that use `WeaponPose` are:
- `Code/Player/HitscanWeapon.cs` (rifle)
- `Code/Player/ShotgunWeapon.cs`
- `Code/Player/DroneJammerGun.cs`
- `Code/Equipment/ThrowableGrenade.cs` + `FragGrenade.cs` / `ChaffGrenade.cs` / `EmpGrenade.cs`

For each: verify
- `Slot` property is correctly set (`PrimarySlot` for guns, `EquipmentSlot` for grenades)
- `IsSelected` uses `WeaponPose.IsSlotSelected(this, Slot)`
- `OnUpdate` calls `WeaponPose.SetVisibility` and `WeaponPose.UpdateViewmodel` with the correct args
- Input gating: `Input.Pressed/Down("Attack1")` etc. should *only* fire when `IsSelected` and not while sliding/sprinting (per the project rule that sprinting disables firing)
- Sounds owned by the item (e.g. `DroneJammerGun`'s loop) force-stop on deselect
- `HitscanWeapon`: recoil call uses `pc.AddRecoil(RecoilDegrees, Random.Shared.Float(-RecoilDegrees*0.3f, RecoilDegrees*0.3f))` or similar; the trace uses *raw* EyeAngles, not the recoil-kicked display rotation
- `RequestDamageNamed` is called (not the older `RequestDamage`) with the weapon's `WeaponDisplayName`
- Reload state machine: verify `BeginReload` schedules `MagDropSound` / `MagInsertSound` / `BoltRackSound` at the correct offsets and that they don't fire twice or stack on rapid reload-cancel-reload

### D. `Health.cs` event model

- `OnDamaged` and `OnKilled` fire on every peer, not just host. Verify with `[Rpc.Broadcast]` or similar.
- `RequestDamageNamed` is host-authoritative. Verify the call path (client → host → broadcast).
- Subscribers (HudPanel, KillFeedTracker) store the handler reference so they can unsubscribe. Verify this on both.
- `DamageInfo.WeaponName` falls back to `"Unknown"` if not set. Verify no nulls bubble through to the UI.

### E. `HudPanel.razor` + `.razor.scss`

- The HUD reads `Connection.Local` and `LocalRole` to decide what to show. Verify it handles the case where the local player hasn't picked a role yet without crashing.
- `BuildHash()` is the re-render gate. Verify it includes every reactive value used in the markup (HP, stamina, AdsT, ammo, kill-feed length, suppression, low-HP class, damage arcs, etc.). A missed input means stale UI.
- `HashCode.Combine` has a max-8-args overload; check no call site exceeds it (the agent had a fix mid-session for a 9-arg call).
- CSS: verify `.low-hp` class triggers only when HP < 25%. Verify the damage-direction arc rotation uses the correct atan2 of (damage source - player position).
- Crosshair: verify only shown when `LocalRole == Soldier`.
- Scoreboard: verify reading `GameStats.GetScoreboard()` doesn't allocate every frame while Tab is held.

### F. `KillFeedTracker.cs`

- Auto-subscription to every `Health` in the scene. Verify it handles `Health` components added *after* scene start (new spawns).
- Pruning: verify `EntryLifetimeSeconds` (5.5) is the cutoff and entries older than that are removed each frame.
- `MaxEntries` (8) cap is enforced even when entries are recent.
- The component lives on `GameManager` in `main.scene`.

### G. Sound files

`Assets/sounds/` should contain matching pairs of `<name>.wav` + `<name>.sound`. Spot-check that each `.sound` JSON has:
- A valid `Sounds` array pointing to the .wav
- A reasonable `Volume`, `Pitch`
- A `Falloff` curve (key sounds like fire/explosion need ~3000-5000 units of audible range)
- `DistanceAttenuation: false` for UI/FP-only sounds (hitmarker, FP fire, mag clicks, empty click)

Verify no `.sound` references a `.wav` that doesn't exist on disk.

### H. Procedural asset pipeline outputs

For each procedurally generated asset:
- `Assets/models/fps_arms.vmdl` (Phase 7)
- `Assets/models/jammer_gun.vmdl`
- `Assets/models/shotgun.vmdl`
- `Assets/models/frag_grenade.vmdl`, `chaff_grenade.vmdl`, `emp_grenade.vmdl`
- `Assets/models/drone_fpv.vmdl`, `drone_fpv_fiber.vmdl`

Verify:
- `RenderMeshFile.import_scale` is sensible (not 1.0 if the source was small; not too small either)
- `material_remap` entries point to actual `.vmat` files that exist
- The matching `.fbx` file is present alongside the `.vmdl`

### I. Prefab JSON integrity

For each prefab modified in this work:
- `soldier_assault.prefab`, `soldier_counter_uav.prefab`, `soldier_heavy.prefab`, `pilot_ground.prefab` — verify the `Eye` child has an `FpvArms` GameObject with a `ModelRenderer` + `DroneVsPlayers.FpvArms` component, the `ArmsRenderer` component-typed ref is wired correctly, and GUIDs don't collide within the file.
- Same prefabs: verify the weapon GameObject (Weapon, Grenade) has `Slot`, `FirstPersonOffset`, `AdsOffset` (where supported), `FirstPersonRotationOffset`, `ThirdPersonLocalPosition`, `ThirdPersonLocalAngles` set, plus weapon-specific properties (sounds, tracer prefab ref, magazine size, etc.).
- `tracer_default.prefab` — has a `LineRenderer` + `TracerLifetime` component, lifetime ~0.06s.
- `training_dummy.prefab` — has `CharacterController`, `Health`, `TrainingDummy`, plus a `Body` child with `SkinnedModelRenderer` + `CitizenAnimationHelper`.

JSON validity: matched braces, no trailing commas, all `__guid`s well-formed UUIDs, all component-typed refs have the correct shape (`_type`, `component_id`, `go`, `component_type`).

### J. `main.scene` integrity

Confirm the scene contains:
- `GameManager` with `GameRules`, `GameStats`, `GameSetup`, `RoundManager`, `AutoWireHelper`, `KillFeedTracker`, `CollisionDebugViewer`. `RoundManager.MinPlayers = 1`.
- `AmbientBattlefield` GameObject with `AmbientSound` component pointing to `sounds/ambient_battlefield.sound`.
- Four `TrainingDummy_*` GameObjects at the documented positions.
- Soldier spawn `PlayerSpawn` GameObjects at `(-880, ±180, 32)` (not `(-1420, ±180, 32)`).
- The scene file is valid JSON.

### K. Phase 7 — first-person arms

Everything from the previous Phase 7-only review prompt. Specifically:
- `Code/Player/FpvArms.cs` — compiles, API-correct, doesn't NPE on missing renderer, snap-on-first-frame check (`current.LengthSquared < 0.01f`) actually works given that FpvArms is parented to `Eye` which has `Position: 0,0,64` relative to soldier root.
- `RenderType = Off` vs `ShadowsOnly`: FpvArms is *never* meant to be visible to remote players. Is `Off` correct, or should arms cast no shadow either? (Casting arms shadows from the first-person viewmodel onto the world would look wrong.)
- Default offsets `HipOffset=(0,-2,-4)`, `AdsOffset=(-6,-2,2)` vs the mesh bounds `mins(4.5,-12,-19), maxs(32.3,15.7,-7.2)`. Are the arms going to render in a visible position in front of the camera? (They might be too far forward and partially clipped by the near plane, or too low.)
- The 4 prefabs: GUID uniqueness, valid JSON, correct component-typed `ArmsRenderer` refs.

### L. CLAUDE.md accuracy

Read all of `CLAUDE.md`. For every factual claim it makes — file paths, property names, default values, behaviour descriptions, conventions ("don't do X", "always do Y") — cross-check against the actual code. Report any drift.

Particular checks:
- Project-layout tree at top: every file listed should exist where claimed.
- "Recoil" section: `AddRecoil` signature and `EyeAngles`-not-touched claim.
- "Health and damage events" section: `OnDamaged` / `OnKilled` / `DamageInfo.WeaponName` / `RequestDamageNamed` all real.
- "HUD feedback layers" section: every described behaviour matches HudPanel code.
- "Held-item viewmodel architecture" section: the listed `[Property]` set matches every consumer.
- "Slot system" section: PrimarySlot=1, EquipmentSlot=2, ShadowsOnly hide behaviour.
- "First-person arms" section (new): every claim about FpvArms.
- "Collider visualisation" section (new): every claim about CollisionDebugViewer.
- "What not to do" list: verify each forbidden pattern is actually absent from the new code (no `GameObject.Find` in fixed update, no recoil mixed into EyeAngles, no renamed public components without permission, etc.).

### M. Convention adherence sweep

- **Recoil rule**: nowhere should `EyeAngles` be mutated by recoil. Grep for `EyeAngles` mutations in the codebase.
- **Networking rule**: footsteps, whips, explosion sounds need to play for everyone — verify they go through `[Rpc.Broadcast]` and not local-only.
- **Sound stop on deselect rule**: any held item that owns a long-running sound (jammer loop, etc.) must stop it when `!IsSelected`.
- **No `GameObject.Find` in hot paths** — grep for it in any `OnUpdate` / `OnFixedUpdate`.
- **No bespoke prefab spawning** when `GameSetup.SpawnPilotPawn` / `SpawnSoldierPawn` should do the work.
- **`Input.config`** — verify every new input action referenced in code (`Slot1`, `Slot2`, `Score`, `Duck`, `TogglePilotControl`, `Attack1`, `Attack2`) has a binding.

### N. Anything else

- Dead code, commented-out blocks, TODO/FIXME markers.
- Files that look duplicated or unused.
- Any test/debug code accidentally committed.
- Performance: any hot loop that does excessive allocation (foreach over `Scene.GetAllComponents<T>()` every frame is fine for the collider viewer in editor, but would be bad in play mode for, say, footstep surface detection).
- Race conditions in network state (e.g. `[Sync]` reads on a not-yet-replicated value).
- Anywhere a `Component` subscribes to an event without storing the handler reference (per the CLAUDE.md rule).

---

## Output format

Reply with four sections:

1. **Critical defects** — would fail to compile, break the scene, crash at runtime, violate a CLAUDE.md rule, or produce visibly wrong gameplay (e.g. weapons not firing, HUD not rendering, network desync). File + line + fix.
2. **Likely bugs** — probably broken but might happen to work in common cases. File + reasoning + fix.
3. **Concerns / smells** — fishy patterns, performance worries, future maintenance traps. No fix required, but note what to watch.
4. **Verified clean** — short bulleted list of things you actually checked and confirmed correct. Don't pad this; only include items that took meaningful verification.

If you can't verify something without running the editor or actually playtesting (e.g. "do the arms appear in the right position"), say so explicitly in section 3 rather than guessing.

Spend more time on the bits the previous agent was uncertain about: the recoil/aim split, the WeaponPose `LengthSquared < 0.01f` snap-check, the `RenderType = Off` vs `ShadowsOnly` decision for FpvArms, the HUD `BuildHash` completeness, the `Health` event unsubscribe pattern, and the M4 `import_scale` fix interacting with the `WeaponVisual.Rotation = "0,-90,0"` muzzle alignment.
