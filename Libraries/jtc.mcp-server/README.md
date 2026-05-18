# MCP Server for s&box

In-editor MCP server for s&box. It lets an MCP client drive the editor through
HTTP on `localhost:29015`: scene graph, components, assets, docs, execution,
screenshots, play/stop, sound, and control-plane status.

## What it can do (57 tools)

**Scene graph (12)** - `scene_list_objects`, `scene_get_object`,
`scene_create_object`, `scene_delete_object`, `scene_clone_object`,
`scene_reparent_object`, `scene_set_transform`, `scene_get_hierarchy`,
`scene_load`, `scene_find_objects`, `scene_find_by_component`,
`scene_find_by_tag`

**Components (5)** - `component_list`, `component_get`, `component_set`,
`component_add`, `component_remove`

**Tags (3)** - `tag_add`, `tag_remove`, `tag_list`

**Cloud assets (4)** - `asset_search`, `asset_fetch`, `asset_mount`,
`asset_browse_local`

**Editor (11)** - `editor_get_selection`, `editor_select_object`,
`editor_undo`, `editor_redo`, `editor_save_scene`, `editor_take_screenshot`,
`editor_play`, `editor_stop`, `editor_is_playing`, `editor_scene_info`,
`editor_console_output`

**Files and execution (7)** - `file_read`, `file_write`, `file_list`,
`project_info`, `console_run`, `execute_csharp`, `get_server_status`

**Docs and API search (6)** - `sbox_search_docs`, `sbox_get_doc_page`,
`sbox_list_doc_categories`, `sbox_search_api`, `sbox_get_api_type`,
`sbox_cache_status`

**Sound (6)** - `sound_list`, `sound_inspect`, `sound_create_event`,
`sound_preview`, `sound_place_point`, `sound_find_hooks`

**Control plane (2)** - `control_plane_status`, `control_plane_capabilities`

## Features under the hood

- HTTP transport on `localhost:29015`.
- Reflection-based tool discovery via `[McpToolGroup]` and `[McpTool]`.
- Main-thread dispatch for editor APIs.
- Dirty tracking through undo snapshots, edit markers, and reflection setters.
- Process singleton that survives hot reloads.
- Dock UI with live status, request counter, uptime, and activity log.
- Built-in docs/API crawler and graceful degradation for optional systems.

## Setup

1. Open the project in s&box.
2. Open or keep running the MCP Server dock.
3. Register/use `http://localhost:29015/mcp` as the `sbox` MCP endpoint.
4. The MCP client can use all 57 tools while the editor is open.

When new MCP tool classes are added, restart or fully reload the S&Box editor MCP
server before expecting them in `tools/list`. A running editor process can keep
serving the previous loaded assembly even after the project builds cleanly.

## Architecture

```text
MCP client -> HTTP :29015 -> s&box editor
                           -> McpHttpServer
                           -> ToolRegistry
                           -> HandlerDispatcher
                           -> Handlers
                           -> DocsService
```

One process. 57 tools. Direct editor API access.
