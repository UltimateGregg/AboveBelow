# Tactical Farmhouse Remodel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully remodel `House_Large` and `House_Small` into distinct, high-fidelity tactical rural compound buildings while preserving all public asset identities.

**Architecture:** Keep the existing Blender -> FBX -> VMDL -> prefab pipeline as the source of truth. Upgrade the current deterministic building generator so it produces local image-backed materials, authored Blender geometry, asset-specific material remaps, prefab collision helpers, ladders, and zones for only the two approved house assets. Treat scene edits as a final narrow correction pass only if the new bounds break existing `House_Large_*` or `House_Small_*` placements.

**Tech Stack:** Blender Python, S&Box `.vmat` materials, PNG texture maps, `scripts/asset_pipeline.py`, S&Box prefab JSON, PowerShell agent audits, `dotnet build Code\dronevsplayers.csproj --no-restore`.

---

## Scope And Ownership

Owned implementation files:

- Create: `docs/assets/briefs/house_large_tactical_farmhouse.md`
- Create: `docs/assets/briefs/house_small_tactical_safehouse.md`
- Modify: `scripts/building_architecture_pipeline.py`
- Create or modify only if needed for repeatable proof: `scripts/render_environment_asset_views.py`
- Modify: `scripts/house_large_asset_pipeline.json`
- Modify: `scripts/house_small_asset_pipeline.json`
- Modify: `environment_model.blend/house_large.blend`
- Modify: `environment_model.blend/house_small.blend`
- Modify: `Assets/models/house_large.fbx`
- Modify: `Assets/models/house_large.vmdl`
- Modify: `Assets/models/house_small.fbx`
- Modify: `Assets/models/house_small.vmdl`
- Create: `Assets/materials/environment/house_large_*`
- Create: `Assets/materials/environment/house_small_*`
- Modify: `Assets/prefabs/environment/House_Large.prefab`
- Modify: `Assets/prefabs/environment/House_Small.prefab`
- Modify only if new bounds require it: `Assets/scenes/main.scene`
- Generate local proof artifacts: `screenshots/asset_previews/house_large_*`, `screenshots/asset_previews/house_small_*`

Do not touch:

- `environment_model.blend/house_rural.blend`
- `Assets/models/house_rural.*`
- `Assets/prefabs/environment/house_rural*`
- `WaterTower` assets, prefabs, scene objects, or collision helpers
- Gameplay, UI, networking, class, weapon, drone, or round logic

Current baseline facts to preserve:

- `House_Large` prefab root name remains `House_Large`.
- `House_Small` prefab root name remains `House_Small`.
- Model resource paths remain `models/house_large.vmdl` and `models/house_small.vmdl`.
- Blender root empties remain `HouseLarge_Root` and `HouseSmall_Root`.
- Export combined objects remain `HouseLargeMesh` and `HouseSmallMesh`.
- Scene instances remain `House_Large_01`, `House_Large_02`, `House_Small_01`, `House_Small_02`, `House_Small_03`, and `House_Small_04`.

## Task 1: Baseline And Diff Hygiene

**Files:**

- Read: `docs/superpowers/specs/2026-05-24-tactical-farmhouse-remodel-design.md`
- Read: `.agents/sbox/aaa-asset-quality-agent.md`
- Read: `.agents/sbox/asset-brief-agent.md`
- Read: `.agents/sbox/blender-quality-agent.md`
- Read: `.agents/sbox/material-texture-agent.md`
- Read: `.agents/sbox/asset-pipeline-agent.md`
- Read: `.agents/sbox/visual-review-agent.md`
- Read: `scripts/building_architecture_pipeline.py`
- Read: `scripts/house_large_asset_pipeline.json`
- Read: `scripts/house_small_asset_pipeline.json`
- Read: `Assets/prefabs/environment/House_Large.prefab`
- Read: `Assets/prefabs/environment/House_Small.prefab`
- Read: `Assets/scenes/main.scene`

- [ ] **Step 1: Capture dirty-tree scope before edits**

Run:

```powershell
git status --short
```

Expected: existing unrelated dirty files may be present. Record them in the work log and do not revert or reformat them.

- [ ] **Step 2: Confirm the approved spec is the active design**

