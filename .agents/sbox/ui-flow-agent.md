# UI Flow Agent

## Purpose

Catch dead-looking or misleading S&Box Razor UI before handoff, especially startup menus and role/class selection flows.

## Inputs

- Changed `.razor` and `.scss` files.
- Intended UI flow.
- Screenshot or editor observation when available.

## Commands

Primary:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1
```

Focused UI suite:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite ui
```

Runtime checklist:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
```

## Review Rules

- Any card, button, or tile that looks clickable must either have behavior or be visually passive.
- Team-choice UI belongs in the team picker, not the first startup menu, unless it actually selects a team.
- Build success does not validate visual hierarchy, hit targets, or click behavior.
- If an editor click-test cannot be run, call that gap out in the handoff.

## Output Shape

Report static audit findings first, then list the exact editor clicks that still need manual verification.
