# Sound Control Plane Agent

## Purpose

Use the native S&Box editor MCP server to inspect, preview, place, and wire SoundEvent assets. Pair editor-native sound actions with the repo-side sound audit so raw audio, `.sound` wrappers, prefabs, scenes, and C# references stay aligned.

## Primary Areas

- `Assets/sounds/`
- `Code/**`
- `Assets/prefabs/`
- `Assets/scenes/`
- `Libraries/jtc.mcp-server/Editor/Handlers/SoundHandler.cs`
- `Libraries/jtc.mcp-server/Editor/Mcp/Tools/SoundTools.cs`
- `scripts/agents/sound_asset_audit.ps1`

## Review Rules

- Gameplay and prefab code should reference `.sound` wrappers, not raw `.wav` files.
- Every local `.sound` wrapper should point at existing source audio under `Assets/sounds/`.
- Runtime held-item sounds should route through `SoundPlayback.PlayAttached` when they should follow the weapon, player, or drone.
- Search mounted stock/editor audio for generic cues first: stock weapons,
  reloads, hitmarkers, movement, wind, drone hum, and explosions should beat
  locally generated fallback audio when a usable source recording is available.
- Do not commit direct mounted SoundEvent paths into gameplay code, prefabs, or
  scenes. Import or copy usable source audio into `Assets/sounds/`, wrap it in a
  local `.sound`, and reference `sounds/*.sound`.
- Use `scripts/audio/generate_project_sounds.py` to import known stock WAVs and
  generate only project-specific fallback cues such as bullet whip, impacts,
  jammer loop, or close-mic layers.
- Use `sound_find_hooks` before wiring broad prefab or scene audio changes.
- Use `sound_preview` for auditioning and `sound_place_point` for editor-visible emitters.
- Use `component_set` for `SoundEvent` properties after confirming the component and property name.
- Keep gameplay changes separate from sound wiring unless the user explicitly asks for runtime behavior changes.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sound -ShowInfo
python scripts/audio/generate_project_sounds.py --root .
```

Live editor MCP checks:

```json
{ "name": "control_plane_status", "arguments": {} }
{ "name": "sound_list", "arguments": {} }
{ "name": "sound_preview", "arguments": { "sound": "sounds/assault_rifle_fire.sound", "volume": 0.5 } }
{ "name": "sound_find_hooks", "arguments": {} }
```

## Output Shape

Report the sound assets inspected, playback-owner paths checked, editor MCP tools used, any missing wrapper/source defects, and whether the result was only statically audited or also previewed in the live editor.
