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
- `https://sbox.game/api`
- `https://github.com/Facepunch/sbox-public`
- existing project code and audits in this checkout

Use community posts, wikis, and third-party tools only as secondary context. Label anything volatile with an `as of YYYY-MM-DD` source marker.

## Work

- Summarize the engine fact in project-specific terms.
- Reject or soften claims that are not backed by official docs, public source, or local evidence.
- Update `docs/sbox_engine_llm_reference.md` or `docs/known_sbox_patterns.md` when the lesson is broadly useful.
- Add or update a focused audit if the lesson prevents a repeatable failure.
- Keep product-specific gameplay, scene, prefab, UI, and asset edits out of this workflow unless they are tiny fixtures for the audit.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_engine_reference_audit.ps1 -Root . -ShowInfo
```

## Output Shape

- Verified facts used.
- Rejected or unverified claims.
- Files changed.
- Evidence command results.
- Remaining human/editor verification gaps.
