# Claude Training Note: Blender Building Alignment for S&Box

When the user asks to line up a building in Blender, treat the current open `.blend` file and screenshot as the source of truth. Do not trust stale generated prefab dimensions until you have compared them against the actual Blender mesh bounds.

## Required Workflow

1. Inspect the handoff, the current `.blend`, the S&Box prefab, and any scene instances before editing.
2. Align by bounds, not by eyeballing object origins:
   - floor top equals wall bottom,
   - next floor top equals upper-wall bottom,
   - roof/eave bottom meets the upper wall top,
   - stairs and ladders start and end exactly on floor surfaces.
3. Save the visible Blender file after alignment.
4. Apply unapplied transforms on edited mesh objects before export.
5. Re-export with the asset pipeline config for that asset.
6. Render a preview and inspect it for disconnected floors, floating walls, or roof drift.
7. Sync S&Box prefab and scene-instance collision boxes from Blender mesh bounds, preserving existing GUIDs.
8. Update any generator/pipeline script constants so a future run cannot regenerate the old broken layout.
9. Verify with:
   - `python -m py_compile scripts\building_architecture_pipeline.py scripts\render_asset_preview.py`
   - `python scripts\asset_pipeline.py --config scripts\house_large_asset_pipeline.json`
   - `powershell -ExecutionPolicy Bypass -File scripts\agents\fbx_material_slot_audit.ps1 -Config scripts\house_large_asset_pipeline.json -ShowInfo`
   - `powershell -ExecutionPolicy Bypass -File scripts\agents\prefab_graph_audit.ps1 -ShowInfo`
   - `powershell -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite scene -ShowInfo`
   - `dotnet build Code\dronevsplayers.csproj --no-restore`

## What Went Wrong This Time

The visual Blender model and the S&Box collision/prefab values were not kept in sync. Some floor and wall pieces were still using old dimensions, which made the building look disconnected and left stale collider values in the scene. The fix was to snap the meshes in Blender, export the corrected model, then update the prefab and placed scene instances from the real Blender bounds.

## Reporting Standard

Separate new task-caused warnings from older unrelated repo warnings. If a Blender quality audit reports new unapplied transforms on the edited asset, fix them before claiming the asset is ready.