Run:

```powershell
git show --stat --oneline --decorate --no-renames 135bb34
Get-Content docs\superpowers\specs\2026-05-24-tactical-farmhouse-remodel-design.md
```

Expected: commit `135bb34` contains only the tactical farmhouse remodel spec, and the spec excludes WaterTower, `house_rural`, gameplay, UI, networking, and broad level redesign.

- [ ] **Step 3: Inventory current house asset paths**

Run:

```powershell
Get-ChildItem environment_model.blend -Filter 'house_*.blend' | Select-Object Name,Length,LastWriteTime
Get-ChildItem Assets\models -Filter 'house_*.*' | Select-Object Name,Length,LastWriteTime
Get-ChildItem Assets\materials\environment | Where-Object { $_.Name -like 'house_*' } | Select-Object Name,Length,LastWriteTime
```

Expected: `house_large`, `house_small`, and `house_rural` files are visible, but only `house_large` and `house_small` become owned files.

- [ ] **Step 4: Inventory prefab and scene identities**

Run:

```powershell
rg -n "House_Large|House_Small|models/house_large|models/house_small|Collision_|Ladder_|Zone_" Assets\prefabs\environment\House_Large.prefab Assets\prefabs\environment\House_Small.prefab Assets\scenes\main.scene
```

Expected: both prefabs have `Model_Visual`, authored `Collision_*` helpers, `Ladder_To_Loft`, `Ladder_To_Roof`, and zone triggers. The scene contains only the six existing house instances listed in the scope section.

- [ ] **Step 5: Run baseline focused checks before changing assets**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\aaa_asset_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\blender_quality_audit.ps1 -Blend @('environment_model.blend/house_large.blend','environment_model.blend/house_small.blend') -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\material_texture_audit.ps1 -Category environment -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\prefab_graph_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\collision_authoring_agent.ps1 -ShowInfo
```

Expected: failures or warnings may reflect the current low-detail house state. Save the relevant output in the work log so final verification can separate pre-existing issues from new regressions.

## Task 2: Asset Briefs

**Files:**

- Create: `docs/assets/briefs/house_large_tactical_farmhouse.md`
- Create: `docs/assets/briefs/house_small_tactical_safehouse.md`

- [ ] **Step 1: Generate the two environment briefs**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\new_asset_brief.ps1 -Name house_large_tactical_farmhouse -Category environment -Prefab "Assets/prefabs/environment/House_Large.prefab" -Model "Assets/models/house_large.vmdl"
powershell -ExecutionPolicy Bypass -File scripts\agents\new_asset_brief.ps1 -Name house_small_tactical_safehouse -Category environment -Prefab "Assets/prefabs/environment/House_Small.prefab" -Model "Assets/models/house_small.vmdl"
```

Expected: both brief files are created under `docs/assets/briefs/` and preserve the intended prefab/model targets.

- [ ] **Step 2: Fill `house_large_tactical_farmhouse.md` with the exact production contract**

Set these decisions in the brief:

- Asset role: fortified main farmhouse.
- Model target: `Assets/models/house_large.vmdl`.
- Prefab target: `Assets/prefabs/environment/House_Large.prefab`.
- Source target: `environment_model.blend/house_large.blend`.
- Architecture: broad farmhouse mass, wrap/side porch, cellar entry, partial second floor or loft, roof access, protected but usable windows, roof fighting position.
- Material roles: aged painted siding, oxidized metal roof, concrete or masonry foundation, dark interior wood, exterior trim/fascia/gutters, dusty glass, rail/ladder metal, tactical tarp/patch/barricade material, dirt/grime/repair masks.
- Traversal: cellar or basement route, main-floor cover, loft access, roof access, visible ladders, roof exposure readable from drone height.
- Visual review: ground-height exterior, ground-height entry/interior, drone-height overview, three-quarter asset preview, texture contact sheet.

- [ ] **Step 3: Fill `house_small_tactical_safehouse.md` with the exact production contract**

Set these decisions in the brief:

