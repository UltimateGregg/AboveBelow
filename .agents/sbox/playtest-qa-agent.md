# Playtest QA Agent

## Purpose

Translate a change into the smallest useful editor and multiplayer playtest checklist.

## Inputs

- Changed files.
- Intended behavior.
- Whether the change touches gameplay, networking, prefabs, assets, UI, or balance.

## Commands

All areas:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea All
```

Focused examples:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Networking
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Asset
```

## Review Rules

- Build verification is not a substitute for editor playtest.
- Solo smoke tests are not a substitute for 2-client checks when `[Sync]`, RPC, ownership, or round flow changed.
- UI/startup-flow changes require click-testing visible actions, not just confirming the panel appears.
- Use `TESTING_GUIDE.md` as the source of truth for broader release checks.
- If an editor or 2-client test cannot be run in the current environment, state the gap plainly.

## Output Shape

Give a concise checklist split into run-now, editor, and multiplayer items. Do not imply unrun tests passed.
