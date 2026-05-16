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

function Get-ModelDocAssignments {
    param(
        [string]$Raw,
        [string]$Name
    )

    $values = New-Object System.Collections.Generic.List[string]
    $pattern = '(?m)\b' + [regex]::Escape($Name) + '\s*=\s*"(?<value>[^"]*)"'
    foreach ($match in [regex]::Matches($Raw, $pattern)) {
        $values.Add($match.Groups["value"].Value)
    }

    return @($values)
}

function Get-ModelDocBoolAssignments {
    param(
        [string]$Raw,
        [string]$Name
    )

    $values = New-Object System.Collections.Generic.List[bool]
    $pattern = '(?m)\b' + [regex]::Escape($Name) + '\s*=\s*(?<value>true|false)'
    foreach ($match in [regex]::Matches($Raw, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $values.Add($match.Groups["value"].Value.Equals("true", [System.StringComparison]::OrdinalIgnoreCase))
    }

    return @($values)
}

function Get-ModelDocConfigMap {
    param([string]$Root)

    $map = @{}
    $configDir = Join-Path $Root "scripts"
    if (-not (Test-Path -LiteralPath $configDir)) {
        return $map
    }

    foreach ($config in Get-ChildItem -LiteralPath $configDir -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue) {
        try {
            $json = Read-AgentJson -Path $config.FullName
        }
        catch {
            continue
        }

        if (-not ($json.PSObject.Properties.Name -contains "target_vmdl")) {
            continue
        }

        $target = [string]$json.target_vmdl
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match "\$\{") {
            continue
        }

        $full = [System.IO.Path]::GetFullPath((Join-Path $Root $target))
        if (-not $map.ContainsKey($full)) {
            $map[$full] = New-Object System.Collections.Generic.List[object]
        }

        $map[$full].Add([pscustomobject]@{
            Path = $config.FullName
            RelativePath = ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root
            Json = $json
        })
    }

    return $map
}

function Get-VmdlMaterialSourceSuffix {
    param([object]$Json)

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains "vmdl_material_source_suffix")) {
        return $null
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

function Test-ModelDocResource {
    param(
        [string]$ResourcePath,
        [string]$VmdlRelative,
        [string]$Area,
        [string]$Recommendation
    )

    if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
        Add-AgentIssue $issues "Error" $Area $VmdlRelative "Blank resource path." $Recommendation
        return
    }

    if ($ResourcePath -match "\$\{") {
        Add-AgentIssue $issues "Error" $Area $VmdlRelative "Unexpanded variable in resource path '$ResourcePath'." $Recommendation
        return
    }

    $resolved = Resolve-AgentResourcePath -ResourcePath $ResourcePath -Root $Root
    if ($null -eq $resolved) {
        Add-AgentIssue $issues "Info" $Area $VmdlRelative "Skipped built-in or external resource '$ResourcePath'."
        return
    }

    if (-not (Test-Path -LiteralPath $resolved)) {
        Add-AgentIssue $issues "Error" $Area $VmdlRelative "Resource does not exist: $ResourcePath" $Recommendation
    }
}

