# ABOVE / BELOW - Gameplay Loop

## Core Loop (Per Frame / Tick)

### Host (Server)

```
OnFixedUpdate (30 Hz tick rate)
- Input Processing: Receive RPCs from clients
- Physics & Movement: Update drone and soldier positions
- Jam Sources: Decay expired JamSource records on every JammingReceiver
- Game Logic: Check win conditions (per-team), track deaths, drive pilot-death cascade
- Networking Output: Send [Sync] updates and RPCs
```

### Clients (Non-Host)

```
OnFixedUpdate (30 Hz)
- Input Processing: Keyboard/mouse → RPC requests
- Local Prediction: Apply input optimistically
- Receive Updates: Deserialize [Sync] properties
- Apply Jam Gate: Set DroneController.InputEnabled from synced JammingReceiver state
- UI Updates: HudPanel displays health, timer, jam warning, scoreboard
- Audio/Visual Effects: Weapon fire, kills, damage, fiber cable line
```

## Soldier Gameplay Loop

Solo smoke tests start with one local player so the class picker, spawn path,
round timer, and training dummies can be verified without a second client. Team
balance remains configured separately through `GameRules.PilotTeamSize` and
`GameRules.SoldierTeamSize`.

Each soldier picks one of three classes from the HUD picker on first spawn:

| Class | Primary | Secondary |
|-------|---------|-----------|
| Assault | HitscanWeapon (assault rifle) | ChaffGrenade (small AoE drone-jam, 3 s) |
| Counter-UAV | DroneJammerGun (directional, sustained) | FragGrenade (anti-personnel + drone) |
| Heavy | ShotgunWeapon (8 pellets) | EmpGrenade (large AoE drone-jam, 6 s) |

Balance role summary:

| Soldier | Favored Into | Weak Into |
|---------|--------------|-----------|
| Assault | Fiber-Optic FPV | FPV |
| Counter-UAV | GPS | Fiber-Optic FPV |
| Heavy | FPV | GPS |

### Per-Round Active State

```
Every Frame:
- Input: WASD movement, Space jump, Shift sprint
- Movement: CharacterController physics (HeavySoldier walks slower, jumps lower)
- Slot1 selects the primary weapon through `SoldierLoadout`
- Primary weapon (Attack1): hitscan / pellet spread / jam pulse
- Assault rifle uses a 30-round magazine, synced reserve ammo, and `Reload` (`R`) to refill from reserve
- Grenade (Attack2): ThrowableGrenade.BeginThrow -> host-spawned ThrownGrenadeProjectile -> live landing/fuse detonation -> OnDetonate
- HudPanel: Display health, timer, jam warning, scoreboard, and numbered loadout slots
```

### Death

```
Takes Lethal Damage:
- Health.IsDead = true [Sync]
- Health.BroadcastKilled() fires OnKilled event
- GameStats.RecordKill() records the kill
- HudPanel shows "Eliminated by {killer}"
- Spectate until round end
```

## Pilot Gameplay Loop

Each pilot has TWO pawns: a `pilot_ground.prefab` ground avatar (vulnerable, no offensive weapon) AND a linked drone prefab (`drone_gps`, `drone_fpv`, or `drone_fpv_fiber`).

| Variant | Identity | Jam Susceptibility | Notes |
|---------|----------|--------------------|-------|
| GPS | `GpsDrone` | 1.0 (full) | Stable hover, longer range, jammable |
| FPV | `FpvDrone` | 0.85 | Agile, kamikaze-capable |
| Fiber-Optic FPV | `FiberOpticFpvDrone : FpvDrone` | **0.0 (immune)** | Renders a `FiberCable` line back to pilot |

Balance role summary:

| Drone | Favored Into | Weak Into |
|-------|--------------|-----------|
| GPS | Heavy | Counter-UAV |
| FPV | Assault | Heavy |
| Fiber-Optic FPV | Counter-UAV | Assault |

### Per-Round Active State

