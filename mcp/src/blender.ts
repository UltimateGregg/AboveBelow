#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
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

function pyNumberArray(values: readonly number[]): string {
  return `[${values.map((value) => Number(value).toString()).join(", ")}]`;
}

function projectRoot(): string {
  if (process.env.SBOX_PROJECT_ROOT) return process.env.SBOX_PROJECT_ROOT;
  const moduleDir = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(moduleDir, "..", "..");
}

async function runPowerShellScript(
  scriptRelativePath: string,
  args: string[],
  timeoutMs = 300_000,
): Promise<{ script: string; exitCode: number; stdout: string; stderr: string }> {
  const root = projectRoot();
  const script = path.join(root, scriptRelativePath);
  const commandArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...args];

  return await new Promise((resolve, reject) => {
    const child = spawn("powershell.exe", commandArgs, {
      cwd: root,
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill();
      reject(new Error(`${scriptRelativePath} timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const exitCode = code ?? 1;
      if (exitCode !== 0) {
        reject(new Error(`${scriptRelativePath} failed with exit code ${exitCode}\n${(stderr || stdout).slice(0, 2000)}`));
        return;
      }
      resolve({ script, exitCode, stdout, stderr });
    });
  });
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

  server.registerTool(
    "blender_sbox_scene_status",
    {
      title: "S&Box scene status",
      description:
        "Inspect the visible Blender session for S&Box asset roots, sockets, materials, mesh counts, and current file.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy

def is_socket(obj):
    return obj.type == "EMPTY" and (obj.get("sbox_socket") or obj.name.lower().startswith(("socket_", "muzzle", "grip")))

roots = []
sockets = []
meshes = []
for obj in bpy.context.scene.objects:
    if obj.get("sbox_asset_root"):
        roots.append({
            "name": obj.name,
            "category": obj.get("sbox_asset_category"),
            "children": [child.name for child in obj.children],
        })
    if is_socket(obj):
        sockets.append({
            "name": obj.name,
            "parent": obj.parent.name if obj.parent else None,
            "location": [round(v, 5) for v in obj.location],
            "rotation_degrees": [round(v * 57.29577951308232, 3) for v in obj.rotation_euler],
        })
    if obj.type == "MESH":
        meshes.append(obj.name)

result = {
    "file": bpy.data.filepath,
    "scene": bpy.context.scene.name if bpy.context.scene else None,
    "roots": roots,
    "sockets": sockets,
    "mesh_count": len(meshes),
    "mesh_names": meshes,
    "materials": [mat.name for mat in bpy.data.materials],
    "active_object": bpy.context.object.name if bpy.context.object else None,
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_sbox_setup_asset_scene",
    {
      title: "Setup S&Box asset scene",
      description:
        "Create a visible S&Box production scene scaffold in Blender: root empty, category sockets, material presets, preview light, and camera.",
      inputSchema: z
        .object({
          asset_name: z.string().min(1).describe("Asset name, for example assault_rifle_m4."),
          category: z.enum(["weapon", "drone", "character", "environment"]).default("weapon"),
          clear_scene: z.boolean().default(false).describe("Delete existing scene objects before scaffolding."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
import re

asset_name = ${pyString(params.asset_name)}
category = ${pyString(params.category)}
clear_scene = ${pyBool(params.clear_scene)}

socket_presets = {
    "weapon": [
        ("socket_muzzle", (0.0, 1.2, 0.15), (90.0, 0.0, 0.0)),
        ("socket_grip", (0.0, -0.35, -0.22), (0.0, 0.0, 0.0)),
        ("socket_attachment", (0.0, 0.15, 0.32), (0.0, 0.0, 0.0)),
    ],
    "drone": [
        ("socket_camera", (0.0, -0.45, -0.12), (75.0, 0.0, 0.0)),
        ("socket_muzzle", (0.0, -0.65, -0.08), (90.0, 0.0, 0.0)),
        ("socket_prop_front_left", (-0.55, 0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_front_right", (0.55, 0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_rear_left", (-0.55, -0.55, 0.08), (0.0, 0.0, 0.0)),
        ("socket_prop_rear_right", (0.55, -0.55, 0.08), (0.0, 0.0, 0.0)),
    ],
    "character": [
        ("socket_head", (0.0, 0.0, 1.72), (0.0, 0.0, 0.0)),
        ("socket_weapon_r", (0.34, -0.08, 1.15), (0.0, 0.0, 0.0)),
        ("socket_pack", (0.0, 0.16, 1.25), (0.0, 0.0, 0.0)),
    ],
    "environment": [
        ("socket_origin", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        ("socket_collision_note", (0.0, 0.0, 1.0), (0.0, 0.0, 0.0)),
    ],
}

material_presets = {
    "weapon": [("SBox_Metal", (0.45, 0.46, 0.44, 1.0), 0.85, 0.34), ("SBox_Polymer", (0.045, 0.052, 0.058, 1.0), 0.0, 0.62)],
    "drone": [("SBox_Frame", (0.08, 0.095, 0.11, 1.0), 0.45, 0.42), ("SBox_Motor", (0.18, 0.19, 0.2, 1.0), 0.75, 0.28)],
    "character": [("SBox_Fabric", (0.14, 0.18, 0.15, 1.0), 0.0, 0.72), ("SBox_Gear", (0.09, 0.085, 0.075, 1.0), 0.1, 0.55)],
    "environment": [("SBox_Surface", (0.32, 0.35, 0.31, 1.0), 0.0, 0.68), ("SBox_EdgeWear", (0.66, 0.62, 0.52, 1.0), 0.0, 0.5)],
}

def safe_name(value):
    return re.sub(r"[^A-Za-z0-9_]+", "_", value.strip()).strip("_") or "sbox_asset"

def make_material(name, color, metallic, roughness):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat

def make_empty(name, location, rotation_degrees, parent):
    obj = bpy.data.objects.get(name)
    if obj is None:
        obj = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(obj)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 0.18
    obj.location = location
    obj.rotation_euler = tuple(v * 0.017453292519943295 for v in rotation_degrees)
    obj.parent = parent
    obj["sbox_socket"] = True
    return obj

if clear_scene:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

asset = safe_name(asset_name)
root_name = asset + "_Root"
root = bpy.data.objects.get(root_name)
if root is None:
    root = bpy.data.objects.new(root_name, None)
    bpy.context.scene.collection.objects.link(root)
root.empty_display_type = "PLAIN_AXES"
root.empty_display_size = 0.5
root["sbox_asset_root"] = True
root["sbox_asset_category"] = category

materials = [make_material(*entry).name for entry in material_presets[category]]
sockets = [make_empty(name, location, rotation, root).name for name, location, rotation in socket_presets[category]]

if bpy.data.objects.get("SBox_Key_Area") is None:
    bpy.ops.object.light_add(type="AREA", location=(2.5, -4.0, 4.0))
    light = bpy.context.object
    light.name = "SBox_Key_Area"
    light.data.energy = 450
    light.data.size = 5
if bpy.data.objects.get("SBox_PreviewCamera") is None:
    bpy.ops.object.camera_add(location=(3.0, -5.5, 2.4), rotation=(1.2, 0.0, 0.48))
    camera = bpy.context.object
    camera.name = "SBox_PreviewCamera"
    bpy.context.scene.camera = camera

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
bpy.context.view_layer.objects.active = root

result = {
    "asset_name": asset,
    "category": category,
    "root": root.name,
    "materials": materials,
    "sockets": sockets,
    "object_count": len(bpy.data.objects),
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_sbox_add_socket",
    {
      title: "Add S&Box socket",
      description: "Add or update a visible S&Box socket empty in the current Blender scene.",
      inputSchema: z
        .object({
          name: z.string().min(1).describe("Socket object name, for example socket_muzzle."),
          parent: z.string().optional().describe("Optional parent object name."),
          location: z.tuple([z.number(), z.number(), z.number()]).default([0, 0, 0]),
          rotation_degrees: z.tuple([z.number(), z.number(), z.number()]).default([0, 0, 0]),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
name = ${pyString(params.name)}
parent_name = ${params.parent ? pyString(params.parent) : "None"}
location = ${pyNumberArray(params.location)}
rotation_degrees = ${pyNumberArray(params.rotation_degrees)}
obj = bpy.data.objects.get(name)
if obj is None:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
obj.empty_display_type = "ARROWS"
obj.empty_display_size = 0.18
obj.location = location
obj.rotation_euler = tuple(v * 0.017453292519943295 for v in rotation_degrees)
obj["sbox_socket"] = True
if parent_name:
    parent = bpy.data.objects.get(parent_name)
    if parent is None:
        raise RuntimeError("Parent object not found: " + parent_name)
    obj.parent = parent
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
result = {
    "name": obj.name,
    "parent": obj.parent.name if obj.parent else None,
    "location": [round(v, 5) for v in obj.location],
    "rotation_degrees": [round(v * 57.29577951308232, 3) for v in obj.rotation_euler],
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_sbox_create_material",
    {
      title: "Create S&Box material",
      description: "Create or update a visible Blender material with S&Box production-friendly PBR defaults.",
      inputSchema: z
        .object({
          name: z.string().min(1),
          base_color: z.tuple([z.number(), z.number(), z.number(), z.number()]).default([0.4, 0.4, 0.4, 1]),
          metallic: z.number().min(0).max(1).default(0),
          roughness: z.number().min(0).max(1).default(0.55),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const response = await blenderExecute(
          `
import bpy
name = ${pyString(params.name)}
base_color = ${pyNumberArray(params.base_color)}
metallic = ${params.metallic}
roughness = ${params.roughness}
mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
mat.diffuse_color = base_color
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
if bsdf:
    if "Base Color" in bsdf.inputs:
        bsdf.inputs["Base Color"].default_value = base_color
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = roughness
result = {
    "name": mat.name,
    "base_color": list(mat.diffuse_color),
    "metallic": metallic,
    "roughness": roughness,
}
`,
          { strictJson: true },
        );
        return response.result;
      }),
  );

  server.registerTool(
    "blender_sbox_render_current_preview",
    {
      title: "Render current S&Box preview",
      description:
        "Save the visible Blender file if needed, then run the repo asset visual review tool against the current file.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async () =>
      safe(async () => {
        const fileResponse = await blenderExecute(
          `
import bpy
if not bpy.data.filepath:
    raise RuntimeError("Current Blender file has no path; save it before rendering a preview.")
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
result = {"file": bpy.data.filepath}
`,
          { strictJson: true },
        );
        const file = (fileResponse.result as { file?: string }).file;
        if (!file) throw new Error("Blender did not return a current file path.");
        const run = await runPowerShellScript("scripts/agents/asset_visual_review.ps1", ["-Blend", file, "-ShowInfo"], 240_000);
        const previewPaths = Array.from(run.stdout.matchAll(/(?:^|\s)(screenshots[^\r\n]+?\.png)/g)).map((match) =>
          match[1].trim(),
        );
        return {
          file,
          preview_paths: previewPaths,
          stdout: run.stdout,
          stderr: run.stderr,
        };
      }),
  );

  server.registerTool(
    "blender_sbox_export_current_asset",
    {
      title: "Export current S&Box asset",
      description:
        "Save the visible Blender file, then run scripts/smart_asset_export.ps1 for the current .blend file.",
      inputSchema: z.object({ skip_prefab: z.boolean().default(false), skip_export: z.boolean().default(false) }).strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async (params) =>
      safe(async () => {
        const fileResponse = await blenderExecute(
          `
import bpy
if not bpy.data.filepath:
    raise RuntimeError("Current Blender file has no path; save it before export.")
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
result = {"file": bpy.data.filepath}
`,
          { strictJson: true },
        );
        const file = (fileResponse.result as { file?: string }).file;
        if (!file) throw new Error("Blender did not return a current file path.");
        const args = ["-BlendFilePath", file];
        if (params.skip_export) args.push("-SkipExport");
        if (params.skip_prefab) args.push("-SkipPrefab");
        const run = await runPowerShellScript("scripts/smart_asset_export.ps1", args, 600_000);
        return {
          file,
          stdout: run.stdout,
          stderr: run.stderr,
        };
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
