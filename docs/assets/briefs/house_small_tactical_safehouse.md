# house_small_tactical_safehouse

## Asset

- Name: house_small_tactical_safehouse
- Category: environment
- Profile: Environment and Prop
- Asset role: compact secondary safehouse or outbuilding

## S&Box Targets

- Source: environment_model.blend/house_small.blend
- Model: Assets/models/house_small.vmdl
- Prefab: Assets/prefabs/environment/House_Small.prefab
- Model resource path: models/house_small.vmdl
- Root empty: HouseSmall_Root
- Combined export object: HouseSmallMesh

## Reference Requirements

- Rural outbuilding or compact safehouse massing with asymmetric footprint, porch or lean-to identity, metal roof, visible foundation, trim, gutters, and practical utility details.
- Occupied tactical dressing that is lighter than House_Large: reinforced openings, small roof/loft lookout, utility panel, tarp or patch material, and defensive clutter.
- Fast soldier read for one primary room path, one side room or lean-to route, and loft or roof access.
- Drone-readable roof silhouette, roof ladder/landing, and compact defensive position.

## Architecture Contract

- Smaller asymmetric footprint with strong porch or lean-to identity, one main level, attic/loft or roof access, and faster interior read than House_Large.
- Footprint target is about 330 x 280 game units for the main mass, with total porch/lean-to bounds staying within about 410 x 350 game units.
- The building stays structurally intact. It should feel fortified and occupied, not destroyed.
- Source object names must include the required small-house prefixes: HouseSmall_Root, Small_Foundation_*, Small_MainRoom_*, Small_Porch_*, Small_LeanTo_*, Small_Window_Reinforced_*, Small_Loft_*, Small_Roof_*, Small_Ladder_*, Small_Cover_*, Small_Tactical_*, and Small_Utility_*.

## Material Plan

- Weathered siding distinct from House_Large: image-backed color, normal, roughness, and ambient-occlusion maps with separate hue and wear pattern.
- Metal roof: image-backed color, normal, roughness, and ambient-occlusion maps with simpler panel layout than House_Large.
- Concrete block or pier foundation: image-backed color, normal, roughness, and ambient-occlusion maps.
- Interior dark wood: image-backed color, roughness, and ambient-occlusion maps for floor, side room, loft, and cover.
- Trim/fascia/gutter details: image-backed color, normal, roughness, and ambient-occlusion maps.
- Dusty glass: color texture plus material parameters that keep windows readable.
- Rail/ladder metal: color, roughness, and ambient-occlusion maps.
- Utility panel or tactical tarp/patch material: color, roughness, and ambient-occlusion maps.
- Dirt/grime variation masks: color, roughness, and ambient-occlusion maps so repeated scene instances do not read as exact scaled copies of House_Large.

## Traversal And Collision Expectations

- One primary room path and one side room or lean-to route.
- Loft or roof access with shorter ladder and smaller fighting/detail position.
- Fewer branches than House_Large; the compact layout should read quickly during combat.
- Prefab collision helpers, ladder triggers, and zone triggers are generated from the final helper contract and kept separate from the visual mesh export.

## Scale And Orientation

- Preserve public asset identity and path names.
- Keep the root empty centered for stable scene placement across four existing scene instances.
- Keep bounds consistent with current House_Small scene placement unless final visual proof shows entries or critical paths are buried.

## Visual Review Plan

- Render ground-height exterior showing porch or lean-to identity, windows, and material scale.
- Render ground-height entry/interior showing primary room, side route, and ladder/loft read.
- Render drone-height overview showing roof access, roof exposure, silhouette, and compact defensive position.
- Render three-quarter asset preview showing authored geometry and distinct material breakup.
- Generate a texture contact sheet for all house_small material remap targets.
- After import, inspect the model in S&Box lighting for material remap, scale, collision, repeated-instance readability, and traversal alignment.

## Acceptance Checklist

- [ ] Public prefab root remains House_Small.
- [ ] Model resource path remains models/house_small.vmdl.
- [ ] Source root remains HouseSmall_Root and export object remains HouseSmallMesh.
- [ ] No WaterTower, house_rural, gameplay, UI, networking, weapon, drone, or round logic changes are required by this brief.
- [ ] Generated local materials do not use arena placeholder material remaps.
- [ ] Collision, ladders, and zones are documented separately from visual mesh export.
