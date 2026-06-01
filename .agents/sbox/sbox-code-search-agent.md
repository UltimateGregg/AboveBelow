# S&Box Code Search Agent

## Purpose

Use this agent when a task needs examples from public S&Box packages at `https://sbox.game/codesearch`, especially when local docs or `API.json` prove a symbol exists but do not show enough practical usage.

Code Search is a pattern-discovery resource, not implementation authority. It searches source from published packages, including game, editor, and unit-test code. Treat package code as examples to compare and learn from; verify exact APIs through local `API.json`, official API pages, official docs, or local project code before editing this repo.

## Sources

Prefer this order:

- local project patterns and focused audits,
- local `API.json` / `api.json` through `scripts/agents/sbox_api_lookup.ps1`,
- official docs source via `sbox-docs-source-agent.md`,
- official API pages and API changes,
- `https://sbox.game/codesearch` public package examples,
- Learn tutorials or release notes when they are the better source for the question.

The Code Search page is useful because it exposes package type, code type, and year filters. Prefer recent examples, compare more than one package, and separate runtime game code from editor-only or unit-test examples before copying a pattern into this project.

## Work

- Search Code Search for the exact type, method, attribute, or workflow term.
- Bias toward recent game-code examples for runtime gameplay and editor-code examples for tooling.
- Compare multiple results before adopting a pattern, especially for networking, UI refresh, editor tools, asset writing, sound, and physics.
- Cross-check unfamiliar C# symbols with `scripts/agents/sbox_api_lookup.ps1` before implementation.
- Do not vendor package source into this repo. Quote only small snippets when needed, then write project-specific code using local conventions.
- Promote reusable lessons into `docs/sbox_engine_llm_reference.md`, `docs/known_sbox_patterns.md`, agents, hooks, or focused audits.
- Keep gameplay, scene, prefab, UI, and asset product edits out of this workflow unless the user separately asks for implementation.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite code-search -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_code_search_audit.ps1 -Root . -ShowInfo
```

## Output Shape

- Code Search terms and filters used.
- Example packages compared, with source dates or recency filters when available.
- API symbols verified locally or explicitly left unverified.
- Durable workflow surfaces changed.
- Evidence command results.
