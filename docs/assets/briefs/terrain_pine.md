# terrain_pine

## Asset

- Name: terrain_pine
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

- Prefab: Assets/scenes/main.scene
- Model: Assets/models/terrain_pine.vmdl

## Reference Notes

- User approved option B from the silhouette screen: a readable layered pine.
- Branches should resemble the supplied white pine reference: horizontal whorls, open air between tiers, irregular flattened needle pads, and sparse visible twig structure.
- Foliage should stay in the upper third of a tall thin tree, with a mostly bare lower trunk and a few dead branch stubs.

## Material Plan

- Use `TerrainPineBark` for the trunk, branches, twigs, and dead lower stubs.
- Use `terrain_pine_bark_color.png` as a procedural vertical-grain bark color texture so the wood reads brown instead of flat color.
- Use `TerrainPineNeedlesCardA` and `TerrainPineNeedlesCardB` for transparent foliage cards.
- Use `terrain_pine_needles_card_a_color.png` / `terrain_pine_needles_card_b_color.png` for branch-and-needle card color and matching `_trans.png` masks for alpha-tested cutouts.
- No normal, roughness, or ambient-occlusion textures are required for this pass; the current environment material audit treats those as optional warnings.

## Scale and Orientation

Confirm origin and dimensions are sensible for scene placement.

## Sockets and Attachments

- No sockets or attachments. This is a static environment visual asset used by scene `ModelRenderer` components.

## Acceptance Checklist

- [ ] Collision expectations are documented separately from visual mesh export.
- [ ] Repeated props have stable names and avoid giant bounds.
- [ ] Blockout dev-box collider sync remains a separate workflow.
