# ABOVE / BELOW - Architecture Overview

## System Architecture

### Game Managers
| Component | Purpose | Scope |
|-----------|---------|-------|
| **GameSetup** | Handles player connections and pawn spawning | Host-authoritative |
| **RoundManager** | State machine for game flow (Waiting → Countdown → Active → Ended) | Host-authoritative |
| **GameRules** | Replicated balance settings (health, speeds, damage) | All peers |
| **GameStats** | Networked scoreboard with kill/death tracking | All peers |

### Player Systems
| Component | Purpose | Spawned |
|-----------|---------|---------|
| **GroundPlayerController** | First/third-person ground controller (used by soldier classes AND pilot ground avatars) | Per ground pawn |
| **DroneController** | Arcade hover flight model (sealed; shared by all drone variants) | Per drone |
| **Health** | Networked health with damage/death events | All pawns |
| **SoldierLoadout** | Networked soldier slot selection (`1` primary, `2` equipment) | Per soldier pawn |
| **HitscanWeapon** | Hitscan rifle (Assault class) | Per assault soldier |
| **ShotgunWeapon** | Multi-pellet hitscan (Heavy class) | Per heavy soldier |
| **DroneJammerGun** | Directional cone jammer (Counter-UAV class) | Per counter-UAV soldier |

### Class & Variant Identity
| Component | Purpose |
|-----------|---------|
| **SoldierBase** (abstract) | Common identity for soldier classes; subclasses expose `Class : SoldierClass` |
| **AssaultSoldier / CounterUavSoldier / HeavySoldier** | Concrete soldier classes; sit alongside `GroundPlayerController` on each prefab |
| **PilotSoldier** | Identity for pilot ground avatars; carries `LinkedDroneId`, `ChosenDrone` |
| **RemoteController** | Pilot's drone-camera toggle (sibling to `PilotSoldier`) |
| **DroneBase** (abstract) | Common identity for drone variants; subclasses expose `Type : DroneType` and `JamSusceptibility` |
| **GpsDrone / FpvDrone / FiberOpticFpvDrone** | Concrete drone variants; sit alongside `DroneController` on each prefab |

### Drone-Counter & Jamming
| Component | Purpose |
|-----------|---------|
| **JammingReceiver** | Sits on every drone; tracks active `JamSource` records, exposes `[Sync] IsJammed`, gates `DroneController.InputEnabled` based on effective jam (= incoming × susceptibility) |
| **PilotLink** | Binds drone to pilot connection; subscribes to pilot `Health.OnKilled` and triggers crash cascade |
| **FiberCable** | Visual-only line renderer between fiber-optic FPV and its pilot |
| **ThrowableGrenade** (abstract) | Base for thrown items; handles fuse + cooldown, dispatches `OnDetonate` |
| **ChaffGrenade / EmpGrenade / FragGrenade** | Concrete throwables — chaff and EMP apply jam in radius, frag deals damage in radius |

### UI Systems
| Component | Purpose | Parent |
|-----------|---------|--------|
| **ScreenPanel** | Base UI container in `main.scene` | Scene UI |
| **HudPanel** | In-game role picker, health, timer, scoreboard, kill feed | ScreenPanel |
| **MainMenuPanel** | Optional standalone menu panel, not used by startup scene | ScreenPanel |

## Network Architecture

### Replication Model: Host-Authoritative

```
Host (Running Full Game)
├── Authoritative State (RoundManager, GameSetup)
├── All Player Inputs Validated
├── Physics & Combat Resolved
└── Broadcasts [Sync] Updates to Clients
    
Clients (Running Input & Visuals Only)
├── Local Input → RPC Request to Host
├── Receive [Sync] Property Updates
├── Mirror Server State for Display
└── Never Mutate Game Logic
```

### [Sync] Properties (Automatic Replication)

**GameRules** (host → all)
- PilotHealth, SoldierHealth
- DroneSpeedMax, SoldierSprintSpeed
- DroneHitscanDamage, SoldierHitscanDamage
- RoundTimeSeconds, CountdownSeconds

**GameStats** (host → all)
- PlayerKills (NetDictionary<Guid, int>)
- PlayerDeaths (NetDictionary<Guid, int>)
- PlayerNames (NetDictionary<Guid, string>)
- PilotConnection (Guid)

**RoundManager** (host → all)
- State (RoundState enum)
- StateEndsAt (float - timestamp)
- StateSecondsRemaining (int - calculated)
- PilotWins, SoldierWins (int)