- Asset role: compact secondary safehouse or outbuilding.
- Model target: `Assets/models/house_small.vmdl`.
- Prefab target: `Assets/prefabs/environment/House_Small.prefab`.
- Source target: `environment_model.blend/house_small.blend`.
- Architecture: smaller asymmetric footprint, strong porch or lean-to identity, one main level, attic/loft or roof access, faster interior read than the large house.
- Material roles: weathered siding distinct from the large house, metal roof, concrete block or pier foundation, interior dark wood, trim/fascia/gutter details, dusty glass, rail/ladder metal, utility panel or tarp patch material, dirt/grime variation masks.
- Traversal: one primary room path, one side room or lean-to route, loft or roof access, fewer branches than `House_Large`.
- Visual review: ground-height exterior, ground-height entry/interior, drone-height overview, three-quarter asset preview, texture contact sheet.

- [ ] **Step 4: Verify briefs have no generated stub language**

Run:

```powershell
$patterns = @("TB" + "D", "TO" + "DO", "fill" + " in", "REPLACE_ME", "FIXME")
foreach ($pattern in $patterns) {
  rg -n $pattern docs\assets\briefs\house_large_tactical_farmhouse.md docs\assets\briefs\house_small_tactical_safehouse.md
}
```

Expected: no matches.

## Task 3: Local Material And Texture Generation

**Files:**

- Modify: `scripts/building_architecture_pipeline.py`
- Modify: `scripts/house_large_asset_pipeline.json`
- Modify: `scripts/house_small_asset_pipeline.json`
- Create: `Assets/materials/environment/house_large_siding.*`
- Create: `Assets/materials/environment/house_large_roof.*`
- Create: `Assets/materials/environment/house_large_foundation.*`
- Create: `Assets/materials/environment/house_large_trim.*`
- Create: `Assets/materials/environment/house_large_interior_wood.*`
- Create: `Assets/materials/environment/house_large_glass.*`
- Create: `Assets/materials/environment/house_large_metal.*`
- Create: `Assets/materials/environment/house_large_tactical_patch.*`
- Create: `Assets/materials/environment/house_large_dirt_mask.*`
- Create: `Assets/materials/environment/house_small_siding.*`
- Create: `Assets/materials/environment/house_small_roof.*`
- Create: `Assets/materials/environment/house_small_foundation.*`
- Create: `Assets/materials/environment/house_small_trim.*`
- Create: `Assets/materials/environment/house_small_interior_wood.*`
- Create: `Assets/materials/environment/house_small_glass.*`
- Create: `Assets/materials/environment/house_small_metal.*`
- Create: `Assets/materials/environment/house_small_tactical_patch.*`
- Create: `Assets/materials/environment/house_small_dirt_mask.*`

- [ ] **Step 1: Replace arena-material remaps with house-specific material slots**

In `scripts/building_architecture_pipeline.py`, replace the current shared `MATERIAL_REMAP` with per-house remap dictionaries:

```python
HOUSE_LARGE_MATERIAL_REMAP = {
    "M_HouseLarge_Siding": "materials/environment/house_large_siding.vmat",
    "M_HouseLarge_Roof": "materials/environment/house_large_roof.vmat",
    "M_HouseLarge_Foundation": "materials/environment/house_large_foundation.vmat",
    "M_HouseLarge_Trim": "materials/environment/house_large_trim.vmat",
    "M_HouseLarge_InteriorWood": "materials/environment/house_large_interior_wood.vmat",
    "M_HouseLarge_Glass": "materials/environment/house_large_glass.vmat",
    "M_HouseLarge_Metal": "materials/environment/house_large_metal.vmat",
    "M_HouseLarge_TacticalPatch": "materials/environment/house_large_tactical_patch.vmat",
    "M_HouseLarge_DirtMask": "materials/environment/house_large_dirt_mask.vmat",
}

HOUSE_SMALL_MATERIAL_REMAP = {
    "M_HouseSmall_Siding": "materials/environment/house_small_siding.vmat",
    "M_HouseSmall_Roof": "materials/environment/house_small_roof.vmat",
    "M_HouseSmall_Foundation": "materials/environment/house_small_foundation.vmat",
    "M_HouseSmall_Trim": "materials/environment/house_small_trim.vmat",
    "M_HouseSmall_InteriorWood": "materials/environment/house_small_interior_wood.vmat",
    "M_HouseSmall_Glass": "materials/environment/house_small_glass.vmat",
    "M_HouseSmall_Metal": "materials/environment/house_small_metal.vmat",
    "M_HouseSmall_TacticalPatch": "materials/environment/house_small_tactical_patch.vmat",
    "M_HouseSmall_DirtMask": "materials/environment/house_small_dirt_mask.vmat",
}
```

