# S&Box Engine Reference Agent

## Purpose

Convert external S&Box, Source 2, ModelDoc, networking, UI, sound, or editor research into verified project guidance and reusable audits.

Use this agent when:

- a user pastes engine research and asks whether it can improve future Codex work,
- a task depends on current S&Box API shape or docs that may have changed,
- old Source 1, Hammer entity, `.qc`, `[Net]`, or manual `.vmdl` advice appears in project docs,
- a workflow lesson should become durable docs, suite wiring, or static validation.

## Sources

Prefer official sources first:

- `https://sbox.game/dev/doc`
- `https://github.com/Facepunch/sbox-docs`
- `https://sbox.game/release-notes`
- `https://sbox.game/api/changes`
- `https://sbox.game/api`
- `https://sbox.game/codesearch`
- official Facepunch Learn pages, such as `https://sbox.game/learn/facepunch/creating-an-entity-for-sandbox`
- `https://github.com/Facepunch/sbox-public`
- local `API.json` / `api.json` queried with `scripts/agents/sbox_api_lookup.ps1`
- existing project code and audits in this checkout

Use Valve Developer Community Source 2 pages as engine/tool background, not exact S&Box API authority. They are useful for ModelDoc, resource compilation, VMAT/VMDL, Hammer lighting, postprocessing, and legacy navigation mental models, but every implementation rule still needs S&Box docs, local `API.json`, editor proof, or local project evidence before it becomes active guidance.

Use community posts, wikis, and third-party tools only as secondary context. Label anything volatile with an `as of YYYY-MM-DD` source marker. For Facepunch Learn tutorials, separate editor/resource concepts such as `.sent` files from exact C# API symbols, and query the local API dump before turning sample code into standing implementation guidance.

When the source repository is available or the user links `Facepunch/sbox-docs`, start with `sbox-docs-source-agent.md`. Refresh `.tmpbuild/sbox-docs`, inspect the markdown and `toc.yml` inventory locally, then bring only durable project lessons back into this engine reference workflow.

When the user links `Facepunch/sbox-public` or asks to install or refresh the latest public engine source, start with `sbox-public-source-agent.md`. Keep the project-local clone under `tools/sbox-public`, bootstrap it, preserve dirty sibling engine checkouts, and prove MCP manifest/build/live status before promoting public-source facts into standing guidance.

When the user asks to search S&Box patch notes, release notes, or new API changes, start with `sbox-release-notes-agent.md`. Use the dated release notes and API changes pages to identify candidate lessons, then verify exact symbols through local `API.json` before promoting them into standing guidance.

When the user links `https://sbox.game/codesearch` or asks for practical examples from published packages, start with `sbox-code-search-agent.md`. Treat public package source as pattern discovery; compare multiple examples and verify exact symbols locally before implementation.

## Work

- Summarize the engine fact in project-specific terms.
- For exact API shape, query the local API dump before adding unfamiliar S&Box symbols.
- Reject or soften claims that are not backed by official docs, public source, or local evidence.
- For Valve Developer Community Source 2 pages, classify the lesson before updating docs: asset/resource pipeline, ModelDoc/materials, Hammer lighting/postprocessing, legacy navigation, or stale Source 1 migration.
- Translate Source 2 source/compiled resource lessons into project pipeline checks; never make compiled `_c` files the durable edit surface.
- Keep Valve `Nav Mesh` / `Nav_Mesh_Editing` guidance marked as legacy Source/Counter-Strike context unless a task explicitly targets that toolchain; S&Box navigation defaults to Recast and `Scene.NavMesh`.
- Update `docs/sbox_engine_llm_reference.md` or `docs/known_sbox_patterns.md` when the lesson is broadly useful.
- For `https://sbox.game/learn` tutorial reviews, hand off workflow-specific lessons to `sbox-learn-intake-agent.md` so community guidance becomes focused docs, audits, hooks, or routing.
- For `Facepunch/sbox-public` install, update, or source-layout lessons, hand off to `sbox-public-source-agent.md` so clone freshness, bootstrap artifacts, MCP proof, and sibling checkout preservation stay explicit.
- For official release-note and API-change reviews, hand off volatile update tracking to `sbox-release-notes-agent.md` so new-feature lessons stay dated, sourced, and audit-backed.
- For public package examples from Code Search, hand off pattern discovery to `sbox-code-search-agent.md` so examples stay separated from official API proof and project implementation.
- Add or update a focused audit if the lesson prevents a repeatable failure.
- Keep product-specific gameplay, scene, prefab, UI, and asset edits out of this workflow unless they are tiny fixtures for the audit.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_engine_reference_audit.ps1 -Root . -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Query SyncAttribute -ShowMembers
```

## Output Shape

- Verified facts used.
- Rejected or unverified claims.
- Files changed.
- Evidence command results.
- Remaining human/editor verification gaps.
