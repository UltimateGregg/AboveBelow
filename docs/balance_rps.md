# ABOVE / BELOW - Rock-Paper-Scissors Balance Spec

## Goal

The class system should feel like a readable rock-paper-scissors game layered on
top of an asymmetric shooter. Each drone variant should have one soldier class it
wants to hunt, one soldier class it should avoid, and one roughly skill-based
matchup. Each soldier class should have the same shape against the drone roster.

This is not meant to create hard counters. A good target is:

| Matchup Type | Desired Feel |
|--------------|--------------|
| Favored | About 60-70% win chance when both players are equally skilled |
| Even | Decided by timing, cover, aim, and team support |
| Unfavored | Still playable, but the player must disengage, bait cooldowns, or call help |

The project already has most of the needed mechanics: jamming susceptibility,
drone speed/health differences, rifle/shotgun damage, chaff, EMP, frag, and
kamikaze FPV drones. The main work left is tuning, readable assets, and small
ability polish where noted below.

## Current Implemented Loadouts

### Pilot Team

| Drone | Current Prefab | Current Role | Key Existing Values |
|-------|----------------|--------------|---------------------|
| GPS | `Assets/prefabs/drone_gps.prefab` | Stable long-range drone | 60 HP, 900 speed, 1.0 jam susceptibility, low-DPS hitscan enabled |
| FPV | `Assets/prefabs/drone_fpv.prefab` | Fast kamikaze dive drone | 45 HP, 1300 speed, 0.85 jam susceptibility, kamikaze enabled |
| Fiber-Optic FPV | `Assets/prefabs/drone_fpv_fiber.prefab` | Jam-immune tether drone | 45 HP, 1100 speed, 0.0 jam susceptibility, kamikaze enabled, visible cable |

Pilots also have a ground avatar:

| Pilot Asset | Role |
|-------------|------|
| `Assets/prefabs/pilot_ground.prefab` | 60 HP remote operator. No offensive weapon. Killing this avatar crashes its linked drone. |

### Soldier Team

| Soldier | Current Prefab | Current Role | Key Existing Values |
|---------|----------------|--------------|---------------------|
| Assault | `Assets/prefabs/soldier_assault.prefab` | Rifle generalist with quick anti-drone cover | 100 HP, rifle 18 damage every 0.12 s, chaff 600 radius / 3 s jam |
| Counter-UAV | `Assets/prefabs/soldier_counter_uav.prefab` | Directional anti-RF specialist | 100 HP, jammer 4000 range / 12 degree cone, frag 320 radius / 130 damage |
| Heavy | `Assets/prefabs/soldier_heavy.prefab` | Tanky close-range area denial | 150 HP, shotgun 8 x 9 damage, EMP 1100 radius / 6 s jam, slower movement |

## Core Counter Triangle

The cleanest balance triangle using the existing roster is:

| Drone | Hunts | Is Countered By | Why |
|-------|-------|-----------------|-----|
| GPS | Heavy | Counter-UAV | GPS can stay outside shotgun/EMP range and punish slow targets. Counter-UAV can hold a jam cone on GPS because GPS is slower and fully RF-susceptible. |
| FPV | Assault | Heavy | FPV speed and burst angle pressure can beat rifle tracking. Heavy survives closer threats, catches dives with EMP, then finishes with shotgun. |
| Fiber FPV | Counter-UAV | Assault | Fiber ignores the jammer gun entirely. Assault does not depend on RF tools and can answer with sustained hitscan damage. |

Soldier view of the same triangle:

| Soldier | Hunts | Is Countered By | Why |
|---------|-------|-----------------|-----|
| Assault | Fiber FPV | FPV | Assault rifle is the best non-RF answer to a jam-immune drone. Fast FPV can force close chaos and punish missed tracking. |
| Counter-UAV | GPS | Fiber FPV | Jammer gun is purpose-built for GPS. Fiber ignores the whole primary weapon, forcing Counter-UAV to rely on frag or teammates. |
| Heavy | FPV | GPS | EMP plus high HP makes Heavy the anti-dive class. GPS can refuse close range and chip down the slow Heavy. |

## 3x3 Matchup Matrix

