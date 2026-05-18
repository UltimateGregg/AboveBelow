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
                    })
                }
            }
        }

        if ($null -ne $object.Children) {
            Add-AmbientNamedSoundRefs -Objects @($object.Children) -Refs $Refs
        }
    }
}

$scenePath = Join-Path $Root "Assets\scenes\main.scene"
if (Test-Path -LiteralPath $scenePath) {
    try {
        $sceneJson = Get-Content -LiteralPath $scenePath -Raw | ConvertFrom-Json
        $ambientRefs = New-Object System.Collections.Generic.List[object]
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

    $birdMatch = [regex]::Match($generatorText, 'def\s+ambient_birds_chirping\s*\(\)\s*->\s*list\[float\]:[\s\S]*?(?=\r?\ndef\s+|\r?\nSOUNDS\s*=)')
    if ($birdMatch.Success -and $birdMatch.Value -match 'add_filtered_noise\(\s*b\s*,\s*0\.0\s*,\s*duration') {
        Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Bird ambience still contains a continuous synthetic noise bed." "Keep chirps, but remove the always-on noise layer."
    }
}
else {
    Add-AgentIssue $issues "Error" "Ambient Noise" "scripts/audio/generate_project_sounds.py" "Sound generator is missing." "Restore the generator so local ambience sources are reproducible."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