Keep `vmdl_use_global_default: false` and `strict_vmdl_material_sources: true` in both generated configs.

- [ ] **Step 2: Add deterministic local texture generation**

Add a normal Python path in `scripts/building_architecture_pipeline.py` for writing PNG maps and `.vmat` files before Blender export. Generate these map sets:

- `TextureColor`, `TextureNormal`, `TextureRoughness`, and `TextureAmbientOcclusion` for siding, roof, foundation, and trim.
- `TextureColor`, `TextureRoughness`, and `TextureAmbientOcclusion` for interior wood, rail/ladder metal, tactical patch, and dirt mask.
- `TextureColor` plus material parameters for glass.

Use seeded procedural functions in the repo script, not downloaded PBR libraries. Suggested deterministic seeds:

```python
HOUSE_TEXTURE_SEEDS = {
    "house_large": 4101,
    "house_small": 5101,
}
```

Generate at least 512x512 maps for siding, roof, foundation, trim, and interior wood. Generate 256x256 maps for glass, metal, tactical patch, and dirt mask.

- [ ] **Step 3: Write `.vmat` files with real texture references**

Each generated material must use S&Box `shaders/complex.shader` and resource paths under `materials/environment/`. For example:

```text
"Layer0"
{
    "shader"        "shaders/complex.shader"
    "TextureColor"        "materials/environment/house_large_siding_color.png"
    "TextureNormal"        "materials/environment/house_large_siding_normal.png"
    "TextureRoughness"        "materials/environment/house_large_siding_rough.png"
    "TextureAmbientOcclusion"        "materials/environment/house_large_siding_ao.png"
    "g_flModelTintAmount"        "1.000000"
    "g_vColorTint"        "[1.000000 1.000000 1.000000 0.000000]"
    "g_flMetalness"        "0.000000"
    "g_flRoughness"        "0.780000"
    "g_bFogEnabled"        "1"
    "g_vTexCoordScale"        "[1.000 1.000]"
    "g_vTexCoordOffset"        "[0.000 0.000]"
    "g_vTexCoordScrollSpeed"        "[0.000 0.000]"
}
```

Use the same format for each house-specific material with its matching texture filenames.

- [ ] **Step 4: Generate materials and configs**

Run the normal Python side of the building pipeline:

```powershell
python scripts\building_architecture_pipeline.py --write-materials --write-configs
```

Expected:

- Both house configs reference only `materials/environment/house_large_*` and `materials/environment/house_small_*`.
- No config references `materials/arena/concrete_wall.vmat`, `materials/arena/asphalt_cover.vmat`, or `materials/arena/metal_pad.vmat`.
- Generated PNGs and `.vmat` files exist under `Assets/materials/environment/`.