| Soldier vs Drone | GPS | FPV | Fiber FPV |
|------------------|-----|-----|-----------|
| Assault | Slightly unfavored. Rifle can damage GPS, but GPS should be able to fight from range. Chaff only matters if GPS gets close. | Unfavored. FPV should be fast enough to force panic and punish bad tracking. Timed chaff can still save Assault. | Favored. Rifle remains effective, chaff is not the plan, and the visible tether gives Assault useful information. |
| Counter-UAV | Favored. Jammer cone should reliably freeze GPS if the operator keeps line of sight. | Skill matchup, slightly unfavored. FPV can cross the cone quickly, but a held beam still punishes straight-line dives. | Hard unfavored. Fiber ignores RF jam. Counter-UAV must use frag, terrain, or call Assault. |
| Heavy | Unfavored. GPS should stay beyond shotgun/EMP threat and chip or spot Heavy. | Favored. EMP catches dive paths and shotgun punishes close approach. Heavy HP can survive imperfect FPV burst. | Skill matchup, slightly unfavored. EMP does nothing, but Heavy can deny tight spaces and one-shot careless close passes with shotgun. |

## Recommended Pilot Roles

### GPS Drone - Overwatch

Purpose:
- Long-range pressure and information.
- Best into Heavy because Heavy is slow and short-ranged.
- Worst into Counter-UAV because the jammer cone can lock it down.

Use existing systems:
- Keep `JamSusceptibility = 1.0`.
- Keep 60 HP and stable movement.
- Use `DroneWeapon` as the simplest implementation path for a low-DPS precision weapon.

Implemented starting tuning:
- `DroneWeapon` is enabled on `drone_gps.prefab`.
- `EnableHitscan = true`.
- `EnableKamikaze = false` so GPS does not overlap FPV's job.
- Current first-pass values: `HitscanDamage = 7`, `HitscanInterval = 0.25`, `HitscanRange = 7500`.

Asset direction:
- Larger, stable drone silhouette.
- Antenna/GPS mast.
- Subtle scanning light or camera gimbal.
- Clear long-range muzzle/socket if hitscan remains.
- Audio should be lower and steadier than FPV.

### FPV Drone - Diver

Purpose:
- Fast punish tool against isolated Assault soldiers.
- Best into Assault because speed and commit timing stress rifle tracking.
- Worst into Heavy because EMP catches dive routes and shotgun punishes close range.

Use existing systems:
- Keep `EnableHitscan = false`.
- Keep kamikaze enabled.
- Keep fastest speed and lowest HP.
- Keep nonzero jam susceptibility so chaff, EMP, and jammer can all interrupt it.

Recommended next tuning:
- Keep 45 HP.
- Keep speed around 1300 and boost high.
- Consider a short arming delay or loud arming cue before kamikaze so Heavy can react.
- Do not give FPV a reliable ranged weapon; that would erase the GPS role.

Asset direction:
- Small racing frame.
- Exposed warhead or nose charge.
- Bright arming indicator.
- High-pitched prop audio.
- Strong motion trail/readability for dive paths.

### Fiber-Optic FPV - Jammer Breaker

Purpose:
- Counter Counter-UAV and RF-heavy defenses.
- Best into Counter-UAV because jammer gun, chaff, and EMP do not stop it.
- Worst into Assault because bullets are still bullets.

Use existing systems:
- Keep `JamSusceptibility = 0.0`.
- Keep `FiberCable` visible.
- Keep slower than normal FPV.
- Keep 45 HP.

Recommended next tuning:
- Keep max speed below FPV: 1050-1150 is a good first band.
- Keep kamikaze enabled for now, but consider slightly lower blast radius if it dominates.
- Do not let the cable be invisible; the tether is the main readability cost.
- Later, consider a cable interaction only if needed: cable snag, cable damage, or pilot-location reveal. Do not add this until playtests prove Fiber is too safe.

Asset direction:
- Visible fiber spool on the drone or pilot pack.
- Cable attachment point on drone body.
- Warm/tan or yellow accent to separate it from normal FPV.
- Cable should visually point back toward the pilot often enough that Soldiers can infer a route.

## Recommended Soldier Roles

### Assault - Marksman Generalist

Purpose:
- Best all-around gunfighter.
- Best answer to Fiber because it does not depend on RF disruption.
- Vulnerable to FPV if caught alone or if chaff is mistimed.

