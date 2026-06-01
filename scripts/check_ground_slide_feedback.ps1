param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]

function Read-ProjectFile {
    param([string]$Path)

    $fullPath = Join-Path $Root $Path
    if (!(Test-Path -LiteralPath $fullPath)) {
        $failures.Add("Missing file: $Path")
        return ""
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Require-Match {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Pattern
    )

    if (![regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Label)
    }
}

$controller = Read-ProjectFile "Code/Player/GroundPlayerController.cs"

Require-Match "GroundPlayerController should expose a 1.5x slide speed multiplier." `
    $controller "SlideSpeedMultiplier\s*\{\s*get;\s*set;\s*\}\s*=\s*1\.5f"

Require-Match "GroundPlayerController should expose a slide SoundEvent." `
    $controller "\[Property\]\s+public\s+SoundEvent\s+SlideSound\s*\{\s*get;\s*set;\s*\}"

Require-Match "GroundPlayerController should keep a local slide sound fallback path." `
    $controller 'DefaultSlideSoundPath\s*=\s*"sounds/slide_scrape\.sound"'

Require-Match "Slide entry should apply both the existing initial boost and the new slide speed multiplier." `
    $controller "horizVel\.Length\s*\*\s*SlideInitialBoost\s*\*\s*SlideSpeedMultiplier"

Require-Match "Slide entry should broadcast a slide-start sound." `
    $controller "IsSliding\s*=\s*true[\s\S]{0,340}BroadcastSlideStarted\(\)"

Require-Match "Slide-start broadcast should play the configured slide SoundEvent." `
    $controller "\[Rpc\.Broadcast\]\s*void\s+BroadcastSlideStarted\(\)[\s\S]{0,360}SlideSound[\s\S]{0,280}(SoundPlayback\.PlayAttached|Sound\.Play)"

Require-Match "Slide-start broadcast should fall back to the local slide SoundEvent path." `
    $controller "BroadcastSlideStarted\(\)[\s\S]{0,420}Sound\.Play\(\s*DefaultSlideSoundPath\s*,\s*WorldPosition\s*\)"

$soundEvent = Read-ProjectFile "Assets/sounds/slide_scrape.sound"
Require-Match "Slide SoundEvent wrapper should reference the local slide scrape WAV." `
    $soundEvent '"Sounds"\s*:\s*\[\s*"sounds/slide_scrape\.wav"\s*\]'

$slideWav = Join-Path $Root "Assets/sounds/slide_scrape.wav"
if (!(Test-Path -LiteralPath $slideWav)) {
    $failures.Add("Missing generated slide scrape WAV: Assets/sounds/slide_scrape.wav")
}

foreach ($prefab in @(
    "Assets/prefabs/soldier.prefab",
    "Assets/prefabs/soldier_assault.prefab",
    "Assets/prefabs/soldier_counter_uav.prefab",
    "Assets/prefabs/soldier_heavy.prefab",
    "Assets/prefabs/pilot_ground.prefab"
)) {
    $text = Read-ProjectFile $prefab
    Require-Match "$prefab should wire SlideSound to the local slide SoundEvent." `
        $text '"SlideSound"\s*:\s*"sounds/slide_scrape\.sound"'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Ground slide feedback check passed."
