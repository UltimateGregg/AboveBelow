# ModelDoc Agent Builder

## Purpose

Design and validate the first real ModelDoc automation agent before MCP tools, scripts, or editor workflows are added.

Use this agent when the next task is to create a ModelDoc-focused agent, MCP tool set, or validation workflow for `.vmdl` model documents.

## Primary Areas

- `Libraries/jtc.mcp-server/Editor/Mcp/Tools/`
- `Libraries/jtc.mcp-server/Editor/Handlers/`
- `scripts/agents/`
- `.agents/sbox/`
- `docs/agent_toolkit.md`
- `docs/asset_pipeline.md`
- `Assets/models/**/*.vmdl`
- `scripts/*_asset_pipeline.json`

## Build Rules

- Start from the repo's existing MCP server and agent-card patterns.
- Treat ModelDoc automation as editor tooling, not gameplay logic.
- Do not drive the ModelDoc UI by brittle clicks for the first version.
- Prefer file-backed `.vmdl` inspection, generation, repair, and validation that can be checked in source control.
- Keep Blender mesh authoring, asset export, prefab wiring, and ModelDoc validation as separate phases.
- Reuse `asset_pipeline.py` for generated VMDL shape where possible.
- Do not manually edit generated `.fbx` files.
- Do not rename public models, prefabs, components, or asset paths unless the user explicitly asks.

## Design Checklist

- Define the first user-facing goal in one sentence.
- Decide whether the first slice is read-only audit, safe repair, MCP exposure, or a full agent workflow.
- Identify exact owned files before editing.
- Add a dedicated `.agents/sbox/modeldoc-agent.md` only after this builder has a concrete scope.
- Add a static audit script before adding broad repair behavior.
- Wire new recurring checks into `scripts/agents/run_agent_checks.ps1` only when the script is stable.
- Add a self-test entry if the new tool becomes part of the required automation layer.
- Document exact evidence commands in `.agents/sbox/README.md`.

## Minimum First Slice

The first shippable ModelDoc automation agent should provide:

- A route in `.agents/sbox/README.md`.
- A dedicated `.agents/sbox/modeldoc-agent.md` card.
- A script that reads `.vmdl` files and reports missing source files, missing material targets, invalid model paths, and material remap drift.
- A narrow suite or command for repeatable validation.
- A short doc entry explaining when to use the ModelDoc lane instead of Blender, prefab wiring, or scene editing.

## Evidence Commands

Use these before handing off a ModelDoc-agent implementation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

If a new ModelDoc audit script exists, run it directly and through the suite that owns it:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
```

## Output Shape

Report:

1. Intended ModelDoc agent scope.
2. Files the implementation agent should own.
3. MCP tools, scripts, docs, and agent cards to create or modify.
4. Validation commands and expected results.
5. What stays out of scope for the first version.

## Stop Conditions

Stop and ask for user approval before implementation if the design would:

- Add live UI-click automation.
- Change generated model or prefab asset names.
- Rewrite the existing asset pipeline.
- Combine ModelDoc tooling with gameplay, networking, UI, or map-scene edits.
