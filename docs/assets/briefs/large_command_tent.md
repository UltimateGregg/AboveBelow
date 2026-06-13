# large_command_tent

## Asset

- Name: large_command_tent
- Category: environment
- Profile: Environment and Prop

## Category Profile

Required material roles:
- surface

Optional texture maps:
- TextureNormal
- TextureRoughness
- TextureAmbientOcclusion

Required name hints:
- root

## S&Box Targets

- Prefab: Assets/prefabs/environment/large_command_tent.prefab
- Model: Assets/models/large_command_tent.vmdl

## Reference Notes

- Large open military command tent for reusable camp/staging-area dressing.
- Chosen direction: olive-drab canvas, open front, raised side flaps, visible interior, support poles, stakes, seams, patches, dirt/wear, and visual-only guy ropes.
- Target footprint is approximately 10m x 6m including stakes/rope endpoints, with a command-tent body that remains readable from both soldier height and drone height.

## Reference Requirements

- Collect scale, construction, material, wear, and gameplay-cover reference before detailed modeling.
- Document intended placement context, repetition count, collision expectations, and player traversal impact.
- Record material breakup for surface, trim, glass, metal, dirt, foliage, decals, and damage states when relevant.

## Production Quality Targets

- Large forms read from drone height while close surfaces hold up for soldier-scale inspection.
- Materials avoid one-note color fills and include believable roughness, normal, dirt, trim, and edge variation.
- Origins, pivots, and root empties support scene placement, repeated props, and authored collision helpers.
- Foliage and alpha-card assets include clean cutout masks and do not rely on default textures.

## Material Plan

- `LargeCommandTentCanvas`: olive-drab woven canvas with subtle procedural weave, roughness, AO, and normal texture.
- `LargeCommandTentPatch`: darker patched/rolled flap fabric used for repairs, folded flap edges, and seams.
- `LargeCommandTentPole`: dark weathered support poles and ridge/eave beams.
- `LargeCommandTentRope`: tan cordage for guy ropes; visual only, not included as blocking collision.
- `LargeCommandTentStake`: dull metal/wood stake material for small ground anchors.
- `LargeCommandTentDirt`: muddy wear and footfall staining near the open entry and side skirt.

## Scale and Orientation

- Approximate model target: 10m x 6m including guy-line stake endpoints, 3.3m peak height.
- Source Blender asset is authored in inch-style source units and exported with `global_scale = 0.0254`, matching the existing environment asset pipeline.
- Origin is centered on the tent footprint at ground level so the prefab can be placed directly on terrain.

## Placement and Collision

- Solid prop collision default would normally be `collision.mode = render_mesh`, but this asset is a documented primitive-collision exception because the tent must stay hollow/walk-through and the guy ropes must not snag players.
- Primitive collision covers the back/side canvas blockers, support poles, ridge/eave beams, and stakes. Ropes and raised fabric flap detail are visual-only.
- Placement rule: place the prefab (`Assets/prefabs/environment/large_command_tent.prefab`), not the raw `.vmdl`, so the instance keeps the static collider contract and does not fall on play.
- Runtime proof plan: place the prefab in a throwaway test scene or editor staging area, enter play, confirm it renders, stays put, the interior is walkable, poles/stakes block, and guy ropes do not snag movement.

## Sockets and Attachments

- None for v1. Future scene dressing such as radios, tables, lights, or flags should be separate prefabs placed under/near the tent.

## Visual Review Plan

- Render Blender previews from ground, drone-height, and three-quarter angles before export.
- After import, inspect the asset in S&Box lighting with material remaps, collision helpers, and scale visible.
- For foliage or cards, review color texture, translucency/cutout mask, and checkerboard contact sheet.

## Acceptance Checklist

- [x] Collision expectations are documented separately from visual mesh export.
- [x] Repeated prop uses stable `large_command_tent` naming and keeps bounds limited to the intended tent footprint.
- [x] Blockout dev-box collider sync remains a separate workflow.
