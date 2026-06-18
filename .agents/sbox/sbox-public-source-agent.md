# S&Box Public Source Agent

## Purpose

Use this agent when a task links `https://github.com/Facepunch/sbox-public`, asks for the latest public engine source, or needs broad engine-source context that should become durable project guidance.

This route is for the public engine source checkout and bootstrap artifacts. Use `sbox-docs-source-agent.md` for official docs markdown, `sbox-release-notes-agent.md` for dated release/API changes, and `sbox-engine-reference-agent.md` when the result becomes a standing engine/API rule.

## Sources

Prefer official and local sources:

- `https://github.com/Facepunch/sbox-public`
- project-local clone at `tools/sbox-public`
- upstream `master` checked with `git ls-remote`
- local `API.json` / `api.json` through `scripts/agents/sbox_api_lookup.ps1` when exact C# symbols matter
- existing project code, MCP projects, agents, and audits

The public source checkout is a local engine reference, not game content. Do not vendor copied engine code into this game project. Keep the clone under `tools/sbox-public`, run `Bootstrap.bat` there after updates, and record the reviewed commit/date before promoting durable lessons.

## Work

- Verify the latest upstream commit before claiming freshness.
- Install or refresh `tools/sbox-public`, then run `cmd /c Bootstrap.bat` from that folder so `game/sbox-dev.exe` and `game/bin/managed` artifacts exist.
- Preserve dirty sibling checkouts such as `C:\Programming\sbox-public`; do not reset or overwrite them just because this project has a latest project-local clone.
- Before changing project references, check whether `tools/sbox-public` exposes the same editor project references expected by this repo. If not, keep MCP builds on the existing sibling checkout or intentionally convert references to verified DLL references in a separate scoped change.
- Verify MCP health after public-source updates with `.mcp.json`, `tools/list` or `control_plane_status`, and the MCP editor project build.
- Route exact API claims through `sbox_api_lookup.ps1` before changing C#.
- Keep gameplay, scene, prefab, UI, and asset product edits out of this workflow unless the user separately asks for implementation.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_public_source_audit.ps1 -Root . -RequireLatest -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sbox-public -ShowInfo
dotnet build Libraries/jtc.mcp-server/Editor/mcp-server.editor.csproj --no-restore
```

For live editor proof, call `control_plane_status` through the native S&Box MCP server at `http://localhost:29015/mcp`.

## Output Shape

- Public source commit/date reviewed.
- Install path and bootstrap artifact status.
- MCP manifest/build/live status.
- Durable docs, agents, hooks, or audits changed.
- Exact API claims verified or left unpromoted.
- Evidence command results.
