# Post-Task Training Agent

## Purpose

Turn lessons from the just-finished task into durable workflow improvements with minimal user involvement.

This agent does not edit gameplay, assets, or scenes. It inspects the recent goal, changed files, existing docs, hooks, agents, pipelines, and validation suites, then points Codex at the workflow surfaces that should be updated before the next similar task.

## Default Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite train
```

Direct script form:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/post_task_training_agent.ps1 -ShowFiles -WriteReport
```

The report is written to `.tmpbuild/post-task-training-report.md` when `-WriteReport` is supplied.

## When To Use

- When the user types exactly `train`.
- After a completed task that revealed a missed check, repeated mistake, weak handoff, or manual workflow step.
- After adding or changing hooks, agents, subagents, pipelines, validation scripts, or project instructions.
- Before ending a long session if the next agent would benefit from updated routing or documentation.

## Review Rules

- Focus on reusable workflow improvements, not task-specific product edits.
- Prefer adding or tightening a focused audit over broad instructions.
- For Blender/modeling goals, favor durable quality gates such as asset briefs, reference requirements, material/texture checks, preview/contact-sheet proof, ModelDoc/FBX validation, and S&Box editor proof routing.
- Put recurring checks in three places when they are meant to stick:
  - `scripts/agents/run_agent_checks.ps1`
  - `scripts/agents/test_full_automation_layer.ps1`
  - human-facing docs such as `docs/agent_toolkit.md`, `.agents/sbox/README.md`, `AGENTS.md`, or `docs/known_sbox_patterns.md`
- Keep gameplay, UI, prefab/scene, asset, networking, and tooling changes as separate phases.
- Do not claim runtime validation from this agent. It is a workflow-training pass, not an editor playtest.

## Output Shape

The training pass should leave Codex with:

- Changed-file areas that matter for future workflow.
- Checks that should be run for similar work.
- Missing suite/doc/self-test wiring.
- A concise report of durable workflow changes made or still recommended.
