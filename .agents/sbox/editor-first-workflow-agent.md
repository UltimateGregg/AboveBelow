# Editor-First Workflow Agent

## Purpose

Make future Codex passes use the live S&Box editor as the first authoring surface whenever the requested work can reasonably happen through the native editor MCP server.

Use this agent before scene, prefab, component, asset-browser, sound, screenshot, playtest, terrain, blockout, or editor-tooling tasks. Do not force it onto pure C# refactors or documentation-only work, but still use the editor for final runtime proof when behavior changed.

## Primary Control Plane

- Native S&Box MCP: `http://localhost:29015/mcp`
- MCP manifest: `.mcp.json`
- Control-plane docs: `docs/editor_control_plane.md`
- Capability source: `Libraries/jtc.mcp-server/README.md`
- Workflow audit: `scripts/agents/editor_first_workflow_audit.ps1`

## Startup Checks

1. Confirm the S&Box editor is the intended surface for the task.
2. Check live control-plane status first:

```json
{ "name": "control_plane_status", "arguments": {} }
```

3. If callable MCP tools are not exposed in the active client session, query JSON-RPC directly:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
Invoke-WebRequest -Uri 'http://localhost:29015/mcp' -Method POST -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 5
```

4. Use `control_plane_capabilities` or `tools/list` to choose available tools instead of inventing tool names.
5. If the native editor MCP is unavailable, record it as an environment blocker and use the safest file/script fallback. Do not pretend the work was editor-native.
6. Record `hasUnsavedChanges` from `control_plane_status` / `editor_scene_info`. If the editor was already dirty before your change, treat that state as user-owned: do not call `editor_save_scene`, `scene_open`, reload commands, or any operation likely to raise a save prompt unless the user explicitly approves that path. If the editor is clean and saved-file scene edits were just made by the agent, reload the current scene through `scene_load` / `scene_open` to clear the editor reload prompt, then verify the live scene path and dirty/play state.

## Editor-First Work Rules

- Inspect before mutation: use `editor_scene_info`, `scene_get_hierarchy`, `scene_find_objects`, `scene_list_objects`, `component_list`, and `component_get` as applicable before editing saved scene or prefab JSON.
- Mutate through the editor when possible: prefer `scene_create_object`, `scene_delete_object`, `scene_clone_object`, `component_add`, `component_remove`, `component_set`, `asset_*`, `sound_*`, and editor commands exposed in `tools/list`.
- Save through the editor after live scene or prefab edits with `editor_save_scene` only when you know the editor was not pre-dirty and the live mutations are yours, then verify both live editor state and saved files.
- After agent-owned saved-file scene edits, and only when `hasUnsavedChanges` is false, reload the active scene with `scene_load` or `scene_open` so the user does not have to manually accept the reload prompt.
- When the editor is pre-dirty or save ownership is uncertain, prefer read-only editor inspection plus a saved-file fallback, or stop and ask before using any save/reload flow that could force a manual save prompt.
- Use `editor_take_screenshot`, `editor_play`, `editor_stop`, `editor_is_playing`, and `editor_console_output` for proof when the task affects visuals, controls, audio, physics, or runtime behavior.
- For first-person held-item hand/IK work, tune against live rendered objects in play mode. Spawn or select the relevant pawn, use `scene_find_objects` / `scene_find_by_component` plus `component_get` to inspect the held item, use `component_set` for temporary grip-anchor values, take screenshots from the active camera, then persist only the validated values back to the prefab/template. Prefer visual-relative IK anchors on the held controller, weapon, drone, or prop over independent eye-space offsets so hands stay attached during movement and turning.
- Keep code, UI, prefab, scene, asset, and networking changes in separate phases even when the editor is available.
- Use CoworkBridge only after confirming the native MCP server lacks the needed operation.

## Fallback Rules

- If a property conversion fails through `component_set`, fix or route the converter when that is the real blocker; do not silently patch JSON unless the user needs an immediate unblock.
- If active editor state and saved JSON disagree, treat the live editor as potentially newer until you prove otherwise.
- If the editor is not running or the MCP dock is not listening, say that explicitly in the handoff and list which work was completed statically.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-first -ShowInfo
```

## Output Shape

Report the editor MCP status, the live editor objects/components inspected or changed, the exact native tools used, fallback work if any, saved-file verification, and any runtime/editor proof that remains manual.
