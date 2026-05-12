# Setup guide

Step-by-step to get from this scaffold to a playable scene in the s&box editor. Assumes s&box is installed at `D:\SteamLibrary\steamapps\common\sbox` and you have the editor open.

## 1. Move the project into a workspace s&box can see

s&box looks for projects in your `My Documents\sbox\` folder by default (or any folder you add via Editor > Manage Projects). Copy this folder there, or add this folder as a project from the editor's project manager.

When the editor reloads, you should see "ABOVE / BELOW" in your project list.

## 2. Verify the scaffold compiled

Open the project. The editor will compile `Code/` automatically. If you get errors, check the Console window. Most likely culprits on first run:

- Missing assets referenced by `[Property]` fields - fine, just leave them null until you create the prefabs in step 4.
- `Sandbox.Citizen` not found - this is a built-in package; if missing, add it via the Project Settings > Packages tab.

## 3. Create the main scene

`File > New Scene`, save as `Assets/scenes/main.scene`. Then in `dronevsplayers.sbproj` set `StartupScene` to `scenes/main.scene` (already pre-set in the scaffold).

In the scene, create the following GameObjects:

- `World`
  - Add a Map component pointing at any test map (the scaffold uses `facepunch.construct` as a placeholder).
- `GameManager`
  - Add `GameSetup` component
  - Add `RoundManager` component
  - Wire `RoundManager.Setup` -> the `GameSetup` on the same object
- `Camera`
  - Add `CameraComponent`. Leave it where it is; player and drone components grab it from the scene.
- `SpawnPoints`
  - Add child GameObjects with `PlayerSpawn` components. Set Role to Pilot or Soldier on each. Place a few of each around the map.

## 4. Create the Soldier prefab

`Assets/prefabs/soldier.prefab` (`File > New Prefab`):

- Root GameObject
  - `CharacterController` component (capsule height 72, radius 16)
  - `GroundPlayerController` component
  - `Health` component (MaxHealth 100)
  - `Body` child GameObject
    - `SkinnedModelRenderer` -> `models/citizen/citizen.vmdl`
    - `CitizenAnimationHelper` component
  - `Eye` child GameObject (offset Vector3(0, 0, 64))
    - empty, just used as a camera anchor
  - Wire `GroundPlayerController.Body` -> Body, `Eye` -> Eye, `AnimationHelper` -> the helper on Body
- Add a child `Weapon` GameObject under the Body's right hand bone with:
  - `HitscanWeapon` component (Damage 18, FireInterval 0.12)

In `GameSetup`, set `SoldierPrefab` to this prefab.

## 5. Create the Drone prefab

`Assets/prefabs/drone.prefab`:

- Root GameObject
  - `Rigidbody` component (Mass 2.5, Gravity OFF, LinearDamping 2.5, AngularDamping 12)
  - `BoxCollider` or several smaller colliders sized to the drone shell
  - `DroneController` component (link `Body` -> the Rigidbody on the same object, link `VisualModel` -> child below)
  - `DroneCamera` component (link `Drone` -> the controller, `CameraSocket` -> a child socket below)
  - `DroneWeapon` component (link `Drone` -> the controller, `MuzzleSocket` -> child socket below)
  - `Health` component (MaxHealth 60, drone is fragile by design)
- Children:
  - `Visual` -> ModelRenderer with whatever drone mesh you have (for now use `models/dev/box.vmdl` and scale it)
  - `CameraSocket` -> empty, place at front of drone (Vector3(0, 0, 8) is a good start)
  - `MuzzleSocket` -> empty, place at front-bottom

In `GameSetup`, set `DronePrefab` to this prefab.

## 6. Input bindings

Open `Project Settings > Input Actions` and confirm these actions exist (s&box ships defaults for most):

- `Forward`, `Backward`, `Left`, `Right` (default: WASD)
- `Jump` (Space) - reused as drone "ascend"
- `Duck` (Ctrl) - reused as drone "descend"
- `Run` (Shift) - sprint for soldier, boost for drone
- `Attack1` (LMB)
- `Attack2` (RMB)
- `use` (E)

If any are missing, add them. Mouse look is read via `Input.AnalogLook` / `Input.MouseDelta` and doesn't need an action binding.

## 7. Test

`Play Scene` button. You should spawn as the Pilot (in the drone) on the first launch. Open a second client (Tools > Spawn Local Client) - that connection becomes a Soldier. Verify:

- Drone hovers in place when sticks are released
- WASD translates relative to drone's yaw
- Space/Ctrl ascend/descend
- Mouse turns the drone
- Soldier shoots drone -> drone Health drops -> RoundManager detects death -> round ends, roles rotate
- Drone Attack2 (kamikaze) damages soldiers in radius and kills the drone

## Common gotchas

- "Drone falls instantly": Rigidbody Gravity is on. Turn it off in the prefab (DroneController also disables it in OnStart, but the visual fall happens before the first frame).
- "Camera doesn't follow anyone": there is no CameraComponent in the scene. Add one to the World root.
- "I'm IsProxy on my own pawn": the prefab was instantiated without `NetworkSpawn(channel)`. GameSetup handles this; check the console for spawn errors.
- "All players spawn as Soldier": `GameSetup.PilotConnectionId` is reset; verify `[HostSync]` is firing on the host (run in editor with networking active).

## 8. Class & variant prefabs (post-Phase-0.5)

The scaffold now ships seven prefabs in addition to the legacy two:

```
Assets/prefabs/
├── soldier.prefab               (legacy, used as fallback)
├── drone.prefab                 (legacy, used as fallback)
├── soldier_assault.prefab       Assault class — HitscanWeapon + ChaffGrenade
├── soldier_counter_uav.prefab   Counter-UAV class — DroneJammerGun + FragGrenade
├── soldier_heavy.prefab         Heavy class — ShotgunWeapon + EmpGrenade
├── pilot_ground.prefab          Pilot's ground avatar (no offensive weapon, RemoteController)
├── drone_gps.prefab             GPS variant (full RF susceptibility)
├── drone_fpv.prefab             FPV variant (RF susceptible, more agile)
└── drone_fpv_fiber.prefab       Fiber-optic FPV (immune to RF jamming, has LineRenderer + FiberCable)
```

You don't need to wire these by hand — `Code/code/Wiring/AutoWire.cs` resolves prefab references on `GameSetup` at scene start. As long as `AutoWireHelper` exists on the `GameManager`, all seven prefab fields populate automatically.

If you create additional class/variant prefabs, follow the same component layout (`SoldierBase` subclass + Weapon/Grenade children for soldiers; `DroneBase` subclass + `JammingReceiver` + `PilotLink` for drones), then add a path field on `GameSetup` and a wiring entry in `AutoWire.cs`.