```
Pilot's Ground Avatar:
- WASD/Space/Shift to walk (slightly slower than soldiers, lower HP)
- RemoteController.ToggleInput (`TogglePilotControl`, F by default) flips between ground POV and drone POV

Pilot's Drone (POV active):
- WASD: Translate (yaw-only frame)
- Space/Ctrl: Ascend/descend
- Mouse X: yaw, Mouse Y: camera pitch
- Shift: boost
- Slot1/Slot2: highlight primary / payload in the loadout HUD
- Attack1: drone primary, if enabled by DroneWeapon config
- Attack2: drone payload / kamikaze, if enabled by DroneWeapon config
- DroneController.InputEnabled is gated by JammingReceiver and PilotLink
```

### Pilot-Death Cascade

```
PilotSoldier.Health.OnKilled fires (host)
  ↓
Linked drone's PilotLink.OnPilotKilled():
  ├─ DroneBase.IsCrashing = true [Sync]
  ├─ DroneController.SetInputEnabled(false)
  └─ Rigidbody.Gravity = true → drone falls
  ↓
On impact OR after CrashTimeout (5 s default):
  ├─ Spawn ExplosionPrefab on all peers
  └─ Health.RequestDamage(9999) destroys drone
```

## Anti-Drone Equipment Loop

```
Counter-UAV soldier holds Drone Jammer Gun:
- Every TickInterval (0.1 s), cone-cast forward
- For each JammingReceiver inside the cone (LOS-checked):
  - ApplyJam(sourceId, Strength=1, Duration=0.3 s)
- The receiver decays sources by Time.Now and re-publishes IsJammed

Soldier throws Chaff or EMP:
- ThrowableGrenade spawns a live grenade projectile on the host
- The projectile traces/bounces through the scene and detonates from its current world position
- On detonation, AoE-iterates all JammingReceiver in radius
- ApplyJam with the grenade's tuned strength + duration

A drone with non-zero JamSusceptibility freezes input until jam decays.
A drone with JamSusceptibility = 0 (fiber-optic FPV) keeps flying through it.
```

## Rock-Paper-Scissors Balance

The current target balance is:

```
Counter-UAV beats GPS
Heavy beats FPV
Assault beats Fiber-Optic FPV

GPS pressures Heavy
FPV pressures Assault
Fiber-Optic FPV pressures Counter-UAV
```

Keep these as strong advantages, not guaranteed wins. See
`docs/balance_rps.md` for the full matchup matrix, asset requirements, and
recommended next tuning.

## Win Conditions

```
Soldiers Win: All PilotSoldier ground avatars IsDead   OR   round timer expires
Pilots Win:   All SoldierBase soldiers IsDead
Round End:    5-second victory screen by default
Next Round:   Respawns players with their latest selected soldier class / drone variant
```

## Statistics Tracking

```
Player A shoots Player B for N damage:
- Health.RequestDamage(N, PlayerA.Id)
- Host applies, CurrentHealth -= N
- If HP <= 0: IsDead = true, BroadcastKilled()
- RoundManager detects the transition
- GameStats.RecordKill(A.Id), RecordDeath(B.Id)
- HudPanel scoreboard updates
```

## Key Timings

| Event | Default | Tunable in |
|-------|---------|------------|
| Countdown | 5 s | `GameRules.CountdownSeconds` |
| Active round | 300 s | `GameRules.RoundTimeSeconds` |
| Round end screen | 5 s | `GameRules.RoundEndScreenSeconds` |
| Pilot crash timeout | 5 s | `GameRules.DroneCrashTimeout` / `PilotLink.CrashTimeout` |
| Drone Jammer Gun pulse | 0.3 s, every 0.1 s | `DroneJammerGun.PulseDuration`, `TickInterval` |
| Assault rifle reload | 1.65 s, 30-round magazine | `HitscanWeapon.ReloadSeconds`, `MagazineSize` |
| Chaff jam | 3 s in 600 unit radius | `GameRules.ChaffRadius`, `ChaffJamSeconds` |
| EMP jam | 6 s in 1100 unit radius | `GameRules.EmpRadius`, `EmpJamSeconds` |

---

Version: 2.1 - Two-team class system with RPS balance target
