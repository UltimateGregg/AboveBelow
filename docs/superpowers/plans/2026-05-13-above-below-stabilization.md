# ABOVE / BELOW Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the playable round, spawn, and loadout loop before moving into feel and art/content passes.

**Architecture:** Keep changes inside the existing S&Box component model. `GameSetup` remains the host-authoritative spawn/loadout owner, `RoundManager` remains the round state machine, and docs mirror actual configured controls.

**Tech Stack:** S&Box C# components, prefab/scene JSON, PowerShell validation scripts, `dotnet build`.

---

### Task 1: Baseline Verification

**Files:**
- Read: `C:\Programming\S&Box\Code\dronevsplayers.csproj`
- Read: `C:\Programming\S&Box\scripts\check_loadout_slots.ps1`

- [ ] **Step 1: Confirm compile health**

Run:

```powershell
dotnet build Code\dronevsplayers.csproj --no-restore
```

Expected: `Build succeeded.` with `0 Warning(s), 0 Error(s)`.

- [ ] **Step 2: Confirm loadout slot wiring**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_loadout_slots.ps1
```

Expected: `Loadout slot check passed for 4 prefabs.`

### Task 2: Solo Smoke-Test Start

**Files:**
- Modify: `C:\Programming\S&Box\Code\Game\GameRules.cs`
- Modify: `C:\Programming\S&Box\Assets\scenes\main.scene`
- Modify: `C:\Programming\S&Box\docs\gameplay_loop.md`

- [ ] **Step 1: Make solo start the code default**

In `Code\Game\GameRules.cs`, set:

```csharp
[Property, Sync] public int MinPlayersToStart { get; set; } = 1;
```

- [ ] **Step 2: Make the scene match the code default**

In `Assets\scenes\main.scene`, set both saved values to `1`:

```json
"MinPlayersToStart": 1
"MinPlayers": 1
```

- [ ] **Step 3: Document solo smoke-test behavior**

In `docs\gameplay_loop.md`, make the player-count section say solo smoke testing starts at one local player, while production team balance remains driven by `GameRules.PilotTeamSize` and `GameRules.SoldierTeamSize`.

- [ ] **Step 4: Verify**

Run:

```powershell
dotnet build Code\dronevsplayers.csproj --no-restore
powershell -ExecutionPolicy Bypass -File scripts\check_loadout_slots.ps1
```

Expected: compile and loadout checks both pass.

### Task 3: Preserve Selected Loadouts Across Round Reset

**Files:**
- Modify: `C:\Programming\S&Box\Code\Game\GameSetup.cs`
- Modify: `C:\Programming\S&Box\Code\Game\RoundManager.cs`
- Modify: `C:\Programming\S&Box\docs\architecture.md`

- [ ] **Step 1: Store selected loadouts host-side**

Add dictionaries to `GameSetup`:

```csharp
readonly Dictionary<Guid, SoldierClass> _selectedSoldierClasses = new();
readonly Dictionary<Guid, DroneType> _selectedDroneTypes = new();
```

- [ ] **Step 2: Record selections on spawn requests**

Inside `RequestSpawn`, after validating `role`, `cls`, and `type`, record the current choice:

```csharp
if ( role == PlayerRole.Pilot )
	_selectedDroneTypes[connId] = type;
else if ( role == PlayerRole.Soldier )
	_selectedSoldierClasses[connId] = cls;
```

- [ ] **Step 3: Add explicit respawn helper**

Add `RespawnWithSelectedLoadout(Connection channel, PlayerRole role)` to `GameSetup`. It should use `_selectedDroneTypes.GetValueOrDefault(channel.Id, DroneType.Gps)` for pilots and `_selectedSoldierClasses.GetValueOrDefault(channel.Id, SoldierClass.Assault)` for soldiers.

- [ ] **Step 4: Use selected loadouts during round reset**

In `RoundManager.ResetForNextRound`, replace calls to `Setup.SpawnPawnFor(conn, PlayerRole.Soldier)` with `Setup.RespawnWithSelectedLoadout(conn, PlayerRole.Soldier)`.

- [ ] **Step 5: Preserve promoted pilot choice when possible**

In `GameSetup.PromotePilot`, spawn the new pilot using their stored drone type and demoted pilots using their stored soldier class instead of forcing GPS and Assault.

- [ ] **Step 6: Verify**

Run:

```powershell
dotnet build Code\dronevsplayers.csproj --no-restore
```

Expected: compile passes with no warnings or errors.

### Task 4: Control Prompt And Documentation Drift

**Files:**
- Modify: `C:\Programming\S&Box\README.md`
- Modify: `C:\Programming\S&Box\docs\gameplay_loop.md`
- Verify: `C:\Programming\S&Box\ProjectSettings\Input.config`
- Verify: `C:\Programming\S&Box\Code\UI\HudPanel.razor`

- [ ] **Step 1: Align pilot ground toggle docs**

Ensure every documented pilot ground toggle says `F`, matching `TogglePilotControl` in `ProjectSettings\Input.config` and the HUD.

- [ ] **Step 2: Align drone camera toggle docs**

Ensure every documented drone camera toggle says `X`, matching `ToggleDroneCamera`.

- [ ] **Step 3: Verify text references**

Run:

```powershell
rg -n "TogglePilotControl|ToggleDroneCamera| T | F | X " README.md docs Code\UI\HudPanel.razor ProjectSettings\Input.config
```

Expected: no remaining stale claim that `TogglePilotControl` is bound to `T`.

### Task 5: Stabilization Gate

**Files:**
- Read: changed files from Tasks 2-4

- [ ] **Step 1: Run compile and slot validation**

Run:

```powershell
dotnet build Code\dronevsplayers.csproj --no-restore
powershell -ExecutionPolicy Bypass -File scripts\check_loadout_slots.ps1
```

Expected: both pass.

- [ ] **Step 2: Summarize remaining runtime gap**

If S&Box editor logs are unavailable or stale, state that runtime playtest confirmation still needs an editor play session. Do not claim multiplayer behavior is fully verified from build-only evidence.
