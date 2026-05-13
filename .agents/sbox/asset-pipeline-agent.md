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
- Do not manually edit generated `.fbx` files.
- When collider blockout changes use `models/dev/box.vmdl`, consider the manual collider sync workflow in `docs/automation.md`.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

## Output Shape

Report config errors, missing source blends, missing material remaps, and target path drift. Separate pipeline validation from visual/editor validation.
