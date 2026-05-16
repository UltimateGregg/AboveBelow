# terrain_assets

## Asset

- Name: terrain_assets
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

- Source blend: `environment_model.blend/terrain_assets.blend`
- Export config: `scripts/terrain_assets_asset_pipeline.json`
- Model: `Assets/models/terrain_assets.vmdl`
- Scene use: `Assets/scenes/main.scene` tree `ModelRenderer` components reference `models/terrain_assets.vmdl`

## Workflow Rule

The asset browser name must match the Blender source name unless the user explicitly asks for a legacy alias. For this asset, saving `terrain_assets.blend` must produce `terrain_assets.fbx` and `terrain_assets.vmdl` in `Assets/models/`; it must not silently refresh `terrain_pine.vmdl`.

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
- [ ] The S&Box inspector shows `terrain_assets` for placed trees, not a legacy alias such as `terrain_pine`.
