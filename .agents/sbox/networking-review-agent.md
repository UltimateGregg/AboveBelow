# Networking Review Agent

## Purpose

Review multiplayer-sensitive changes for host authority, replication, RPC semantics, and ownership.

## Primary Areas

- `Code/Game/`
- `Code/Player/`
- `Code/Drone/`
- `Code/Equipment/`

## Review Rules

- Host applies game state changes.
- Clients may request or display, but should not authoritatively mutate health, round state, jam state, team membership, ammo, or spawned gameplay objects.
- Runtime replicated state should use `[Sync]`.
- Broadcast RPCs should be notifications or must guard host-only mutation with `Networking.IsHost`.
- `NetworkSpawn(connection)` or equivalent owner assignment is required for player-owned pawns and drones.
- Validate any new RPC parameters for range, cooldown, and ownership.
- Static audit warnings are prompts for inspection, not automatic proof of a bug.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

## Output Shape

Lead with concrete authority risks. For each risk, state whether it is a confirmed bug or a static-analysis prompt that needs manual review.
