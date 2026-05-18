param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

function Get-ProjectText {
    param([string]$RelativePath)

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Sound Playback" $RelativePath "Expected source file is missing." "Restore the file or update this audit if the audio owner moved."
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Remove-AllowedSoundPlay {
    param(
        [string]$Text,
        [string[]]$AllowedPatterns
    )

    $result = $Text
    foreach ($pattern in $AllowedPatterns) {
        $result = [regex]::Replace($result, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }

    return $result
}

Write-AgentSection "Sound Playback Audit"
Write-Host "Root: $Root"

$helperText = Get-ProjectText "Code/Common/SoundPlayback.cs"
if ($null -eq $helperText) {
    Add-AgentIssue $issues "Error" "Sound Playback" "Code/Common/SoundPlayback.cs" "No shared helper exists for attaching player-owned sounds." "Add a helper that parents held-item audio handles to the weapon or player GameObject."
}
else {
    foreach ($required in @("PlayAttached", "SoundHandle", ".Parent", ".Position")) {
        if ($helperText -notmatch [regex]::Escape($required)) {
            Add-AgentIssue $issues "Error" "Sound Playback" "Code/Common/SoundPlayback.cs" "Sound playback helper is missing '$required'." "Keep attached player-owned sounds parented and positioned through the shared helper."
        }
    }
}

$ownedSoundFiles = @(
    @{
        Path = "Code/Player/HitscanWeapon.cs"
        Allowed = @(
            'Sound\.Play\(\s*FireSoundFirstPerson\s*\)',
            'Sound\.Play\(\s*"sounds/bullet_whip\.sound"\s*,\s*closest\s*\)'
        )
    },
    @{
        Path = "Code/Player/ShotgunWeapon.cs"
        Allowed = @()
    },
    @{
        Path = "Code/Drone/DroneWeapon.cs"
        Allowed = @()
    },
    @{
        Path = "Code/Player/DroneJammerGun.cs"
        Allowed = @()
    },
    @{
        Path = "Code/Equipment/ThrowableGrenade.cs"
        Allowed = @(
            'Sound\.Play\(\s*DetonateSound\s*,\s*position\s*\)'
        )
    }
)

foreach ($entry in $ownedSoundFiles) {
    $text = Get-ProjectText $entry.Path
    if ($null -eq $text) {
        continue
    }

    $checkedText = Remove-AllowedSoundPlay -Text $text -AllowedPatterns $entry.Allowed
    if ($checkedText -match 'Sound\.Play\s*\(') {
        Add-AgentIssue $issues "Error" "Sound Playback" $entry.Path "Held-item/player-owned audio still calls Sound.Play directly." "Route the cue through SoundPlayback.PlayAttached so muzzle, reload, loop, and throw sounds follow their owning object instead of being stranded at an old world position."
    }
}

Add-AgentIssue $issues "Info" "Sound Playback" "" "Checked held-item/player-owned sound playback sites for attached playback routing."
Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