**Health** (host → all)
- CurrentHealth (float)
- IsDead (bool)

**Controllers** (owner → all)
- EyeAngles (Angles)
- IsSprinting (bool) - GroundPlayer only
- BoostActive (bool) - Drone only

**SoldierLoadout / HitscanWeapon** (host → all)
- SelectedSlot (int)
- AmmoInMagazine / AmmoReserve (int)
- IsReloading / ReloadFinishTime

**JammingReceiver** (host → all)
- IsJammed (bool)
- IncomingStrength (float)

**DroneBase** (host → all)
- IsCrashing (bool)

**PilotLink** (host → all)
- PilotId (Guid) — connection ID of the pilot operating this drone

**PilotSoldier** (host → all)
- LinkedDroneId (Guid) — the drone GameObject this pilot is flying
- ChosenDrone (DroneType)

**GameSetup** (host → all)
- PilotTeam (NetList&lt;Guid&gt;) — connection IDs on the pilot team
- SoldierTeam (NetList&lt;Guid&gt;) — connection IDs on the soldier team
- PilotConnectionId (Guid, legacy mirror of `PilotTeam[0]`)

### RPC Broadcasts (Fire & Forget)

**Health.BroadcastKilled()**
```csharp
[Rpc.Broadcast]
private void BroadcastKilled( Guid attackerId, float amount )
{
    // Fires on all peers when death occurs
    // Used to trigger HUD kill feed notifications
    OnKilled?.Invoke( damageInfo );
}
```

**RoundManager.BroadcastRoundEnd()**
```csharp
[Rpc.Broadcast]
void BroadcastRoundEnd( int winnerInt )
{
    // Log round result to all peers
    Log.Info( $"{winner} wins!" );
}
```

**GameSetup.PromotePilot()**
```csharp
[Rpc.Broadcast]
public void PromotePilot( Guid newPilotId )
{
    // Host spawns new pilot pawn, demotes old pilot to soldier
}
```

## State Flow

### Per-Round Lifecycle

```
WaitingForPlayers
  ↓ (When 2+ players connected)
Countdown (5 seconds)
  ↓ (Countdown expires)
Active (300 seconds / 5 minutes)
  ├─ CheckWinConditions() each frame
  │  ├─ All PilotSoldier ground avatars dead? → Soldiers win
  │  ├─ All SoldierBase soldiers dead?         → Pilots win
  │  └─ (Legacy fallback if no PilotSoldier in scene: all DroneController dead → Soldiers win)
  └─ Timer expires? → Soldiers win (pilot timeout)
  ↓ (Win condition met)
Ended (8 seconds victory screen)
  ↓ (Screen expires)
ResetForNextRound()
  ├─ Currently uses legacy single-pilot rotation as a respawn fallback
  └─ Future: re-prompt class picker
  ↓
Countdown (5 seconds) [back to top]
```

### Pilot-Death Cascade

```
Soldier kills PilotSoldier ground avatar
  ↓
PilotSoldier.Health.OnKilled fires (host)
  ↓
PilotLink.OnPilotKilled() runs on the linked drone (host only):
  ├─ DroneBase.IsCrashing = true   [Sync → clients]
  ├─ DroneController.SetInputEnabled(false)
  └─ Rigidbody.Gravity = true   (drone falls)
  ↓
PilotLink.OnUpdate() (host) waits for impact OR DroneCrashTimeout
  ↓
Detonate():
  ├─ BroadcastExplosionFx() spawns ExplosionPrefab on all clients
  └─ Health.RequestDamage(9999) destroys the drone
```

### Jamming Pipeline

```
Soldier triggers a jamming tool
  ├─ DroneJammerGun (held)        — directional cone, ApplyJam every TickInterval
  ├─ ChaffGrenade  (on detonate)  — small AoE, ApplyJam to drones in radius
  └─ EmpGrenade    (on detonate)  — large AoE, longer ApplyJam
  ↓
JammingReceiver.ApplyJam(sourceId, strength, duration)  [Rpc.Broadcast, host applies]
  ↓
Host accumulates JamSource records, expires them by Time.Now
  ↓
JammingReceiver.TickHost() recomputes IncomingStrength + IsJammed [Sync → clients]
  ↓
Every peer (including drone owner): JammingReceiver.OnUpdate()
  ├─ effective = IncomingStrength × DroneBase.JamSusceptibility
  └─ DroneController.InputEnabled = (effective < 0.01) && !IsCrashing
```

