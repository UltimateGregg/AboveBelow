#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { BlenderBridgeError, blenderBridgeAddress, blenderExecute } from "./blenderClient.js";

type Content = { type: "text"; text: string };
type SuccessResult = {
  content: Content[];
  structuredContent: Record<string, unknown>;
};
type ErrorResult = {
  content: Content[];
  isError: true;
};
type ToolResult = SuccessResult | ErrorResult;

function ok(data: unknown): SuccessResult {
  const structured: Record<string, unknown> =
    data !== null && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : { result: data };
  return {
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    structuredContent: structured,
  };
}

function err(message: string): ErrorResult {
  return {
    content: [{ type: "text", text: `Error: ${message}` }],
    isError: true,
  };
}

async function safe<T>(fn: () => Promise<T>): Promise<ToolResult> {
  try {
    return ok(await fn());
  } catch (e) {
    if (e instanceof BlenderBridgeError) return err(e.message);
    return err(`Unexpected error: ${e instanceof Error ? e.message : String(e)}`);
  }
}

function pyString(value: string): string {
  return JSON.stringify(value);
}

function pyBool(value: boolean): string {
  return value ? "True" : "False";
}

function registerTools(server: McpServer): void {
  server.registerTool(
    "blender_bridge_config",
    {
      title: "Blender bridge config",
      description:
        "Show the local host/port this MCP server uses and the project scripts that start the Blender-side bridge.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () =>
      ok({
        ...blenderBridgeAddress(),
        interactive_start_script: "scripts/start_blender_mcp.py",
        background_start_script: "scripts/start_blender_mcp_background.ps1",
      }),
  );

  server.registerTool(
    "blender_ping",
    {
      title: "Ping Blender",
      description:
        "Verify the Blender-side bridge is reachable. Returns Blender version, open file, active scene, and selection summary.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
result = {
    "ok": True,
    "blender_version": bpy.app.version_string,
    "file": bpy.data.filepath,
    "scene": bpy.context.scene.name if bpy.context.scene else None,
    "object_count": len(bpy.data.objects),
    "active_object": bpy.context.object.name if bpy.context.object else None,
    "selected_objects": [obj.name for obj in bpy.context.selected_objects],
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_scene_summary",
    {
      title: "Summarize Blender scene",
      description:
        "Read the current Blender scene hierarchy. Use before editing so changes can be targeted by object name.",
      inputSchema: z
        .object({
          object_limit: z.number().int().min(1).max(1000).default(200).describe("Maximum objects to include."),
          selected_only: z.boolean().default(false).describe("Only include selected objects."),
          include_materials: z.boolean().default(true).describe("Include material slot names for each object."),
        })
        .strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
object_limit = ${params.object_limit}
selected_only = ${pyBool(params.selected_only)}
include_materials = ${pyBool(params.include_materials)}
source = list(bpy.context.selected_objects) if selected_only else list(bpy.context.scene.objects)
objects = []
for obj in source[:object_limit]:
    item = {
        "name": obj.name,
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "children": [child.name for child in obj.children],
        "location": [round(v, 5) for v in obj.location],
        "rotation_euler": [round(v, 5) for v in obj.rotation_euler],
        "scale": [round(v, 5) for v in obj.scale],
        "dimensions": [round(v, 5) for v in obj.dimensions],
        "visible": obj.visible_get(),
    }
    if include_materials:
        item["materials"] = [
            slot.material.name if slot.material else None
            for slot in obj.material_slots
        ]
    objects.append(item)
result = {
    "scene": bpy.context.scene.name if bpy.context.scene else None,
    "file": bpy.data.filepath,
    "object_count_total": len(source),
    "object_count_returned": len(objects),
    "truncated": len(source) > object_limit,
    "active_object": bpy.context.object.name if bpy.context.object else None,
    "objects": objects,
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_exec_python",
    {
      title: "Run Python in Blender",
      description:
        "Execute Python inside Blender on the main thread. The code should assign a dictionary to `result`. Use this for targeted scene edits, object creation, import/export, and inspection.",
      inputSchema: z
        .object({
          code: z
            .string()
            .min(1)
            .describe("Python code to execute in Blender. Assign return data to a `result` dict."),
          strict_json: z
            .boolean()
            .default(false)
            .describe("Require `result` to be JSON-serializable. Leave false for exploratory scripts."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(params.code, { strictJson: params.strict_json });
        return response;
      }),
  );

  server.registerTool(
    "blender_open_file",
    {
      title: "Open Blender file",
      description:
        "Open a .blend file in the connected Blender session. This replaces the current open file in that Blender process.",
      inputSchema: z
        .object({
          path: z.string().min(1).describe("Absolute path to the .blend file to open."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
path = ${pyString(params.path)}
bpy.ops.wm.open_mainfile(filepath=path)
result = {
    "opened": bpy.data.filepath,
    "scene": bpy.context.scene.name if bpy.context.scene else None,
    "object_count": len(bpy.data.objects),
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_save_file",
    {
      title: "Save Blender file",
      description:
        "Save the connected Blender session. Provide a path to Save As, or omit it to save the current file.",
      inputSchema: z
        .object({
          path: z.string().min(1).optional().describe("Optional absolute path for Save As."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const saveAs = params.path ? `bpy.ops.wm.save_as_mainfile(filepath=${pyString(params.path)})` : "bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)";
        const response = await blenderExecute(
          `
import bpy
if not bpy.data.filepath and ${params.path ? "False" : "True"}:
    raise RuntimeError("Current Blender file has no path; pass a path to save as.")
${saveAs}
result = {
    "saved": bpy.data.filepath,
    "scene": bpy.context.scene.name if bpy.context.scene else None,
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_export_fbx",
    {
      title: "Export FBX",
      description:
        "Export the current Blender scene, or just the selected objects, to an FBX file for the S&Box asset pipeline.",
      inputSchema: z
        .object({
          path: z.string().min(1).describe("Absolute output path for the .fbx file."),
          selected_only: z.boolean().default(false).describe("Export only selected objects."),
          apply_unit_scale: z.boolean().default(true).describe("Apply unit scale during export."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
path = ${pyString(params.path)}
bpy.ops.export_scene.fbx(
    filepath=path,
    use_selection=${pyBool(params.selected_only)},
    apply_unit_scale=${pyBool(params.apply_unit_scale)},
)
result = {
    "exported": path,
    "selected_only": ${pyBool(params.selected_only)},
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );
}

const server = new McpServer({
  name: "blender-mcp-server",
  version: "0.1.0",
});

registerTools(server);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  const { host, port } = blenderBridgeAddress();
  console.error(`blender-mcp-server connected (stdio). Bridge socket: ${host}:${port}`);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
