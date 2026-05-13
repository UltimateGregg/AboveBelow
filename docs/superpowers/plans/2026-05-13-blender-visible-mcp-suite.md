# Blender Visible MCP Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing Blender MCP and asset-production toolkit usable from a visible Blender session.

**Architecture:** Keep the existing socket bridge and repo-side PowerShell/Python tools as the source of truth. Add a Blender add-on as the visible control surface, then extend the stdio MCP server with S&Box-specific authoring tools that operate on the same open Blender window.

**Tech Stack:** Blender Python add-on, PowerShell launch/install scripts, TypeScript MCP server, existing S&Box asset pipeline scripts.

---

### Task 1: Static Self-Test Gate

**Files:**
- Create: `scripts/agents/blender_live_toolkit_self_test.ps1`

- [ ] Create a self-test that verifies the Blender add-on, visible launcher, MCP source tool names, and docs exist.
- [ ] Run it before implementation and confirm it fails because those files/tools are missing.

### Task 2: Blender Add-On Control Surface

**Files:**
- Create: `blender_addons/sbox_asset_toolkit/__init__.py`
- Create: `scripts/install_blender_asset_toolkit.ps1`
- Create: `scripts/start_visible_blender_asset_toolkit.ps1`

- [ ] Add an `S&Box Asset Toolkit` sidebar panel in Blender.
- [ ] Add buttons for bridge startup, production scene setup, asset brief, quality audit, preview render, S&Box export, production checks, and opening latest preview/report.
- [ ] Add install and visible-launch scripts that use repo-relative files and preserve the visible Blender session workflow.

### Task 3: S&Box MCP Tool Expansion

**Files:**
- Modify: `mcp/src/blender.ts`

- [ ] Add high-level MCP tools for S&Box scene status, scene setup, socket creation, material creation, current-file preview render, and current-file export.
- [ ] Keep existing low-level tools intact.
- [ ] Build the MCP TypeScript package locally with `node .\mcp\node_modules\typescript\bin\tsc -p .\mcp\tsconfig.json` so the ignored `mcp/dist/` runtime is refreshed for this checkout.

### Task 4: Docs And Verification

**Files:**
- Modify: `docs/blender_mcp.md`
- Modify: `docs/agent_toolkit.md`

- [ ] Document visible Blender workflow, install/start commands, add-on panel actions, and MCP tool names.
- [ ] Run the self-test, PowerShell parser checks, Python compile checks, TypeScript build, and existing agent checks.
