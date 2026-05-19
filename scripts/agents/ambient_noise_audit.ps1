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

function Resolve-LocalSoundSource {
    param(
        [string]$Source,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Source)) {
        return $null
    }

    $normalized = $Source.Replace("\", "/").Trim().TrimStart("/")
    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $Root $normalized
    }

    if ($normalized.StartsWith("sounds/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path (Join-Path $Root "Assets") $normalized
    }

    return $null
}

function Get-SoundSources {
    param(
        [string]$SoundPath,
        [string]$Root
    )

    $resolved = Resolve-AgentResourcePath -ResourcePath $SoundPath -Root $Root
    if ($null -eq $resolved -or -not (Test-Path -LiteralPath $resolved)) {
        return @()
    }

    try {
        $json = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    }
    catch {
        return @()
    }

    if ($null -eq $json -or -not ($json.PSObject.Properties.Name -contains "Sounds")) {
        return @()
    }

    if ($json.Sounds -is [array]) {
        return @($json.Sounds)
    }

    return @($json.Sounds)
}

Write-AgentSection "Ambient Noise Audit"
Write-Host "Root: $Root"

function Add-AmbientNamedSoundRefs {
    param(
        [object[]]$Objects,
        [System.Collections.Generic.List[object]]$Refs
    )

    foreach ($object in @($Objects)) {
        $name = [string]$object.Name
        if ($name.StartsWith("Ambient", [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($component in @($object.Components)) {
                if ($component.PSObject.Properties.Name -contains "Sound" -and -not [string]::IsNullOrWhiteSpace([string]$component.Sound)) {
                    $Refs.Add([pscustomobject]@{
                        ObjectName = $name
                        Sound = [string]$component.Sound
                        Component = $component
                    })
                }
            }
        }

        if ($null -ne $object.Children) {
            Add-AmbientNamedSoundRefs -Objects @($object.Children) -Refs $Refs
        }
    }
}

$ambientRefs = New-Object System.Collections.Generic.List[object]
$scenePath = Join-Path $Root "Assets\scenes\main.scene"
if (Test-Path -LiteralPath $scenePath) {
    try {
        $sceneJson = Get-Content -LiteralPath $scenePath -Raw | ConvertFrom-Json
        Add-AmbientNamedSoundRefs -Objects @($sceneJson.GameObjects) -Refs $ambientRefs

        foreach ($ref in $ambientRefs) {
            $sound = $ref.Sound.Replace("\", "/")
            if ($sound -in @("sounds/ambient_tree_rustle.sound", "sounds/ambient_battlefield.sound")) {
                Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "Ambient emitter '$($ref.ObjectName)' references broad noise-bed SoundEvent '$sound'." "Use cleaner wind/bird ambience or author a non-hissing source before wiring it into the scene."
            }

            foreach ($source in @(Get-SoundSources -SoundPath $sound -Root $Root)) {
                $sourceText = [string]$source
                if ($sourceText.EndsWith(".mp3", [System.StringComparison]::OrdinalIgnoreCase) -and $sound -match "ambient|wind|bird") {
                    Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "Ambient emitter '$($ref.ObjectName)' uses MP3 source '$sourceText' through '$sound'." "Use a local WAV source for ambience so the sound suite can guard against broad hiss."
                }
            }

            if ($ref.ObjectName -eq "AmbientLightWind") {
                $component = $ref.Component
                $duration = 0.0
                $overlap = 0.0
                $hasDuration = $component.PSObject.Properties.Name -contains "LoopDurationSeconds"
                $hasOverlap = $component.PSObject.Properties.Name -contains "LoopOverlapSeconds"
                $parsedDuration = $hasDuration -and [double]::TryParse([string]$component.LoopDurationSeconds, [ref]$duration)
                $parsedOverlap = $hasOverlap -and [double]::TryParse([string]$component.LoopOverlapSeconds, [ref]$overlap)

                if (-not $parsedDuration -or $duration -lt 2.0) {
                    Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "AmbientLightWind does not declare a usable loop duration for overlap scheduling." "Set LoopDurationSeconds to the source WAV length so the next wind pass can start before the current one ends."
                }

                if (-not $parsedOverlap -or $overlap -lt 0.5) {
                    Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "AmbientLightWind does not overlap its loop restart enough to hide the seam." "Set LoopOverlapSeconds to at least 0.5 seconds; 1.25 seconds works well for the generated wind bed."
                }
                elseif ($parsedDuration -and $overlap -ge $duration) {
                    Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "AmbientLightWind loop overlap is not shorter than the loop duration." "Keep LoopOverlapSeconds below LoopDurationSeconds."
                }
            }
        }

        Add-AgentIssue $issues "Info" "Ambient Noise" "Assets/scenes/main.scene" "Checked $($ambientRefs.Count) AmbientSound scene emitter(s)."
    }
    catch {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "Failed to parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before auditing ambient emitters."
    }
}
else {
    Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "Main scene is missing." "Restore the main scene before auditing ambient sound sources."
}

$requiredBirdLayers = @(
    [pscustomobject]@{ ObjectName = "AmbientBirdsChirping"; Wrapper = "sounds/ambient_birds_chirping.sound"; Source = "sounds/ambient_birds_chirping.wav" },
    [pscustomobject]@{ ObjectName = "AmbientBirdsCanopyFar"; Wrapper = "sounds/ambient_birds_canopy_far.sound"; Source = "sounds/ambient_birds_canopy_far.wav" },
    [pscustomobject]@{ ObjectName = "AmbientCrowsDistant"; Wrapper = "sounds/ambient_crows_distant.sound"; Source = "sounds/ambient_crows_distant.wav" }
)

foreach ($layer in $requiredBirdLayers) {
    $sources = @(Get-SoundSources -SoundPath $layer.Wrapper -Root $Root)
    $normalizedSources = @($sources | ForEach-Object { ([string]$_).Replace("\", "/") })
    if ($normalizedSources -notcontains $layer.Source) {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/sounds/$($layer.Wrapper.Substring(7))" "Bird ambience layer '$($layer.Wrapper)' does not use guarded local WAV source '$($layer.Source)'." "Point the SoundEvent at the expected local WAV source."
    }

    $sourcePath = Resolve-LocalSoundSource -Source $layer.Source -Root $Root
    if ($null -eq $sourcePath -or -not (Test-Path -LiteralPath $sourcePath)) {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/sounds/$($layer.Source.Substring(7))" "Bird ambience source '$($layer.Source)' is missing." "Run scripts/audio/generate_project_sounds.py after updating the bird builders."
    }

    $sceneMatch = @($ambientRefs | Where-Object {
        ([string]$_.ObjectName) -eq $layer.ObjectName -and ([string]$_.Sound).Replace("\", "/") -eq $layer.Wrapper
    })
    if ($sceneMatch.Count -eq 0) {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/scenes/main.scene" "Missing bird ambience emitter '$($layer.ObjectName)' for '$($layer.Wrapper)'." "Keep the bird ambience spatially layered with local SoundEvent wrappers."
    }
}

$windWrapper = Join-Path $Root "Assets\sounds\ambient_light_wind.sound"
if (Test-Path -LiteralPath $windWrapper) {
    $sources = @(Get-SoundSources -SoundPath "sounds/ambient_light_wind.sound" -Root $Root)
    if ($sources -notcontains "sounds/ambient_light_wind.wav") {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/sounds/ambient_light_wind.sound" "Wind ambience does not use the guarded local WAV source." "Point the SoundEvent at sounds/ambient_light_wind.wav."
    }

    $windSource = Join-Path $Root "Assets\sounds\ambient_light_wind.wav"
    if (-not (Test-Path -LiteralPath $windSource)) {
        Add-AgentIssue $issues "Error" "Ambient Noise" "Assets/sounds/ambient_light_wind.wav" "Guarded wind WAV source is missing." "Regenerate project sounds after adding the clean wind builder."
    }
}

$generatorPath = Join-Path $Root "scripts\audio\generate_project_sounds.py"
if (Test-Path -LiteralPath $generatorPath) {
    $generatorText = Get-Content -LiteralPath $generatorPath -Raw
    if ($generatorText -notmatch '"ambient_light_wind\.wav"\s*:\s*ambient_light_wind') {
        Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Generator does not own a local ambient_light_wind.wav builder." "Keep wind ambience reproducible instead of depending on the broad stock MP3 source."
    }

    if ($generatorText -match '"ambient_light_wind\.mp3"\s*:') {
        Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Generator still imports the stock ambient_light_wind.mp3 source." "Remove the stock MP3 import for scene ambience."
    }

    foreach ($name in @("ambient_birds_chirping", "ambient_birds_canopy_far", "ambient_crows_distant")) {
        if ($generatorText -notmatch "def\s+$name\s*\(\)\s*->\s*list\[float\]:") {
            Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Generator is missing bird ambience builder '$name'." "Keep near, far-canopy, and distant-crow bird layers reproducible."
        }
    }

    foreach ($wavName in @("ambient_birds_chirping.wav", "ambient_birds_canopy_far.wav", "ambient_crows_distant.wav")) {
        $escapedName = [regex]::Escape($wavName)
        if ($generatorText -notmatch "`"$escapedName`"\s*:") {
            Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Generator SOUNDS map is missing '$wavName'." "Add the WAV to SOUNDS so regeneration keeps all bird layers current."
        }
    }

    if ($generatorText -match 'def\s+add_bird_chirp\s*\(') {
        Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Generator still contains the old simple add_bird_chirp helper." "Use varied phrase builders so bird ambience does not regress to a short beep-like loop."
    }

    $birdMatch = [regex]::Match($generatorText, 'def\s+ambient_birds_chirping\s*\(\)\s*->\s*list\[float\]:[\s\S]*?(?=\r?\ndef\s+|\r?\nSOUNDS\s*=)')
    if ($birdMatch.Success -and $birdMatch.Value -match 'add_filtered_noise\(\s*b\s*,\s*0\.0\s*,\s*duration') {
        Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Bird ambience still contains a continuous synthetic noise bed." "Keep chirps, but remove the always-on noise layer."
    }
    if ($birdMatch.Success) {
        $durationMatch = [regex]::Match($birdMatch.Value, 'duration\s*=\s*(?<value>\d+(?:\.\d+)?)')
        if ($durationMatch.Success -and [double]$durationMatch.Groups["value"].Value -lt 24.0) {
            Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Near bird ambience loop is shorter than 24 seconds." "Use a longer phrase sequence so bird calls do not repeat obviously."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Sound generator is missing." "Restore the generator so local ambience sources are reproducible."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
