# Claude Code Workflow Quick Reference

This guide helps Claude Code follow the structured workflows that power this project's iteration speed and reliability.

## When Starting Any Task

1. **Read CLAUDE.md section** relevant to the task (input, rendering, networking, HUD, drone, etc.)
2. **Check if code matches docs** — cross-reference behavior line-by-line
3. **Form a hypothesis** about what's needed or broken
4. **Ask clarifying questions** (in plan mode) before committing to investigation steps
5. **Reference existing patterns** instead of creating new systems

## Agent Scripts by Change Type

Run these in the order listed. All must pass before declaring work done.

### Gameplay or C# Changes
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

### Drone Input, Pilot Control, or HUD Changes
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/playtest_checklist.ps1 -ChangeArea Gameplay
```

### Prefab or Scene Changes
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

### Blender Asset Changes
The `blend-auto-export` hook fires automatically on `.blend` save.
```powershell
# Manual re-run if needed:
powershell -ExecutionPolicy Bypass -File scripts/smart_asset_export.ps1 -BlendFilePath "path/to/asset.blend"

# Then validate:
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1
```

### Collision Changes
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/collision_authoring_agent.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

### UI Changes
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/ui_flow_audit.ps1 -FailOnWarning
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
```

### Before Final Handoff (Any Change Type)
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite quick
```

Or for thorough validation:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite full
```

## Automatic Hooks (No Action Required)

| Hook | Trigger | Action |
|------|---------|--------|
| `blend-auto-export` | Any `.blend` file saved | Exports FBX → VMDL → prefab |
| `drone-control-regression-check` | Drone-related files saved | Runs gameplay_regression_guard.ps1 |
| `sbox-editor-first-workflow-check` | Editor-control-plane docs, MCP manifest, editor-first agent, or suite wiring saved | Runs `run_agent_checks.ps1 -Suite editor-first -ShowInfo` |
| `sbox-learn-intake-check` | Learn-derived docs, UI/Razor agent docs, or related audit/suite files saved | Runs `run_agent_checks.ps1 -Suite learn -ShowInfo` |

## Key Documentation Sections to Read First

| Task Type | Read This Section in CLAUDE.md |
|-----------|------|
| Visibility/rendering bug | "Held-item pose/IK architecture" + "human first-person body rendering" + "HUD feedback layers" |
| Weapon or grenade behavior | "Held-item pose/IK architecture" + "Slot system" + "Health and damage events" |
| Drone prefab work | "Drone prefab conventions" + "Pilot / drone control flow" |
| Networking issue | Search CLAUDE.md for `[Sync]`, `Rpc`, "host-authoritative" |
| Input/controls | "Recoil" + "GroundPlayerController" + relevant weapon class |

## Common Clarifying Questions to Ask (Plan Mode)

### Visibility Issues
- Are all items visible at once, or just the wrong one?
- Do they disappear when switching slots, or stay visible?
- Does the same issue affect first-person and third-person view?

### Weapon/Grenade Issues
- Is the weapon firing but doing nothing, or not firing at all?
- Does it fail for local player only, all players, or the host?
- Is the issue with the model, sound, damage, or input?

### Drone Issues
- Is the drone controllable or completely unresponsive?
- Can you see the drone on screen but not control it, or vice versa?
- Does the issue appear only on the pilot's view or for all players?

### Networking Issues
- Is the issue seen by all players, only the local player, or only non-local players?
- Is it a property that should sync or a one-time event?
- Does it work in single-player editor playtest?

## Memory Files to Check First

Before starting work, scan these for relevant patterns:
- `tooling_blender_mcp.md` — Blender MCP constraints and workarounds
- `tooling_sbox_mcp.md` — S&Box editor MCP quirks
- `lesson_debugging_workflow.md` — Doc-first debugging pattern
- `lesson_visibility_bugs.md` — Visibility/RenderType patterns
- `project_drone_pipeline.md` — Drone asset pipeline gotchas

Full list in `MEMORY.md`.

## When to Create New Memory Files

After work is complete, save these as memory:
1. **Tooling discovery** — "We found that X MCP tool has Y constraint"
2. **Debugging pattern** — "Cross-checking docs to code first catches Y bugs faster"
3. **Code pattern** — "New soldier classes must follow the composition pattern with SoldierBase subclass + children"
4. **Project state change** — "As of date, we moved X to Y location"

Template:
```markdown
---
name: kebab-case-slug
description: One-line summary for relevance lookups
metadata:
  type: tooling | feedback | project | reference
---

**Rule:** The key insight or pattern.

**Why:** The reason this matters (incident, constraint, or discovery).

**How to apply:** When/where/how to use this pattern in future work.

**Related:** [[other-memory-name]]
```

## Exit Criteria (Before Declaring Work Done)

- [ ] All relevant agent scripts pass (no exit code 1)
- [ ] Build compiles with no new errors
- [ ] CLAUDE.md or AGENTS.md behavior matches code
- [ ] Clarifying questions from plan mode were addressed
- [ ] If discovered new pattern/constraint, saved to memory
- [ ] Tested in editor playtest (if gameplay/input change)
- [ ] Pre-handoff suite passed

## Self-Training (Continuous Improvement)

**Trigger:** Type `train` after completing any substantial task

**What happens:**
1. Runs full audit suite (`scripts/agents/run_agent_checks.ps1 -Suite train`)
2. Inspects findings to identify durable workflow improvements
3. Updates documentation, hooks, agents, and memory based on patterns discovered
4. Summarizes changes and validation gaps

**What gets improved:**
- Documentation (CLAUDE.md, AGENTS.md, docs/)
- Hooks for new automation (.claude/settings.json)
- Agent scripts (new agents, improved existing ones)
- Memory files (new patterns, lessons learned)
- Workflow routing (agent selection guide)

**What doesn't change:**
- Gameplay code, scene content, prefabs, assets, UI (unless part of workflow improvement)

See `docs/training_workflow.md` for full details.

## Quick Workflow Checklist

**In Plan Mode:**
- [ ] Read relevant CLAUDE.md section
- [ ] Form hypothesis
- [ ] Ask clarifying questions (not "is this plan ok?" but concrete behavioral questions)
- [ ] Reference existing patterns, don't design new systems

**During Implementation:**
- [ ] Make changes following CLAUDE.md conventions
- [ ] Run appropriate agent scripts for change type
- [ ] Address agent failures as errors (investigate root cause)
- [ ] Save new learnings to memory

**Before Handoff:**
- [ ] Run full or subset agent suite
- [ ] All agents must pass
- [ ] Summarize changes and validation

**After Handoff (Optional):**
- [ ] Type `train` to run continuous improvement workflow
- [ ] Review suggested improvements to docs/hooks/agents/memory
- [ ] Commit improvements that make sense
