/**
 * Tool registrations for the s&box MCP server. Each tool wraps an endpoint on
 * the CoworkBridge HTTP listener.
 *
 * Naming: all tools are prefixed `sbox_` so they're easy to find when mixed
 * with other MCPs. Snake_case action-oriented per MCP best practices.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeCall, BridgeError } from "./client.js";

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
  // The SDK requires structuredContent to be a JSON object. Wrap arrays/primitives.
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
    const data = await fn();
    return ok(data);
  } catch (e) {
    if (e instanceof BridgeError) return err(e.message);
    return err(`Unexpected error: ${e instanceof Error ? e.message : String(e)}`);
  }
}

export function registerTools(server: McpServer): void {
  // --- Sanity / metadata ---

  server.registerTool(
    "sbox_ping",
    {
      title: "Ping s&box bridge",
      description:
        "Verify the editor bridge is reachable. Returns `ok: true` and a timestamp if the editor is open and the Cowork bridge is running. Use this first whenever you suspect the bridge isn't responding.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => safe(() => bridgeCall("/ping")),
  );

  server.registerTool(
    "sbox_scene_info",
    {
      title: "Active scene info",
      description:
        "Return summary info about the currently focused scene editor session: scene name, GUID, root GameObject count, whether it's a prefab scene. Read-only, safe to call any time.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => safe(() => bridgeCall("/scene/info")),
  );

  server.registerTool(
    "sbox_scene_tree",
    {
      title: "Scene hierarchy tree",
      description:
        "Return the full GameObject hierarchy of the active scene with each node's GUID, name, enabled state, and component type names. Use this to map the scene before making targeted reads with sbox_gameobject_get.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => safe(() => bridgeCall("/scene/tree")),
  );

  server.registerTool(
    "sbox_scene_open",
    {
      title: "Open scene or prefab",
      description:
        "Open a local project .scene or .prefab asset in the s&box editor. Accepts either asset-browser paths like `Assets/scenes/main.scene` and `Assets/prefabs/drone.prefab`, or resource paths like `scenes/main.scene`. Use this before inspecting or editing a scene or prefab that is not currently focused.",
      inputSchema: z
        .object({
          path: z.string().min(1).describe("Path to a .scene or .prefab asset to open."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/scene/open", params)),
  );

  // --- GameObject inspection ---

  const GameObjectIdSchema = z
    .object({
      guid: z
        .string()
        .uuid()
        .optional()
        .describe("Stable GUID of the GameObject (preferred)."),
      name: z
        .string()
        .min(1)
        .optional()
        .describe("Name of the GameObject. Falls back to first match if multiple share the name."),
    })
    .strict()
    .refine((v) => v.guid || v.name, { message: "Provide either guid or name" });

  server.registerTool(
    "sbox_gameobject_get",
    {
      title: "Inspect a GameObject",
      description:
        "Return a single GameObject's full state: transform (position/rotation/scale), parent GUID, children GUIDs, and every component with its [Property]-marked fields and current values. Pass `guid` (preferred) or `name`.",
      inputSchema: GameObjectIdSchema,
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/gameobject/get", params)),
  );

  server.registerTool(
    "sbox_gameobject_select",
    {
      title: "Select a GameObject in the editor",
      description:
        "Select a GameObject in the editor's hierarchy panel (replaces current selection). Useful so the user can see what tool just acted on. Pass `guid` (preferred) or `name`.",
      inputSchema: GameObjectIdSchema,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/gameobject/select", params)),
  );

  // --- Scene mutation ---

  server.registerTool(
    "sbox_scene_save",
    {
      title: "Save active scene",
      description:
        "Save the currently focused scene editor session to disk. Returns the saved scene name. Idempotent.",
      inputSchema: z.object({}).strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => safe(() => bridgeCall("/scene/save")),
  );

  server.registerTool(
    "sbox_component_set_property",
    {
      title: "Set a component value property",
      description:
        "Set a primitive or simple property on a component. Wraps the change in an editor undo scope. Supported value types: string, number, bool, Vector3 (as [x,y,z] or 'x,y,z'), enum (string name).\n\n" +
        "For wiring GameObject or Component references, use sbox_component_wire_reference instead.\n\n" +
        "Returns `{ ok, property, value_type }` on success.",
      inputSchema: z
        .object({
          component_guid: z.string().uuid().describe("GUID of the target component (from sbox_gameobject_get)."),
          property_name: z.string().min(1).describe("Property name on the component (case-insensitive)."),
          value: z.unknown().describe("New value. Type must match the property's type."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/component/set_property", params)),
  );

  server.registerTool(
    "sbox_component_wire_reference",
    {
      title: "Wire a GameObject/component reference",
      description:
        "Set a reference-type [Property] on a component (e.g. DroneController.VisualModel = the Visual child GameObject). This is the painful manual drag-and-drop made automatic.\n\n" +
        "Steps to use:\n" +
        "1. Call sbox_gameobject_get on the component's owner to find the component_guid and the property_name to wire.\n" +
        "2. Call sbox_gameobject_get on the desired target to get its guid (or a child component's guid).\n" +
        "3. Call this tool with target_kind='gameobject' or 'component'.\n\n" +
        "Wrapped in an undo scope so the user can ctrl-z if needed.",
      inputSchema: z
        .object({
          component_guid: z.string().uuid().describe("Component whose property is being wired."),
          property_name: z.string().min(1).describe("Reference property name (e.g. 'VisualModel', 'Body', 'Target')."),
          target_guid: z.string().uuid().describe("GUID of the GameObject or Component being assigned."),
          target_kind: z
            .enum(["gameobject", "component"])
            .default("gameobject")
            .describe("Whether target_guid is a GameObject or a Component. Defaults to gameobject."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/component/wire_reference", params)),
  );

  server.registerTool(
    "sbox_console_log",
    {
      title: "Write to editor console",
      description:
        "Log a message to the s&box editor console. Useful for surfacing notes to the user, marking session boundaries, or smoke-testing the bridge.",
      inputSchema: z
        .object({
          message: z.string().min(1).max(2000).describe("Text to log."),
          level: z
            .enum(["info", "warn", "error"])
            .default("info")
            .describe("Log severity: info, warn, or error."),
        })
        .strict(),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async (params) => safe(() => bridgeCall("/console/log", params)),
  );
}