Use existing systems:
- Keep `HitscanWeapon`.
- Keep `ChaffGrenade` as a panic/self-peel tool.
- Keep standard 100 HP and normal mobility.

Recommended next tuning:
- Rifle should remain accurate enough to punish Fiber, but not so high-DPS that it deletes every drone instantly.
- Chaff should be short and local: 600 radius / 3 seconds is a good starting point.
- If Assault becomes too strong against FPV, reduce rifle air-target reliability before nerfing chaff.

Asset direction:
- Clean rifle silhouette.
- Chaff grenade should be visually different from frag/EMP: small canister, metallic particle cloud.
- Armor should read as the baseline Soldier body.

### Counter-UAV - RF Lockdown

Purpose:
- Hard answer to GPS and careless FPV.
- Weak into Fiber because RF jamming has no control path to attack.
- Team enabler rather than direct killer.

Use existing systems:
- Keep `DroneJammerGun`.
- Keep `FragGrenade` for non-jam damage.
- Keep standard 100 HP and normal mobility.

Recommended next tuning:
- Jammer should be narrow and readable: 12 degree cone is a good start.
- Keep range high enough to contest GPS: 4000 is a reasonable first value.
- Add strong beam/cone VFX before adding damage. The drone pilot needs to understand why control dropped.
- Do not make the jammer damage Fiber; that would remove Fiber's main purpose.

Asset direction:
- Directional antenna, yagi array, or dish-shaped gun.
- Battery backpack or cable to make the tool recognizable.
- Beam/cone effect that is visible to pilots and soldiers.
- Frag grenade should stay conventional and visually explosive.

### Heavy - Anti-Dive Anchor

Purpose:
- Hold space against FPV dives.
- Best into FPV because EMP catches fast approach and shotgun finishes close drones.
- Weak into GPS because GPS can play outside the Heavy's effective range.

Use existing systems:
- Keep `ShotgunWeapon`.
- Keep `EmpGrenade`.
- Keep 150 HP, slower walk/sprint.

Recommended next tuning:
- EMP should remain big and long: 1100 radius / 6 seconds is the team's major area-denial button.
- EMP should still not affect Fiber if Fiber remains RF-immune.
- Shotgun should be lethal only if the drone commits close. Avoid making it a mid-range anti-air rifle.
- Heavy should need cover or teammates against GPS.

Asset direction:
- Larger armor silhouette.
- Shotgun should read instantly from first person and third person.
- EMP should use a large blue-white pulse sphere/ring so pilots know the danger zone.
- Slower movement needs heavier footstep/audio feedback.

## Team Composition Guidance

Default team sizes are currently 3 Pilots vs 4 Soldiers. That works well for an
RPS layer because one team can cover all three drone jobs while Soldiers get one
extra body for redundancy.

Recommended healthy 4-soldier composition:

| Soldier Slot | Reason |
|--------------|--------|
| 1 Assault | Required Fiber answer and general gun pressure |
| 1 Counter-UAV | Required GPS answer |
| 1 Heavy | Required FPV answer |
| 1 Flex | Map-dependent; Assault on open maps, Heavy on dense maps, Counter-UAV if GPS dominates |

Recommended healthy 3-pilot composition:

| Pilot Slot | Reason |
|------------|--------|
| 1 GPS | Long-range pressure and anti-Heavy |
| 1 FPV | Dive pressure and anti-Assault |
| 1 Fiber | Jammer breaker and anti-Counter-UAV |

If player count is low, prefer one of each role before duplicates. Duplicate FPV
or duplicate Heavy can make the game feel bursty; duplicate GPS or Counter-UAV
can make the game feel stalled.

## Map Balance Requirements

The class triangle only works if the map gives every class a place to play.

Open lanes:
- Needed for GPS to matter.
- Should be broken by rooflines, walls, or smokeable gaps so GPS cannot free-fire forever.

Close cover:
- Needed for FPV approach routes and Heavy anchor positions.
- Should include enough vertical cover that drones must commit into risk.

Jammer sightlines:
- Counter-UAV needs medium-long line-of-sight positions.
- These should not cover the entire skybox from one safe point.

