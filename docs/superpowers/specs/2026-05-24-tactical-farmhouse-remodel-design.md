# Tactical Farmhouse Remodel Design

## Summary

Remodel `House_Large` and `House_Small` as high-fidelity tactical rural compound buildings. The houses should stay structurally intact, but read as occupied and fortified for drone-vs-ground combat. The pass includes full visual geometry, generated local texture/material work, S&Box model export, prefab collision/traversal updates, visual proof, and focused validation.

This spec covers only the two house families currently used in `Assets/scenes/main.scene`:

- `environment_model.blend/house_large.blend`
- `environment_model.blend/house_small.blend`
- `Assets/models/house_large.fbx`
- `Assets/models/house_large.vmdl`
- `Assets/models/house_small.fbx`
- `Assets/models/house_small.vmdl`
- `Assets/prefabs/environment/House_Large.prefab`
- `Assets/prefabs/environment/House_Small.prefab`
- `scripts/house_large_asset_pipeline.json`
- `scripts/house_small_asset_pipeline.json`

`WaterTower`, `house_rural`, gameplay code, networking, UI, and unrelated level-layout changes are out of scope. The only allowed scene edits are placement or rotation adjustments to existing `House_Large_*` and `House_Small_*` instances when the new house bounds visibly block intended paths or bury entrances.

## Goals

- Replace blocky house visuals with authored, AAA-targeted rural tactical compound architecture.
- Keep both houses structurally sound rather than destroyed or collapsed.
- Use locally generated or baked textures, not external downloaded texture libraries.
- Give major visible surfaces material fidelity: color, normal, roughness, ambient occlusion, dirt, edge wear, staining, and local variation for siding, roof, foundation, trim, and major tactical additions.
- Rebuild geometry and prefab collision/traversal together so visuals, ladders, zones, and solid surfaces stay aligned.
- Preserve public asset identities: do not rename existing model, prefab, scene, component, or public class paths.
- Maintain clear gameplay readability from soldier height and drone height.

## Creative Direction

The chosen direction is a tactical rural compound. The buildings should look like farm property that has been intentionally occupied and fortified, not ruins.

Visual rules:

- Houses remain buildable and structurally intact. Avoid major collapse, blown-out walls, or a destroyed-warzone look.
- Silhouettes must stop reading as plain boxes by using overhangs, roof layers, fascia, gutters, trim, porch structures, stairs, rails, vents, utility panels, cables, foundation detail, and layered openings.
- Tactical additions should be restrained but readable: reinforced window frames, roof fighting positions, improvised cover, comms or antenna details, patched sightlines, barricaded-but-usable entries, and roof/porch utility clutter.
- The art must expose traversal intent: entrances, ladders, roof access, window sightlines, interior cover, basement/cellar routes, and risky roof exposure should be visible in the model.
- Materials should carry much of the AAA quality: aged painted siding, oxidized metal roofing, rough concrete/foundation, dark interior wood, weathered trim, dusty glass, ladder/rail metal, tarp/patch materials, dirt accumulation, and decals.

## Building Roles

### House_Large

`House_Large` is the compound's fortified main house and should remain the most complex tactical building.

Expected design:

- Broad farmhouse silhouette with a stronger front/side entry identity.
- Basement or cellar route for low concealment and rotation.
- Main-floor interior cover with visible room separation and usable sightlines.
- Partial second-floor or loft area that creates elevation without turning the house into a tall tower.
- Roof access with a fighting position or lookout detail that is readable from drone height and risky for ground players.
- Reinforced windows, patched panels, railings, roof gear, cable runs, and utility props that make the building feel occupied.
- Collision, ladders, roof surfaces, and zones rebuilt to match the new mesh.

Gameplay intent:

- Ground players can choose between hiding low, rotating through interior cover, taking controlled window/porch peeks, or climbing to the roof for a risky vantage point.
- Drone players can read the silhouette, spot roof exposure, and understand likely access routes from above.

### House_Small

`House_Small` is the compact secondary safehouse/outbuilding used several times in the scene.

Expected design:

- Smaller, faster-to-read footprint than `House_Large`.
- Strong porch, lean-to, or side-entry identity.
- One primary interior level plus attic/loft or roof access.
- Fewer rooms and fewer traversal branches than `House_Large`.
- Clear defensive adaptations: reinforced openings, small lookout/roof detail, utility clutter, and patched panels.
- Variation strategy for repeated scene instances through generated texture variation, decal masks, and optional non-gameplay detail clusters.

Gameplay intent:

- Players should understand the building quickly during combat.
- Repeated instances should feel like part of the same compound kit without looking like exact scale copies of the large house.

## Asset Briefs

Implementation starts by generating or updating production asset briefs for both houses under `docs/assets/briefs/`.

Each brief must document:

- Intended model and prefab targets.
- Reference requirements for rural farm construction, tactical occupation details, material roles, and traversal readability.
- Production quality targets for geometry, materials, UVs, scale, sockets/helpers if any, and visual proof.
- Material roles and texture-map expectations.
- Collision and traversal expectations separate from visual mesh export.
- Required visual review angles: soldier-height exterior, soldier-height interior/entry, drone-height overview, and three-quarter asset preview.

