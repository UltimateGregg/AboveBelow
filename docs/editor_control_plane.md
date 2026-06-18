# S&Box Editor Control Plane

This project uses the in-editor MCP server as the primary AI control plane for
editor-native work. The endpoint is registered in `.mcp.json` as `sbox` and
listens at:

```text
http://localhost:29015/mcp
```

Keep the S&Box MCP Server dock running in the editor. Prefer this native MCP
server for scene, component, asset, docs, screenshot, play/stop, and sound work.
Use the older CoworkBridge on `127.0.0.1:38080` only as a fallback when a needed
operation is not exposed through the native MCP tools. CoworkBridge starts
automatically from the editor frame pump after the project editor assembly loads;
the `Editor > Cowork` menu remains available for manual stop/start fallback.

If a newly built tool is missing from `tools/list`, restart or fully reload the
S&Box editor MCP server. New tool classes can compile successfully while the
running editor process still serves its previously loaded assembly.

## Editor-First Command Workflow

For any command that touches scene objects, prefabs, components, assets, sounds,
screenshots, play mode, terrain, or editor tooling, start in the live editor
before editing saved JSON directly.

1. Check `control_plane_status`.
2. If client-side MCP tools are not exposed, send JSON-RPC `tools/list` to
   `http://localhost:29015/mcp` and use the returned tool names.
3. Use `control_plane_capabilities` to choose the narrowest editor tool domain.
4. Inspect active state with `editor_scene_info`, `scene_get_hierarchy`,
   `scene_find_objects`, `scene_list_objects`, `component_list`, and
   `component_get` before mutation.
5. Prefer native mutations such as `scene_create_object`, `component_set`,
   `asset_*`, and `sound_*` over hand-editing scene or prefab JSON.
6. Save live scene work with `editor_save_scene`, then verify both live editor
   state and saved files.
7. Use `editor_take_screenshot`, `editor_play`, `editor_stop`,
   `editor_is_playing`, and `editor_console_output` when runtime or visual proof
   matters.

Use CoworkBridge only as a fallback after the native MCP tools are checked. If
the editor, MCP dock, or required tool domain is unavailable, report that as an
environment blocker and state which parts were completed statically.

## Core Tool Domains

- `control_plane_*`: server, scene, tool-domain, and workflow status.
- `scene_*`: active scene and prefab hierarchy inspection/mutation.
- `component_*`: component listing, adding, removal, and typed property setting.
- `asset_*`: project and cloud asset search/browse/mount.
- `editor_*`: selection, save, screenshot, play/stop, console output.
- `sbox_*`: local S&Box docs and API search.
- `sound_*`: SoundEvent inventory, inspection, preview, point placement, and hook discovery.

## Sound Workflow

1. Run the static sound suite:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sound -ShowInfo
```

2. Inspect live editor readiness:

```json
{ "name": "control_plane_status", "arguments": {} }
```

3. List or inspect SoundEvents:

```json
{ "name": "sound_list", "arguments": {} }
{ "name": "sound_inspect", "arguments": { "sound": "sounds/drone_hum.sound" } }
{ "name": "sound_inspect", "arguments": { "sound": "sounds/assault_rifle_fire.sound" } }
```

4. Find editable SoundEvent hooks in the active scene:

```json
{ "name": "sound_find_hooks", "arguments": {} }
```

5. Preview before wiring or placing:

```json
{ "name": "sound_preview", "arguments": { "sound": "sounds/drone_hum.sound", "position": "0,0,200", "volume": 0.5 } }
{ "name": "sound_preview", "arguments": { "sound": "sounds/round_start_swell.sound", "volume": 0.5 } }
```

6. Wire a component property through `component_set` or place an editor-visible
   `SoundPointComponent` through `sound_place_point`.

## Guardrails

- Treat `.sound` files as the gameplay-facing assets. Raw audio files are source
  data and should be referenced by `.sound` wrappers.
- Search stock/editor audio for common weapons, movement, UI, wind, and
  explosions before generating new WAV files, but do not commit direct mounted
  package paths in gameplay code, prefabs, or scenes. Import or copy usable stock
  source audio into `Assets/sounds/`, wrap it in a local `.sound`, and reference
  `sounds/*.sound`.
- When stock audio is unavailable or a project-specific cue is still needed, run
  `python scripts/audio/generate_project_sounds.py --root .` instead of adding
  one-off noise bursts by hand. The generator imports known stock WAVs first and
  uses deterministic synthesis only as a fallback.
- For scene ambience, keep wind and bird emitters on clean local WAV-backed
  SoundEvents. The sound suite includes `ambient_noise_audit.ps1` to catch broad
  noise-bed emitters and stock MP3 ambience before playtest.
- Use `component_list` and `component_get` before mutating component properties.
- Verify successful scene/prefab opens with `editor_scene_info`; top-level tool
  success is not enough when editor state can be stale.
- After MCP source changes, build the editor project:

```powershell
dotnet build Libraries\jtc.mcp-server\Editor\mcp-server.editor.csproj --no-restore
```

- After live editor changes, run the relevant agent suite and check fresh editor
  logs before claiming runtime/editor health.
