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

## Visible S&Box Asset Toolkit

Use the S&Box Asset Toolkit add-on when you want the AI workflow to operate in
the Blender window you can see. It adds a `View3D > Sidebar > S&Box` panel with
buttons for live MCP bridge startup, production scene setup, briefs, audits,
preview renders, S&Box export, and asset-production checks.

Install the add-on into the active Blender user scripts folder:

```powershell
.\scripts\install_blender_asset_toolkit.ps1
```

Start a visible Blender window with the add-on enabled and the bridge started:

```powershell
.\scripts\start_visible_blender_asset_toolkit.ps1
```

To open a specific file visibly:

```powershell
.\scripts\start_visible_blender_asset_toolkit.ps1 -BlendFile "C:\Programming\S&Box\weapons_model.blend\assault_rifle_m4.blend"
```

Inside Blender, open the right sidebar with `N`, choose the `S&Box` tab, and use
the `S&Box Asset Toolkit` panel. The `Setup Production Scene` button creates a
root empty, category-specific sockets, material presets, lighting, and a preview
camera in the visible scene. The audit, preview, export, and production-check
buttons call the same repo-side scripts documented in `docs/agent_toolkit.md`.

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
- `blender_sbox_scene_status` reads S&Box roots, sockets, mesh count, material
  names, and current file from the visible scene.
- `blender_sbox_setup_asset_scene` creates a production scaffold in the visible
  Blender scene for `weapon`, `drone`, `character`, or `environment` assets.
- `blender_sbox_add_socket` creates or updates an S&Box socket empty.
- `blender_sbox_create_material` creates or updates a PBR-friendly Blender
  material preset.
- `blender_sbox_render_current_preview` saves the visible `.blend` and runs the
  asset visual review preview renderer.
- `blender_sbox_export_current_asset` saves the visible `.blend` and runs the
  smart Blender to S&Box export pipeline.

After changing `mcp/src/blender.ts`, rebuild the local stdio runtime. Use the
direct TypeScript compiler path on this checkout because the `S&Box` folder name
can confuse `npm run` shell quoting on Windows:

```powershell
node .\mcp\node_modules\typescript\bin\tsc -p .\mcp\tsconfig.json
```

## Notes

- The open Blender session must keep running while tools are used.
- Long Python scripts run on Blender's main thread and can freeze the UI until
  they finish.
- The add-on buttons that run PowerShell also block Blender until the command
  finishes. Reports are written under `.tmpbuild/blender_live_toolkit/`.
- If Blender's official MCP add-on is installed and already listening on
  `127.0.0.1:9876`, the Node MCP wrapper can use that bridge too.
