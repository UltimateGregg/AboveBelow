# UI Agent Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the local agent toolkit so UI/startup-flow regressions are easier to catch before handoff.

**Architecture:** Add a focused static Razor audit for interactive-looking UI elements, wire it into the agent runner and readiness report, and update the human playtest checklist so visual interaction gaps are explicit.

**Tech Stack:** PowerShell validation scripts, Codex agent markdown playbooks, S&Box Razor UI files.

---

### Task 1: Self-Test Gate

**Files:**
- Modify: `C:\Programming\S&Box\scripts\agents\test_full_automation_layer.ps1`

- [ ] Add `scripts/agents/ui_flow_audit.ps1` to required script checks.
- [ ] Require `run_agent_checks.ps1` to expose a `ui` suite.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite self-test`.
- [ ] Expected before implementation: failure because the UI audit script and suite do not exist yet.

### Task 2: UI Flow Audit

**Files:**
- Create: `C:\Programming\S&Box\scripts\agents\ui_flow_audit.ps1`
- Modify: `C:\Programming\S&Box\scripts\agents\run_agent_checks.ps1`

- [ ] Add a script that scans `Code/UI/*.razor`.
- [ ] Flag `div` elements with class names containing `choice`, `team-choice`, `menu-button`, `main-menu-button`, `option-button`, or `action-button` when they do not have `onclick=`.
- [ ] Suppress warnings for elements explicitly marked `passive`, `info`, `static`, `readonly`, or `disabled`.
- [ ] Add the script to `quick`, `full`, and a dedicated `ui` suite.

### Task 3: Readiness And Playtest Routing

**Files:**
- Modify: `C:\Programming\S&Box\scripts\agents\feature_readiness_report.ps1`
- Modify: `C:\Programming\S&Box\scripts\agents\playtest_checklist.ps1`
- Modify: `C:\Programming\S&Box\scripts\agents\current_log_audit.ps1`
- Modify: `C:\Programming\S&Box\scripts\agents\run_agent_checks.ps1`

- [ ] Make UI changes require `ui_flow_audit.ps1` and `playtest_checklist.ps1 -ChangeArea UI`.
- [ ] Add startup-flow click expectations to UI checklist output.
- [ ] Filter `.superpowers/brainstorm/` generated files from readiness reports.
- [ ] Make quick-suite log audit show info so missing fresh logs are visible.

### Task 4: Agent Documentation

**Files:**
- Create: `C:\Programming\S&Box\.agents\sbox\ui-flow-agent.md`
- Modify: `C:\Programming\S&Box\.agents\sbox\README.md`
- Modify: `C:\Programming\S&Box\.agents\sbox\playtest-qa-agent.md`
- Modify: `C:\Programming\S&Box\.agents\sbox\pre-handoff-agent.md`
- Modify: `C:\Programming\S&Box\docs\agent_toolkit.md`

- [ ] Document the new UI flow agent and command.
- [ ] Add the rule that static/build checks do not prove editor click behavior.
- [ ] Point UI/startup changes to the UI flow audit and focused playtest checklist.

### Task 5: Verification

**Files:**
- Read: changed tooling and docs files.

- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite self-test`.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite ui`.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\agents\run_agent_checks.ps1 -Suite quick`.
- [ ] Run `dotnet build Code\dronevsplayers.csproj --no-restore`.
- [ ] State any editor click-test gap plainly.
