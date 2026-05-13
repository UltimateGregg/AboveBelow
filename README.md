# ABOVE / BELOW

A vertical asymmetric shooter. **Pilot team** flies drones from the ground; **Soldier team** hunts pilots and intercepts drones. Pick a class each round, fight until one team is wiped.

> Internal vocabulary: drone operators are **Pilots** (`PlayerRole.Pilot`), ground combatants are **Soldiers** (`PlayerRole.Soldier`). HUD labels still read **ABOVE** for pilots and **BELOW** for soldiers in places where flavor text is desirable.

## Game Overview

**Genre:** Asymmetric team PvP
**Players:** 1-8. Solo smoke tests start with one local player; intended team play defaults to 3 pilots vs 4 soldiers through `GameRules`.
**Platform:** S&Box
**Status:** Class system implemented. Rock-paper-scissors balance design is documented; tuning and art pass pending.

### Teams

**Pilot Team** — each pilot picks one of three drone variants:

| Drone | Strength | Weakness |
|-------|----------|----------|
| **GPS** | Long range, stable hover, anti-Heavy pressure | Fully susceptible to Counter-UAV jamming |
| **FPV** | Agile, kamikaze-capable, strong into isolated Assault | Vulnerable to Heavy EMP/shotgun area denial |
| **Fiber-Optic FPV** | **Immune to all RF jamming**; strong into Counter-UAV | Lower top-end than FPV, visible tether, vulnerable to rifle fire |

Pilots walk on the ground inside a lightly-armored avatar. Killing the pilot crashes the drone immediately.

**Soldier Team** — each soldier picks one of three combat classes:

| Class | Weapon | Grenade | Notes |
|-------|--------|---------|-------|
| **Assault** | Assault rifle (HitscanWeapon, 18 dmg) | **Chaff Grenade** (small AoE, ~3 s drone-jam) | Best non-RF answer to Fiber FPV |
| **Counter-UAV** | **Drone Jammer Gun** (directional cone, sustained jam) | Frag grenade | Best answer to GPS drones |
| **Heavy** | Shotgun (8 pellets, close range) | **EMP Grenade** (large AoE, ~6 s drone-jam) | Best answer to FPV dive drones |

Core counter triangle: **Counter-UAV beats GPS**, **Heavy beats FPV**, **Assault beats Fiber**. In the other direction, **GPS pressures Heavy**, **FPV pressures Assault**, and **Fiber pressures Counter-UAV**. See [Rock-Paper-Scissors Balance Spec](docs/balance_rps.md).

### Win Conditions

- **Soldiers win** when every Pilot ground avatar is dead.
- **Pilots win** when every Soldier is dead.
- Round timer (default 5 min) auto-ends in soldier favor if neither team is wiped.

## Getting Started

### Setup
1. Open project in S&Box (`scenes/main.scene` is the default).
2. Press Play in editor.
3. Pick a class or drone type from the in-game HUD picker.

### Key Controls

**Soldier (Assault / Counter-UAV / Heavy):**
- WASD, Space, Shift — Move / Jump / Sprint
- 1 / 2 — Highlight primary / equipment in the loadout HUD
- Left Click — Primary weapon
- Right Click — Throw grenade

**Pilot (drone POV):**
- WASD — Translate (yaw-only frame)
- Space / Ctrl — Ascend / Descend
- Mouse X — Yaw · Mouse Y — Camera pitch
- Shift — Boost
- 1 / 2 — Highlight primary / payload in the loadout HUD
- Left Click — Drone primary, if equipped
- Right Click — Drone payload / ability, if equipped
- X — Toggle camera between FPV and chase

**Pilot (ground POV — Remote Controller):**
- F — Toggle between drone view and ground view
- Standard ground movement otherwise

## Project Structure

```
Code/
├── Common/        PlayerRole · SoldierClass · DroneType · JamSource · PlayerSpawn
├── Game/          GameRules · GameSetup · GameStats · RoundManager
├── Player/        GroundPlayerController · Health
│                  HitscanWeapon · ShotgunWeapon · DroneJammerGun
│                  SoldierBase · AssaultSoldier · CounterUavSoldier · HeavySoldier
│                  PilotSoldier · RemoteController
├── Drone/         DroneController · DroneCamera · DroneWeapon
│                  DroneBase · GpsDrone · FpvDrone · FiberOpticFpvDrone
│                  JammingReceiver · PilotLink · FiberCable
├── Equipment/     ThrowableGrenade · ChaffGrenade · EmpGrenade · FragGrenade
└── UI/            HudPanel · MainMenuPanel

Assets/prefabs/
├── soldier.prefab               (legacy template, kept as fallback)
├── drone.prefab                 (legacy template, kept as fallback)
├── soldier_assault.prefab       Assault class
├── soldier_counter_uav.prefab   Counter-UAV class
├── soldier_heavy.prefab         Heavy class
├── pilot_ground.prefab          Pilot's ground avatar (no offensive weapon)
├── drone_gps.prefab             GPS drone variant
├── drone_fpv.prefab             FPV drone variant
└── drone_fpv_fiber.prefab       Fiber-optic FPV (immune to jamming)
```

