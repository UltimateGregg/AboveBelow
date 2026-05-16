# AI Agent Rules for This S&Box Project

## Core Principles

- Use C# patterns compatible with S&Box.
- Do not make large rewrites without explaining the plan first.
- Prefer small, testable changes.
- Keep gameplay logic separated from UI and editor-only tools.
- Never rename public classes, components, prefabs, or assets unless asked.
- When editing scenes through MCP, summarize objects changed.
- After changes, check compile errors and editor logs.
- Do not invent S&Box APIs. Check docs or existing project patterns first.
- AI Workflow Discipline:
- Break large tasks into small, verifiable phases.
- Complete one gameplay/system change at a time before starting another.
- After each phase:
- compile the project,
- check editor logs,
- summarize changed files,
- and confirm no new warnings/errors were introduced.
- Prefer incremental commits/checkpoints after successful milestones.
- Do not combine gameplay logic rewrites, prefab restructuring, UI changes, and networking changes into a single execution pass unless explicitly requested.
- Before making broad architectural changes, present a scoped implementation plan first.
- If a task expands in scope during execution, stop and summarize the new scope before continuing.
- Prefer adapting existing project patterns over introducing entirely new systems.
- Avoid repeated compile/test loops without identifying the root cause first.

## Project-Specific Guidelines

### Networking
- All networked state must use `[Sync]` properties or RPCs
- Host-authoritative: only the host applies game state changes
- Use `Networking.IsHost` guards before state mutations
- Broadcast RPCs fire on all peers; use for notifications only

### Component Architecture
- Inherit from `Component` for game logic
- Inherit from `PanelComponent` for UI panels
- Use `[Property]` for inspector-exposed fields
- Use `[Sync]` for networked state
- Add `[Title]`, `[Category]`, `[Icon]` attributes for organization

### Prefabs & Scenes
- Soldier, Pilot, and Drone prefabs in `Assets/prefabs/`. The legacy `soldier.prefab` and `drone.prefab` are kept as fallbacks; new code paths use the per-class / per-variant prefabs:
  - `soldier_assault.prefab`, `soldier_counter_uav.prefab`, `soldier_heavy.prefab`, `pilot_ground.prefab`
  - `drone_gps.prefab`, `drone_fpv.prefab`, `drone_fpv_fiber.prefab`
- Main game scene: `/scenes/main.scene`
- Startup scene: `/scenes/main.scene` (no standalone menu scene by default)
- Do not reorganize prefab structure without discussion
- Prefab-property wiring (component refs, child sockets) is mostly automated by `Code/code/Wiring/AutoWire.cs` — extend that file when you add new prefabs

### Code Organization
```
Code/
├── Common/        # Shared enums (PlayerRole, SoldierClass, DroneType), JamSource, PlayerSpawn
├── Game/          # RoundManager, GameRules, GameStats, GameSetup
├── Player/        # Movement (GroundPlayerController), Health,
│                  # Soldier classes (SoldierBase + AssaultSoldier / CounterUavSoldier / HeavySoldier),
│                  # Pilot ground avatar (PilotSoldier, RemoteController),
│                  # Weapons: HitscanWeapon, ShotgunWeapon, DroneJammerGun
├── Drone/         # Flight (DroneController), camera (DroneCamera), weapon (DroneWeapon),
│                  # Variant identity (DroneBase + GpsDrone / FpvDrone / FiberOpticFpvDrone),
│                  # Jamming/crash (JammingReceiver, PilotLink), tether visual (FiberCable)
├── Equipment/     # ThrowableGrenade base + ChaffGrenade / EmpGrenade / FragGrenade
├── UI/            # HudPanel, MainMenuPanel
└── code/Wiring/   # AutoWireHelper — runs at scene load to wire prefab refs
```

### Class system conventions
- **Composition over deep inheritance.** Existing sealed components (`DroneController`, `GroundPlayerController`, `HitscanWeapon`, etc.) provide shared behavior. Variant identity is a *separate* component on the same prefab (`DroneBase` subclasses, `SoldierBase` subclasses).
- **Don't unseal existing classes** unless absolutely necessary — add a new component instead.
- **Drone variants** override `DroneBase.Type` (an abstract `DroneType`) and `JamSusceptibility`. Fiber-optic FPV's `JamSusceptibility` is `0` to make it RF-immune.
- **Soldier classes** override `SoldierBase.Class` (an abstract `SoldierClass`). The actual weapon and grenade live on child GameObjects ("Weapon", "Grenade") on the prefab.
- **Jamming flow:** counter-drone equipment calls `JammingReceiver.ApplyJam(sourceId, strength, duration)` (an `[Rpc.Broadcast]` that only the host applies). The receiver decays sources, syncs `IsJammed`, and gates `DroneController.InputEnabled` based on effective jam.
- **Pilot-drone coupling:** every drone has a `PilotLink` carrying the pilot's connection ID. On pilot death, the link enables gravity, disables input, and detonates after impact or `CrashTimeout`.

