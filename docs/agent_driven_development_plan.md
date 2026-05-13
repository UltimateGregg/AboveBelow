# Agent-Driven Development Plan

This plan uses the project agents in `.agents/sbox/` as phase gates for ABOVE / BELOW development. It keeps gameplay, UI, prefab, asset, networking, and tooling changes separated.

## Phase 0 - Automation Checkpoint

Goal: treat the agent toolkit as the baseline for future work.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite full
powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles
```

Exit criteria:

- Full suite passes.
- Tooling/docs changes are intentionally staged or left untracked with a known reason.

## Phase 1 - Main Menu And Startup Flow

Goal: players enter `main.scene` through a main menu, then choose team/class/variant.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
```

Manual checks:

- Main menu appears before the class picker.
- Play opens the existing role/class picker.
- Options opens local options.
- Quit closes the game.

## Phase 2 - Two-Client Baseline

Goal: satisfy the Phase 0 roadmap exit criterion.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/current_log_audit.ps1 -RequireFresh
```

Manual checks:

- 2-client local playtest.
- Both clients can choose classes/variants.
- Combat, death, score, and round-end state replicate.

## Phase 3 - Round-End Re-Prompt

Goal: finish the Phase 0.5 roadmap gap by re-opening team/class/variant choice after round reset.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

Manual checks:

- Solo round reset prompts a new choice.
- 2-client round reset prompts both clients without stale pawn state.

## Phase 4 - Drone Feel Pass

Goal: make GPS, FPV, and Fiber FPV feel distinct and controllable.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Balance
```

Manual checks:

- Takeoff, hover, turn, climb, chase, and landing feel good for each variant.
- Before/after tuning values are recorded.

## Phase 5 - BalanceConfig Resource

Goal: move key tuning values into a S&Box resource so balance changes avoid code churn.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

Manual checks:

- Resource values apply consistently on host and clients.
- Existing defaults are preserved unless intentionally tuned.

## Phase 6 - Match Flow Polish

Goal: make the game loop readable and repeatable.

Features:

- Countdown polish.
- Winner banner polish.
- Score persistence UI.
- Dead-player spectator behavior.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea UI
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

## Phase 7 - Production Asset Pipeline Pass

Goal: replace placeholder visuals without breaking prefab references or scene collision.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

Manual checks:

- S&Box editor reloads changed assets.
- No missing model or error material appears.

## Phase 8 - Server Hardening

Goal: reduce public-test cheat surface.

Targets:

- Host-side weapon traces.
- RPC parameter validation.
- RPC cooldown/rate limit validation.
- Kamikaze arming/cooldown validation.

Agent gates:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

Manual checks:

- 2-client combat test.
- Host remains authoritative for damage, jam, round, and spawn state.
