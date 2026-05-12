# sbox-mcp-server

MCP server for the s&box editor. Exposes scene introspection, GameObject queries, and the painful reference-wiring step as tools that any MCP client can call.

## Architecture

```
[MCP client] <--stdio JSON-RPC--> [sbox-mcp-server (Node)] <--HTTP--> [CoworkBridge (in s&box editor)]
                                                                              |
                                                                              v
                                                               SceneEditorSession.Active.Scene
```

Two pieces, both required:

- **CoworkBridge** (C#, lives in this project's `Editor/` folder) - HTTP listener inside the s&box editor on `localhost:38080`. Dispatches incoming requests onto the editor thread via `[EditorEvent.Frame]` so `SceneEditorSession.Active` is safe to access.
- **sbox-mcp-server** (TypeScript, this folder) - Node process speaking MCP over stdio. Tool calls become HTTP POSTs to the bridge.

## Install and run

### 1. The editor side (CoworkBridge)

It's already in the project. Open the s&box editor, load this project, then in the menu bar:

`Editor > Cowork > Start MCP Bridge`

You should see in the console:

```
[CoworkBridge] Listening on http://localhost:38080/
```

If you get an `HttpListenerException` on first run, Windows requires URL reservation. From an elevated cmd:

```
netsh http add urlacl url=http://localhost:38080/ user=Everyone
```

Then try Start again. `Editor > Cowork > Stop MCP Bridge` shuts it down.

The bridge auto-restarts on hotload, so editing C# code while it's running won't kill it.

### 2. The MCP server side

From the `mcp/` folder:

```bash
npm install
npm run build
```

Smoke test (with the editor running and the bridge started):

```bash
SBOX_BRIDGE_URL=http://localhost:38080 node dist/index.js
```

Then in another terminal pipe an MCP `initialize` + `tools/list` request, or just wire it into your MCP client.

### 3. Wire it into your MCP client

For Claude Desktop, add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sbox": {
      "command": "node",
      "args": ["/absolute/path/to/dronevsplayers/mcp/dist/index.js"]
    }
  }
}
```

For Cowork or other stdio MCP hosts, point them at the same `node dist/index.js` command.

## Tools

| Tool | Purpose |
|---|---|
| `sbox_ping` | Liveness check. First call to make if anything seems off. |
| `sbox_scene_open` | Open a local `.scene` or `.prefab` asset in the editor. |
| `sbox_scene_info` | Active scene name, GUID, root count. |
| `sbox_scene_tree` | Full hierarchy tree (GUIDs, names, component types). |
| `sbox_gameobject_get` | Inspect one GameObject including all `[Property]`-marked component fields. |
| `sbox_gameobject_select` | Select a GameObject in the editor (replaces selection). |
| `sbox_scene_save` | Save the active scene. |
| `sbox_component_set_property` | Set a primitive value (string/number/bool/Vector3/enum). |
| `sbox_component_wire_reference` | The big one: wire a GameObject or component reference on a `[Property]`. |
| `sbox_console_log` | Log a message into the editor console. |

## Typical workflow

Wire the GameManager's prefab references in main.scene:

1. `sbox_scene_open` with path=`Assets/scenes/main.scene`
2. `sbox_scene_tree` -> find `GameManager` and the prefab assets in the asset browser context
3. `sbox_gameobject_get` with name=`GameManager` -> get its `GameSetup` component GUID and the property names
4. `sbox_component_wire_reference` once per slot (`SoldierPrefab`, `DronePrefab`, `Round`)
5. `sbox_scene_save`

## Known limits

- Bridge runs in the editor only. When the editor is closed, every tool fails with a clear "cannot reach bridge" message.
- Asset references (prefabs as `GameObject`-typed properties) wire by GUID; the prefab GUID isn't in the scene tree yet. If you need to wire a prefab from the asset browser, you'll have to extend the bridge with a `/asset/list` endpoint that returns prefab GUIDs by path.
- No auth. Do not enable on a shared machine.
- `sbox_scene_open` opens local project `.scene` and `.prefab` assets before the bridge acts on them.

## Extending the bridge

Each tool is a single endpoint defined in two places:

1. C# handler in `Editor/CoworkBridgeHandlers.cs`
2. Route registered in `Editor/CoworkBridge.cs` (`HandleOnEditorThread` switch)
3. TypeScript tool in `mcp/src/tools.ts`

Pattern: handler returns a plain object, the bridge serializes it. Add new endpoints in lockstep on both sides and rebuild the MCP server.
