# S&Box Learn Intake Agent

## Purpose

Convert S&Box Learn tutorials, official editor-doc sweeps, and other external guidance into small, verified project workflow improvements.

Use this agent when:

- a user asks whether material from `https://sbox.game/learn` or `https://sbox.game/dev/doc/editor/` should change day-to-day Codex behavior,
- a tutorial or docs section suggests a repeatable workflow rule for UI, networking, assets, shaders, editor setup, editor tools, or ModelDoc,
- external guidance should become durable docs, audits, hooks, or routing rather than a one-off chat answer.

## Sources

Treat S&Box Learn as useful secondary context. Before turning a tutorial into standing rules, compare it against:

- official S&Box docs and API reference,
- local `API.json` queried through `scripts/agents/sbox_api_lookup.ps1`,
- existing project code and known working patterns,
- existing specialized agents under `.agents/sbox/`.

Treat official S&Box docs as primary context, but still verify exact C# symbols against local `API.json` or existing project patterns before implementation. If a tutorial or official docs sweep is volatile, broad, or recently updated, record the review date and source URL in `docs/sbox_engine_llm_reference.md`.

For official patch notes, release notes, or API-change pages, use `sbox-release-notes-agent.md` first. Bring content back into this Learn route only when the patch note points at tutorial-style guidance or Learn pages.

## Work

- Extract only the parts that are useful for this repo's recurring work.
- Route exact API claims through `sbox-engine-reference-agent.md` and the local API lookup helper.
- Route Razor refresh, HUD, or menu lessons through `ui-razor-reactivity-agent.md` and `ui_flow_audit.ps1`.
- Route Node Editor or custom graph-tool lessons through `editor-node-tool-agent.md` and `editor_node_tool_audit.ps1`.
- Route official editor-doc lessons into the engine reference as short workflow rules, especially editor-only placement, `UndoScope`, `EditorEvent`, inspector attributes, `AssetPreview`, and `TextureGenerator` guidance.
- Prefer focused audit rules, hook patterns, and agent routing over broad prose.
- Do not make gameplay, scene, prefab, or asset edits from tutorial research unless the user explicitly asks for product changes.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite learn -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_learn_intake_audit.ps1 -ShowInfo
```

## Output Shape

- Useful tutorial lessons adopted.
- Tutorial claims rejected or left as secondary context.
- Agents, hooks, docs, or audits changed.
- Evidence command results.
- Remaining editor/runtime verification gaps.
