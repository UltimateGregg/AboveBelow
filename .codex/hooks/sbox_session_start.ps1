$ErrorActionPreference = "Stop"

Write-Output @"
S&Box project context loaded by .codex/hooks/sbox_session_start.ps1:
- Keep gameplay, UI, editor tooling, prefab, and networking changes in separate phases.
- Do not rename public S&Box classes, components, prefabs, or assets unless the user asks.
- Treat networked gameplay as host-authoritative; use [Sync] properties or RPCs for replicated state.
- After meaningful C# or scene/prefab edits, check compile/editor errors before handing off.
- The worktree may be dirty; never reset, clean, or revert user changes without an explicit instruction.
"@
