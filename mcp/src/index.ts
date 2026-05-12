#!/usr/bin/env node
/**
 * sbox-mcp-server
 *
 * MCP server that exposes the s&box editor (via the in-editor CoworkBridge
 * HTTP listener) as a set of tools. Run as a stdio subprocess from any MCP
 * client (Claude Desktop, Cowork, etc.).
 *
 * Prereqs at runtime:
 *   1. s&box editor open with your project loaded
 *   2. Editor menu: Editor > Cowork > Start MCP Bridge clicked once per session
 *
 * Env vars:
 *   SBOX_BRIDGE_URL - override the bridge URL (default http://localhost:38080)
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerTools } from "./tools.js";

const server = new McpServer({
  name: "sbox-mcp-server",
  version: "0.1.0",
});

registerTools(server);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // Logs go to stderr so they don't pollute stdio's JSON-RPC channel.
  console.error("sbox-mcp-server connected (stdio). Bridge URL: " + (process.env.SBOX_BRIDGE_URL ?? "http://localhost:38080"));
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