- [ ] **Step 5: Validate material references before modeling continues**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\material_texture_audit.ps1 -Category environment -ShowInfo
python scripts\texture_contact_sheet.py --config scripts\house_large_asset_pipeline.json --out screenshots\asset_previews\house_large_texture_sheet.png
python scripts\texture_contact_sheet.py --config scripts\house_small_asset_pipeline.json --out screenshots\asset_previews\house_small_texture_sheet.png
```

Expected: no missing `.vmat`, `TextureColor`, or missing texture-file errors for either house. Texture sheets are written for reviewer inspection.

## Task 4: Blender Geometry Rebuild

**Files:**

- Modify: `scripts/building_architecture_pipeline.py`
- Modify: `environment_model.blend/house_large.blend`
- Modify: `environment_model.blend/house_small.blend`

- [ ] **Step 1: Replace current blocky house authoring with the large-house tactical farmhouse design**

In `make_large()`, keep `HouseLarge_Root`, but replace the box-only low-detail form with named source objects that satisfy this layout:

- Footprint budget: main mass about `520 x 430` game units, with roof/porch overhangs not exceeding `600 x 510`.
- Cellar/basement: concrete floor and walls, visible cellar stair or hatch route, low cover crates, and a readable exterior cellar entry.
- Ground floor: front or side porch, main entry, interior cover partitions, reinforced but usable window openings, boarded sections with gaps, foundation band, corner posts, fascia, gutters, downspouts, utility panel, cables.
- Loft/second floor: partial loft volume rather than a full tower, interior railing, exterior window sightlines.
- Roof: layered gable or cross-gable roof, ridge cap, access hatch or ladder landing, low fighting-position cover, antenna/comms detail, roof clutter that does not hide the access route.
- Tactical dressing: restrained sandbag or plank barricades, tarp/patch panels, roof/porch utility clutter, reinforced windows.

Required source object name prefixes:

```text
HouseLarge_Root
Large_Foundation_*
Large_Cellar_*
Large_GroundFloor_*
Large_Porch_*
Large_Window_Reinforced_*
Large_Loft_*
Large_Roof_*
Large_Ladder_*
Large_Cover_*
Large_Tactical_*
Large_Utility_*
```

Use `Large_Cellar_*` in object names; the spaced line above only records the human category.

- [ ] **Step 2: Replace current blocky house authoring with the small-house safehouse design**

In `make_small()`, keep `HouseSmall_Root`, but build a distinct asymmetrical compact structure:

- Footprint budget: main mass about `330 x 280` game units, with lean-to/porch identity and total bounds not exceeding `410 x 350`.
- One main level with fewer internal blockers than `House_Large`.
- Side porch or lean-to entry that is visually different from the large house.
- Attic/loft or roof access with a shorter ladder and a smaller fighting/detail position.
- Fewer tactical additions than `House_Large`, but still readable as occupied and fortified.
- Variation masks and asymmetry so four repeated scene instances do not read as exact scaled copies of `House_Large`.

Required source object name prefixes:

```text
HouseSmall_Root
Small_Foundation_*
Small_MainRoom_*
Small_Porch_*
Small_LeanTo_*
Small_Window_Reinforced_*
Small_Loft_*
Small_Roof_*
Small_Ladder_*
Small_Cover_*
Small_Tactical_*
Small_Utility_*
```

- [ ] **Step 3: Keep generated source mesh quality explicit**

For both houses, each mesh-producing helper must:

- Apply scale after cube or mesh creation.
- Assign UVs based on dominant face axis.
- Use material slot names from the matching house remap dictionary.
- Add bevels to visible construction edges.
- Add weighted normals.
- Avoid hidden renderable meshes, zero-vertex meshes, and off-root top-level meshes.

- [ ] **Step 4: Generate the two `.blend` sources**

Run inside Blender:

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python scripts\building_architecture_pipeline.py -- --generate-blends
```

Expected:

- `environment_model.blend/house_large.blend` is saved with `HouseLarge_Root`.
- `environment_model.blend/house_small.blend` is saved with `HouseSmall_Root`.
- `House_Large` and `House_Small` public asset names are unchanged.
- `house_rural.blend` is untouched.

- [ ] **Step 5: Run Blender source quality checks**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\blender_quality_audit.ps1 -Blend @('environment_model.blend/house_large.blend','environment_model.blend/house_small.blend') -ShowInfo
```

Expected: no missing blend, missing root, zero mesh, zero-vertex, missing UV, or scale/dimension blocker for either house.

## Task 5: Asset Export And ModelDoc Validation

**Files:**

- Modify: `Assets/models/house_large.fbx`
- Modify: `Assets/models/house_large.vmdl`
- Modify: `Assets/models/house_small.fbx`
- Modify: `Assets/models/house_small.vmdl`
- Modify: `scripts/house_large_asset_pipeline.json`
- Modify: `scripts/house_small_asset_pipeline.json`

- [ ] **Step 1: Validate configs before export**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\asset_pipeline_audit.ps1 -ShowInfo
```

Expected: no missing source blend, missing material remap target, target path drift, or config parse error for either house.

- [ ] **Step 2: Export `house_large`**

Run:

