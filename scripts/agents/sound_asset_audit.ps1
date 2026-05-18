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

function Resolve-SoundResourcePath {
    param(
        [string]$ResourcePath,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
        return $null
    }

    $normalized = $ResourcePath.Replace("\", "/").Trim().TrimStart("/")
    if ($normalized -match "^(https?:|file:|asset:)" -or $normalized -match "\$\{") {
        return $null
    }

    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $Root $normalized
    }

    if ($normalized.StartsWith("sounds/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path (Join-Path $Root "Assets") $normalized
    }

    return $null
}

function Resolve-LocalSoundEventPath {
    param(
        [string]$ResourcePath,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
        return $null
    }

    $normalized = $ResourcePath.Replace("\", "/").Trim().TrimStart("/")
    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $Root $normalized
    }

    if ($normalized.StartsWith("sounds/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path (Join-Path $Root "Assets") $normalized
    }

    return $null
}

function Get-SoundJsonArray {
    param(
        [object]$Json,
        [string]$PropertyName
    )

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains $PropertyName)) {
        return @()
    }

    $value = $Json.$PropertyName
    if ($null -eq $value) {
        return @()
    }

    if ($value -is [array]) {
        return @($value)
    }

    return @($value)
}

function Get-SoundLiteralReferences {
    param([string]$Root)

    $patterns = @("*.cs", "*.prefab", "*.scene")
    $files = Get-AgentFiles -Root $Root -Include $patterns
    $references = @()
    $soundRefPattern = '(?<![\w./-])(?<sound>(?:Assets/)?(?:sounds|sound|gameplay|weapons|items|killstreaks|resources)/[^"''\s,;)]*?\.sound)'

    foreach ($file in $files) {
        $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
        $text = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($match in [regex]::Matches($text, $soundRefPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $references += [pscustomobject]@{
                Path = $relative
                Sound = $match.Groups["sound"].Value.Replace("\", "/")
            }
        }
    }

    return $references
}

Write-AgentSection "Sound Asset Audit"
Write-Host "Root: $Root"

$soundRoot = Join-Path $Root "Assets\sounds"
if (-not (Test-Path -LiteralPath $soundRoot)) {
    Add-AgentIssue $issues "Error" "Sound Assets" "Assets/sounds" "Project has no Assets/sounds directory." "Create Assets/sounds and store SoundEvent wrappers there."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$soundFiles = @(Get-ChildItem -LiteralPath $soundRoot -Recurse -File -Filter "*.sound" -ErrorAction SilentlyContinue)
$sourceExtensions = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
@(".wav", ".mp3", ".ogg", ".flac", ".vsnd") | ForEach-Object { $sourceExtensions.Add($_) | Out-Null }
$compiledExtensions = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
@(".sound_c", ".vsnd_c") | ForEach-Object { $compiledExtensions.Add($_) | Out-Null }

$allSoundFiles = @(Get-ChildItem -LiteralPath $soundRoot -Recurse -File -ErrorAction SilentlyContinue)
$sourceFiles = @($allSoundFiles | Where-Object { $sourceExtensions.Contains($_.Extension) })
$compiledFiles = @($allSoundFiles | Where-Object { $_.Name.EndsWith(".sound_c", [System.StringComparison]::OrdinalIgnoreCase) -or $_.Name.EndsWith(".vsnd_c", [System.StringComparison]::OrdinalIgnoreCase) })
$referencedSourcePaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$soundEventsChecked = 0
$sourceReferencesChecked = 0
$directMountedReferences = 0

foreach ($soundFile in $soundFiles) {
    $soundEventsChecked++
    $relative = ConvertTo-AgentRelativePath -Path $soundFile.FullName -Root $Root

    try {
        $json = Get-Content -LiteralPath $soundFile.FullName -Raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Error" "Sound Event" $relative "Failed to parse .sound JSON: $($_.Exception.Message)" "Fix invalid SoundEvent JSON before the editor imports it."
        continue
    }

    $sounds = @(Get-SoundJsonArray -Json $json -PropertyName "Sounds")
    if ($sounds.Count -eq 0) {
        Add-AgentIssue $issues "Error" "Sound Event" $relative "SoundEvent has no source audio in its Sounds array." "Add at least one project audio source such as sounds/example.wav."
    }

    foreach ($source in $sounds) {
        $sourceText = [string]$source
        $sourceReferencesChecked++
        if ([string]::IsNullOrWhiteSpace($sourceText)) {
            Add-AgentIssue $issues "Error" "Sound Event" $relative "SoundEvent contains a blank source audio entry." "Remove the blank entry or assign a real source file."
            continue
        }

        $resolved = Resolve-SoundResourcePath -ResourcePath $sourceText -Root $Root
        if ($null -eq $resolved) {
            Add-AgentIssue $issues "Warning" "Sound Event" $relative "Source audio '$sourceText' could not be resolved as a local project resource." "Use a project resource path such as sounds/example.wav; import stock audio into Assets/sounds before wiring gameplay wrappers."
            continue
        }

        if (Test-Path -LiteralPath $resolved) {
            $referencedSourcePaths.Add((Resolve-Path -LiteralPath $resolved).Path) | Out-Null
        }
        else {
            $parent = Split-Path $resolved -Parent
            $parentResolved = Resolve-Path -LiteralPath $parent -ErrorAction SilentlyContinue
            if ($null -ne $parentResolved) {
                $referencedSourcePaths.Add((Join-Path $parentResolved.Path (Split-Path $resolved -Leaf))) | Out-Null
            }
        }

        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-AgentIssue $issues "Error" "Sound Event" $relative "Source audio '$sourceText' is missing." "Create the source file or update the Sounds entry."
        }
    }

    $isUi = $false
    if ($json.PSObject.Properties.Name -contains "UI") {
        $isUi = [bool]$json.UI
    }

    if (-not $isUi) {
        if (-not ($json.PSObject.Properties.Name -contains "DistanceAttenuation")) {
            Add-AgentIssue $issues "Warning" "Sound Event" $relative "3D SoundEvent does not declare DistanceAttenuation." "Set DistanceAttenuation explicitly so editor previews match playtest expectations."
        }
        if (-not ($json.PSObject.Properties.Name -contains "Distance")) {
            Add-AgentIssue $issues "Warning" "Sound Event" $relative "3D SoundEvent does not declare Distance." "Set Distance to the intended audible range."
        }
    }

    if ($json.PSObject.Properties.Name -contains "Volume") {
        $volumeText = [string]$json.Volume
        $volume = 0.0
        if ([double]::TryParse($volumeText, [ref]$volume) -and ($volume -lt 0 -or $volume -gt 2)) {
            Add-AgentIssue $issues "Warning" "Sound Event" $relative "Volume '$volumeText' is outside the expected 0..2 authoring range." "Check whether this needs a mixer/decibel adjustment instead."
        }
    }
}

foreach ($sourceFile in $sourceFiles) {
    $full = (Resolve-Path -LiteralPath $sourceFile.FullName).Path
    if (-not $referencedSourcePaths.Contains($full)) {
        $relative = ConvertTo-AgentRelativePath -Path $sourceFile.FullName -Root $Root
        Add-AgentIssue $issues "Warning" "Raw Audio" $relative "Raw audio source is not referenced by any local .sound wrapper." "Create or update a matching .sound file; S&Box gameplay should reference the .sound wrapper, not raw audio."
    }
}

$literalReferences = @(Get-SoundLiteralReferences -Root $Root)
$literalCount = 0
foreach ($reference in $literalReferences) {
    $literalCount++
    $resolved = Resolve-LocalSoundEventPath -ResourcePath $reference.Sound -Root $Root
    if ($null -eq $resolved) {
        $directMountedReferences++
        Add-AgentIssue $issues "Error" "Sound Reference" $reference.Path "Direct mounted SoundEvent reference '$($reference.Sound)' is not runtime-safe for this project." "Import or copy the source audio into Assets/sounds, wrap it in a local .sound file, and reference sounds/example.sound from gameplay code, prefabs, and scenes."
        continue
    }

    if (-not (Test-Path -LiteralPath $resolved)) {
        Add-AgentIssue $issues "Error" "Sound Reference" $reference.Path "References missing local SoundEvent '$($reference.Sound)'." "Create the .sound wrapper under Assets/sounds or update the reference."
    }
}

Add-AgentIssue $issues "Info" "Sound Assets" "" "Checked $soundEventsChecked local SoundEvent wrapper(s), $sourceReferencesChecked source audio reference(s), $($sourceFiles.Count) raw source file(s), $literalCount code/prefab/scene SoundEvent reference(s), $directMountedReferences direct mounted SoundEvent reference(s), and $($compiledFiles.Count) compiled sound cache file(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
