# Wiring guide

The scaffold ships with `main.scene` plus a full set of class/variant prefabs in `Assets/prefabs/`. Almost everything is wired automatically by `Code/code/Wiring/AutoWire.cs` (which runs at scene load and self-destructs once it's done its job). This document covers the few cases where you might still need to wire something by hand.

Estimated time for a fresh checkout: 1-2 minutes if `AutoWire` is in the scene; ~5 minutes if you've removed it.

## main.scene

Select the `GameManager` GameObject. `AutoWireHelper` will populate every prefab reference on `GameSetup` from the prefab paths it knows about. If you want to point at a custom prefab, override the inspector field after AutoWire has run (or change the path string property on `GameSetup`).

You can leave the inspector blank for these and AutoWire will fill them in:

- `GameSetup.SoldierPrefab` / `DronePrefab` (legacy fallbacks)
- `GameSetup.AssaultPrefab` / `CounterUavPrefab` / `HeavyPrefab`
- `GameSetup.PilotGroundPrefab`
- `GameSetup.GpsDronePrefab` / `FpvDronePrefab` / `FiberOpticFpvDronePrefab`
- `GameSetup.Round` ↔ `RoundManager.Setup`

Also on the `GameManager`: ensure there's an `AutoWireHelper` component. If it's missing, add it — it's a one-shot that runs at scene start.

## Drone prefabs

`drone_gps.prefab`, `drone_fpv.prefab`, `drone_fpv_fiber.prefab` all share the same component layout (the JSON sets the GUID-based references, AutoWire re-resolves them after load):

- Root has: `Rigidbody`, `BoxCollider`, `DroneController`, `DroneCamera`, `Health`, the variant component (`GpsDrone` / `FpvDrone` / `FiberOpticFpvDrone`), `JammingReceiver`, `PilotLink`, optionally `DroneWeapon` (FPV variants).
- Children: `Visual` (with `ModelRenderer`), `CameraSocket`, `MuzzleSocket`. Add propeller subtrees here as you replace the placeholder model.
- Fiber-optic FPV adds `LineRenderer` + `FiberCable` on the root.

If you build a new drone prefab and AutoWire isn't picking up its references, double-check the GUIDs in the JSON match what the `__type` references expect, or wire the component fields manually in the prefab editor.

## Soldier / Pilot prefabs

`soldier_assault.prefab`, `soldier_counter_uav.prefab`, `soldier_heavy.prefab`, `pilot_ground.prefab` share the same shape as the legacy `soldier.prefab`:

- Root: `CharacterController`, `GroundPlayerController`, `Health`, the class component (`AssaultSoldier`, `CounterUavSoldier`, `HeavySoldier`, or `PilotSoldier` + `RemoteController`).
- `Body` child: `SkinnedModelRenderer` + `CitizenAnimationHelper`. Houses the weapon and grenade child objects.
  - `Weapon` child: weapon component + `MuzzleSocket` child.
  - `Grenade` child: grenade component (no socket needed).
- `Eye` child for first-person camera.

Inspector overrides you may want to set manually:

- `HitscanWeapon` / `ShotgunWeapon` / `DroneJammerGun`: `TracerPrefab`, `FireSound`, `LoopSound` — placeholder is fine, set when you have art.
- `FragGrenade.ExplosionPrefab`: AutoWire points it at `models/effects/explosion_med.prefab`. Override per prefab if you want unique FX.
- `ChaffGrenade.EffectPrefab` / `EmpGrenade.EffectPrefab`: optional, set when you have particle assets.

## Then play

Hit `Play Scene` in the editor. You should:

1. Compile cleanly (no red errors in the editor console).
2. See the in-HUD class picker on first spawn.
3. Be able to spawn as any of the six options (3 soldier classes + 3 drone types).

## If something doesn't fly

- **Drone falls instantly** — `Rigidbody.Gravity` is checked. The prefab JSON sets it false, but `PilotLink` will set it true once the pilot dies. If that happens unexpectedly, check `PilotLink.IsCrashing`.
- **Drone Jammer Gun does nothing against fiber-optic FPV** — that's intentional; the cable carries control around the jam.
- **HUD picker doesn't appear** — the picker is gated on `GameSetup.NeedsLocalRoleChoice()` returning true. Once you're spawned, it hides; pick a different class via console / dev tools or revert state.
- **Pilot can't see the drone POV** — `RemoteController` toggles on `Attack1` (left click) by default. Confirm the `DroneCamera` on the linked drone is enabled and not a proxy.
- **Soldier T-poses** — `CitizenAnimationHelper.Target` reference is missing on the Body child. AutoWire fixes this; if you removed AutoWire, wire it manually.
- **Fiber cable not rendering** — confirm the drone has a `LineRenderer` component (it's part of `drone_fpv_fiber.prefab`) and that `FiberCable.Link.PilotId` resolves to a live `PilotSoldier`.
