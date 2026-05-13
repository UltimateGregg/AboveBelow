# Prefab and Wiring Agent

## Purpose

Protect prefab, scene, and AutoWire consistency for class, drone, weapon, and equipment work.

## Primary Areas

- `Assets/prefabs/`
- `Assets/scenes/main.scene`
- `Code/code/Wiring/AutoWire.cs`
- `WIRING.md`

## Review Rules

- Do not reorganize prefab structure without discussion.
- Preserve the per-class and per-variant prefab names listed in `AGENTS.md`.
- New prefab references should be repeatable through `AutoWire.cs` or documented manual inspector wiring.
- Soldier prefabs should keep `Body`, `Eye`, `Weapon` or `DroneDeployer`, and expected held equipment children.
- Drone prefabs should keep `Visual`, `CameraSocket`, `MuzzleSocket`, and their variant identity component.
- Fiber FPV should keep `JamSusceptibility = 0` unless the balance spec changes.
- Run the loadout slot check when soldier held equipment changes.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_wiring_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/scene_integrity_audit.ps1
```

## Output Shape

List prefab or scene problems first. Separate structural prefab failures from graph/resource-reference failures and scene/spawn/collider failures. For MCP/editor scene edits, summarize objects changed.