Fiber routing:
- Fiber needs paths where the tether is visible but not instantly fatal.
- Avoid too many sharp cable-snag fantasies until a real cable mechanic exists.

Pilot hiding spots:
- Pilots need defensible but not invulnerable ground positions.
- Every strong pilot nest should have at least two soldier approach routes.

## Asset Production Checklist

### Drone Assets

| Asset | Required Readability |
|-------|----------------------|
| GPS drone | Larger frame, antenna/mast, stable hover, long-range camera/muzzle socket |
| FPV drone | Small racer frame, warhead, arming light, fast/loud prop profile |
| Fiber FPV drone | FPV frame plus spool/cable connector, warm accent, visible tether attachment |

### Soldier Assets

| Asset | Required Readability |
|-------|----------------------|
| Assault | Standard armor, rifle, chaff canister |
| Counter-UAV | Antenna gun, battery pack, directional beam emitter |
| Heavy | Bulkier armor, shotgun, EMP grenade/device |

### Pilot Assets

| Asset | Required Readability |
|-------|----------------------|
| Pilot ground avatar | Light armor, remote controller/tablet/goggles |
| GPS pilot variant | Tablet or antenna pack |
| FPV pilot variant | FPV goggles/controller |
| Fiber pilot variant | Cable spool/backpack, tether outlet |

These can start as material/color swaps on `pilot_ground.prefab`; separate pilot
variant prefabs are optional until the art pass needs them.

## Implementation Notes

The spec can be implemented mostly with existing components:

| Need | Existing Path |
|------|---------------|
| GPS ranged pressure | Implemented on `drone_gps.prefab` with hitscan on and kamikaze off |
| FPV dive role | Already present via `DroneWeapon.EnableKamikaze = true` and `EnableHitscan = false` |
| Fiber RF immunity | Already present via `FiberOpticFpvDrone.JamSusceptibility = 0` |
| Assault anti-Fiber role | Already present via `HitscanWeapon`; no RF dependency |
| Counter-UAV anti-GPS role | Already present via `DroneJammerGun` and GPS susceptibility 1.0 |
| Heavy anti-FPV role | Already present via `EmpGrenade`, `ShotgunWeapon`, and 150 HP |

Do not implement new public class names or prefab reorganizations for this pass.
Use existing prefabs and components first. Add new components only if playtests
show a missing rule that cannot be solved through prefab tuning.

## First Playtest Questions

Run 2v2 first, then 3v4 when enough clients are available.

1. Can Counter-UAV reliably stop GPS without also shutting down the whole sky?
2. Can FPV beat Assault through timing, not unavoidable one-shot trades?
3. Can Heavy stop FPV without making the whole area impossible for drones?
4. Does Fiber feel powerful against Counter-UAV but exposed against normal gunfire?
5. Does GPS have enough ranged pressure without feeling like a safer Assault rifle?
6. Does every death feel explainable from visuals/audio alone?

## Known Design Risks

| Risk | Symptom | First Fix To Try |
|------|---------|------------------|
| GPS has no job | GPS pilots avoid combat or pick FPV instead | Increase GPS utility carefully: small hitscan tuning, spotting, or map sightline changes |
| FPV dominates | Soldiers die before reacting | Add arming cue, reduce blast radius, or make EMP/chaff visuals clearer |
| Fiber dominates | Counter-UAV becomes useless and Assault cannot track Fiber | Make tether more visible, lower Fiber speed, or reduce Fiber blast radius |
| Counter-UAV dominates | Drones spend too much time unable to play | Narrow cone, reduce range, or add stronger jammer VFX before changing durations |
| Heavy dominates | Close areas become drone no-fly zones | Lower EMP duration/radius or increase EMP fuse clarity |
| Assault dominates | Rifle deletes every drone too fast | Reduce rifle air-target DPS or add spread/recoil before changing class identity |

## Target Summary

The intended mental model should be easy to explain:

- Bring Counter-UAV when GPS is farming your team.
- Bring Heavy when FPV keeps diving your team.
- Bring Assault when Fiber ignores your jammers.
- Bring GPS when Heavy is locking down the ground.
- Bring FPV when Assault players are isolated.
- Bring Fiber when Counter-UAV is controlling the sky.
