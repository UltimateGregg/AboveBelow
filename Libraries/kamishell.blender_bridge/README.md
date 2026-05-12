# Blender Bridge for s&box

Real-time bidirectional scene sync between **Blender** and the **s&box editor**.

## Features

- **Mesh streaming** — Geometry with per-face PBR materials syncs in real time
- **Bidirectional transforms** — Move objects in either editor, changes appear in both
- **Light sync** — Point, Spot, and Directional lights sync between Blender and s&box
- **Material pipeline** — Principled BSDF materials auto-generate `.vmat` files with textures
- **Chunked transfer** — Large meshes (20k+ vertices) stream without freezing the UI
- **Auto-reconnect** — Connection recovers automatically with full state reconciliation
- **Play mode persistence** — Bridge geometry survives Play/Stop via binary mesh cache
- **Hierarchy grouping** — Bridge objects organized under a "Blender Bridge" group in s&box

## Requirements

- **s&box** (latest version)
- **Blender 5.1+** with the companion Blender addon installed

## Setup

### 1. Install the s&box Library

Add `kamishell.blender_bridge` to your project's package references, or copy this library into your project's `Libraries/` folder.

### 2. Install the Blender Addon

Download the Blender addon from the releases page:

**https://github.com/SanicTehHedgehog/blender-sbox-bridge/releases**

Install in Blender:
1. Edit > Preferences > Add-ons > Install from Disk
2. Select the downloaded `sbox_bridge.zip`
3. Enable "s&box Bridge" in the addon list

### 3. Connect

1. Open s&box — the bridge server starts automatically on port `8099`
2. In Blender, open the N-panel (press N) > **s&box** tab
3. Click **Connect**

## Usage

### Auto Sync (default)
With Auto Sync enabled, any mesh or light you create/edit in Blender appears in s&box automatically. Moving objects in s&box updates Blender too.

### Manual Send
Select objects in Blender and click **Send to Scene** to push specific objects.

### Sync All / Force Resync
- **Sync All** — Sends all unsynced objects and requests full state from s&box
- **Force Resync** — Strips all bridge IDs and re-creates everything from scratch

### Materials
Set your **Assets Path** in the Blender panel to your s&box project's `Assets/` folder. Materials with Principled BSDF nodes auto-generate `.vmat` files with copied textures.

### Grid Alignment
Use the grid size buttons (2, 4, 8, 16, 32) to match Blender's grid to s&box units.

## How It Works

The bridge uses HTTP polling on `localhost:8099`:
- Blender sends changes via `POST /message`
- Blender polls for s&box changes via `GET /poll`
- Sequence-based echo prevention eliminates sync loops
- Session IDs enable automatic reconnection without Force Resync

## Supported Object Types

| Blender | s&box | Notes |
|---------|-------|-------|
| Mesh | MeshComponent / MapMesh | Full geometry + materials |
| Point Light | PointLight | Color, radius |
| Spot Light | SpotLight | Color, radius, cone angles |
| Sun Light | DirectionalLight | Color |
| Area Light | — | Not supported (warning shown) |
| Curve/Surface | Mesh (converted) | Auto-converted to mesh on sync |

## Troubleshooting

- **Objects don't appear**: Check that the bridge server is running (Editor > Blender Bridge > Open Panel)
- **Materials show error texture**: New `.vmat` files need a moment to compile — edit the mesh or resync
- **Connection lost**: The addon auto-reconnects. If it fails after 5 attempts, click Connect again
- **Play mode loses geometry**: Geometry is restored from cache on Play stop. If missing, click Sync All

## License

MIT
