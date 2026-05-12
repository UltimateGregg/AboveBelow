# Roadmap

Phased plan from "open the project" to "publish on sbox.game". Each phase has a clear deliverable so you know when to move on. Don't skip phases, but feel free to compress them once you're comfortable.

## Phase 0 - Foundation

- [x] Project scaffold (.sbproj, Code/, docs)
- [x] GroundPlayerController, DroneController, Health, weapons
- [x] GameSetup (network listener) and RoundManager (state machine)
- [x] Create main.scene with map, GameManager, spawn points
- [x] Build soldier.prefab and drone.prefab per SETUP.md
- [ ] First two-client local playtest succeeds (drone vs soldier, round ends, roles rotate)

Exit criterion: you can play a 2-player round end-to-end without crashes.

## Phase 0.5 - Class & team system (you are here)

Done as a single batch in May 2026:

- [x] Three drone variants — `GpsDrone`, `FpvDrone`, `FiberOpticFpvDrone` (sharing `DroneBase`)
- [x] Three soldier classes — `AssaultSoldier`, `CounterUavSoldier`, `HeavySoldier` (sharing `SoldierBase`)
- [x] Pilots are now ground-avatar pawns (`PilotSoldier`) flying via a `RemoteController`
- [x] Killing a pilot crashes their linked drone (`PilotLink` + `JammingReceiver`)
- [x] Counter-drone equipment: `DroneJammerGun`, `ChaffGrenade`, `EmpGrenade`, `FragGrenade`
- [x] Two-team match flow in `GameSetup` (default 3 pilots vs 4 soldiers)
- [x] Updated `RoundManager` win conditions to team-based
- [x] Per-class tuning fields in `GameRules`
- [x] HUD class/variant picker (`HudPanel.razor`)
- [x] Visual fiber-optic tether (`FiberCable` + `LineRenderer`)
- [ ] Round-end respawn flow that re-prompts the class picker (currently uses legacy single-pilot rotation as a fallback)

Exit criterion: every class/variant can be picked, the jamming hierarchy holds (jammer gun > chaff > EMP for soldiers; fiber-optic FPV ignores all of them), and pilot-death cascades to a drone crash.

## Phase 1 - Feel pass on the drone

This is where the project lives or dies. A bad-feeling drone kills the loop instantly. Spend real time here.

- Tune `MoveAccel`, `MaxSpeed`, `LinearDamping` on `DroneController` until hover feels stable but not sluggish
- [x] Add a small dead-zone on `Input.MouseDelta` so the drone doesn't drift on stationary mouse jitter
- [x] Expose `VisualTiltDegrees` and tilt smoothing so the drone can be tuned toward "leaning into a turn" instead of "tilting in place"
- [x] Add prop spin (just rotate four child GameObjects on their local Z)
- [x] Add prop audio support (optional looped `SoundEvent`; pitch and volume track throttle)
- Test with a controller as well as mouse+keyboard. Most drone players will reach for a gamepad.

Exit criterion: ten people who've never seen the game can take off, navigate, and land without crashing into geometry on their first attempt.

## Phase 2 - Asymmetric balance

Soldier vs drone is hard to balance. The drone has mobility advantage and information advantage (gimbal camera). Soldiers have numbers and ground cover.

Reference design: `docs/balance_rps.md`.

Target counter triangle:

- Counter-UAV beats GPS; Fiber-Optic FPV beats Counter-UAV.
- Heavy beats FPV; GPS beats Heavy.
- Assault beats Fiber-Optic FPV; FPV beats Assault.

Levers to play with:

- Drone health (currently 60) vs soldier weapon damage (currently 18 per shot, ~5/sec sustained = 90 dps at point-blank)
- Drone hitscan damage / fire rate
- Kamikaze radius (currently 320 units) and damage (200) and falloff
- Time to kill calculations: at default values, a soldier can solo a drone in ~0.7s if every shot lands. Drone can one-shot a soldier with kamikaze. Both feel about right for a tense loop.
- Map design: cover density. Open maps favor the drone, dense urban favors soldiers.
- Soldier count vs drone (consider 1v3 or 1v4, not 1v8)

Build a `BalanceConfig` resource (s&box `GameResource`) so you can tune from outside the prefabs without rebuilding.

## Phase 3 - Match flow polish

- Lobby screen: list connections, show who is queued for the pilot slot next round
- Countdown UI (RazorPanel)
- Round result screen with winner banner
- Score persistence across rounds (already in `RoundManager`, just needs UI)
- Spectator camera for dead players (free fly, follow drone, follow random soldier)
- "Next pilot" rotation that uses K/D ratio or volunteer queue, not just connection order

## Phase 4 - Production assets

Replace placeholder content with real art:

- Drone model (3 LODs, ~5k tris top LOD)
- Drone destruction prefab (smoke, sparks, shell breaking apart)
- Soldier model: just use Citizen for now, customize clothing later
- Map: build one purpose-designed asymmetric map (recommend 60m x 60m with mixed cover, 3-4 levels of verticality)
- Sound design: prop whine, fire control, kamikaze warning beep, explosion, soldier gunfire
- UI theme

## Phase 5 - Server side and cheat resistance

Most of the cheat surface in s&box is closed by host-authoritative damage (already done). Things to harden before public release:

- Validate every `[Rpc.Host]` method's parameters (range checks, cooldowns enforced server-side not just client)
- Trace damage on the host, not the client - currently `HitscanWeapon` traces on the firing client and sends the result. Move the trace to a `[Rpc.Host]` method that takes origin+direction and re-runs the trace authoritatively.
- Rate-limit RPCs per connection
- Drone kamikaze should require a server-side cooldown (1.5s arming) so a flick-detonate isn't possible

## Phase 6 - Publish

- Set `Public: true` in `.sbproj`, fill out `Summary` / `Description` / `ReplaceTags`
- Add screenshots and a thumbnail
- Build a 30-second trailer
- Test with 8 players in a single lobby (max for now) over public network
- Submit to sbox.game

## Stretch features

In rough priority order:

1. ~~Multiple drones per match~~ — done in Phase 0.5
2. ~~Drone classes~~ — done (GPS / FPV / Fiber-Optic FPV)
3. ~~Soldier loadouts~~ — done (Assault / Counter-UAV / Heavy)
4. Destructible cover
5. ~~EMP grenade for soldiers~~ — done (Heavy class)
6. Drone repair stations / soldier ammo crates
7. PvE wave mode: co-op soldiers vs AI drones
8. Fiber-cable severing — physical line cut by bullets/explosions, currently visual-only
9. Pilot self-defense sidearm (currently the pilot has no offensive weapon on the ground)
10. Drone respawn — when a pilot's drone crashes but they survive, give them a way back into the air
