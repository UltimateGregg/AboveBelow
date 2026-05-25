# Editor-Native Cover Agent

## Purpose

Guide small cover, barricade, roadblock, and blockout-prop work made directly in the S&Box editor without Blender-authored meshes.

Use this agent when the user asks for cover made from editor primitives, a scene-only prop, or a quick tactical layout object that should stay editable in `Assets/scenes/main.scene`.

## Primary Areas

- `Assets/scenes/main.scene`
- `Assets/materials/`
- `scripts/agents/sandbag_cover_audit.ps1`
- `scripts/agents/burnt_vehicle_block_audit.ps1`
- Native S&Box MCP at `http://localhost:29015/mcp`

## Review Rules

- Inspect the live editor scene before changing the saved JSON. Active editor state can contain user edits that are not saved yet.
- Preserve user-deleted pieces. Do not recreate missing seam strips, detail markers, or removed primitive children unless the user explicitly asks for them back.
- Prefer native editor primitives and `ModelRenderer.MaterialOverride` for single-material blockout props.
- Avoid Blender unless the request changes into a bespoke mesh, UV layout, rig, or high-polish exported asset.
- Keep cover pieces close enough that player-facing gaps are not visible. Use row-spacing checks for repeated pieces instead of relying on a screenshot only.
- Add or reuse a local material/texture set when repeated primitive shapes need to read as a specific object.
- MCP `scene_create_object` positions are world-space even when a parent is provided; for grouped assets, pass parent world position plus intended local offset, then verify saved JSON stores local child offsets.
- Save through MCP after live edits, then verify both saved scene JSON and live editor state.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sandbag_cover_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/burnt_vehicle_block_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite scene -ShowInfo
```

## Output Shape

Summarize the live editor objects changed, note any missing/deleted pieces that were intentionally preserved, and separate focused cover-audit results from unrelated scene-suite failures.