### Testing Changes
- Test in editor playtest before networking
- Verify multiplayer behavior with 2+ clients
- Check that [Sync] properties replicate correctly
- Monitor for compile warnings in editor console

### Documentation
- Update `/docs/` when implementing new systems
- Document new public methods with XML comments
- Link to S&Box docs: https://sbox.game/docs
- Add known issues to `/docs/known_sbox_patterns.md`

### Common Pitfalls to Avoid
- Don't subscribe to events without unsubscribing (memory leaks)
- Don't use `GameObject.Find()` in OnFixedUpdate (performance)
- Don't assume client state is authoritative
- Don't hardcode paths; use prefab references or [Property]
- Don't spawn networked objects without `NetworkSpawn()`

## Asset Pipeline Automation (Claude Code Hooks)

This project uses Claude Code hooks to automate the Blender → S&Box asset export pipeline for **any** Blender asset, reducing iteration time from ~45 seconds to ~5-10 seconds per asset change.

### Primary Hook: Auto-Export on ANY .blend Save

**Hook ID:** `blend-auto-export`  
**Configuration File:** `./.claude/settings.json`  
**Trigger:** File save of ANY `.blend` file  
**Action:** Automatically runs `.\scripts\smart_asset_export.ps1`

#### How It Works

1. Edit **any** `.blend` file in Blender
2. Save file (Ctrl+S)
3. Hook detects modification (within 2 seconds)
4. Smart export script runs in background:
   - Detects which asset was saved
   - Checks for asset-specific config (e.g., `drone_asset_pipeline.json` for `drone.blend`)
   - If no filename-matched config exists, checks for exactly one config whose `source_blend` points at the saved `.blend`
   - Falls back to generic config if specific config doesn't exist
   - Launches Blender with `--background` flag (invisible)
   - Exports FBX to `Assets/models/{asset_name}.fbx`
   - Generates VMDL wrapper at `Assets/models/{asset_name}.vmdl`
   - Updates prefab JSON at `Assets/prefabs/{asset_name}.prefab`
5. S&Box editor auto-detects changes and reloads assets
6. Notification appears in Claude Code UI: "Asset exported successfully"

#### Creating New Assets

**Zero setup needed** — just create a `.blend` file and save it. The generic config automatically exports to the right locations:

| You Create | Gets Automatically Exported |
|-----------|---------------------------|
| `drone_model.blend/drone.blend` | `Assets/models/drone.fbx`, `drone.vmdl`, `drone.prefab` |
| `soldier_model.blend/soldier.blend` | `Assets/models/soldier.fbx`, `soldier.vmdl`, `soldier.prefab` |
| `props_model.blend/barrel.blend` | `Assets/models/barrel.fbx`, `barrel.vmdl`, `barrel.prefab` |

For assets that need custom settings (material remaps, scale overrides), create an asset-specific config: `scripts/{asset_name}_asset_pipeline.json`. See `docs/automation.md` for details.

**Asset naming rule:** the filename, config name, and editor-visible model name should match by default. For example, `environment_model.blend/terrain_assets.blend` uses `scripts/terrain_assets_asset_pipeline.json` and writes `Assets/models/terrain_assets.vmdl`. Do not point a newly named Blender file at an old model name such as `terrain_pine.vmdl` unless the user explicitly asks for a legacy alias.

**Terrain assets material rule:** `terrain_assets` is a strict multi-material foliage asset. Its config must keep raw FBX material source names with `"vmdl_material_source_suffix": ""`, `"vmdl_use_global_default": false`, and `"strict_vmdl_material_sources": true`. Do not fix this model with scene `MaterialOverride` or `Materials.indexed`; that can collapse bark and foliage cards to one material. After export, run `.\scripts\agents\fbx_material_slot_audit.ps1 -Config .\scripts\terrain_assets_asset_pipeline.json` or the `modeldoc` suite.

**No manual script execution needed.** The asset pipeline runs automatically on every `.blend` save, for any asset.

#### Disabling the Hook

If the hook is interfering with development, disable it temporarily:

1. Open `./.claude/settings.json`
2. Change `"enabled": true` to `"enabled": false` in the `blend-auto-export` hook
3. Manually run the asset pipeline when needed: `.\scripts\asset_pipeline.ps1`

#### Troubleshooting

- **Hook doesn't fire**: Verify `./.claude/settings.json` is valid JSON and contains the `blend-auto-export` hook
- **Export times out**: If Blender takes >300 seconds to export, hook will timeout. Check if Blender is hanging or if the model is extremely large
- **Prefab doesn't update**: Check S&Box asset browser—it should auto-refresh. If not, manually reload the prefab or restart the editor
- **Permission error**: Ensure PowerShell execution policy allows script execution: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser`

For detailed hook logs and diagnostics, see `docs/automation.md`.
