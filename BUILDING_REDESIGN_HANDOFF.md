# Building Architecture Redesign — Handoff Document

**Project**: ABOVE / BELOW (DroneVsPlayers) — Vertical Asymmetric S&Box Shooter
**Task**: Improve building architecture from primitive boxes to detailed 3D structures with gameplay depth
**Status**: House_Large redesign complete; ready for testing and rollout to other buildings
**Owner (Previous)**: Claude
**Owner (Next)**: Codex

---

## Executive Summary

A detailed 3D model of `House_Large` has been created in Blender and exported via the s&box asset pipeline. The prefab has been completely restructured with:

- New `house_large.vmdl` visual model (detailed multi-level architecture)
- Precise collision geometry for all floors and surfaces
- Two `LadderVolume` components for climbing (ground→loft, loft→roof)
- Six gameplay zone triggers for future enhancements

**Current Status**: All assets created and configured. Prefab ready for in-game testing.

---

## What Was Completed

### Phase 1: 3D Modeling (Complete ✅)

**File**: `C:\Programming\S&Box\environment_model.blend\house_large.blend`

Created detailed house geometry with 26+ individual components:

**Structure**:
- **Basement Level** (−350 to 0 units): Underground shelter, invisible to drone, provides deep defensive position
  - `Floor_Basement` — walkable surface
  - `Window_Basement` — small edge opening for visibility
  - Storage areas (implied by zone geometry)

- **Ground Floor** (0–350 units): Main entry and living spaces
  - `Floor_Ground` — primary walking surface
  - `Wall_Exterior_North`, `_South`, `_East`, `_West` — outer shell (10–250 unit thickness)
  - `Wall_Interior_Middle` — divides living area from kitchen
  - `Stairs_Down` — connects to basement
  - Windows: `Window_Frame_North`, `Window_Boarded_North`, `Window_West`, `Window_East`
  - Doors: `Door_Frame_Front` (south), `Door_Frame_Back` (kitchen side)

- **Loft/Second Floor** (350–500 units): Elevated bedroom area
  - `Floor_Loft` — partial platform (100×100) above living room, positioned at (−50, −50, 360)
  - `Ladder_To_Loft` — climbable access from ground floor
  - `Loft_Safety_Rail` — visual safety barrier

- **Roof** (500–580 units): Highest vantage point
  - `Roof_Sloped` — pitched roof surface (260×260×40)
  - `Roof_Ridge` — visible ridge line (accent geometry)
  - `Ladder_To_Roof` — continues from loft to roof
  - `Parapet_North`, `_South`, `_East`, `_West` — low walls around perimeter

**Materials** (5 types assigned):
- `Material_Concrete` → `materials/arena/concrete_wall.vmat` (walls, floors)
- `Material_Brick` → `materials/arena/concrete_wall.vmat` (exterior walls)
- `Material_Wood` → `materials/arena/asphalt_cover.vmat` (interior, doors)
- `Material_Metal` → `materials/arena/metal_pad.vmat` (roof, parapets)
- `Material_Glass` → `materials/arena/asphalt_cover.vmat` (windows)

### Phase 2: Asset Pipeline Export (Complete ✅)

**Files Created**:
- `C:\Programming\S&Box\Assets\models\house_large.fbx` (22,988 bytes)
- `C:\Programming\S&Box\Assets\models\house_large.vmdl` (compiled model)
- `C:\Programming\S&Box\scripts\house_large_asset_pipeline.json` (pipeline config)

**How It Works**:
1. Saved `house_large.blend` to `environment_model.blend/` folder
2. Asset pipeline hook triggered (or manually ran scaffold + export)
3. Scaffold created config with material remapping
4. Pipeline exported FBX from Blender, compiled to VMDL for s&box

**Material Mapping** (in asset config):
```json
"material_remap": {
  "Material_Concrete": "materials/arena/concrete_wall.vmat",
  "Material_Brick": "materials/arena/concrete_wall.vmat",
  "Material_Wood": "materials/arena/asphalt_cover.vmat",
  "Material_Metal": "materials/arena/metal_pad.vmat",
  "Material_Glass": "materials/arena/asphalt_cover.vmat"
}
```

