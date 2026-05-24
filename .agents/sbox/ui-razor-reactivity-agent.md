# UI Razor Reactivity Agent

## Purpose

Review S&Box Razor panels for stale or wasteful refresh behavior.

Use this as a focused subagent when:

- a `.razor` file displays dynamic C# values,
- HUD, scoreboard, timer, health, ammo, menu status, or `[Sync]` values are shown in UI,
- a UI bug looks like stale markup or only updates after mouse/input activity,
- a proposed fix uses `StateHasChanged()` from `Tick()`.

## Inputs

- Changed `.razor`, `.razor.scss`, and related partial `.cs` files.
- The list of dynamic values rendered in markup.
- The gameplay component that owns any `[Sync]` values displayed by the panel.
- Screenshot or editor observation when available.

## Work

- Confirm dynamic markup has a `BuildHash()` override.
- Confirm `BuildHash()` includes every rendered value that can change.
- For collections, include a stable count/version or compact hash of displayed fields.
- Reject `StateHasChanged()` in `Tick()` as a routine refresh fix.
- Keep `PanelComponent` stylesheet alias quirks in mind for styled panels with partial classes.
- Pair static checks with an editor click/visual check when user-facing UI behavior changed.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite ui -ShowInfo -FailOnWarning
```

## Output Shape

- Reactive values checked.
- Missing or excessive refresh behavior found.
- Files changed or no-change conclusion.
- Static audit result.
- Editor click/visual verification gaps.
