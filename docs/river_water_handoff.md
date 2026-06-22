# Handoff: Flowing river in the carved channel (water surface not rendering)

> Cold-start handoff for a follow-up agent (e.g. Codex). The river is **set up
> correctly** but the **Water Tool surface does not visibly render in play**.
> Terrain rendering, which broke during testing, has been **fixed**. Your job is to
> get the water surface to actually render in-game (or determine it's a
> library/engine incompatibility and pick an alternative).

## Goal

Add a flowing river to "ABOVE / BELOW" (`DroneVsPlayers`, an s&box game). The river
should follow the **sand-textured, already-carved channel** that winds across the
terrain in `main.scene` and passes **under the road bridge** (`RoadCorridor_Main`).
The user installed the **Water Tool** library (`redsnail.watertool`) for this.

## Environment (important)

- **Patched s&box source build**: `C:\programming\sbox-public\game\sbox-dev.exe`
  ("S&Box Editor (Patched)"). This matters — precompiled library shaders may be
  incompatible with this build.
- Project root: `C:\Programming\S&Box`. Main scene: `Assets/scenes/main.scene`.
- Water Tool library: `Libraries/redsnail.watertool/`.
- Editor MCP server (jtc.mcp-server) on `http://localhost:29015` — used for
  scene/component edits and play control.

## Terrain facts (measured live)

- `ArenaFloor` (GUID `11111111-0001-8010-0000-000000000001`), `Terrain` component.
  `TerrainSize=21600`, centered on origin, base plane world **Z=-8**,
  `TerrainHeight=512`, heightmap `Resolution=512`.
- Height conversion: `worldZ = -8 + (heightmapValue/65535)*512`.
- Heightmap dump: `min=0 max≈47912 mean≈30390`. So grassland/banks ≈ **Z 160–180**
  (road deck Z=168), carved channel floor ranges down to ~Z -8 (deepest, few texels);
  most of the channel floor sits between ~Z 76 and ~Z 160. **The channel is more
  gently carved than the deepest points suggest** — relevant for choosing water Z.
- Console helpers exist (DEBUG editor ConCmds): `dvp_dump_terrain_height`,
  `dvp_dump_arena_terrain_materials`, `dvp_fix_arena_sand_material`,
  `dvp_raise_world` (see `Editor/TerrainSandMaterialFix.cs`, `Editor/TerrainWorldRaise.cs`).

## How the Water Tool renders (read these files)

- `Libraries/redsnail.watertool/Code/Water/WaterManager.cs` —
  `GameObjectSystem<WaterManager>`, auto-instantiates per scene. In its **constructor**
  it does `new ComputeShader("water_clipmap_cs")`. It attaches two double-buffered
  `CommandList`s to **`Scene.Camera`** at `RenderStage.AfterTransparent` (only on camera
  change), builds them in `Stage.FinishUpdate`, dispatches the compute to populate
  clipmap vertices, then `GrabFrameTexture("FrameBufferCopyTexture")` and draws each
  quad with its `Material`. **Renders only through `Scene.Camera` → only visible in
  play / through the game camera, NOT the editor viewport.**
- `Libraries/redsnail.watertool/Code/Water/WaterQuad.cs` — flat clipmap water plane;
  surface = `WorldPosition.z`; `Width/Length/Depth`, `WaterType`, `Material`,
  `FollowCameraForClipmap` (default true), clipmap rings clamp to the quad bounds.
  Auto-adds a hidden trigger `HullCollider` tagged `water` for swim/wade.
- `Libraries/redsnail.watertool/Code/Water/WaterDefinition.cs` — `.wtdef` wave profile
  (GameResource). Profiles assigned in **Project Settings > Water Manager**
  (Ocean/Lake/River/Pool/Custom). `WaterManager.GetWaveProfile` falls back to a built-in
  default if unassigned (logs a benign `[WaterTool] No water profile found` warning).
