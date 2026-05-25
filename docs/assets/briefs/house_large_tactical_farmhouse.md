# house_large_tactical_farmhouse

## Asset

- Name: house_large_tactical_farmhouse
- Category: environment
- Profile: Environment and Prop
- Asset role: fortified main farmhouse

## S&Box Targets

- Source: environment_model.blend/house_large.blend
- Model: Assets/models/house_large.vmdl
- Prefab: Assets/prefabs/environment/House_Large.prefab
- Model resource path: models/house_large.vmdl
- Root empty: HouseLarge_Root
- Combined export object: HouseLargeMesh

## Reference Requirements

- Rural farmhouse massing with broad main volume, porch framing, gabled roof language, visible foundation, fascia, gutters, downspouts, and practical utility details.
- Occupied tactical compound dressing: restrained barricades, reinforced windows, tarp or plank patches, roof lookout cover, antenna/comms detail, cable runs, and exterior clutter that does not make the house look collapsed.
- Soldier-readable routes for cellar access, porch entry, main-floor cover, loft climb, and roof access.
- Drone-readable silhouette, roof exposure, access hatch/landing, and likely defender positions.

## Architecture Contract

- Broad farmhouse mass with a wrap or side porch, cellar entry, partial second floor or loft, roof access, protected but usable windows, and a roof fighting position.
- Footprint target is about 520 x 430 game units for the main mass, with roof and porch overhangs staying within about 600 x 510 game units.
- The building stays structurally intact. Avoid destroyed walls, collapsed roof sections, or ruined-warzone presentation.
- Source object names must include the required large-house prefixes: HouseLarge_Root, Large_Foundation_*, Large_Cellar_*, Large_GroundFloor_*, Large_Porch_*, Large_Window_Reinforced_*, Large_Loft_*, Large_Roof_*, Large_Ladder_*, Large_Cover_*, Large_Tactical_*, and Large_Utility_*.

## Material Plan

- Aged painted siding: image-backed color, normal, roughness, and ambient-occlusion maps with plank variation, edge grime, and repaired paint.
- Oxidized metal roof: image-backed color, normal, roughness, and ambient-occlusion maps with panel seams, ridge cap wear, and water streaking.
- Concrete or masonry foundation: image-backed color, normal, roughness, and ambient-occlusion maps with dirt buildup around the base.
- Dark interior wood: image-backed color, roughness, and ambient-occlusion maps for floors, partitions, loft rail, and interior cover.
- Exterior trim/fascia/gutters: image-backed color, normal, roughness, and ambient-occlusion maps.
- Dusty glass: color texture plus material parameters that keep windows readable without looking like flat blue paint.
- Rail/ladder metal: color, roughness, and ambient-occlusion maps.
- Tactical tarp/patch/barricade material: color, roughness, and ambient-occlusion maps.
- Dirt/grime/repair masks: color, roughness, and ambient-occlusion maps for variation and weathering overlays.

## Traversal And Collision Expectations

- Cellar or basement route with a readable exterior entry and low cover.
- Main-floor cover and room breakup that supports movement without becoming a maze.
- Loft access and roof access with visible ladders, readable exits, and player-safe landing surfaces.
- Roof exposure must be readable from drone height; roof cover should create risk, not a fully protected sniper box.
- Prefab collision helpers, ladder triggers, and zone triggers are generated from the final helper contract and kept separate from the visual mesh export.

## Scale And Orientation

- Preserve public asset identity and path names.
- Keep the root empty centered for stable scene placement.
- Keep bounds consistent with current House_Large scene placement unless final visual proof shows entries or critical paths are buried.

## Visual Review Plan

- Render ground-height exterior showing porch, cellar/entry read, windows, and siding scale.
- Render ground-height entry/interior showing main-floor cover, cellar/loft route read, and material breakup.
- Render drone-height overview showing roof access, roof exposure, silhouette, and fighting-position cover.
- Render three-quarter asset preview showing overall authored geometry and material breakup.
- Generate a texture contact sheet for all house_large material remap targets.
- After import, inspect the model in S&Box lighting for material remap, scale, collision, and traversal alignment.

## Acceptance Checklist

- [ ] Public prefab root remains House_Large.
- [ ] Model resource path remains models/house_large.vmdl.
- [ ] Source root remains HouseLarge_Root and export object remains HouseLargeMesh.
- [ ] No WaterTower, house_rural, gameplay, UI, networking, weapon, drone, or round logic changes are required by this brief.
- [ ] Generated local materials do not use arena placeholder material remaps.
- [ ] Collision, ladders, and zones are documented separately from visual mesh export.
