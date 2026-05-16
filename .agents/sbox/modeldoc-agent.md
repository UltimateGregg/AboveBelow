# ModelDoc Agent

## Purpose

Inspect and validate S&Box ModelDoc `.vmdl` files before a model change is handed off.

Use this agent when work touches generated or hand-authored model documents, material remaps, source mesh references, or future ModelDoc MCP automation.

## Primary Areas

- `Assets/models/**/*.vmdl`
- `Assets/models/**/*.fbx`
- `Assets/materials/**/*.vmat`
- `scripts/*_asset_pipeline.json`
- `scripts/asset_pipeline.py`
- `scripts/agents/modeldoc_audit.ps1`
- `Libraries/jtc.mcp-server/Editor/Mcp/Tools/`
- `Libraries/jtc.mcp-server/Editor/Handlers/`

## Review Rules

- Treat `.vmdl` as the source-controlled ModelDoc surface.
- Prefer read-only audit before any repair or regeneration.
- Keep mesh authoring in Blender and source mesh export separate from ModelDoc validation.
- Check `RenderMeshFile` source paths against files under `Assets/models/`.
- Check material remap targets against real `.vmat` files.
- Compare VMDL material remaps with the owning `scripts/*_asset_pipeline.json` when one exists.
- Respect `strict_vmdl_material_sources` and `vmdl_material_source_suffix` in asset configs.
- For strict multi-material assets, compare VMDL remap `from` values against actual exported FBX material slots with the FBX material-slot audit.
- For foliage or other multi-material assets that rely on source material slots, require `vmdl_use_global_default: false` in the config and `use_global_default = false` in the generated VMDL.
- Do not manually edit generated `.fbx` files.
- Do not rename model, prefab, component, or asset paths unless explicitly asked.
- Do not add brittle live ModelDoc UI-click automation without user approval.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
```

For broader asset work, also run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

## Output Shape

Report missing source meshes, missing material targets, duplicate remap sources, config-to-VMDL drift, and VMDLs with no owning export config. Separate ModelDoc validation from Blender visual quality and from prefab or scene wiring.