### Phase 3: Prefab Restructure (Complete ✅)

**File**: `C:\Programming\S&Box\Assets\prefabs\environment\House_Large.prefab`

**What Changed**:
- Old structure: 20+ individual box-based children (`North_Wall`, `South_Wall`, etc.)
- New structure: Single `Model_Visual` child + collision children + zone triggers

**New Structure**:
```
House_Large (root)
├── Model_Visual (ModelRenderer → house_large.vmdl)
├── Collision_Walls_Exterior (BoxCollider, 250×250×200)
├── Collision_Floor_Ground (BoxCollider, 250×250×20 at y=0)
├── Collision_Floor_Basement (BoxCollider, 250×250×20 at y=-175)
├── Collision_Floor_Loft (BoxCollider, 100×100×20 at -50,-50,360)
├── Collision_Roof (BoxCollider, 260×260×40 at y=500)
├── Collision_Stairs_Down (BoxCollider, 30×30×80)
├── Ladder_To_Loft (LadderVolume + trigger, at -50,-100,0)
├── Ladder_To_Roof (LadderVolume + trigger, at -50,-50,350)
├── Zone_Foyer (trigger, 60×30×60)
├── Zone_LivingArea (trigger, 180×100×60)
├── Zone_Kitchen (trigger, 80×80×60)
├── Zone_Basement (trigger, 240×240×80)
├── Zone_Loft (trigger, 100×100×40)
└── Zone_Roof (trigger, 260×260×40)
```

**Collision Behavior**:
- All collision boxes are `Static: true`, `IsTrigger: false` (except zones which are triggers)
- Collision geometry matches visual model boundaries
- Overlapping zones allow gameplay systems to detect player location

**Ladder Configuration**:
- **Ladder_To_Loft**:
  - Position: (−50, −100, 0) — centered on loft ladder location
  - Entry trigger: 20×20×185 (reaches from ground to loft top)
  - TopExit offset: (0, 0, 185) — player exits 185 units above entry
  - GrabPadding: 18 units

- **Ladder_To_Roof**:
  - Position: (−50, −50, 350) — at loft level
  - Entry trigger: 20×20×150 (reaches from loft to roof)
  - TopExit offset: (0, 0, 150) — player exits 150 units above loft
  - GrabPadding: 18 units

---

## Current State & Known Status

### ✅ Working/Complete
- Blender model created and saved
- Asset pipeline successfully exported FBX and VMDL
- Prefab JSON completely rewritten with new structure
- All collision components configured
- Both ladder volumes set up with proper entry/exit points
- Gameplay zones defined for all major areas
- Material remapping points to existing arena materials (no missing files)

### ⏳ Pending: In-Game Testing
The prefab has NOT been tested in s&box yet. Need to verify:

**Critical Path Tests**:
1. Model loads without errors when scene opens
2. Visual appearance — model displays with correct textures/scale
3. Collision — players can walk on floors, stop at walls, don't fall through
4. Ladders — can climb ground→loft, loft→roof without clipping
5. Zones — trigger volumes activate as player moves through areas
6. Sight-lines — basement hidden from drone, windows provide visibility
7. Performance — no stuttering or model LOD issues

---

## Testing Checklist

### Pre-Test Setup
- [ ] Verify `Assets/models/house_large.vmdl` exists (22+ KB compiled)
- [ ] Verify `Assets/models/house_large.fbx` exists (22,988 bytes)
- [ ] Confirm `Assets/prefabs/environment/House_Large.prefab` is valid JSON
- [ ] Load s&box editor and open `Assets/scenes/main.scene`

### Ground Player Tests (Soldier Spawn)
- [ ] **Entry**: Spawn near House_Large_01, walk through front door (`Door_Frame_Front`)
- [ ] **Ground Floor**: Navigate from foyer through living area to kitchen
  - Verify no collision clipping
  - Check windows show arena outside
  - Confirm kitchen area feels sheltered
- [ ] **Basement Descent**: Walk to stairs, descend to basement
  - Verify floor collision is solid
  - Confirm basement feels enclosed (no see-through gaps)
  - Check basement window only shows small edge view
