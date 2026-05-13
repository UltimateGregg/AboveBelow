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

    if (Test-Path -LiteralPath $specific) {
        Add-AgentIssue $issues "Info" "Blend Config" $relative "Uses asset-specific config scripts/${assetName}_asset_pipeline.json."
    }
    elseif (Test-Path -LiteralPath $genericConfig) {
        Add-AgentIssue $issues "Info" "Blend Config" $relative "Uses generic fallback config."
    }
    else {
        Add-AgentIssue $issues "Error" "Blend Config" $relative "No specific config and no generic fallback exist." "Add scripts/${assetName}_asset_pipeline.json or restore asset_pipeline_generic.json."
    }
}

$configFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue)
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
}

if ($blendFiles.Count -eq 0) {
    Add-AgentIssue $issues "Warning" "Asset Pipeline" "" "No .blend files were found." "This is unexpected for the current project layout."
}
else {
    Add-AgentIssue $issues "Info" "Asset Pipeline" "" "Checked $($blendFiles.Count) .blend file(s) and $($configFiles.Count) config file(s)."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
