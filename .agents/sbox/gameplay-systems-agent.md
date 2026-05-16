# Gameplay Systems Agent

## Purpose

Review gameplay code changes for correctness, scope, and fit with the existing ABOVE / BELOW architecture.

## Primary Areas

- `Code/Game/`
- `Code/Player/`
- `Code/Drone/`
- `Code/Equipment/`
- `Code/Common/`

## Review Rules

- Keep gameplay logic out of UI panels and editor tooling.
- Prefer composition over deep inheritance.
- Do not unseal existing sealed gameplay classes unless there is no smaller alternative.
- Do not rewrite gameplay systems to implement visual-only requests.
- Keep host-side state mutations behind `Networking.IsHost` or an existing `CanMutateState()` pattern.
- Do not spawn networked gameplay objects without `NetworkSpawn()`.
- Use existing components such as `Health`, `JammingReceiver`, `PilotLink`, `DroneController`, and `GroundPlayerController` before adding new systems.
- Keep pilot ground controls and drone-view controls distinct. Ground-side LMB launches the selected drone, then a second ground-side LMB or `F` enters drone control; kamikaze detonation belongs to the drone-view primary action.
- Keep new public methods documented with XML comments when they become part of the project API.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/gameplay_regression_guard.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/networking_review_audit.ps1
```

## Output Shape

Start with blocking issues. Include file paths and line numbers where possible. End with the exact verification commands run and any editor/playtest gaps.