- Shaders: `Libraries/redsnail.watertool/Assets/Shaders/{water_clipmap_cs,advancedwater,
  pp_simplefog,pp_wobble}.shader` (+ shipped `.shader_c`).
- The README's "Standard" path (pools/lakes/**rivers**) = add a `WaterQuad`. The
  "Advanced" path (ocean) = `WaterBodyRenderer` + `WaterQuadBaker` + baked `WaterBody`
  volumes (see `Assets/Scenes/Demo.scene`).

## Why a flat WaterQuad works for a winding river

`WaterQuad` is a flat plane at constant Z, depth-occluded by opaque terrain. Put one
large plane at a Z between the channel floor and the banks: the higher grassland hides
it everywhere except inside the carved channel, so the river takes the channel's winding
shape for free and runs under the road bridge. (This part is sound — the blocker is that
the plane isn't rendering at all, see below.)

## What has been done

1. **River created** in `main.scene`:
   - GameObject **`River_Water`** (GUID `40c5c792-561e-4b5c-b13d-b094d19d65e6`),
     world position `(0, 0, 150)` (the Z is the water surface height; started 110, now 150).
   - Component **`RedSnail.WaterTool.WaterQuad`**: `Material = materials/lakewater.vmat`
     (resolved fine to `Material:lakewater`), `WaterType = River`, `Width = 21000`,
     `Length = 21000`, `Depth = 300`. It auto-created the hidden trigger `HullCollider`
     (tag `water`) as designed. `component_get` confirmed `ParticipatesInRendering=True`,
     `HasValidBuffers=True`.
2. **River wave profile** created at **`Assets/water/river.wtdef`** (gentle directional
   flow). **NOT yet assigned** in Project Settings > Water Manager (default profile is
   used; benign warning until assigned).
3. **Terrain magenta-in-play fix** (a regression that surfaced while testing):
   - New component **`Code/Game/TerrainRuntimeMaterialFix.cs`** added to `ArenaFloor`.
     It calls `Terrain.UpdateMaterialsBuffer()` for the first several frames after start.
   - Combined with reloading the saved scene (editor restart), the terrain now renders
     correctly in play (was rendering as the magenta missing-material checker). Console
     confirms `[TerrainRuntimeMaterialFix] rebuilt terrain material buffer (materials=3)`.

> Scene state: there are unsaved changes (the River_Water Z tweaks) since the last save.

## Current status

- ✅ Terrain renders correctly in play.
- ✅ River GameObject/WaterQuad configured correctly per the tool's docs.
- ❌ **The water surface never visibly renders in play**, at any height.

## The core problem & evidence (what's been ruled out)

The water plane does not render. Diagnosis so far:

- **Not the river causing the magenta** — disabling the WaterQuad left the terrain fully
  magenta; that was a separate terrain issue (now fixed).
- **Not the water height/Z** — raised the surface to **Z=200, above the banks** (should
  flood the whole map as an obvious sheet). **Nothing rendered.** Also tried Z=110, 150.
- **Not the material reference** — `Material` resolved to `Material:lakewater`.
- **Not a missing profile** — default profile renders; the warning is benign.
- **`Scene.Camera` is valid and rendering** — confirmed `main_camera` has
  `Is Main Camera = true` and renders the (menu) view; water still didn't show through it.
- **No shader/compute errors are logged** — filtered console for `shader`/`water`: only
  a benign profile warning (earlier) and unrelated noise. The water just silently
  produces no geometry.

**Leading hypothesis:** the Water Tool's GPU pipeline (the `water_clipmap_cs` compute
shader that builds the surface mesh, and/or the `advancedwater` draw shader) is **not
executing on the patched `sbox-public` build** — the shipped `.shader_c` may be
incompatible and/or `new ComputeShader("water_clipmap_cs")` may be failing. If the
compute never writes vertices, the draw is degenerate → nothing visible, no error.