### Death Tracking Flow

```
Health.TakeDamage(DamageInfo)  [Host only]
  ↓
CurrentHealth -= damage
  ↓
If HP ≤ 0:
  - IsDead = true [Sync → clients]
  - BroadcastKilled(attackerId) [RPC → all]
    ↓
    OnKilled event fires
    ↓
    RoundManager.OnHealthComponentKilled()
      ↓
      GameStats.RecordKill(attackerId)
      ↓
    HudPanel sees kill count increase
      ↓
      Adds to kill feed
```

## Component Ownership

### Network.Owner

```csharp
soldier.GameObject.Network.Owner == Connection.SoldierA
drone.GameObject.Network.Owner == Connection.PilotB
```

Used by:
- HudPanel.GetLocalPlayerHealth() - finds local player's pawn
- RoundManager.FindConnectionForGameObject() - maps pawn to connection
- GroundPlayerController.IsProxy - detects if this instance is non-owner

## Scene Structure

### main.scene (Gameplay)

```
GameObject Tree:
├── GameManager
│   ├── GameSetup (INetworkListener, spawns pawns)
│   ├── RoundManager (state machine)
│   ├── GameRules (balance settings)
│   └── GameStats (scoreboard)
├── Map Geometry
│   ├── Terrain (grass plane)
│   ├── Buildings (4 corner warehouses)
│   ├── Trenches (8 defensive positions)
│   └── Cover (rocks, barriers)
├── Spawn Points
│   ├── PlayerSpawn x3 (west side, soldiers)
│   └── DroneSpawn x4 (east side, pilot)
└── HUD
    ├── ScreenPanel
    └── HudPanel
```

### Prefab Dependencies

```
soldier.prefab
├── GroundPlayerController
├── Health
├── HitscanWeapon
├── CitizenAnimationHelper
└── CharacterController

drone.prefab
├── DroneController
├── Health
├── HitscanWeapon
├── DroneCamera
└── Rigidbody (Gravity=false)
```

## Key Patterns

### Host-Authority Guard
```csharp
public void RecordKill( Guid killerConnection )
{
    if ( !Networking.IsHost ) return;
    // Only host modifies state
    PlayerKills[killerConnection]++;
}
```

### [Sync] Initialization
```csharp
protected override void OnAwake()
{
    // Ensure valid after deserialization
    PlayerKills ??= new NetDictionary<Guid, int>();
}
```

### Dynamic Component Discovery
```csharp
// Find all active Health components each frame
var allHealth = Scene.GetAllComponents<Health>().ToList();
foreach ( var health in allHealth )
{
    if ( health.IsDead && !healthWasDead[health] )
    {
        // Transition detected: alive → dead
        RecordDeath( FindConnectionForGameObject( health.GameObject ) );
    }
}
```

### Owner Verification
```csharp
// Ensure local player can see their own data
if ( health.GameObject.Network.Owner?.Id == Connection.Local?.Id )
{
    // Display this health in HUD
}
```

## Performance Considerations

- **Tick Rate:** 30 ticks/second (configurable in .sbproj)
- **[Sync] Serialization:** Only changed properties are sent
- **Scene Queries:** `GetAllComponents<T>()` runs once per frame in UpdateDeathTracking()
- **Network Bandwidth:** ~1-2 KB/s typical (health updates, position syncs, RPCs)
- **CPU:** ~5ms per frame for game logic (physics, networking, AI if added)

## Future Architecture Extensions

### Spectator Mode
```csharp
public enum PlayerRole { Pilot, Soldier, Spectator }
// Spawn spectator pawn with free camera
// Replicate full scoreboard/HUD data
```

### Power-ups
```csharp
public sealed class PowerUp : Component, INetworkListener
{
    public event Action<Connection> OnPickup;
    public void Activate( GroundPlayerController player ) { ... }
}
```

### Loadout System
```csharp
public sealed class Loadout
{
    public WeaponType weapon;
    public ArmorType armor;
}
// Send loadout from client → host before spawn
```

---

**Architecture Last Reviewed:** May 6, 2026
**Current Version:** 1.0 (Standardized). Player-facing role names rebranded to ABOVE / BELOW; internal `PlayerRole.Pilot`/`.Soldier` enum unchanged.