```powershell
python scripts\asset_pipeline.py --config scripts\house_large_asset_pipeline.json
```

Expected:

- `Assets/models/house_large.fbx` is updated.
- `Assets/models/house_large.vmdl` is updated.
- Export verification finds `HouseLargeMesh`.
- Export verification finds every `M_HouseLarge_*` material slot declared in the config.

- [ ] **Step 3: Export `house_small`**

Run:

```powershell
python scripts\asset_pipeline.py --config scripts\house_small_asset_pipeline.json
```

Expected:

- `Assets/models/house_small.fbx` is updated.
- `Assets/models/house_small.vmdl` is updated.
- Export verification finds `HouseSmallMesh`.
- Export verification finds every `M_HouseSmall_*` material slot declared in the config.

- [ ] **Step 4: Verify FBX material slots and ModelDoc remaps**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\fbx_material_slot_audit.ps1 -Config scripts\house_large_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\fbx_material_slot_audit.ps1 -Config scripts\house_small_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\modeldoc_audit.ps1 -ShowInfo
```

Expected: both FBX files expose the strict material slots expected by each config, and generated `.vmdl` remaps match the configs.

## Task 6: Prefab Collision, Ladders, And Zones

**Files:**

- Modify: `scripts/building_architecture_pipeline.py`
- Modify: `Assets/prefabs/environment/House_Large.prefab`
- Modify: `Assets/prefabs/environment/House_Small.prefab`

- [ ] **Step 1: Replace prefab helper constants with the new geometry contract**

Update `large_house_children()` and `small_house_children()` so helper objects match the new authored geometry. Preserve root prefab names and `Model_Visual` model paths. Use these helper categories:

For `House_Large.prefab`:

- `Collision_Floor_Basement`
- `Collision_Floor_Ground`
- `Collision_Floor_Loft`
- `Collision_Roof_Main`
- `Collision_Roof_Access`
- `Collision_Foundation_*`
- `Collision_Wall_*`
- `Collision_Porch_*`
- `Collision_InteriorCover_*`
- `Collision_RoofCover_*`
- `Collision_Stairs_Down`
- `Ladder_To_Loft`
- `Ladder_To_Roof`
- `Zone_Foyer`
- `Zone_LivingArea`
- `Zone_Kitchen`
- `Zone_Basement`
- `Zone_Loft`
- `Zone_Roof`
- `Zone_Porch`

For `House_Small.prefab`:

- `Collision_Floor_Ground`
- `Collision_Floor_Loft`
- `Collision_Roof_Main`
- `Collision_Porch_*`
- `Collision_LeanTo_*`
- `Collision_Wall_*`
- `Collision_InteriorCover_*`
- `Collision_RoofCover_*`
- `Ladder_To_Loft`
- `Ladder_To_Roof`
- `Zone_Entry`
- `Zone_MainRoom`
- `Zone_SideRoom`
- `Zone_Loft`
- `Zone_Roof`
- `Zone_Porch`

All physical collision helpers must be static non-trigger `Sandbox.BoxCollider` components. Ladder helpers must include `DroneVsPlayers.LadderVolume` plus a trigger `BoxCollider`. Zone helpers must be trigger `BoxCollider` components.

- [ ] **Step 2: Generate prefab JSON from the updated helper contract**

Run:

```powershell
python scripts\building_architecture_pipeline.py --write-prefabs
```

Expected:

- `Assets/prefabs/environment/House_Large.prefab` keeps root name `House_Large` and model path `models/house_large.vmdl`.
- `Assets/prefabs/environment/House_Small.prefab` keeps root name `House_Small` and model path `models/house_small.vmdl`.
- Collision, ladder, and zone helpers match the new geometry names and bounds.

- [ ] **Step 3: Validate prefab graph and authored collision**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\prefab_graph_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\collision_authoring_agent.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite collision -ShowInfo
```

Expected: no missing prefab references, invalid GUID refs, building-without-collision errors, ladder-without-`LadderVolume` errors, or broad helper collisions that contradict the visible model.

## Task 7: Scene Instance Check And Minimal Placement Corrections

**Files:**

- Modify only if needed: `scripts/building_architecture_pipeline.py`
- Modify only if needed: `Assets/scenes/main.scene`

