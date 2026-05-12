# Testing Guide for ABOVE / BELOW

## Quick Start Testing (5 minutes)

### 1. Editor Playtest (Solo)
```
1. Open dronevsplayers.sln in S&Box
2. Load scenes/main.scene
3. Press Play (or F5)
4. Expected:
   - Game loads without errors
   - HUD panel appears with health/timer
   - No console errors or warnings
   - Game waits for players (WaitingForPlayers state)
```

### 2. Check Console Logs
```
Expected (successful startup):
- [GameSetup] ... joined. (if host)
- [Menu] Creating lobby (if creating new)
- No red error messages

Not expected:
- "GameManager not found"
- "GameStats not found"
- "RoundManager not found"
```

### 3. Verify Scene Setup
```
1. In editor, look for GameManager GameObject
2. Should have these components:
   ✓ GameSetup
   ✓ RoundManager
   ✓ GameRules
   ✓ GameStats

If missing any, that's the problem - add them!
```

---

## Full Testing (30 minutes)

### Phase 1: Single Player Solo Test (10 min)

**Setup:**
- Load main.scene
- Play in editor (local server)

**Tests:**
1. **HUD Display**
   - [ ] Health shows current/max
   - [ ] Timer counts down (should show 5s countdown, then count to 300)
   - [ ] Role shows "Spectator" (no spawn yet)
   - [ ] Scoreboard shows "Scoreboard:" with no players

2. **Movement Test**
   - [ ] Can move with WASD (if playing as soldier)
   - [ ] Can sprint with Shift
   - [ ] Can jump with Space
   - [ ] Can look around with mouse

3. **Game State**
   - [ ] Stuck in WaitingForPlayers (needs 2+ players)
   - [ ] No movement in counts down yet

### Phase 2: Two Player Network Test (15 min)

**Setup:**
- Launch two S&Box instances
- First instance: Host a new lobby
- Second instance: Join the lobby

**Host Console Should Show:**
```
[GameSetup] Client A joined.
[GameSetup] Client B joined.
```

**Tests:**
1. **Class / Drone Variant Selection**
   - [ ] HudPanel shows the six-option picker (3 soldier classes + 3 drone variants)
   - [ ] Clicking ASSAULT spawns `soldier_assault.prefab`; loadout HUD lists Assault Rifle + Chaff Grenade and the M4-style rifle visual is present on the weapon child
   - [ ] Clicking COUNTER-UAV spawns `soldier_counter_uav.prefab`; loadout HUD lists Drone Jammer + Frag Grenade
   - [ ] Clicking HEAVY spawns `soldier_heavy.prefab`; loadout HUD lists Shotgun + EMP Grenade
   - [ ] Clicking GPS DRONE spawns `pilot_ground.prefab` plus `drone_gps.prefab`; loadout HUD lists GPS Beam + no payload
   - [ ] Clicking FPV DRONE spawns the FPV variant; loadout HUD lists no primary + Kamikaze Charge
   - [ ] Clicking FIBER FPV also renders a `LineRenderer` cable from drone to pilot and shows Kamikaze Charge
   - [ ] Pressing 1 and 2 changes the selected loadout slot highlight
   - [ ] Weapon and equipment slots show ready/cooldown status after firing or throwing

2. **Spawn & Gameplay**
   - [ ] Pilot ground avatar spawns at a soldier-tagged spawn point
   - [ ] The linked drone spawns at a drone-tagged spawn point
   - [ ] After 2+ players with classes selected, countdown starts
   - [ ] Countdown: 5 seconds; Active round: 300 seconds default

3. **Rock-Paper-Scissors Balance Smoke Test**
   - [ ] Counter-UAV reliably jams GPS when the beam has line of sight.
   - [ ] Fiber-Optic FPV ignores Counter-UAV jammer, chaff, and EMP.
   - [ ] Assault rifle remains the clearest answer to Fiber-Optic FPV.
   - [ ] Heavy EMP catches normal FPV dive paths but does not stop Fiber-Optic FPV.
   - [ ] GPS can pressure Heavy from outside shotgun/EMP range with its ranged role enabled.
   - [ ] FPV can punish isolated Assault players, but timed chaff or rifle fire still creates an outplay window.

4. **Combat & Anti-Drone Equipment**
   - [ ] Assault rifle damages soldiers and drones at range
   - [ ] Shotgun (Heavy) deals high close-range damage, falls off with distance
   - [ ] Drone Jammer Gun (Counter-UAV): aim cone at a GPS or FPV drone → drone freezes (input disabled). Aim at fiber-optic FPV → no effect.
   - [ ] Chaff Grenade: small AoE, ~3 s jam, fast cooldown
   - [ ] EMP Grenade: large AoE, ~6 s jam, longer fuse + cooldown
   - [ ] Frag Grenade: damages both soldiers and drones, no jam

5. **Pilot-Death Cascade**
   - [ ] Killing a pilot's ground avatar triggers `PilotLink.IsCrashing` on their drone
   - [ ] Drone's `Rigidbody.Gravity` flips to true, drone falls under gravity
   - [ ] Drone explodes on impact OR after `DroneCrashTimeout` (default 5 s)
   - [ ] Explosion FX plays; drone Health drops to 0