**Secondary hypothesis (not ruled out):** could not reach **actual gameplay** to confirm.
The flood test was through the menu/pre-spawn camera (which IS `Scene.Camera`), but the
camera changes when the player spawns; there's a small chance water behaves differently
once spawned.

## Recommended next steps (in priority order)

1. **Isolation test — open the Water Tool's own Demo scene and play it.**
   `Libraries/redsnail.watertool/Assets/Scenes/Demo.scene`. If the Demo's water also
   fails to render on this build, it's **definitively a library↔engine incompatibility**,
   not this project's setup — go to step 4/6. If Demo water DOES render, the problem is
   in this project (camera/state) — go to step 2/3.
2. **Confirm `WaterManager.Current` is non-null at runtime.** If
   `new ComputeShader("water_clipmap_cs")` throws in the constructor, the GameObjectSystem
   never initializes → no water, no profile warning. Add a temporary log (or a small
   component) that prints `WaterManager.Current`, whether the quad is registered, and
   whether the compute shader `IsValid`. (Earlier sessions DID emit the profile warning,
   implying the manager initialized then — verify current behavior.)
3. **Play to actual gameplay and look at the channel.** The s&box play viewport did not
   accept synthetic mouse clicks to drive the in-game menu (PLAY → choose team → spawn),
   so this wasn't completed. Do it by hand: spawn in, go to the carved channel, check for
   water. Even a wrong-height sheet proves the renderer works (then just tune Z).
4. **Recompile the Water Tool shaders for the patched build.** Delete/regenerate the
   `.shader_c` in `Libraries/redsnail.watertool/Assets/Shaders/` and let the editor
   recompile the `.shader` sources; watch the shader compiler output for errors. If the
   sources use engine APIs the patched build changed (`GpuBuffer`, `ComputeShader`,
   `CommandList.GrabFrameTexture`, `RenderStage.AfterTransparent`, `DispatchCompute`),
   fix or report them.
5. **Tune once it renders.** Set `River_Water` Z so water sits mid-channel with sandy
   banks showing — start ~Z 140–150 and adjust (banks are ~Z 160–180; channel is gently
   carved). Then assign the River profile (`Assets/water/river.wtdef`) in
   **Project Settings > Water Manager > River**. Optionally shrink the quad from
   21000² to a tighter rectangle over the river and disable `FollowCameraForClipmap`
   to rule out any clipmap-coverage issue.
6. **If it's a hard incompatibility**, fall back to a build-compatible water approach
   (a simpler custom water shader/plane, or a different water asset). The carved channel
   + flat-plane-occluded-by-terrain approach still applies to any flat water surface.

## Gotchas observed (save yourself the pain)

- **Water renders only in play**, through `Scene.Camera` — never in the editor viewport.
- **MCP `editor_stop` desyncs** from the editor UI (returns success but the viewport
  keeps showing play). Click the actual red stop button in the toolbar, or verify with
  `editor_is_playing`.
- **The play viewport ignored synthetic clicks** for the in-game Razor menu — couldn't
  script "PLAY → spawn". Drive gameplay manually.
- **Concurrent MCP activity** was observed during this work — another client creating
  `Spawn_Soldier_*` / `Spawn_Drone_*` GameObjects, adding `DroneVsPlayers.PlayerSpawn`
  components/tags, sometimes failing `Type not found: DroneVsPlayers.PlayerSpawn`.
  Confirm whether a second session/automation is editing the scene; it can conflict.
- `editor_take_screenshot` (MCP) is broken on this project; use desktop screenshots.

## Files changed / added by this session

- `Assets/scenes/main.scene` — added `River_Water` (WaterQuad + auto HullCollider);
  added `TerrainRuntimeMaterialFix` component on `ArenaFloor`. (Unsaved Z tweaks pending.)
- `Code/Game/TerrainRuntimeMaterialFix.cs` — **new** (terrain-in-play fix; keep).
- `Assets/water/river.wtdef` — **new** River wave profile (not yet assigned).
