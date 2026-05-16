# Terrain Pine White Pine Design

## Status

Approved by the user on 2026-05-13. Updated after editor validation to use the editor-visible `terrain_assets` model path instead of the legacy `terrain_pine` alias.

## Goal

Replace the current basic cone-stack tree asset with a tall, thin pine whose foliage is concentrated in the upper third and whose branches resemble the supplied white pine reference.

## Scope

- Use the S&Box model path that matches the Blender source name: `Assets/models/terrain_assets.vmdl`.
- Preserve existing scene placements in `Assets/scenes/main.scene`.
- Keep this as static environment asset work only. No gameplay, UI, networking, or prefab hierarchy changes.
- Keep the existing bark and needle material slots so current material remaps continue to work.

## Visual Design

The model should keep option B's readable game silhouette while replacing the stacked cones with open white-pine branch structure. The trunk is tall and narrow. Lower trunk sections are mostly bare, with a few short dead branch stubs. The upper third contains staggered horizontal branch whorls. Each branch reaches outward and slightly upward, then ends in flattened irregular needle pads rather than solid cones.

The silhouette should be readable at gameplay distance: sparse enough to show real branches, but not so thin that it disappears against the sky.

## Asset Pipeline

The source of truth remains `scripts/create_environment_proxy_assets.py` and `environment_model.blend/terrain_assets.blend`. The dedicated `scripts/terrain_assets_asset_pipeline.json` exports the `TerrainPine_Root` hierarchy to `Assets/models/terrain_assets.fbx` and regenerates `Assets/models/terrain_assets.vmdl`.

## Verification

- Generate or update the `.blend`, `.fbx`, and `.vmdl`.
- Run Blender quality audit on `environment_model.blend/terrain_assets.blend`.
- Run material texture audit for the environment category.
- Generate an asset preview for visual review.
- Run asset pipeline audit.
- Run the S&Box build/log sentinel after asset/script changes.
