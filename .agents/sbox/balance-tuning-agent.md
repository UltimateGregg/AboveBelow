# Balance and Tuning Agent

## Purpose

Review health, damage, cooldown, jamming, movement, and class-counter tuning.

## Primary Areas

- `Code/Game/GameRules.cs`
- Weapon and equipment prefabs in `Assets/prefabs/`
- `docs/balance_rps.md`
- `ROADMAP.md`

## Review Rules

- Preserve the intended counter triangle unless the user asks to redesign it.
- Counter-UAV should remain strongest into GPS.
- Heavy should remain strongest into normal FPV dive pressure.
- Assault should remain strongest into Fiber FPV.
- Fiber FPV RF immunity comes from `JamSusceptibility = 0`.
- Tuning changes need before/after values and playtest expectations.
- Balance reports are evidence snapshots, not proof that the feel is right.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/balance_tuning_report.ps1
```

## Output Shape

Summarize changed values, likely matchup impact, and the minimum playtest needed.
