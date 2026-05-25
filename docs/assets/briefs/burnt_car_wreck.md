# burnt_car_wreck

## Asset

- Name: burnt_car_wreck
- Category: environment
- Profile: Environment and Prop

## S&Box Targets

- Prefab: Assets/prefabs/environment/burnt_car_wreck.prefab
- Model: Assets/models/burnt_car_wreck.vmdl
- Blender source: environment_model.blend/burnt_car_wreck.blend
- Scene placement: replaces the two lane barricade placeholders in Assets/scenes/main.scene.

## Reference Notes

- Damaged sedan-sized wreck used as soldier-scale road cover.
- Burn state should read from drone height: blackened roof/cabin, blistered paint, exposed rusty metal, missing glass, warped hood, ruined tires, ash scatter, and loose debris.
- It should not look like a clean car with a dark tint; the silhouette needs collapsed panels and broken openings.

## Production Quality Targets

- Large body mass blocks sightlines like the original barricade placeholders.
- Close-up silhouette includes deformed panels, exposed frame/engine elements, wheel rims, tire remnants, shattered glass, soot patches, and ground debris.
- Materials are image-backed and split into charred paint, blistered metal, rust, soot interior, rubber, glass, and ash.
- Origin sits at ground center so scene placement can use road-level Z values.

## Material Plan

- BurntCar_CharredPaint: blackened paint with red/brown scorched remnants.
- BurntCar_BlisteredMetal: exposed dull metal and heat staining.
- BurntCar_Rust: orange/brown corrosion on open edges and panels.
- BurntCar_SootInterior: black interior shell and burned cabin void.
- BurntCar_Rubber: charred tire remnants.
- BurntCar_Glass: dark broken glass shards.
- BurntCar_Ash: ash, debris, and scorched ground fragments.

## Scale and Orientation

- Length is roughly 250 S&Box units, width 110, height 80.
- Local X is vehicle length, local Y is width, and local Z is up.
- Root origin is ground center.

## Collision

- The exported modeldoc includes one coarse static metal box shape for the wreck body.
- Scene instances also use Sandbox.ModelCollider so collision coverage stays attached to the visible model.

## Visual Review Plan

- Render a Blender preview before export from a three-quarter ground/drone-readable angle.
- Run Blender quality, material texture, asset-production, modeldoc, prefab, and scene/collision checks after export.
- Verify in the S&Box editor when available because static checks do not prove runtime lighting or walk-into-cover behavior.

## Acceptance Checklist

- [x] Collision expectations are documented separately from visual mesh export.
- [x] Repeated props have stable names and avoid giant bounds.
- [x] Blockout dev-box collider sync remains a separate workflow.
