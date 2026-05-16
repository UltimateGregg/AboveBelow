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

function Get-AssetNameFromBlend {
    param([string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)
    while ($name.ToLowerInvariant().EndsWith(".blend")) {
        $name = $name.Substring(0, $name.Length - ".blend".Length)
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($name)
}

function Resolve-ConfigSourceBlend {
    param([string]$ConfigPath)

    try {
        $json = Read-AgentJson -Path $ConfigPath
    }
    catch {
        return $null
    }

    if (-not ($json.PSObject.Properties.Name -contains "source_blend")) {
        return $null
    }

    $source = [string]$json.source_blend
    if ([string]::IsNullOrWhiteSpace($source) -or $source -match "\$\{") {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($source)) {
        return [System.IO.Path]::GetFullPath($source)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Root $source))
}

function Test-RelativeOutputPath {
    param(
        [string]$ConfigPath,
        [string]$Value,
        [string]$PropertyName,
        [string]$ExpectedPrefix
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Add-AgentIssue $issues "Warning" "Asset Config" $ConfigPath "Missing optional '$PropertyName'." "Most asset configs should declare target outputs explicitly."
        return
    }

    if ($Value -match "\$\{") {
        Add-AgentIssue $issues "Info" "Asset Config" $ConfigPath "$PropertyName uses variable substitution: $Value"
        return
    }

    $normalized = $Value.Replace("\", "/")
    if (-not $normalized.StartsWith($ExpectedPrefix)) {
        Add-AgentIssue $issues "Warning" "Asset Config" $ConfigPath "$PropertyName points outside expected '$ExpectedPrefix': $Value" "Keep generated assets under the normal S&Box asset folders unless this is intentional."
    }

    $full = Join-Path $Root $Value
    $parent = Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        Add-AgentIssue $issues "Error" "Asset Config" $ConfigPath "$PropertyName parent directory is missing: $parent" "Create the target directory or fix the config path."
    }
}

function Get-JsonBool {
    param(
        [object]$Json,
        [string]$Name
    )

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains $Name)) {
        return $false
    }

    return [bool]$Json.$Name
}