function Test-ConfigDrift {
    param(
        [string]$VmdlRelative,
        [string[]]$Filenames,
        [string[]]$MaterialSources,
        [string[]]$MaterialTargets,
        [bool[]]$UseGlobalDefaultValues,
        [object]$ConfigInfo
    )

    $json = $ConfigInfo.Json
    $configRelative = $ConfigInfo.RelativePath

    if ($json.PSObject.Properties.Name -contains "target_fbx") {
        $targetFbx = [string]$json.target_fbx
        if (-not [string]::IsNullOrWhiteSpace($targetFbx) -and $targetFbx -notmatch "\$\{") {
            $expectedFbx = $targetFbx.Replace("\", "/")
            if ($expectedFbx.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
                $expectedFbx = $expectedFbx.Substring("Assets/".Length)
            }

            if ($Filenames -notcontains $expectedFbx) {
                Add-AgentIssue $issues "Warning" "ModelDoc Config Drift" $VmdlRelative "RenderMeshFile filename does not match $configRelative target_fbx '$expectedFbx'." "Re-export with asset_pipeline.py or update the config if this VMDL intentionally imports a different mesh."
            }
        }
    }

    if (-not ($json.PSObject.Properties.Name -contains "material_remap") -or $null -eq $json.material_remap) {
        return
    }

    $expectedUseGlobalDefault = Get-JsonBoolOption -Json $json -Name "vmdl_use_global_default"
    if ($null -ne $expectedUseGlobalDefault) {
        $actualUseGlobalDefault = @($UseGlobalDefaultValues | Select-Object -Unique)
        if ($actualUseGlobalDefault.Count -eq 0) {
            Add-AgentIssue $issues "Error" "ModelDoc Global Default" $VmdlRelative "$configRelative declares vmdl_use_global_default but the VMDL has no use_global_default assignment." "Re-export with asset_pipeline.py so ModelDoc fallback behavior matches the asset config."
        }
        elseif ($actualUseGlobalDefault.Count -ne 1 -or [bool]$actualUseGlobalDefault[0] -ne [bool]$expectedUseGlobalDefault) {
            Add-AgentIssue $issues "Error" "ModelDoc Global Default" $VmdlRelative "use_global_default is '$($actualUseGlobalDefault -join ', ')' but $configRelative expects '$expectedUseGlobalDefault'." "Re-export with asset_pipeline.py or update vmdl_use_global_default if the fallback material is intentional."
        }
        else {
            Add-AgentIssue $issues "Info" "ModelDoc Global Default" $VmdlRelative "use_global_default matches $configRelative."
        }
    }

    $expectedTargets = New-Object System.Collections.Generic.HashSet[string]
    foreach ($property in $json.material_remap.PSObject.Properties) {
        [void]$expectedTargets.Add([string]$property.Value)
    }

    $actualTargets = New-Object System.Collections.Generic.HashSet[string]
    foreach ($target in $MaterialTargets) {
        [void]$actualTargets.Add($target)
    }

    $missingTargets = @($expectedTargets | Where-Object { -not $actualTargets.Contains($_) })
    $unexpectedTargets = @($actualTargets | Where-Object { -not $expectedTargets.Contains($_) })
    if ($missingTargets.Count -gt 0 -or $unexpectedTargets.Count -gt 0) {
        $parts = New-Object System.Collections.Generic.List[string]
        if ($missingTargets.Count -gt 0) {
            $parts.Add("missing targets: $($missingTargets -join ', ')")
        }
        if ($unexpectedTargets.Count -gt 0) {
            $parts.Add("unexpected targets: $($unexpectedTargets -join ', ')")
        }

        Add-AgentIssue $issues "Warning" "ModelDoc Material Drift" $VmdlRelative "Material remap targets differ from $configRelative ($($parts -join '; '))." "Re-export with asset_pipeline.py or update the config and VMDL together."
    }

    $suffix = Get-VmdlMaterialSourceSuffix -Json $json
    $strictSources = Get-JsonBool -Json $json -Name "strict_vmdl_material_sources"
    if ($null -eq $suffix -and -not $strictSources) {
        return
    }

    if ($null -eq $suffix) {
        $suffix = ".vmat"
    }

    $expectedSources = New-Object System.Collections.Generic.HashSet[string]
    foreach ($property in $json.material_remap.PSObject.Properties) {
        [void]$expectedSources.Add((Get-ExpectedVmdlMaterialSource -SourceName ([string]$property.Name) -Suffix $suffix))
    }

    $actualSources = New-Object System.Collections.Generic.HashSet[string]
    foreach ($source in $MaterialSources) {
        [void]$actualSources.Add($source)
    }

    $missingSources = @($expectedSources | Where-Object { -not $actualSources.Contains($_) })
    $unexpectedSources = @($actualSources | Where-Object { -not $expectedSources.Contains($_) })
    if ($missingSources.Count -eq 0 -and $unexpectedSources.Count -eq 0) {
        Add-AgentIssue $issues "Info" "ModelDoc Material Sources" $VmdlRelative "Material remap sources match $configRelative."
        return
    }

    $parts = New-Object System.Collections.Generic.List[string]
    if ($missingSources.Count -gt 0) {
        $parts.Add("missing sources: $($missingSources -join ', ')")
    }
    if ($unexpectedSources.Count -gt 0) {
        $parts.Add("unexpected sources: $($unexpectedSources -join ', ')")
    }

    $severity = if ($strictSources) { "Error" } else { "Warning" }
    Add-AgentIssue $issues $severity "ModelDoc Material Sources" $VmdlRelative "Material remap sources differ from $configRelative ($($parts -join '; '))." "Re-export with asset_pipeline.py or set vmdl_material_source_suffix to the source-name style S&Box expects."
}

Write-AgentSection "ModelDoc Audit"
Write-Host "Root: $Root"

$modelsDir = Join-Path $Root "Assets\models"
if (-not (Test-Path -LiteralPath $modelsDir)) {
    Add-AgentIssue $issues "Error" "ModelDoc" "Assets/models" "Model asset directory is missing." "Restore Assets/models before running ModelDoc automation."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$configMap = Get-ModelDocConfigMap -Root $Root
foreach ($entry in $configMap.GetEnumerator()) {
    if ($entry.Value.Count -gt 1) {
        $configs = @($entry.Value | ForEach-Object { $_.RelativePath }) -join ", "
        $targetRelative = ConvertTo-AgentRelativePath -Path $entry.Key -Root $Root
        Add-AgentIssue $issues "Error" "ModelDoc Config" $targetRelative "Multiple asset configs target the same VMDL: $configs" "Keep one owning export config per generated VMDL."
    }
}

$vmdlFiles = @(Get-ChildItem -LiteralPath $modelsDir -Recurse -File -Filter "*.vmdl" -ErrorAction SilentlyContinue)
if ($vmdlFiles.Count -eq 0) {
    Add-AgentIssue $issues "Warning" "ModelDoc" "Assets/models" "No .vmdl files found." "This is unexpected for this project; check the asset export path."
}

foreach ($vmdl in $vmdlFiles) {
    $relative = ConvertTo-AgentRelativePath -Path $vmdl.FullName -Root $Root
    $raw = Get-Content -LiteralPath $vmdl.FullName -Raw

    if ($raw -notmatch "format:modeldoc") {
        Add-AgentIssue $issues "Error" "ModelDoc Format" $relative "Missing ModelDoc KV3 format header." "Regenerate this VMDL through asset_pipeline.py or ModelDoc."
    }

    if ($raw -notmatch '_class\s*=\s*"RootNode"') {
        Add-AgentIssue $issues "Error" "ModelDoc Format" $relative "Missing RootNode." "Regenerate this VMDL through asset_pipeline.py or ModelDoc."
    }

    $filenames = @(Get-ModelDocAssignments -Raw $raw -Name "filename")
    if ($filenames.Count -eq 0) {
        Add-AgentIssue $issues "Error" "ModelDoc Mesh" $relative "No RenderMeshFile filename entries found." "Add a RenderMeshFile node or regenerate this VMDL from the asset pipeline."
    }

    foreach ($filename in $filenames) {
        $extension = [System.IO.Path]::GetExtension($filename).ToLowerInvariant()
        if (@(".fbx", ".obj", ".dmx", ".smd", ".vox") -notcontains $extension) {
            Add-AgentIssue $issues "Warning" "ModelDoc Mesh" $relative "RenderMeshFile uses unusual source type '$filename'." "Confirm ModelDoc supports this source type before relying on automation."
        }

        Test-ModelDocResource -ResourcePath $filename -VmdlRelative $relative -Area "ModelDoc Mesh" -Recommendation "Restore the source mesh or update the RenderMeshFile filename."
    }

    $materialSources = @(Get-ModelDocAssignments -Raw $raw -Name "from")
    $materialTargets = @(Get-ModelDocAssignments -Raw $raw -Name "to")
    $useGlobalDefaultValues = @(Get-ModelDocBoolAssignments -Raw $raw -Name "use_global_default")
    if ($materialTargets.Count -eq 0) {
        Add-AgentIssue $issues "Info" "ModelDoc Materials" $relative "No material remaps found."
    }

    foreach ($source in $materialSources) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            Add-AgentIssue $issues "Warning" "ModelDoc Materials" $relative "Blank material remap source." "Name source materials in Blender/ModelDoc so remaps remain deterministic."
        }
    }

    $duplicateSources = @($materialSources | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($duplicateSources.Count -gt 0) {
        Add-AgentIssue $issues "Warning" "ModelDoc Materials" $relative "Duplicate material remap sources: $($duplicateSources -join ', ')" "Deduplicate source material names before relying on automated remap repair."
    }

    foreach ($target in $materialTargets) {
        Test-ModelDocResource -ResourcePath $target -VmdlRelative $relative -Area "ModelDoc Materials" -Recommendation "Create the material or update the material remap target."
    }

    $vmdlFull = [System.IO.Path]::GetFullPath($vmdl.FullName)
    if ($configMap.ContainsKey($vmdlFull)) {
        foreach ($configInfo in $configMap[$vmdlFull]) {
            Test-ConfigDrift -VmdlRelative $relative -Filenames $filenames -MaterialSources $materialSources -MaterialTargets $materialTargets -UseGlobalDefaultValues $useGlobalDefaultValues -ConfigInfo $configInfo
        }
    }
    else {
        Add-AgentIssue $issues "Warning" "ModelDoc Config" $relative "No asset pipeline config targets this VMDL." "Add a config when this model should be reproducible from source, or document why it is hand-authored."
    }
}

Add-AgentIssue $issues "Info" "ModelDoc" "" "Checked $($vmdlFiles.Count) VMDL file(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