6. **Round Flow**
   - [ ] When all pilot ground avatars dead: "Soldiers win"
   - [ ] When all soldiers dead: "Pilots win"
   - [ ] Victory screen lasts 8 seconds
   - [ ] Next round prompts class picker again (or uses legacy auto-respawn fallback)

### Phase 3: Console Validation (5 min)

**Check for These Log Messages:**

✅ **Expected (Info Level):**
```
[GameSetup] Connection joined.
[Menu] Creating lobby.
[RoundManager] State changed to Countdown
[RoundManager] State changed to Active
[RoundManager] Pilot wins! Score: Pilot 1 - Soldiers 0
```

✅ **Expected (Warning Level, if missing components):**
```
[RoundManager] GameRules component not found.
[HudPanel] GameManager not found.
[MainMenuPanel] GameSetup not found.
```

❌ **NOT Expected (Error Level):**
```
NullReferenceException
ArgumentNullException
Missing component error
```

---

## Advanced Testing (1 hour)

### Memory Leak Test
```
1. Play for 5 full rounds
2. Open S&Box profiler (Shift+F12)
3. Check memory:
   ✓ Memory should NOT continuously increase
   ✓ After garbage collection, should return to baseline
   ✓ If memory increases unbounded → memory leak in events
```

### Network Bandwidth Test
```
1. Use S&Box network profiler
2. Expected bandwidth:
   - ~1-2 KB/s during gameplay
   - ~100 bytes/s waiting for round
3. If much higher:
   - May be sending too much data
   - Check [Sync] properties aren't changing every frame
```

### Stress Test (3+ Players)
```
1. Connect 3-4 clients
2. Play 2-3 full rounds
3. Verify:
   - All clients see same scoreboard
   - No desyncs in kill counts
   - No lag in state updates
   - All win conditions work correctly
```

---

## Common Issues & Debugging

### Issue: "GameManager not found"
**Cause:** Scene doesn't have GameManager GameObject  
**Fix:** 
1. Check scenes/main.scene in editor
2. Create empty GameObject named "GameManager"
3. Add GameSetup, RoundManager, GameRules, GameStats components

### Issue: "WaitingForPlayers forever"
**Cause:** Game never transitions out of WaitingForPlayers  
**Debug:**
1. Check Connection.All.Count in RoundManager.OnFixedUpdate
2. Add temporary Log.Info: `Log.Info( $"Players: {Connection.All.Count}, MinPlayers: {MinPlayers}" );`
3. Should show player count increasing

### Issue: "Scoreboard not updating"
**Cause:** GameStats is null or kills aren't being recorded  
**Debug:**
1. Check RoundManager.OnStart logging for "GameStats not found"
2. In RoundManager.OnHealthComponentKilled, verify damageInfo.AttackerId is valid
3. Add Log.Info in GameStats.RecordKill to verify it's called

### Issue: "HUD doesn't show health"
**Cause:** LocalPlayerHealth is null  
**Debug:**
1. Check GetLocalPlayerHealth() is finding your pawn
2. Verify pawn has Health component
3. Verify Network.Owner is set correctly on spawn

### Issue: "Role selection does nothing"
**Cause:** GameSetup is null or SelectLocalRole isn't being called  
**Debug:**
1. Check MainMenuPanel.OnStart logging
2. Verify GameManager exists and has GameSetup
3. Check console for "Role selected:" log message

---

## Test Checklist

### Before Release
- [ ] Solo playtest works without errors
- [ ] 2-player multiplayer test passes
- [ ] 3-player multiplayer test passes
- [ ] Kill/death tracking accurate
- [ ] Scoreboard syncs across clients
- [ ] Role rotation works
- [ ] No memory leaks detected
- [ ] Network bandwidth acceptable
- [ ] All expected log messages appear
- [ ] No unexpected error messages

### Performance Targets
- [ ] 60 FPS solo playtest
- [ ] 30 FPS multiplayer (3 players)
- [ ] <1s network latency
- [ ] <50ms state update lag

### Edge Cases
- [ ] Player joins mid-round (joins next round)
- [ ] Player disconnects mid-round (game continues)
- [ ] All players disconnect (game stops)
- [ ] Rapid role selection (debounced correctly)

---

## Debugging Commands

**In S&Box Console:**
```csharp
// Check current game state
Log.Info( RoundManager.State );

// Force end round
RoundManager.EndRound( WinningSide.Pilot );

// Get current scoreboard
Log.Info( GameStats.GetScoreboard() );

// Check player count
Log.Info( Connection.All.Count );
```

---

## Performance Profiling

**To profile gameplay:**
1. In S&Box, enable `Profiler` in game settings
2. Play normal gameplay
3. Check:
   - Network ticks: Should be 30/sec
   - [Sync] property updates: Should show bandwidth usage
   - Component updates: Check for expensive operations
   - Memory: Check for leaks

---

## Next Steps After Testing

If all tests pass:
1. ✅ Code is ready for production
2. Create optimized build
3. Deploy to players
4. Monitor server logs for issues

If issues found:
1. Check TEST_AND_IMPROVEMENTS.md for known issues
2. Apply recommended fixes
3. Re-run testing
4. Document new issues found

---

**Test Date:** ________________  
**Tester Name:** ________________  
**Results:** ________________  

Version: 1.0 - Standardization Testing
