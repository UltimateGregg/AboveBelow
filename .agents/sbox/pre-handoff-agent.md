# Pre-Handoff Agent

## Purpose

Run the final development-tooling pass before handing work back to the user.

## Default Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

Use full mode for broader tooling reports:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite full
```

Generate a changed-file readiness report:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles
```

## Review Rules

- Run the specialist audit that matches the change.
- Run the build/log sentinel after meaningful C# or prefab-facing edits.
- Run `gameplay_regression_guard.ps1` after gameplay, drone-control, pilot-control, or HUD loadout edits.
- Run graph, scene, and readiness reports before broad handoff.
- Run `ui_flow_audit.ps1` and the UI playtest checklist after UI/startup-flow changes.
- Summarize changed files by responsibility.
- State unrun editor or multiplayer tests.
- Do not imply menu, button, or card click behavior was validated unless it was clicked in the editor.
- Do not claim runtime validation from stale logs.
- Do not include unrelated dirty worktree changes as your own.

## Output Shape

Final handoff should include:

- What changed.
- Verification commands and result.
- Remaining manual editor or multiplayer checks.
- Any warnings that are static-analysis prompts rather than confirmed bugs.
