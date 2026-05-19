# Training Workflow

This project supports continuous self-improvement through automated training runs. After completing tasks, you can request training to identify patterns and make durable improvements to workflows, documentation, and automation.

## How It Works

**User triggers training by simply typing: `train`**

Claude Code will:
1. Run the training agent suite: `scripts/agents/run_agent_checks.ps1 -Suite train`
2. Inspect outputs to understand what changed and what patterns emerged
3. Identify durable improvements across these categories:
   - Documentation updates (CLAUDE.md, AGENTS.md, docs/)
   - Hook configuration improvements (.claude/settings.json)
   - Agent/script updates and new agent creation
   - Workflow/routing documentation (docs/claude_workflow_quick_ref.md)
   - Memory capture of new patterns and lessons learned
4. Apply improvements immediately (where feasible)
5. Summarize what was learned and what still needs human review

## What the Training Suite Checks

The `train` suite runs comprehensive audits:
- **Build & compile state**: Fresh compile, new errors/warnings
- **Gameplay regressions**: Drone control, loadout, slot system
- **Prefab wiring**: Component references, AutoWire conventions
- **Scene integrity**: Managers, spawns, collision patterns
- **Networking**: Authority, replication, RPC patterns
- **Asset pipeline**: Blend configs, VMDL outputs, material remaps
- **UI flows**: Interactive elements, click behavior
- **Documentation drift**: Docs vs code mismatch
- **Memory coverage**: Patterns that should be captured

## Typical Training Outcomes

### Documentation Updates
- If gameplay behavior changed, update CLAUDE.md with new details
- If a new pattern emerged, add it to docs/known_sbox_patterns.md
- If agent routing changed, update docs/claude_workflow_quick_ref.md

### Hook/Agent Improvements
- Add new hooks for auto-validation if a change type is detected repeatedly
- Create new focused agents if a validation gap is found
- Update .claude/settings.json trigger patterns based on file change patterns

### Memory Capture
- Capture new patterns discovered during the task (e.g., "drone physics behaves X way when Y")
- Document new tooling constraints or workarounds
- Link related memories together

### Workflow Documentation
- Expand agent routing guide if new change type patterns emerge
- Add new clarifying questions if planning gaps are identified
- Update exit criteria if new validation needs are discovered

## When to Train

- **After completing any substantial task** (gameplay, prefab, asset, networking, etc.)
- **When experiencing repeated issues** in a particular area (suggests new pattern to capture)
- **Before major feature work** (snapshot current state, establish baseline)
- **After discovering a new tool/script/pattern** (generalize it for reuse)

## What Gets Improved vs. What Doesn't

### Improved by Training (Durable Workflow Improvements)
- Documentation that guides future work (CLAUDE.md sections, AGENTS.md, docs/)
- Hooks that prevent regressions (auto-validation on file saves)
- Agent scripts that catch issues (new agents, improved existing agents)
- Memory capture of patterns and lessons
- Workflow routing (which agents to run when)

### NOT Improved by Training (Product-Specific Code)
- Gameplay logic (weapon balance, drone behavior, etc.)
- Scene content (spawns, prefabs, assets, etc.)
- UI implementation (HUD panels, menus, etc.)
- Networking code (RPCs, sync properties, etc.)

Training focuses on **workflow, automation, and documentation** that helps future tasks, not on continuing product development.

## Example Training Session

```
User: [completes a drone weapon task]
User: train

Claude:
1. Runs: scripts/agents/run_agent_checks.ps1 -Suite train
2. Discovers: Drone weapon tests now need validation in 3 new areas
3. Actions taken:
   - Updated docs/claude_workflow_quick_ref.md with new "Drone Weapon Changes" agent routing
   - Created memory file: "drone_weapon_testing_pattern.md"
   - Updated .claude/settings.json hook to add new drone weapon files to regression check
   - Added new clarifying questions to docs/claude_workflow_quick_ref.md for drone weapon bugs
4. Summary:
   - Updated 3 docs, created 1 memory file, modified 1 hook config
   - New drone weapon test pattern now documented and automated
   - Validation gap for drone reload mechanics identified for next time
```

## Training Output Summary

After training completes, you'll see:
- **Files updated**: Which docs, hooks, agents, or memory files changed
- **New patterns discovered**: What durable improvements were made
- **Validation gaps**: What still needs manual review or testing
- **Next steps**: Suggestions for further improvements (if any)

## Technical Details

The training suite is powered by:
- **Build Sentinel**: Detects new compile errors/warnings
- **Gameplay Regression Guard**: Validates game logic still works
- **Prefab/Scene/Networking Audits**: Checks for architecture drift
- **Asset Pipeline Audit**: Validates model/material/config consistency
- **UI Flow Audit**: Ensures interactive elements are wired
- **Docs Audit**: Compares documentation to code
- **Feature Readiness Report**: Maps changed files to required validation

Each audit returns findings categorized as `Error`, `Warning`, or `Info`. Training uses these to identify patterns.

## Tips for Effective Training

1. **Train after complete features**, not mid-task. It's more useful to look at finished work.
2. **Describe what you're training on**: "train after adding the new jammer grenade variant" helps context
3. **Run training after significant refactoring**: Patterns often emerge when code structure changes
4. **Don't skip manual review**: Training identifies improvements but you should review them before committing
5. **Save training insights to memory**: If you discover why a pattern worked, capture it for future reference

## Limitations

- Training is static analysis + audit scripts, not runtime validation
- It cannot test gameplay without an editor playtest first
- It cannot verify multiplayer behavior without a live session
- Memory file creation is automated but should be human-reviewed before committing
- Hook creation is suggested but requires JSON validation before enabling

For runtime validation, pair training output with editor playtests and multiplayer sessions.
