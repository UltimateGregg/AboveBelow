# AAA Asset Quality Agent

## Purpose

Route high-polish Blender asset work through concrete reference, modeling, material, preview, and S&Box import proof instead of treating "AAA quality" as a vague art request.

## Primary Areas

- `scripts/asset_quality_profiles.json`
- `docs/assets/briefs/`
- `*.blend`
- `Assets/models/`
- `Assets/materials/`
- `Assets/prefabs/`
- `screenshots/asset_previews/`

## Review Rules

- Start new high-polish assets from an asset brief that lists reference requirements, production quality targets, material roles, sockets, scale, and visual review checks.
- Do not accept a Blender preview as the final result. The path is: brief -> Blender source quality -> material/texture audit -> export/import -> ModelDoc/FBX slot validation -> prefab/editor visual proof.
- Use `.agents/sbox/blender-quality-agent.md` for object, transform, UV, root, naming, and scale checks.
- Use `.agents/sbox/material-texture-agent.md` for image-backed materials, baked procedural looks, default-texture avoidance, alpha masks, and optional normal/roughness/AO maps.
- Use `.agents/sbox/visual-review-agent.md` for rendered previews and contact sheets. For foliage, decals, glass, emissive, or alpha cards, require contact-sheet or editor screenshot evidence.
- Use `.agents/sbox/asset-pipeline-agent.md` and `.agents/sbox/modeldoc-agent.md` for config, FBX, VMDL, material slot, and prefab graph validation.
- Keep gameplay, UI, prefab restructuring, and networking changes in separate phases unless the user explicitly asks for a combined pass.
- Prefer Facepunch stock assets as reference or reusable source where appropriate, but do not copy compiled-only assets as if they were editable source.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category environment
powershell -ExecutionPolicy Bypass -File scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production -ShowInfo
```

For visual proof:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend environment_model.blend/my_asset.blend -ShowInfo
python scripts/texture_contact_sheet.py --config scripts/my_asset_asset_pipeline.json --out screenshots/asset_previews/my_asset_texture_sheet.png
```

## Output Shape

Lead with missing proof or quality blockers. Then list the loaded agent cards, reference gaps, material/texture gaps, Blender source issues, import validation status, generated preview paths, and remaining manual editor checks.