## Architecture Highlights

### Two-team class system
- `SoldierClass` enum + `SoldierBase` abstract identity component on each soldier prefab.
- `DroneType` enum + `DroneBase` abstract identity component on each drone prefab.
- Existing sealed `DroneController` / `GroundPlayerController` provide shared flight & movement; variant identity sits on a separate sibling component (composition over deep inheritance).

### Jamming
- `JammingReceiver` lives on every drone. Tracks active `JamSource` records host-side, exposes a synced `IsJammed` for clients.
- Effective jam = `IncomingStrength × DroneBase.JamSusceptibility`. Fiber-optic FPV's susceptibility is `0`, so it ignores all RF-based jamming.
- Three jamming tools, each tuned to a different niche:
  - **DroneJammerGun** — directional cone, sustained while held, single-target.
  - **ChaffGrenade** — small AoE, short duration, low cooldown (MGS-style).
  - **EmpGrenade** — large AoE, long duration, longer fuse + cooldown.

### Pilot ↔ Drone link
- `PilotLink` on each drone holds the pilot's connection ID (`PilotId`).
- When the pilot's `Health.OnKilled` fires, the link sets `IsCrashing`, enables gravity on the rigidbody, disables the drone's input, and detonates after impact or `CrashTimeout`.

### Network Pattern (host-authoritative)
- `[Sync]` for replicated state (jam status, health, team lists).
- `[Rpc.Broadcast]` + `if (!Networking.IsHost) return;` for damage / spawn / jam application.
- `NetList<Guid>` on `GameSetup.PilotTeam` / `SoldierTeam` syncs team membership.

### Game Configuration
- `GameRules.cs` exposes per-class health/speed, per-tool tuning (jam radii, durations), team sizes, crash timeout.
- All `[Property, Sync]`, so tweak in the inspector at runtime.

## Adding Content

### Add a new soldier class
1. Add an enum value to `SoldierClass`.
2. Create `MyNewClass : SoldierBase` returning that enum value.
3. Duplicate `soldier_assault.prefab`, swap the `SoldierBase` component for your subclass, and pick weapon + grenade child components.
4. Add a prefab reference + path field to `GameSetup.cs` (and an option to the HUD picker).

### Add a new drone variant
1. Add an enum value to `DroneType`.
2. Create `MyNewDrone : DroneBase` (or `: FpvDrone` etc.) with the right `JamSusceptibility`.
3. Duplicate `drone_gps.prefab`, swap the variant component, retune the `DroneController` properties for flight feel.
4. Wire it into `GameSetup` and the HUD picker.

### Add anti-drone equipment
- Apply jam to drones via `JammingReceiver.ApplyJam(sourceId, strength, duration)` from any host-only context.
- Pattern after `DroneJammerGun` (continuous) or `ChaffGrenade` / `EmpGrenade` (instantaneous AoE).

## Testing Checklist

- [ ] Solo playtest spawns the class picker and lets you choose any class / drone variant.
- [ ] Drone Jammer Gun cone disables a GPS / FPV drone but **not** a fiber-optic FPV.
- [ ] Chaff vs EMP show the expected radius/duration delta.
- [ ] Killing the pilot's ground avatar crashes their drone within `DroneCrashTimeout`.
- [ ] Round ends correctly when one whole team is wiped.
- [ ] No console errors after compile.

## References

- [S&Box Documentation](https://sbox.game/docs)
- [S&Box Networking Guide](https://sbox.game/docs/networking)
- [Rock-Paper-Scissors Balance Spec](docs/balance_rps.md)
- [Game Architecture](docs/architecture.md)
- [Gameplay Loop](docs/gameplay_loop.md)
- [Wiring Guide](WIRING.md) — manual prefab inspector wiring (mostly automated by `AutoWireHelper`)

---

**Last Updated:** May 8, 2026
**Status:** Two-team class system in. RPS balance spec documented. Tuning + production art still pending.
