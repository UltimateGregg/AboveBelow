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
- Use `vmdl_material_source_suffix` per asset when the model compiler expects raw FBX names instead of suffixed names. Set `strict_vmdl_material_sources: true` on assets where a mismatch should block handoff.
- Do not manually edit generated `.fbx` files.
- When collider blockout changes use `models/dev/box.vmdl`, consider the manual collider sync workflow in `docs/automation.md`.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

## Output Shape

Report config errors, missing source blends, missing material remaps, target path drift, and `.vmdl` remap source drift. Separate pipeline validation from visual/editor validation; a Blender preview is not proof that S&Box compiled and displayed the intended material.
