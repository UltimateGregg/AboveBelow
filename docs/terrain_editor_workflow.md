# Terrain Editing Workflow

The main scene terrain is `BlockoutMap/ArenaFloor`, backed by `Assets/terrain/arena_floor.terrain`.

## Adjust Height In The Editor

1. Open `Assets/scenes/main.scene`.
2. Select `BlockoutMap/ArenaFloor` in the Hierarchy.
3. In the Inspector, keep the `Terrain` component linked to `terrain/arena_floor.terrain`.
4. Click `Edit Terrain`.
5. Choose a sculpt/raise/lower/smooth brush.
6. Use small brush strength near playable props.
7. Keep the road, house pads, and boundary wall bases flat unless you also move those objects.
8. Use Smooth around the edge of any raised area so collision transitions are not abrupt.
9. Save the scene and terrain asset.
10. Run `powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite terrain -ShowInfo`.

## Adjust Terrain Paint

1. Select `ArenaFloor`.
2. Click `Edit Terrain`.
3. Open the paint/material tool.
4. Select `grass_ground` for the base grass layer or `terrain_dirt_patch` for the raised-terrain grass variation layer.
5. Paint grass variation on raised/open terrain, not under the road meshes or house footprints.
6. Use a low brush strength for transitions.
7. Save the scene and terrain asset.
8. Rerun the terrain suite.

## Regenerate The Current Procedural Pass

Use the editor console command `dvp_generate_arena_terrain_variance` to rebuild the current rolling heightmap and grass variation splat layer. The command preserves flat protected samples on the road and six house footprints, then saves through S&Box `TerrainStorage`.
