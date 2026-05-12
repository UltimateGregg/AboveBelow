# Blender MCP

This project has a local MCP wrapper that lets an AI client run Python inside
Blender through the Blender MCP socket bridge.

The existing `.mcp.json` `blender` entry is intentionally left as the SSE
server at `http://localhost:9876` so existing Claude connections keep working.
The optional stdio wrapper is registered as `blender_stdio`.

## Pieces

- `mcp/dist/blender.js` is the optional stdio MCP server used by clients that
  need stdio instead of SSE.
- `mcp-1.0.0/` is the Blender-side socket bridge package.
- `scripts/start_blender_mcp.py` starts the bridge inside an already-open
  Blender window.
- `scripts/start_blender_mcp_background.ps1` starts Blender in background mode
  and keeps the bridge alive.

The default bridge address is `127.0.0.1:9876`.

## Use With An Open Blender Window

1. In Blender, open the Scripting workspace.
2. Open `C:\Programming\S&Box\scripts\start_blender_mcp.py`.
3. Click Run Script.
4. Restart or reload only the MCP client that should use `blender_stdio`.
5. Call `blender_ping` first from that client to confirm the bridge is reachable.

This lets tools operate on the visible Blender session.
If the bridge is already listening on `127.0.0.1:9876`, the startup script
leaves it alone.

## Use In Background Mode

Run this from the project root:

```powershell
.\scripts\start_blender_mcp_background.ps1
```

To open a specific file:

```powershell
.\scripts\start_blender_mcp_background.ps1 -BlendFile "C:\Programming\S&Box\drone_model.blend\drone_fpv.blend"
```

The background bridge blocks that terminal until stopped.

## Available MCP Tools

- `blender_bridge_config` shows host, port, and startup scripts.
- `blender_ping` checks that Blender is reachable.
- `blender_scene_summary` returns scene objects, transforms, parents, and
  materials.
- `blender_exec_python` runs arbitrary Blender Python and returns the `result`
  dictionary.
- `blender_open_file` opens a `.blend` file.
- `blender_save_file` saves the current file or saves as a new path.
- `blender_export_fbx` exports the scene or selection to FBX.

## Notes

- The open Blender session must keep running while tools are used.
- Long Python scripts run on Blender's main thread and can freeze the UI until
  they finish.
- If Blender's official MCP add-on is installed and already listening on
  `127.0.0.1:9876`, the Node MCP wrapper can use that bridge too.