- [ ] **Step 1: Inspect current scene placements**

Run:

```powershell
$scene = Get-Content -LiteralPath 'Assets\scenes\main.scene' -Raw | ConvertFrom-Json
function Visit($node,$path){
  if($null -eq $node){ return }
  $name = [string]$node.Name
  if($name -like 'House_Large_*' -or $name -like 'House_Small_*'){
    [pscustomobject]@{Name=$name; Position=$node.Position; Rotation=$node.Rotation; Scale=$node.Scale; Path=$path} | Format-List
  }
  foreach($child in @($node.Children)){ Visit $child "$path/$name" }
}
foreach($go in @($scene.GameObjects)){ Visit $go '' }
if($scene.RootObject){ Visit $scene.RootObject '' }
```

Expected scene instances before edits:

- `House_Large_01` at `-1680,1520,0`
- `House_Large_02` at `-1740,-1540,0`
- `House_Small_01` at `1120,1680,0`
- `House_Small_02` at `1340,-1660,0`
- `House_Small_03` at `2050,620,0`
- `House_Small_04` at `-2220,620,0`

- [ ] **Step 2: Update scene helper children only after prefab helpers are final**

If helper child data in the scene needs to mirror the new prefab children, run:

```powershell
python scripts\building_architecture_pipeline.py --update-scene
```

Expected: only existing `House_Large_*` and `House_Small_*` instance children are replaced with the generated house helper set. No new house instances are added.

- [ ] **Step 3: Adjust placement or rotation only if new bounds visibly break paths**

Allowed edits:

- Move or rotate only existing `House_Large_*` and `House_Small_*` roots.
- Keep root names, GUIDs, prefab/model references, and scale intact.
- Limit movement to the minimum needed to unbury entries, clear critical paths, or prevent new porch/roof overhangs from clipping major authored paths.

Disallowed edits:

- Adding `house_rural`.
- Moving WaterTower.
- Redesigning roads, grass, arena layout, spawn layout, or gameplay flow.

- [ ] **Step 4: Validate scene integrity after any scene edit**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\scene_integrity_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite scene -ShowInfo
```

Expected: no scene parse errors, no invalid model references, and no unrelated scene changes.

## Task 8: Visual Proof

**Files:**

- Create or modify: `scripts/render_environment_asset_views.py`
- Create: `screenshots/asset_previews/house_large_ground.png`
- Create: `screenshots/asset_previews/house_large_drone.png`
- Create: `screenshots/asset_previews/house_large_three_quarter.png`
- Create: `screenshots/asset_previews/house_large_texture_sheet.png`
- Create: `screenshots/asset_previews/house_small_ground.png`
- Create: `screenshots/asset_previews/house_small_drone.png`
- Create: `screenshots/asset_previews/house_small_three_quarter.png`
- Create: `screenshots/asset_previews/house_small_texture_sheet.png`

- [ ] **Step 1: Add or reuse a repeatable environment asset view renderer**

If the existing single-angle `asset_visual_review.ps1` cannot emit named ground, drone, and three-quarter views, add `scripts/render_environment_asset_views.py`. It should:

- Take `--blend`, `--asset-name`, and `--out-dir`.
- Launch Blender in background mode.
- Render three PNGs per asset: `<asset-name>_ground.png`, `<asset-name>_drone.png`, and `<asset-name>_three_quarter.png`.
- Write a JSON sidecar with mesh count, material count, bounds, camera names, and output paths.
- Leave the `.blend` file unmodified.

- [ ] **Step 2: Render required house previews**

Run:

```powershell
python scripts\render_environment_asset_views.py --blend environment_model.blend/house_large.blend --asset-name house_large --out-dir screenshots\asset_previews
python scripts\render_environment_asset_views.py --blend environment_model.blend/house_small.blend --asset-name house_small --out-dir screenshots\asset_previews
```

Expected:

- Ground-height images show soldier-readable entrances, porch, windows, and material scale.
- Drone-height images show roof access, roof exposure, silhouette, and distinct building shapes.
- Three-quarter images show the overall authored geometry and material breakup.

- [ ] **Step 3: Generate texture contact sheets from final configs**

Run:

```powershell
python scripts\texture_contact_sheet.py --config scripts\house_large_asset_pipeline.json --out screenshots\asset_previews\house_large_texture_sheet.png
python scripts\texture_contact_sheet.py --config scripts\house_small_asset_pipeline.json --out screenshots\asset_previews\house_small_texture_sheet.png
```

Expected: texture sheets show real color maps and any masks for every material remap target.

- [ ] **Step 4: Perform visual self-review before final validation**

Open the generated PNGs and check:

- `House_Large` reads as a fortified main farmhouse, not a simple box.
- `House_Small` reads as a compact safehouse/outbuilding, not a scaled `House_Large`.
- Both are structurally sound, occupied, and fortified without looking collapsed or ruined.
- Tactical details are restrained and legible.
- Entrances, ladders, roof access, windows, cellar/loft routes, and cover read from soldier and drone angles.
- Materials do not collapse into the old arena texture set.

## Task 9: Final Automated Validation

**Files:**

- Validate all owned files from Tasks 2-8.

- [ ] **Step 1: Run focused AAA and asset checks**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\aaa_asset_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\blender_quality_audit.ps1 -Blend @('environment_model.blend/house_large.blend','environment_model.blend/house_small.blend') -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\material_texture_audit.ps1 -Category environment -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\asset_pipeline_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\fbx_material_slot_audit.ps1 -Config scripts\house_large_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\fbx_material_slot_audit.ps1 -Config scripts\house_small_asset_pipeline.json -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\modeldoc_audit.ps1 -ShowInfo
```

