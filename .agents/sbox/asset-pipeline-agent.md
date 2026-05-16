# Asset Pipeline Agent

## Purpose

Validate Blender to S&Box asset pipeline inputs and outputs.

## Primary Areas

- `*.blend`
- `scripts/*_asset_pipeline.json`
- `scripts/asset_pipeline.py`
- `scripts/smart_asset_export.ps1`
- `Assets/models/`
- `Assets/materials/`
- `Assets/prefabs/`
- `docs/automation.md`

## Review Rules

- Use the production lane before export: asset brief, Blender quality audit, material/texture audit, then the export path.
- Prefer the existing smart export path for `.blend` saves.
- Use asset-specific configs when scale, material remaps, or target paths differ from the generic convention.
- Keep generated outputs under normal S&Box asset folders.
- Material remaps must point to existing `.vmat` files.
- Material remap source names must be verified at the `.vmdl` layer, not just in Blender. If S&Box renders a remapped model with the wrong/default material, compare the exported FBX source material names, the config `material_remap` keys, and the generated `.vmdl` `from` values before changing geometry.
- For strict multi-material assets, verify the actual exported FBX material slots with `fbx_material_slot_audit.ps1`; config-to-VMDL drift checks are not enough to prove S&Box will bind the right slots.
- Use `vmdl_material_source_suffix` per asset when the model compiler expects raw FBX names instead of suffixed names. Set `strict_vmdl_material_sources: true` on assets where a mismatch should block handoff.
- For multi-material foliage and authored environment props such as `terrain_assets` or `watertower`, keep `vmdl_use_global_default: false` so a missed remap does not collapse the whole model to `materials/default.vmat`.
- Do not use scene or prefab `MaterialOverride` to fix a bad multi-material bind. Clear `MaterialOverride` and `Materials.indexed`, then fix the source asset config, FBX slots, and generated `.vmdl`.
- If Blender materials are procedural nodes instead of image textures, use `procedural-texture-transfer-agent.md`: bake color textures in background Blender, point `.vmat` `TextureColor` at the baked PNGs, and then re-export through the asset pipeline.
- Do not manually edit generated `.fbx` files.
- When collider blockout changes use `models/dev/box.vmdl`, consider the manual collider sync workflow in `docs/automation.md`.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

## Output Shape

Report config errors, missing source blends, missing material remaps, target path drift, and `.vmdl` remap source drift. Separate pipeline validation from visual/editor validation; a Blender preview is not proof that S&Box compiled and displayed the intended material.