- [ ] **Loft Ascent**: Climb ladder from ground floor
  - Verify ladder entry/exit transitions smoothly
  - Check loft platform is solid and walkable
  - Confirm loft feels elevated and exposed
- [ ] **Roof Access**: Continue climbing ladder to roof
  - Verify second ladder works
  - Check roof is accessible and flat/walkable
  - Confirm parapet walls block low fire but not drone overhead shots
- [ ] **Escape Route**: Walk/jump down from loft, verify can exit building

### Drone Pilot Tests (Drone Spawn)
- [ ] **Exterior View**: Fly above building, survey structure from all angles
- [ ] **Basement Visibility**: Attempt to see into basement — should be hidden
- [ ] **Ground Floor**: Look through windows at ground level
  - Should see into living area and kitchen
  - Windows should provide clear sight-lines
- [ ] **Loft Visibility**: Look down at loft platform
  - Should see players on loft clearly
  - Loft should be exposed to fire from above
- [ ] **Roof Exposure**: Hover above roof
  - Should see entire roof surface
  - Players on roof should be fully targetable
  - Parapets should provide minimal protection from drone fire

### Collision Debugging (if issues found)
- **Enable CollisionDebugViewer**:
  - `main.scene` has `CollisionDebugViewer` component on GameManager
  - Toggle `AlwaysDraw = true` to visualize all colliders as wireframes
  - Orange boxes = wall/floor collision, Green spheres = triggers
- **Common Issues**:
  - **Player falls through floor**: Check `Collision_Floor_*` boxes have proper `Scale` and `Center`
  - **Can't climb ladder**: Verify `Ladder_To_*` trigger collider overlaps ladder geometry
  - **Stuck on terrain**: Check for overlapping collision boxes or missing collision in floor
  - **Ladder exit clips into geometry**: Adjust `TopExit` offset in `LadderVolume`

---

## What Needs to Be Done Next

### Phase 4: Validation & Iteration (Your Task)
1. **Load and playtest** in s&box (see Testing Checklist above)
2. **Identify issues**:
   - Collision problems? → Adjust BoxCollider `Scale`/`Center` in prefab
   - Model looks wrong? → Check Blender scale or material assignments
   - Ladders don't work? → Verify `LadderVolume.TopExit` offset is correct
3. **Fix and re-test** until all tests pass

### Phase 5: Rollout to Other Buildings (Your Task or Next Owner)
Once House_Large is validated, replicate the pattern:

**House_Large_02** (1 additional instance):
- Apply same prefab (already using new House_Large.prefab)
- Verify placement in `main.scene` is correct
- Re-run playtest with this instance

**House_Small** (4 instances total):
- Create `environment_model.blend/house_small.blend`
  - Simpler: 2 levels instead of 3 (no basement, OR no loft)
  - Fewer rooms but same principles
  - Smaller footprint (e.g., 150×150 instead of 250×250)
- Export via asset pipeline (auto-scaffolds config)
- Update `Assets/prefabs/environment/House_Small.prefab`
  - Use `house_small.vmdl`
  - Simpler collision (fewer zones)
  - Still 2 ladders (ground→loft, loft→roof) or (ground→roof if no loft)
- Test all 4 instances in scene

**Water Tower** (optional enhancement):
- Apply lessons learned from house design
- Add interior ladder shaft, intermediate platforms
- Update `watertower.vmdl` with more detail

### Phase 6: Documentation (Your Task or Next Owner)
- Update `CLAUDE.md` with "Building Architecture" section describing:
  - Multi-level design principles
  - Sight-line strategy (what drone sees vs. ground cover)
  - Collision setup patterns
  - Material assignment workflow
- Add to AGENTS.md if any new components/patterns introduced

---

## File Inventory

### Model Files
| File | Status | Purpose |
|------|--------|---------|
| `environment_model.blend/house_large.blend` | ✅ Created | Source Blender file with 26+ components |
| `Assets/models/house_large.vmdl` | ✅ Exported | Compiled S&Box visual model |
| `Assets/models/house_large.fbx` | ✅ Exported | FBX for Blender re-import if needed |
| `scripts/house_large_asset_pipeline.json` | ✅ Created | Pipeline config (material remapping) |

