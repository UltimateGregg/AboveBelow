# Asset Pipeline

Use `scripts/asset_pipeline.py` to move a Blender-authored asset into S&Box and wire it to a prefab.

The script does three repeatable jobs:

1. Opens a `.blend` file in Blender background mode.
2. Exports a named object hierarchy to an FBX under `Assets/`.
3. Optionally writes a `.vmdl` model document that imports that FBX.
4. Optionally updates a prefab `Sandbox.ModelRenderer` to point at that model resource.

For simple visual assets, set `combine_meshes: true` in the config. This bakes the selected Blender hierarchy into one exported mesh, which makes S&Box source-FBX previews and thumbnails much more reliable.

## Drone Example

From the project root:

```powershell
.\scripts\asset_pipeline.ps1
```

That config exports:

- `drone_model.blend/drone.blend.blend`
- root object `Drone`
- to `Assets/models/drone_high.fbx`
- writes `Assets/models/drone_high.vmdl`
- then wires `Assets/prefabs/drone.prefab` object `Visual` to `models/drone_high.vmdl`

## General Usage

For another asset, copy `scripts/drone_asset_pipeline.json` and change:

- `source_blend`
- `root_object`
- `target_fbx`
- `target_vmdl`
- `model_resource_path`
- `prefab`
- `visual_object`
- `required_object`
- `combine_meshes`
- `combined_object_name`
- `material_remap`

The script creates timestamped backups before replacing FBX or prefab files.
Backups are stored under `.tmpbuild/asset_backups` so the S&Box asset browser does not import them as real game assets.

Run a different config:

```powershell
.\scripts\asset_pipeline.ps1 -Config .\scripts\my_asset_pipeline.json
```

Preview prefab changes without exporting or writing:

```powershell
.\scripts\asset_pipeline.ps1 -DryRun
```

Use the Python entrypoint directly when you need every option:

```powershell
python .\scripts\asset_pipeline.py --help
```

## Notes

- `target_fbx` must be inside the project `Assets/` folder so the script can derive an S&Box resource path.
- Prefer pointing prefabs at `.vmdl`, not source `.fbx`, because S&Box previews and renderers handle model documents as normal compiled model assets.
- For S&Box model exports, prefer `axis_forward: "-Y"` and `axis_up: "Z"` unless a specific asset needs different orientation.
- If `combine_meshes` is enabled, `required_object` should normally contain the `combined_object_name`.
- `required_object` is a verification list. The script imports the exported FBX back into Blender and fails if any required objects are missing.
- If a prefab has generated cache trouble, rerun with `--remove-compiled-cache` from a normal PowerShell prompt so S&Box rebuilds the compiled prefab cache.
- A single FBX assigned to one `ModelRenderer` displays the full model, but individual submesh animation needs separate child renderers, bones, or attachments.

## Weapon Asset Example

`scripts/assault_rifle_m4_asset_pipeline.json` is the first weapon-specific
config. It exports `weapon_model.blend/assault_rifle_m4.blend` to
`Assets/models/weapons/assault_rifle_m4.fbx`, writes the matching `.vmdl`, and
updates the standalone `Assets/prefabs/assault_rifle_m4.prefab` visual renderer.

Use this pattern for soldier equipment assets: keep a dedicated source `.blend`,
dedicated material remaps under `Assets/materials/weapons/`, and a standalone
prefab that can later be attached to soldier class prefabs without re-exporting
the model.

## Scene Blockout Helper

Use `scripts/scene_blockout.py` for repeatable scene-JSON blockout edits that do not need Blender-authored meshes.

```powershell
python .\scripts\scene_blockout.py add-road-intersection --dry-run
python .\scripts\scene_blockout.py add-road-intersection
```

The helper finds `BlockoutMap`, installs a deterministic `RoadIntersection_Center` group, and replaces that group on rerun instead of duplicating objects. It uses the same `models/dev/box.vmdl` and `models/dev/plane.vmdl` patterns already used by `Assets/scenes/main.scene`.

## Blockout Collider Sync

Use `scripts/sync_box_colliders_to_renderers.ps1` after editing map blockout boxes, composed-box environment prefabs, or any scene/prefab object that uses `models/dev/box.vmdl`.

For `models/dev/box.vmdl`, the renderer's local model bounds are 50 x 50 x 50 units. S&Box applies the GameObject transform scale to both the renderer and the collider, so matching collision means:

- `BoxCollider.Center`: `0,0,0`
- `BoxCollider.Scale`: `50,50,50`

Do not set the collider scale to the already-scaled world size, such as `320,16,192`, on a scaled GameObject. That makes the editor collision outline too large because S&Box scales the collider again.

Preview the current map and environment prefab kit without writing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1
```

Apply the fix to the current map and environment prefab kit:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1 -Apply
```

Audit and apply across every `.scene` and `.prefab` under `Assets`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1 -All -Apply
```

The script skips trigger colliders by default. Pass `-IncludeTriggers` only when a trigger is intentionally meant to match the visible dev-box model exactly.
