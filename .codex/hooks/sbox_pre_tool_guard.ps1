$ErrorActionPreference = "Stop"

$stdin = [Console]::In.ReadToEnd()

try {
    $payload = if ([string]::IsNullOrWhiteSpace($stdin)) { $null } else { $stdin | ConvertFrom-Json }
} catch {
    exit 0
}

function Get-ToolCommand {
    param($Payload)

    if ($null -eq $Payload -or $null -eq $Payload.tool_input) {
        return ""
    }

    if ($Payload.tool_input -is [string]) {
        return $Payload.tool_input
    }

    if ($Payload.tool_input.PSObject.Properties.Name -contains "command") {
        return [string]$Payload.tool_input.command
    }

    return ($Payload.tool_input | ConvertTo-Json -Depth 32 -Compress)
}

function Deny-ToolUse {
    param([string]$Reason)

    $response = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $Reason
        }
    }

    $response | ConvertTo-Json -Depth 10 -Compress
    exit 0
}

$command = Get-ToolCommand -Payload $payload

if ([string]::IsNullOrWhiteSpace($command)) {
    exit 0
}

$denyRules = @(
    @{
        Pattern = '(?i)\bgit\s+reset\s+--hard\b'
        Reason = 'Blocked git reset --hard. The S&Box worktree is shared and may contain user changes.'
    },
    @{
        Pattern = '(?i)\bgit\s+clean\b'
        Reason = 'Blocked git clean. Review untracked files explicitly before deleting generated or user-created assets.'
    },
    @{
        Pattern = '(?i)\bgit\s+checkout\s+--(?=$|\s)'
        Reason = 'Blocked git checkout --. Reverting paths requires an explicit user instruction.'
    },
    @{
        Pattern = '(?i)\bgit\s+restore\s+(\.|:\/|--source|--worktree|--staged|\S+)'
        Reason = 'Blocked git restore. Reverting paths requires an explicit user instruction.'
    },
    @{
        Pattern = '(?i)\bRemove-Item\b(?=.*(?:^|\s)-Recurse(?:\s|$))'
        Reason = 'Blocked recursive Remove-Item. Confirm the exact target before deleting project files.'
    },
    @{
        Pattern = '(?i)(^|[\s;&|])rm\s+-[A-Za-z]*r[A-Za-z]*\b'
        Reason = 'Blocked recursive rm. Confirm the exact target before deleting project files.'
    },
    @{
        Pattern = '(?i)(^|[\s;&|])del\s+\/[A-Za-z]*[sq][A-Za-z]*\b'
        Reason = 'Blocked recursive/quiet del. Confirm the exact target before deleting project files.'
    }
)

foreach ($rule in $denyRules) {
    if ($command -match $rule.Pattern) {
        Deny-ToolUse -Reason $rule.Reason
    }
}

exit 0