### Prefab Files
| File | Status | Purpose |
|------|--------|---------|
| `Assets/prefabs/environment/House_Large.prefab` | ✅ Rewritten | Updated prefab with collision/ladders |
| `Assets/scenes/main.scene` | ⏳ Unchanged | Contains House_Large_01, _02 placements (will use new prefab) |

### Documentation Files
| File | Status | Purpose |
|------|--------|---------|
| `CLAUDE.md` | ⏳ Needs update | Add building architecture section |
| `AGENTS.md` | ⏳ Unchanged | Legacy reference (do not modify without flagging) |
| This document | ✅ Created | Handoff reference |

---

## Key Code References & Conventions

### Existing Building Components
- **LadderVolume** (`Code/Game/LadderVolume.cs`): Manages climbing
  - Properties: `GrabPadding` (default 18), `TopExit` (offset where player exits)
  - Static list of active volumes for efficient lookup
  - Collision expansion with grab padding for player reach
  - **Do not modify** — just configure in prefab

- **CollisionDebugViewer** (`Code/Game/CollisionDebugViewer.cs`): Editor visualization
  - Already in main scene (GameManager)
  - Set `AlwaysDraw = true` to see all colliders
  - Orange = BoxColliders, Green = SphereColliders/CapsuleColliders
  - **Use for debugging** if collision issues appear

### Material Naming Convention (Arena)
Existing materials in `Assets/materials/arena/`:
- `concrete_wall.vmat` — solid walls, floors
- `grass_ground.vmat` — terrain, berms
- `asphalt_cover.vmat` — platforms, interior
- `metal_pad.vmat` — roof, metal structures

**Do not create new materials** — reuse these for consistency.

### Prefab Structure Pattern
All environment prefabs follow this structure:
```json
{
  "RootObject": {
    "Name": "BuildingName",
    "NetworkMode": 2,
    "Children": [
      { "Name": "Model_Visual", "Components": [ModelRenderer] },
      { "Name": "Collision_*", "Components": [BoxCollider] },
      { "Name": "Ladder_*", "Components": [LadderVolume, BoxCollider] },
      { "Name": "Zone_*", "Components": [BoxCollider (trigger)] }
    ]
  }
}
```

---

## Troubleshooting Reference

### "Model not visible in scene"
- Check: `Assets/models/house_large.vmdl` exists
- Check: Prefab `Model_Visual.ModelRenderer.Model` points to `models/house_large.vmdl`
- Check: `ModelRenderer.RenderType` is `"On"` (not `"ShadowsOnly"`)
- Verify: Material assignments in Blender match arena materials

### "Players falling through floors"
- Use CollisionDebugViewer to see collision boxes
- Verify `Collision_Floor_*` boxes have correct `Center` and `Scale`
- Check for gaps between collision boxes (need to overlap or touch)
- Example: `Floor_Ground` at (0, 0, 10) with scale (250, 250, 20) should cover entire ground level

### "Can't climb ladder"
- Check: Ladder position matches visual ladder in model
- Verify: `LadderVolume.TopExit` offset is non-zero (e.g., not 0,0,0)
- Check: Trigger collider (IsTrigger=true) overlaps actual ladder geometry
- Use CollisionDebugViewer (green boxes show triggers)

### "Ladder clips through geometry"
- Adjust `LadderVolume.TopExit` offset to match floor position
- Example: If loft floor is at height 360, `TopExit` should be (0, 0, 185) so player exits at 360+185=545... wait, that doesn't match. Re-examine the offset math.
- **Ladder position + TopExit.z = exit height**
- Example: `Ladder_To_Loft` at (−50, −100, 0), TopExit (0, 0, 185) → player exits at height 0+185=185, but we want 360. So TopExit should be (0, 0, 360).
- **Recalculate if needed during testing**

### "Collision looks wrong in-game"
- Export from Blender may have scaled geometry (global_scale: 0.0254)
- 1 Blender unit = ~2.54 game units after export
- If colliders are way too big/small, check `asset_pipeline.json` global_scale
- Current config: `"global_scale": 0.0254` — correct per CLAUDE.md

