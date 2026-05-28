# S&Box Docs Source Agent

## Purpose

Use this agent when a task depends on the official S&Box documentation source repository at `https://github.com/Facepunch/sbox-docs`, when the live docs may have changed, or when a broad docs sweep should become durable project guidance.

This route is for official docs source intake. Use `sbox-learn-intake-agent.md` for `https://sbox.game/learn` tutorials and `sbox-engine-reference-agent.md` when the result is a standing engine/API rule.

## Sources

Prefer the docs source repository over shallow website scraping:

- `https://github.com/Facepunch/sbox-docs`
- `https://sbox.game/dev/doc`
- local clone at `.tmpbuild/sbox-docs`
- local `API.json` / `api.json` through `scripts/agents/sbox_api_lookup.ps1` when exact C# symbols matter
- existing project code, agents, and audits

The docs repo is a reference source, not a vendored dependency. Do not copy the whole docs tree into this project. Clone or refresh it under `.tmpbuild`, record the reviewed commit/date in `docs/sbox_engine_llm_reference.md` when a lesson becomes durable, and keep exact implementation claims verified locally.

## Work

- Run the docs source audit with `-Refresh` before broad docs research or when the user asks to train on `Facepunch/sbox-docs`.
- Use `.tmpbuild/sbox-docs-source-index.md`, `toc.yml` files, and `rg` over `.tmpbuild/sbox-docs/docs` to find relevant pages.
- Record only reusable project lessons in `docs/sbox_engine_llm_reference.md` or `docs/known_sbox_patterns.md`.
- Route exact API claims through `sbox_api_lookup.ps1` before changing C#.
- Route editor-tooling rules through `sbox-engine-reference-agent.md`, editor-first workflow docs, or focused editor audits.
- Route Razor/UI lessons through `ui-razor-reactivity-agent.md` and `ui_flow_audit.ps1`.
- Keep gameplay, scene, prefab, UI, and asset changes out of this workflow unless the user separately asks for product work.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_docs_source_audit.ps1 -Root . -Refresh -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite sbox-docs -ShowInfo
```

## Output Shape

- Docs source commit/date reviewed.
- Official docs sections inspected, with a generated page index.
- Durable docs, agents, hooks, or audits changed.
- Exact API claims verified or left unpromoted.
- Evidence command results.
