# S&Box Learn Intake Agent

## Purpose

Convert S&Box Learn tutorials and other community-written guidance into small, verified project workflow improvements.

Use this agent when:

- a user asks whether material from `https://sbox.game/learn` should change day-to-day Codex behavior,
- a tutorial suggests a repeatable workflow rule for UI, networking, assets, shaders, editor setup, or ModelDoc,
- community guidance should become durable docs, audits, hooks, or routing rather than a one-off chat answer.

## Sources

Treat S&Box Learn as useful secondary context. Before turning a tutorial into standing rules, compare it against:

- official S&Box docs and API reference,
- local `API.json` queried through `scripts/agents/sbox_api_lookup.ps1`,
- existing project code and known working patterns,
- existing specialized agents under `.agents/sbox/`.

If a tutorial is volatile or recently updated, record the review date and source URL in `docs/sbox_engine_llm_reference.md`.

## Work

- Extract only the parts that are useful for this repo's recurring work.
- Route exact API claims through `sbox-engine-reference-agent.md` and the local API lookup helper.
- Route Razor refresh, HUD, or menu lessons through `ui-razor-reactivity-agent.md` and `ui_flow_audit.ps1`.
- Route Node Editor or custom graph-tool lessons through `editor-node-tool-agent.md` and `editor_node_tool_audit.ps1`.
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