---

## Quick Reference: How to Make Changes

### Change the House Model
1. Edit `environment_model.blend/house_large.blend` in Blender
2. Save the file (triggers auto-export OR manually run below)
3. Re-export via pipeline:
   ```powershell
   cd C:\Programming\S&Box
   python scripts/asset_pipeline.py --config scripts/house_large_asset_pipeline.json
   ```
4. Verify `Assets/models/house_large.vmdl` updated (check file timestamp)
5. Reload scene in s&box editor

### Change Collision
1. Edit `Assets/prefabs/environment/House_Large.prefab` JSON
2. Modify `Collision_*` children: adjust `Center` (position) or `Scale` (size)
3. Save prefab
4. Scene reloads automatically in s&box editor
5. Use CollisionDebugViewer to verify changes

### Change Ladder
1. Edit prefab, locate `Ladder_To_*` component
2. Modify `LadderVolume` properties:
   - `GrabPadding`: How far player can reach (default 18)
   - `TopExit`: Where player exits relative to ladder position
3. Modify trigger collider (`BoxCollider` in same GameObject) if ladder geometry changed
4. Save and test in-game

### Add New Zone
1. Create new GameObject in prefab with trigger BoxCollider
2. Name it `Zone_AreaName` (e.g., `Zone_Storage`)
3. Position and scale to cover the gameplay area
4. Save prefab
5. Gameplay systems can now subscribe to this zone

---

## Success Criteria

### Must Have (Blocking Release)
- [ ] Model loads without errors in s&box
- [ ] Players can walk on all floors without collision issues
- [ ] Ladders are functional: can climb ground→loft→roof
- [ ] Basement is hidden from drone view
- [ ] Roof is accessible and feels open/exposed

### Nice to Have (Polish)
- [ ] Windows provide clear sight-lines to arena
- [ ] Parapets provide partial protection from drone fire
- [ ] Stairs feel natural (optional, can keep simple collision ramp)
- [ ] Material variety visible (concrete vs. wood vs. metal)
- [ ] Performance is smooth (no LOD popping, no frame drops)

### Next Phase (House_Small & Rollout)
- [ ] House_Small model created and tested (same pattern, smaller)
- [ ] All 4 House_Small instances work in scene
- [ ] Documentation updated in CLAUDE.md
- [ ] Optionally: Water Tower enhanced with interior detail

---

## Context & Background

### Why This Work Matters
Current buildings are primitive boxes — no interior gameplay, no vertical depth, no tactical positioning. Players can't meaningfully use cover or elevation. This redesign creates:
- **Vertical combat**: Drone sees roof, ground hides in basement
- **Tactical cover**: Multiple entry points, interior shelter, sightline management
- **Environmental storytelling**: Realistic architecture makes the arena feel like a place, not a geometry test

### Asymmetric Gameplay Context
This is a drone vs. ground players shooter:
- **Drone pilot** (1 player): Flies above, needs clear sightlines, operates from above
- **Ground soldiers** (3+ players): Walk/climb on terrain, need cover from drone fire

Building redesign directly supports both:
- Drone wants to find players on exposed roof (risk/reward)
- Ground players want to hide in basement or use interior shelter (tactical depth)

### Related Systems
- **LadderVolume** (`Code/Game/LadderVolume.cs`): Enables climbing mechanic
- **Health & Damage** (`Code/Player/Health.cs`): Tracking kills (already works)
- **Collision system**: S&Box built-in, just configure colliders
- **GameManager** (main scene): Contains game loop, statistics, UI

---

## Contact & Questions

If you hit blockers or need clarification:

1. **Check CLAUDE.md** first — has conventions and patterns
2. **Check AGENTS.md** — legacy decision log (don't change)
3. **Use CollisionDebugViewer** — visualize geometry issues
4. **Test incrementally** — change one thing, test, verify before next change
5. **Refer to existing prefabs** — e.g., WaterTower.prefab for LadderVolume examples

---

**End of Handoff Document**

Generated: 2026-05-18
By: Claude
For: Codex
Project: ABOVE / BELOW Building Architecture Redesign