function Get-JsonBoolOption {
    param(
        [object]$Json,
        [string]$Name,
        [Nullable[bool]]$Default = $null
    )

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Json.$Name
    if ($null -eq $value) {
        return $Default
    }

    if ($value -is [bool]) {
        return [bool]$value
    }

    $text = ([string]$value).Trim()
    if ($text.Equals("true", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($text.Equals("false", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    return [bool]$value
}

function Get-VmdlMaterialSourceSuffix {
    param([object]$Json)

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains "vmdl_material_source_suffix")) {
        return ".vmat"
    }

    $value = $Json.vmdl_material_source_suffix
    if ($null -eq $value -or $value -eq $false) {
        return ""
    }

    $text = [string]$value
    if ($text.Equals("false", [System.StringComparison]::OrdinalIgnoreCase) -or
        $text.Equals("none", [System.StringComparison]::OrdinalIgnoreCase) -or
        $text.Equals("null", [System.StringComparison]::OrdinalIgnoreCase)) {
        return ""
    }

    return $text
}

function Get-ExpectedVmdlMaterialSource {
    param(
        [string]$SourceName,
        [string]$Suffix
    )

    if ([string]::IsNullOrWhiteSpace($Suffix)) {
        return $SourceName
    }

    if ($SourceName.EndsWith($Suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $SourceName
    }

    return "$SourceName$Suffix"
}

function Get-VmdlRemapSources {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $sources = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($raw, 'from\s*=\s*"(?<source>[^"]+)"')) {
        $sources.Add($match.Groups["source"].Value)
    }
    return @($sources)
}

function Get-VmdlUseGlobalDefault {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($raw, '(?m)\buse_global_default\s*=\s*(?<value>true|false)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups["value"].Value.Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-VmdlGlobalDefault {
    param(
        [string]$ConfigPath,
        [object]$Json
    )

    $expected = Get-JsonBoolOption -Json $Json -Name "vmdl_use_global_default"
    if ($null -eq $expected) {
        return
    }

    $targetVmdl = [string]$Json.target_vmdl
    if ([string]::IsNullOrWhiteSpace($targetVmdl) -or $targetVmdl -match "\$\{") {
        return
    }

    $targetVmdlFull = Join-Path $Root $targetVmdl
    if (-not (Test-Path -LiteralPath $targetVmdlFull)) {
        return
    }

    $actual = Get-VmdlUseGlobalDefault -Path $targetVmdlFull
    if ($null -eq $actual) {
        Add-AgentIssue $issues "Error" "VMDL Global Default" $ConfigPath "Config declares vmdl_use_global_default but generated VMDL has no use_global_default assignment." "Re-export with asset_pipeline.py so ModelDoc fallback behavior is reproducible."
        return
    }

    if ([bool]$actual -ne [bool]$expected) {
        Add-AgentIssue $issues "Error" "VMDL Global Default" $ConfigPath "Generated VMDL use_global_default is '$actual' but config expects '$expected'." "Re-export with asset_pipeline.py or update vmdl_use_global_default if this fallback is intentional."
        return
    }

    Add-AgentIssue $issues "Info" "VMDL Global Default" $ConfigPath "VMDL use_global_default matches the config."
}

function Test-VmdlMaterialSources {
    param(
        [string]$ConfigPath,
        [object]$Json
    )

    if (-not ($Json.PSObject.Properties.Name -contains "material_remap") -or $null -eq $Json.material_remap) {
        return
    }

    $hasConfiguredSourceStyle = ($Json.PSObject.Properties.Name -contains "vmdl_material_source_suffix") -or
        ($Json.PSObject.Properties.Name -contains "strict_vmdl_material_sources")
    if (-not $hasConfiguredSourceStyle) {
        return
    }

    $targetVmdl = [string]$Json.target_vmdl
    if ([string]::IsNullOrWhiteSpace($targetVmdl) -or $targetVmdl -match "\$\{") {
        return
    }

    $targetVmdlFull = Join-Path $Root $targetVmdl
    if (-not (Test-Path -LiteralPath $targetVmdlFull)) {
        return
    }

    $suffix = Get-VmdlMaterialSourceSuffix -Json $Json
    $expected = New-Object System.Collections.Generic.HashSet[string]
    foreach ($property in $Json.material_remap.PSObject.Properties) {
        [void]$expected.Add((Get-ExpectedVmdlMaterialSource -SourceName ([string]$property.Name) -Suffix $suffix))
    }

    $actual = New-Object System.Collections.Generic.HashSet[string]
    foreach ($source in @(Get-VmdlRemapSources -Path $targetVmdlFull)) {
        [void]$actual.Add($source)
    }

    $missing = @($expected | Where-Object { -not $actual.Contains($_) })
    $unexpected = @($actual | Where-Object { -not $expected.Contains($_) })
    if ($missing.Count -eq 0 -and $unexpected.Count -eq 0) {
        Add-AgentIssue $issues "Info" "VMDL Material Sources" $ConfigPath "VMDL remap sources match the configured source-name style."
        return
    }

    $strict = Get-JsonBool -Json $Json -Name "strict_vmdl_material_sources"
    $severity = if ($strict) { "Error" } else { "Warning" }
    $parts = New-Object System.Collections.Generic.List[string]
    if ($missing.Count -gt 0) {
        $parts.Add("missing expected: $($missing -join ', ')")
    }
    if ($unexpected.Count -gt 0) {
        $parts.Add("unexpected existing: $($unexpected -join ', ')")
    }

    Add-AgentIssue $issues $severity "VMDL Material Sources" $ConfigPath "Generated VMDL remap sources do not match the config ($($parts -join '; '))." "Re-export with asset_pipeline.py or set vmdl_material_source_suffix to the style S&Box actually matches for this FBX."
}

Write-AgentSection "Asset Pipeline Audit"
Write-Host "Root: $Root"

$genericConfig = Join-Path $Root "scripts\asset_pipeline_generic.json"
if (-not (Test-Path -LiteralPath $genericConfig)) {
    Add-AgentIssue $issues "Error" "Asset Pipeline" "scripts/asset_pipeline_generic.json" "Generic asset pipeline config is missing." "Restore this fallback or every .blend file needs a specific config."
}

$pipelineFiles = @(
    "scripts/smart_asset_export.ps1",
    "scripts/asset_pipeline.py",
    "scripts/scaffold_asset_config.py"
)

foreach ($path in $pipelineFiles) {
    $full = Join-Path $Root $path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-AgentIssue $issues "Error" "Asset Pipeline" $path "Required asset pipeline file is missing." "Restore the pipeline file before relying on .blend auto-export."
    }
}

$blendFiles = @(Get-AgentFiles -Root $Root -Include @("*.blend"))
foreach ($file in $blendFiles) {
    $assetName = Get-AssetNameFromBlend -Path $file.FullName
    $relative = ConvertTo-AgentRelativePath -Path $file.FullName -Root $Root
    $specific = Join-Path $Root "scripts\${assetName}_asset_pipeline.json"
    $normalizedBlend = [System.IO.Path]::GetFullPath($file.FullName)

    if (Test-Path -LiteralPath $specific) {
        Add-AgentIssue $issues "Info" "Blend Config" $relative "Uses asset-specific config scripts/${assetName}_asset_pipeline.json."
    }
    else {
        $sourceBlendConfigs = @(
            Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue |
                Where-Object {
                    $configSource = Resolve-ConfigSourceBlend -ConfigPath $_.FullName
                    $configSource -and [string]::Equals($configSource, $normalizedBlend, [System.StringComparison]::OrdinalIgnoreCase)
                }
        )

        if ($sourceBlendConfigs.Count -eq 1) {
            $configRelative = ConvertTo-AgentRelativePath -Path $sourceBlendConfigs[0].FullName -Root $Root
            Add-AgentIssue $issues "Info" "Blend Config" $relative "Uses source_blend config $configRelative."
        }
        elseif ($sourceBlendConfigs.Count -gt 1) {
            $matches = @($sourceBlendConfigs | ForEach-Object { ConvertTo-AgentRelativePath -Path $_.FullName -Root $Root }) -join ", "
            Add-AgentIssue $issues "Error" "Blend Config" $relative "Multiple configs point at this blend: $matches" "Keep only one auto-export config per .blend source or make the hook disambiguate them."
        }
        elseif (Test-Path -LiteralPath $genericConfig) {
            Add-AgentIssue $issues "Info" "Blend Config" $relative "Uses generic fallback config."
        }
        else {
            Add-AgentIssue $issues "Error" "Blend Config" $relative "No specific config and no generic fallback exist." "Add scripts/${assetName}_asset_pipeline.json or restore asset_pipeline_generic.json."
        }
    }
}

$configFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue)
$configsBySourceBlend = @{}
foreach ($config in $configFiles) {
    $sourceBlend = Resolve-ConfigSourceBlend -ConfigPath $config.FullName
    if ([string]::IsNullOrWhiteSpace($sourceBlend)) {
        continue
    }

    if (-not $configsBySourceBlend.ContainsKey($sourceBlend)) {
        $configsBySourceBlend[$sourceBlend] = New-Object System.Collections.Generic.List[string]
    }
    $configsBySourceBlend[$sourceBlend].Add((ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root))
}

foreach ($entry in $configsBySourceBlend.GetEnumerator()) {
    if ($entry.Value.Count -le 1) {
        continue
    }

    $blendRelative = ConvertTo-AgentRelativePath -Path $entry.Key -Root $Root
    Add-AgentIssue $issues "Error" "Blend Config" $blendRelative "Multiple asset pipeline configs point at the same source blend: $($entry.Value -join ', ')." "Keep one auto-export config per .blend so saving the file produces the expected asset-browser name and folder output."
}

foreach ($config in $configFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root
    try {
        $json = Read-AgentJson -Path $config.FullName
    }
    catch {
        Add-AgentIssue $issues "Error" "Asset Config" $relative $_.Exception.Message "Fix invalid JSON."
        continue
    }

    if ($json.PSObject.Properties.Name -contains "source_blend") {
        $source = [string]$json.source_blend
        if (-not [string]::IsNullOrWhiteSpace($source) -and $source -notmatch "\$\{") {
            $sourceFull = Join-Path $Root $source
            if (-not (Test-Path -LiteralPath $sourceFull)) {
                Add-AgentIssue $issues "Warning" "Asset Config" $relative "source_blend is missing on disk: $source" "Fix the config or remove stale configs."
            }
        }
    }
    else {
        Add-AgentIssue $issues "Error" "Asset Config" $relative "Missing required source_blend property." "Every asset pipeline config should name its source .blend file."
    }

    Test-RelativeOutputPath -ConfigPath $relative -Value ([string]$json.target_fbx) -PropertyName "target_fbx" -ExpectedPrefix "Assets/models/"
    Test-RelativeOutputPath -ConfigPath $relative -Value ([string]$json.target_vmdl) -PropertyName "target_vmdl" -ExpectedPrefix "Assets/models/"

    if ($json.PSObject.Properties.Name -contains "prefab") {
        Test-RelativeOutputPath -ConfigPath $relative -Value ([string]$json.prefab) -PropertyName "prefab" -ExpectedPrefix "Assets/prefabs/"
    }

    if ($json.PSObject.Properties.Name -contains "material_remap" -and $null -ne $json.material_remap) {
        foreach ($property in $json.material_remap.PSObject.Properties) {
            $target = [string]$property.Value
            if ($target -match "\$\{") {
                continue
            }
            $materialFull = Join-Path $Root ("Assets\" + $target.TrimStart("/").Replace("/", "\"))
            if ($target.Replace("\", "/").StartsWith("Assets/")) {
                $materialFull = Join-Path $Root $target
            }
            if (-not (Test-Path -LiteralPath $materialFull)) {
                Add-AgentIssue $issues "Error" "Material Remap" $relative "Material remap '$($property.Name)' points to missing material '$target'." "Create the material or fix the remap."
            }
        }
    }

    Test-VmdlMaterialSources -ConfigPath $relative -Json $json
    Test-VmdlGlobalDefault -ConfigPath $relative -Json $json
}

if ($blendFiles.Count -eq 0) {
    Add-AgentIssue $issues "Warning" "Asset Pipeline" "" "No .blend files were found." "This is unexpected for the current project layout."
}
else {
    Add-AgentIssue $issues "Info" "Asset Pipeline" "" "Checked $($blendFiles.Count) .blend file(s) and $($configFiles.Count) config file(s)."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
