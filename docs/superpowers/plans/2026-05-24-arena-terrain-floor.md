# Arena Terrain Floor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `ArenaFloor` from a scaled dev plane into native S&Box terrain that can be sculpted and heightmap-ed in the editor.

**Architecture:** Keep the existing scene layout and object name stable. Add a repo-owned terrain asset under `Assets/terrain/`, replace only the `ArenaFloor` components with `Sandbox.Terrain`, and add a focused audit so future map work preserves the native terrain contract.

**Tech Stack:** S&Box scene JSON, `Sandbox.Terrain`, `Sandbox.TerrainStorage`, PowerShell agent audits, `run_agent_checks.ps1`.

---

### Task 1: Terrain Audit Red Check

**Files:**
- Create: `scripts/agents/terrain_floor_audit.ps1`
- Modify: `scripts/agents/run_agent_checks.ps1`
- Modify: `scripts/agents/test_full_automation_layer.ps1`

- [ ] **Step 1: Write the failing audit**

Create `scripts/agents/terrain_floor_audit.ps1` to parse `Assets/scenes/main.scene`, find the single `ArenaFloor` object, and require:

```powershell
$terrainComponent = $arenaFloor.Components | Where-Object { $_.'__type' -eq 'Sandbox.Terrain' }
$legacyPlane = $arenaFloor.Components | Where-Object { $_.'__type' -eq 'Sandbox.ModelRenderer' -and $_.Model -eq 'models/dev/plane.vmdl' }
$legacyBox = $arenaFloor.Components | Where-Object { $_.'__type' -eq 'Sandbox.BoxCollider' }
```

The audit must fail while `ArenaFloor` is still a dev plane or has a giant box collider.

- [ ] **Step 2: Run the audit and verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/terrain_floor_audit.ps1 -ShowInfo
```

Expected: non-zero exit, with an error explaining that `ArenaFloor` must use `Sandbox.Terrain`.

- [ ] **Step 3: Wire the audit into agent checks**

Add a `terrain` suite to `scripts/agents/run_agent_checks.ps1`, and add a self-test fixture in `scripts/agents/test_full_automation_layer.ps1` so the suite stays discoverable.

### Task 2: Terrain Asset and Scene Conversion

**Files:**
- Create: `Assets/terrain/arena_floor.terrain`
- Modify: `Assets/scenes/main.scene`

- [ ] **Step 1: Create the terrain asset**

Create `Assets/terrain/arena_floor.terrain` as a 512 resolution native terrain asset with:

```json
"Resolution": 512,
"TerrainSize": 10800,
"TerrainHeight": 512,
"Materials": [
  "materials/arena/grass_ground.tmat"
]
```

Use flat initial height data so editor sculpting starts from the current flat floor.

- [ ] **Step 2: Replace only ArenaFloor components**

In `Assets/scenes/main.scene`, leave `ArenaFloor` name, GUID, position, rotation, and scale stable unless editor serialization requires terrain scale reset. Replace the `Sandbox.ModelRenderer` and `Sandbox.BoxCollider` components with a single `Sandbox.Terrain` component linked to `terrain/arena_floor.terrain`, collision enabled, and `TerrainSize` / `TerrainHeight` matching the asset.

- [ ] **Step 3: Verify GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/terrain_floor_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite terrain -ShowInfo
dotnet build Code\dronevsplayers.csproj --no-restore
```

Expected: audit and suite exit 0; build exits 0 or reports only unrelated pre-existing errors that are called out.

### Task 3: Documentation

**Files:**
- Modify: `docs/known_sbox_patterns.md`
- Modify: `docs/agent_toolkit.md`

- [ ] **Step 1: Document the terrain floor contract**

Document that `ArenaFloor` is a native `Sandbox.Terrain` object backed by `Assets/terrain/arena_floor.terrain`, and that terrain edits should preserve the asset-backed heightmap/control-map workflow instead of reverting to `models/dev/plane.vmdl`.

- [ ] **Step 2: Run docs/terrain verification**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite terrain -ShowInfo
```

Expected: exit 0.
