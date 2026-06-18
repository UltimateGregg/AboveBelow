# bouneurmaum_park_sign

## Asset

- Name: bouneurmaum_park_sign
- Category: environment
- Profile: Environment and Prop

## Setting

- Part of **Bouneurmaum National Park** — this is the park's welcome sign at an entrance / trailhead. Art-direction source of truth: [`docs/setting.md`](../../setting.md).

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

- Prefab: Assets/prefabs/environment/bouneurmaum_park_sign.prefab
- Model: Assets/models/bouneurmaum_park_sign.vmdl
- Blender source: environment_model.blend/bouneurmaum_park_sign.blend
- Scene placement: standalone environment prop; no scene placement in this task.

## Reference Notes

- Reference image is the attached national-park sign, ignoring the photographic background.
- Text must read as the phrase "Welcome to Bouneurmaum National Park".
- The sign should keep the reference language: rounded trapezoid face, dark brown raised border, inset tan wood panel, pine-tree silhouettes, and a dark lower national-park plaque.

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

- BouneurmaumSignWoodFace: image-backed light wood face with subtle horizontal grain.
- BouneurmaumSignDarkBrown: image-backed dark brown trim, body, raised welcome/name text, tree icons, divider, and screw caps.
- BouneurmaumSignCream: image-backed cream lower-plaque lettering.

## Scale and Orientation

- Approximate dimensions are 4.35 units wide, 2.35 units tall, and 0.18 units deep, with an asymmetric swept-left outline matching the reference sign.
- Local X is sign width, local Y is depth, local Z is up.
- Front face points toward local -Y; root origin is centered along width and depth near the lower edge for simple scene placement.

## Sockets and Attachments

- No sockets or gameplay attachments are required.

## Collision

- The generated ModelDoc should use `collision.mode = render_mesh` so the static `ModelCollider` matches the visible sign bounds.
- Place the sign through `Assets/prefabs/environment/bouneurmaum_park_sign.prefab`, not by dragging the raw `.vmdl`.
- Runtime proof requirement: place the prefab in a scene, enter play, confirm it renders, stays put, and collides, then record `ModelCollider.LocalBounds` approximately matching `ModelRenderer.LocalBounds`.

## Visual Review Plan

- Render Blender previews from ground, drone-height, and three-quarter angles before export.
- After import, inspect the asset in S&Box lighting with material remaps, collision helpers, and scale visible.
- For foliage or cards, review color texture, translucency/cutout mask, and checkerboard contact sheet.

## Acceptance Checklist

- [x] Collision expectations are documented separately from visual mesh export.
- [x] Repeated props have stable names and avoid giant bounds.
- [x] Blockout dev-box collider sync remains a separate workflow.
