# Build and Log Sentinel

## Purpose

Verify that the project compiles and surface fresh editor/runtime log problems without pretending stale logs prove anything.

## When To Use

- After C# edits.
- After prefab or scene edits that could trigger generated code or editor load errors.
- Before claiming a task is complete.

## Commands

Primary:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
```

Current runtime/editor log discovery:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh
```

Strict mode:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1 -FailOnWarning
```

Skip build only when another command already ran the same build in this turn:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1 -NoBuild
```

## Review Rules

- Compiler errors block handoff.
- New compiler warnings must be called out even if build succeeds.
- Fresh log exceptions or warning lines require inspection.
- Stale logs are only historical context.
- If no runtime log exists, report that editor validation is unavailable.
- `current_log_audit.ps1 -RequireFresh` should be run after an editor playtest when runtime behavior changed.

## Output Shape

Report:

- Build command and result.
- Fresh log files checked.
- Stale log files ignored.
- Remaining runtime validation gap, if any.
