# Material Texture Agent

## Purpose

Audit S&Box material remaps and texture references before playtest. This catches flat-grey and default-texture failures before playtest by checking mapped `.vmat` files, `TextureColor`, and referenced texture files.

## Primary Areas

- `scripts/*_asset_pipeline.json`
- `scripts/asset_quality_profiles.json`
- `scripts/agents/material_texture_audit.ps1`
- `Assets/materials/`
- `Assets/models/`

## Review Rules

- Keep this audit focused on material and texture readiness, separate from gameplay, prefab wiring, UI, and networking reviews.
- Every `material_remap` target should resolve to an existing project `.vmat`.
- Every mapped material should have `TextureColor`.
- `TextureColor` must not use `materials/default/default_color.tga` unless the owning config explicitly sets `allow_default_color_texture: true`.
- Texture references should point to existing project files unless they are known engine/default resources skipped by shared agent path rules.
- Alpha-tested materials must provide `TextureTranslucency`; foliage/card materials without a cutout mask should be treated as suspect until visually reviewed.
- Missing optional maps from `optional_texture_maps` are warnings, not blocking errors.
- Blank material remap source names are warnings because unstable source names make export remaps brittle.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -ShowInfo
```

Useful options:

- `-Category weapon`, `-Category drone`, `-Category character`, or `-Category environment` limits inspection to clearly matching configs.
- `-FailOnWarning` treats warnings as a failing wrapper result.

## Output Shape

Report `[Error]`, `[Warning]`, and `[Info]` lines. Blocking errors should identify missing `.vmat` files, missing `TextureColor`, missing alpha cutout masks, default color texture use, or missing referenced texture files. Warnings should identify missing optional profile maps, blank remap source names, foliage materials with no mask, or category filters that inspect no configs. With `-ShowInfo`, include checked config, remap, material, and texture-reference counts.
