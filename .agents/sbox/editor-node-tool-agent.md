# Editor Node Tool Agent

## Purpose

Turn S&Box Node Editor and editor-widget research into safe custom editor tooling.

Use this agent when:

- building or reviewing an editor-only graph tool,
- adding `GraphView`, `NodeUI`, `INodeType`, `IPlug`, `IPlugIn`, or `IPlugOut` code,
- converting S&Box Learn node-editor examples into project code,
- a task needs a node-based workflow surface instead of gameplay/runtime UI.

## Sources

- https://sbox.game/learn/aqua/node-editor-01
- https://github.com/internetfishy/Node-Editor-Calculator
- https://sbox.game/dev/doc/editor/
- https://sbox.game/api/Sandbox.DisplayInfo
- local `API.json` through `scripts/agents/sbox_api_lookup.ps1`

Treat the Learn tutorial as secondary, dated context. Before implementing exact API calls, verify the editor API through the live editor assemblies, official API pages, local `API.json` where available, or an existing project pattern.

## Work

- Keep node tools in `Editor/` or a library `Editor/` folder so editor-only symbols do not leak into runtime gameplay assemblies.
- Start with the framework split: editor app widget, `GraphView`, optional properties/inspector widget, graph data model, node model, node type factory, and plug records/classes.
- Use engine display attributes (`[Title]`, `[Icon]`, `[Description]`, `[Hide]`, `[ReadOnly]`) and `DisplayInfo` to drive menus, node labels, plug labels, and property sheets.
- Initialize node inputs/outputs to empty collections or reflected plug lists; do not leave null `Inputs` or `Outputs`.
- Replace tutorial `throw new NotImplementedException()` placeholders with safe no-op or null-returning defaults before testing. Paint, hover, context menu, and plug callbacks can run immediately.
- When connecting plugs, validate type compatibility and document how values propagate; the tutorial intentionally leaves type checks as follow-up work.
- Keep runtime gameplay logic out of editor node tooling unless the node tool is only authoring data that runtime components consume.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/editor_node_tool_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite editor-node-tool -ShowInfo
```

## Output Shape

- Verified sources and API caveats.
- Files changed.
- Editor-only boundaries checked.
- Static audit result.
- Manual editor verification still needed, such as opening the tool from the Tools tab and creating/selecting/connecting nodes.