Expected: no errors tied to the remodeled houses.

- [ ] **Step 2: Run prefab, scene, and collision checks**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\prefab_graph_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\scene_integrity_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\collision_authoring_agent.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite collision -ShowInfo
```

Expected: no errors tied to the remodeled house prefabs or existing house scene instances.

- [ ] **Step 3: Run the broad asset-production suite**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite asset-production -ShowInfo
```

Expected: no errors tied to house briefs, Blender source, material texture references, asset configs, ModelDoc, FBX material slots, or prefab graph.

- [ ] **Step 4: Compile the C# project**

Run:

```powershell
dotnet build Code\dronevsplayers.csproj --no-restore
```

Expected: build succeeds, or any failure is confirmed as pre-existing and unrelated to the house asset work.

- [ ] **Step 5: Check final diff scope**

Run:

```powershell
git diff --name-status
git diff --check
```

Expected:

- Diff only includes owned files listed in this plan, plus optional scene placement updates if justified.
- No `house_rural`, WaterTower, gameplay, UI, networking, weapon, drone, or round logic changes are present.
- `git diff --check` reports no whitespace errors.

## Task 10: Manual Editor And Playtest Handoff

**Files:**

- No additional file edits unless a manual check exposes a concrete house-asset blocker.

- [ ] **Step 1: Inspect imported houses in S&Box editor lighting**

Manual checks:

- `House_Large` and `House_Small` render at expected scale in `Assets/scenes/main.scene`.
- Material remaps bind correctly in S&Box, not only Blender.
- Generated `.vmat` textures appear on siding, roof, foundation, trim, and tactical additions.
- Scene placements do not bury entries, cellar access, porches, ladders, or roof exits.

- [ ] **Step 2: Playtest collision and traversal**

Manual checks:

- Player can walk all intended floors, porch surfaces, lofts, and roof access areas.
- Player cannot fall through floors or clip into major wall/roof geometry.
- Ladders exit cleanly without trapping or launching the player.
- Cellar/basement, interior cover, and window openings provide useful cover without making players impossible to find.
- Drone-height view reads roof exposure, access routes, and silhouettes for both houses.
- Four `House_Small` instances read as compact compound buildings without looking like exact scaled `House_Large` copies.

- [ ] **Step 3: Final report**

Report:

- Loaded agent cards and workflow gates used.
- Files changed by category: briefs, generator/script, materials/textures, Blender sources, models/VMDLs, prefabs, optional scene edits, proof screenshots.
- Validation commands and results.
- Preview/contact-sheet paths.
- Manual editor/playtest checks still needed if they were not completed in the editor.
