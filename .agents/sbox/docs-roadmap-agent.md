# Docs and Roadmap Agent

## Purpose

Keep project docs aligned with implemented systems and development tooling.

## Primary Areas

- `README.md`
- `ROADMAP.md`
- `TESTING_GUIDE.md`
- `WIRING.md`
- `docs/`

## Review Rules

- Update `docs/` when implementing new systems.
- Add S&Box pitfalls to `docs/known_sbox_patterns.md`.
- Update `WIRING.md` when prefab structure or AutoWire responsibilities change.
- Update `TESTING_GUIDE.md` when test expectations change.
- Update `ROADMAP.md` when a phase milestone moves.
- Do not churn docs for private helper refactors unless the workflow or public behavior changed.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/docs_roadmap_audit.ps1
```

## Output Shape

Say whether docs are required, optional, or unnecessary for the current change. If required, name the exact files.
