# Blender Quality Agent

## Purpose

Audit Blender source files for production asset readiness before export into S&Box.

## Primary Areas

- `*.blend`
- `scripts/blender_asset_audit.py`
- `scripts/asset_quality_profiles.json`
- `scripts/agents/blender_quality_audit.ps1`
- `Assets/models/`
- `Assets/prefabs/`

## Review Rules

- Blender quality checks do not edit `.blend` files.
- Treat missing `.blend` inputs, missing Blender executable, zero mesh count, and zero-vertex meshes as blocking errors.
- Treat unapplied scale or rotation as warnings until the artist confirms it is intentional.
- Meshes with material slots should have UV layers.
- Multi-mesh assets should have a clear root empty when they are not a single joined mesh.
- When working in the visible Blender window, keep the handoff scene readable. Large forests of parent relationship lines should be avoided by combining source meshes for export or by organizing/hiding helper relationships before asking for visual approval.
- Category-specific assets should include required naming hints from `scripts/asset_quality_profiles.json`.
- Flag dimensions below `0.01` or above `10000` on any axis for scale review.
- Keep visual asset validation separate from prefab wiring, gameplay, UI, and networking checks.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Category weapon
```

Useful options:

- `-BlenderExe "C:\Path\To\blender.exe"` overrides the default Blender executable.
- `-TimeoutSeconds 120` controls the per-file Blender inspection timeout.
- `-ShowInfo` includes the inspection JSON summary.
- `-FailOnWarning` treats warning findings as a failing wrapper result.

## Output Shape

Report `[Error]`, `[Warning]`, and `[Info]` lines. Blocking errors should appear first in reviews when present, followed by warnings about transforms, UVs, roots, naming hints, or dimensions. Include the inspected JSON summary when `-ShowInfo` is used.
