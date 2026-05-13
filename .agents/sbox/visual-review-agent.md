# Visual Review Agent

## Purpose

Render local preview images for Blender source assets so reviewers can inspect asset shape, framing, materials, and silhouette before S&Box import work continues.

## Primary Areas

- `*.blend`
- `scripts/render_asset_preview.py`
- `scripts/agents/asset_visual_review.ps1`
- `screenshots/asset_previews/`

## Review Rules

- Visual review renders do not edit or save `.blend` files.
- Preview images and JSON sidecars are local review artifacts.
- Preview artifacts are ignored through `screenshots/`.
- Keep visual asset validation separate from prefab wiring, gameplay, UI, and networking checks.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend
```

Useful options:

- `-OutDir screenshots/asset_previews` controls where previews are written.
- `-BlenderExe "C:\Path\To\blender.exe"` overrides the default Blender executable.
- `-TimeoutSeconds 180` controls the per-file render timeout.
- `-ShowInfo` includes renderer metadata from the JSON sidecar.
- `-FailOnWarning` treats warning findings as a failing wrapper result.

## Output Shape

Report `[Error]`, `[Warning]`, and `[Info]` lines using agent conventions. Print each generated preview path, such as `screenshots/asset_previews/weapons_model_blend_assault_rifle_m4_preview.png`, so reviewers can open the local artifact directly.
