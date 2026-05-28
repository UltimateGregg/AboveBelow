# S&Box Release Notes Intake Agent

## Purpose

Convert official S&Box release notes, news updates, and API-change pages into dated project guidance, audits, and routing.

Use this agent when:

- a user asks to search S&Box patch notes, release notes, update posts, or API changes,
- a new engine feature looks useful but could have changed recently,
- a release note suggests replacing old project patterns with a new API or editor workflow,
- the result should improve future Codex behavior rather than produce a one-off summary.

## Sources

Prefer official, dated sources:

- `https://sbox.game/release-notes`
- `https://sbox.game/news`
- `https://sbox.game/api/changes`
- the official API page for the exact symbol,
- local `API.json` or `api.json` queried through `scripts/agents/sbox_api_lookup.ps1`,
- existing project code and audited patterns.

Treat release-note summaries as volatile. Record the reviewed date and the source update date before promoting a claim into standing guidance. If a release note names a C# symbol, verify the exact symbol through `https://sbox.game/api`, API changes, local `API.json`, or existing code before implementation.

## Work

- Extract recurring workflow lessons, not every patch note.
- Separate player/platform changes from creator-facing C#, editor, asset, networking, UI, physics, sound, or rendering changes.
- Promote only lessons that affect this repo's future work into `docs/sbox_engine_llm_reference.md`, `docs/known_sbox_patterns.md`, agents, hooks, or audit scripts.
- Route tutorial-style content to `sbox-learn-intake-agent.md`.
- Route exact API adoption to `sbox-engine-reference-agent.md` and `sbox_api_lookup.ps1`.
- Add focused audit markers when a new release note replaces a risky old pattern.
- Do not make gameplay, scene, prefab, UI, or asset product edits from patch-note research unless the user explicitly asks for that implementation.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite release-notes -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_release_notes_audit.ps1 -Root . -ShowInfo
```

## Output Shape

- Official update/API sources reviewed, with dates.
- Useful lessons adopted into durable workflow surfaces.
- Claims left as volatile or requiring API/editor verification.
- Files changed.
- Evidence command results.