## Materials And Textures

Texture source policy:

- Use generated or baked local textures.
- Do not depend on external CC0/PBR downloads for this pass.
- Generated textures must be committed under appropriate project material/texture paths if they are required by `.vmat` files.

Material roles must include:

- Painted or stained siding.
- Metal roof.
- Concrete or masonry foundation.
- Interior dark wood.
- Exterior trim/fascia/gutters.
- Glass.
- Rail/ladder metal.
- At least one tactical-addition material for tarp, patch, barricade, or utility panels.
- Dirt, grime, water streak, repair, decal, or variation masks for the exterior shell.

Quality expectations:

- Major exterior surfaces should not use broad arena placeholder materials.
- `.vmat` files should reference real `TextureColor` maps.
- Normal, roughness, and ambient-occlusion maps should be generated for siding, roof, foundation, and trim.
- Optional maps may be omitted for glass, tiny props, or narrow metal details when a color map plus material parameters are visually sufficient.
- Multi-material remaps must remain explicit and protected by `strict_vmdl_material_sources`.

## Blender Source Requirements

For both house `.blend` files:

- Use stable root empties and export object names expected by the asset pipeline configs.
- Apply transforms on edited mesh objects before export.
- Preserve or create UVs for textured mesh surfaces.
- Use stable, descriptive material slot names that match pipeline remaps.
- Separate major construction layers enough for visual polish and material assignment.
- Keep traversal-relevant pieces named clearly, such as ladders, floors, roof access, porch, cellar/basement, reinforced windows, and major cover pieces.
- Avoid large hidden geometry, zero-vertex meshes, and unintentional top-level export objects.

## Prefab And Scene Requirements

Prefab updates are in scope for:

- `Assets/prefabs/environment/House_Large.prefab`
- `Assets/prefabs/environment/House_Small.prefab`

Allowed prefab changes:

- Rebuild collision children to match the new geometry.
- Rebuild ladder trigger volumes and `LadderVolume` settings to match visible climb paths.
- Rebuild gameplay zone triggers for major areas.
- Update child object names when needed for clear collision/traversal authoring.
- Preserve public root prefab names and model resource paths.

Scene changes are limited to:

- Adjusting existing `House_Large_*` and `House_Small_*` placements only if the new bounds or access paths make the existing placement visibly broken.
- Avoiding unrelated level redesign in this pass.

## Validation Plan

Required automated checks:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name house_large_tactical_farmhouse -Category environment
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name house_small_tactical_safehouse -Category environment
powershell -ExecutionPolicy Bypass -File scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Blend @('environment_model.blend/house_large.blend','environment_model.blend/house_small.blend') -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -Category environment -ShowInfo
python scripts/asset_pipeline.py --config scripts/house_large_asset_pipeline.json
python scripts/asset_pipeline.py --config scripts/house_small_asset_pipeline.json
powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1 -Config scripts/house_large_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1 -Config scripts/house_small_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1 -ShowInfo
dotnet build Code\dronevsplayers.csproj --no-restore
```

Required visual proof:

- Render `House_Large` and `House_Small` previews to `screenshots/asset_previews/`.
- Include at least ground-height, drone-height, and three-quarter views.
- Place generated material sheets or texture contact sheets under `screenshots/asset_previews/` for siding, roof, and foundation textures.
- After import, capture or manually inspect the houses in S&Box editor lighting for material remap, scale, collision, and traversal alignment.

Manual editor/playtest checks:

- Model appears at the expected scale in `main.scene`.
- Players can walk on all intended floors and roof areas.
- Players cannot fall through floors or clip into major wall/roof geometry.
- Ladders and exits work without trapping or launching players.
- Basement/cellar and interior areas provide cover without hiding all gameplay.
- Drone-height view can read roof exposure, access routes, and silhouette.
- Repeated `House_Small` instances do not look distractingly identical.

## Risks And Mitigations

- Generated textures may look less photoreal than external PBR libraries. Mitigation: prioritize strong UVs, baked variation, normal/roughness/AO on major surfaces, and close visual review.
- Full geometry rework may invalidate existing collision and ladder values. Mitigation: rebuild prefab helpers from the new Blender bounds and verify with collision audits/editor playtest.
- Strong tactical dressing may drift away from rural-house identity. Mitigation: keep the base architecture structurally sound and farmhouse-like; use tactical details as additions, not the dominant mass.
- Repeated `House_Small` instances may become visually repetitive. Mitigation: use texture/decal variation within the shared asset and preserve a single prefab identity unless a later task explicitly adds variants.
- Existing uncommitted workflow or scene changes may overlap. Mitigation: inspect diffs before editing touched files and preserve unrelated user changes.

## Out Of Scope

- Water tower remodel.
- Replacing `house_rural` or adding it to `main.scene`.
- New gameplay systems, UI changes, networking changes, class balance, or weapon/drone changes.
- Public asset renames.
- Broad level-layout redesign beyond house placement fixes required by changed bounds.
