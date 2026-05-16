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

function Get-RegexValues {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Group = "value"
    )

    return @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups[$Group].Value })
}

function Get-JsonBoolOption {
    param(
        [object]$Json,
        [string]$Name,
        [bool]$Default = $false
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

function Get-ModelResourcePathFromConfig {
    param([object]$Json)

    if ($Json.PSObject.Properties.Name -contains "model_resource_path" -and -not [string]::IsNullOrWhiteSpace([string]$Json.model_resource_path)) {
        return ([string]$Json.model_resource_path).Replace("\", "/").TrimStart("/")
    }

    if (-not ($Json.PSObject.Properties.Name -contains "target_vmdl")) {
        return $null
    }

    $target = ([string]$Json.target_vmdl).Replace("\", "/").TrimStart("/")
    if ([string]::IsNullOrWhiteSpace($target) -or $target -match "\$\{") {
        return $null
    }

    if ($target.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $target.Substring("Assets/".Length)
    }

    return $target
}

function Get-MaterialProtectedModels {
    param([string]$Root)

    $models = @{}
    $configDir = Join-Path $Root "scripts"
    if (-not (Test-Path -LiteralPath $configDir)) {
        return $models
    }

    foreach ($config in Get-ChildItem -LiteralPath $configDir -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue) {
        try {
            $json = Read-AgentJson -Path $config.FullName
        }
        catch {
            continue
        }

        if (-not ($json.PSObject.Properties.Name -contains "material_remap") -or $null -eq $json.material_remap) {
            continue
        }

        $remapCount = @($json.material_remap.PSObject.Properties).Count
        if ($remapCount -le 1) {
            continue
        }

        if (Get-JsonBoolOption -Json $json -Name "allow_scene_material_overrides" -Default:$false) {
            continue
        }

        $usesGlobalDefault = Get-JsonBoolOption -Json $json -Name "vmdl_use_global_default" -Default:$true
        $disallowOverrides = Get-JsonBoolOption -Json $json -Name "disallow_scene_material_overrides" -Default:$false
        if ($usesGlobalDefault -and -not $disallowOverrides) {
            continue
        }

        $modelPath = Get-ModelResourcePathFromConfig -Json $json
        if ([string]::IsNullOrWhiteSpace($modelPath)) {
            continue
        }

        $models[$modelPath] = ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root
    }

    return $models
}

function Test-MaterialOverridesOnObject {
    param(
        [object]$Object,
        [hashtable]$ProtectedModels,
        [string]$RelativePath
    )

    if ($null -eq $Object) {
        return
    }

    $objectName = if ($Object.PSObject.Properties.Name -contains "Name") { [string]$Object.Name } else { "<unnamed>" }
    if ($Object.PSObject.Properties.Name -contains "Components" -and $null -ne $Object.Components) {
        foreach ($component in @($Object.Components)) {
            if ($null -eq $component) {
                continue
            }

            if (-not ($component.PSObject.Properties.Name -contains "Model")) {
                continue
            }

            $model = ([string]$component.Model).Replace("\", "/").TrimStart("/")
            if (-not $ProtectedModels.ContainsKey($model)) {
                continue
            }

            $hasMaterialOverride = $false
            if ($component.PSObject.Properties.Name -contains "MaterialOverride" -and -not [string]::IsNullOrWhiteSpace([string]$component.MaterialOverride)) {
                $hasMaterialOverride = $true
            }

            $hasIndexedMaterials = $false
            if ($component.PSObject.Properties.Name -contains "Materials" -and $null -ne $component.Materials) {
                if ($component.Materials.PSObject.Properties.Name -contains "indexed" -and $null -ne $component.Materials.indexed) {
                    $hasIndexedMaterials = @($component.Materials.indexed.PSObject.Properties).Count -gt 0
                }
            }

            if ($hasMaterialOverride -or $hasIndexedMaterials) {
                $sourceConfig = [string]$ProtectedModels[$model]
                Add-AgentIssue $issues "Error" "Material Override" $RelativePath "$objectName overrides materials on protected multi-material model '$model' from $sourceConfig." "Clear MaterialOverride and Materials.indexed; fix material slots through the asset config, FBX, and VMDL instead."
            }
        }
    }

    if ($Object.PSObject.Properties.Name -contains "Children" -and $null -ne $Object.Children) {
        foreach ($child in @($Object.Children)) {
            Test-MaterialOverridesOnObject -Object $child -ProtectedModels $ProtectedModels -RelativePath $RelativePath
        }
    }
}

function Test-MaterialOverridesInGraphFile {
    param(
        [string]$Raw,
        [string]$RelativePath,
        [hashtable]$ProtectedModels
    )

    if ($ProtectedModels.Count -eq 0) {
        return
    }

    try {
        $json = $Raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Warning" "Material Override" $RelativePath "Could not parse JSON for protected material override checks: $($_.Exception.Message)" "Fix JSON before relying on material override safety checks."
        return
    }

    if ($json.PSObject.Properties.Name -contains "RootObject") {
        Test-MaterialOverridesOnObject -Object $json.RootObject -ProtectedModels $ProtectedModels -RelativePath $RelativePath
    }

    if ($json.PSObject.Properties.Name -contains "GameObjects") {
        foreach ($object in @($json.GameObjects)) {
            Test-MaterialOverridesOnObject -Object $object -ProtectedModels $ProtectedModels -RelativePath $RelativePath
        }
    }
}

function Test-GraphFile {
    param([string]$Path)

    $relative = ConvertTo-AgentRelativePath -Path $Path -Root $Root
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) {
        $raw = ""
    }

    $guidDefs = @(Get-RegexValues -Text $raw -Pattern '"__guid"\s*:\s*"(?<value>[^"]+)"')
    $guidSet = @{}
    foreach ($guid in $guidDefs) {
        if ($guidSet.ContainsKey($guid)) {
            $guidSet[$guid] += 1
        }
        else {
            $guidSet[$guid] = 1
        }
    }

    foreach ($entry in $guidSet.GetEnumerator()) {
        if ($entry.Value -gt 1) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "Duplicate GUID definition '$($entry.Key)' appears $($entry.Value) times." "Duplicate GUIDs can break references after editor load."
        }
    }

    $goRefs = @(Get-RegexValues -Text $raw -Pattern '"go"\s*:\s*"(?<value>[^"]+)"')
    foreach ($go in ($goRefs | Select-Object -Unique)) {
        if (-not $guidSet.ContainsKey($go)) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "GameObject reference points to missing GUID '$go'." "Repair the prefab or scene reference in the editor."
        }
    }

    $componentRefs = @(Get-RegexValues -Text $raw -Pattern '"component_id"\s*:\s*"(?<value>[^"]+)"')
    foreach ($component in ($componentRefs | Select-Object -Unique)) {
        if (-not $guidSet.ContainsKey($component)) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "Component reference points to missing GUID '$component'." "Repair the component reference in the editor or update AutoWire."
        }
    }

    $resourceValues = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @(
        '"prefab"\s*:\s*"(?<value>[^"]+)"',
        '"(?:Model|MaterialOverride|FireSound|FireSoundFirstPerson|ReloadSound|MagDropSound|MagInsertSound|BoltRackSound|EmptyClickSound|LoopSound|ThrowSound|DetonateSound|FootstepSound|JumpSound|LandSound|PropellerSound|SkyMaterial)"\s*:\s*"(?<value>[^"]+)"',
        '"(?<value>(?:prefabs|models|materials|sounds|scenes|ui)/[^"]+)"'
    )) {
        foreach ($value in Get-RegexValues -Text $raw -Pattern $pattern) {
            $resourceValues.Add($value)
        }
    }

    foreach ($resource in ($resourceValues | Select-Object -Unique)) {
        $resolved = Resolve-AgentResourcePath -ResourcePath $resource -Root $Root
        if ($null -ne $resolved -and -not (Test-Path -LiteralPath $resolved)) {
            Add-AgentIssue $issues "Error" "Resource Reference" $relative "Resource '$resource' does not exist at expected path." "Fix the path, restore the asset, or mark it as an engine resource in the audit if appropriate."
        }
    }

    Test-MaterialOverridesInGraphFile -Raw $raw -RelativePath $relative -ProtectedModels $script:protectedModels

    Add-AgentIssue $issues "Info" "Prefab Graph" $relative "Checked $($guidDefs.Count) GUID definitions, $($goRefs.Count) GameObject refs, $($componentRefs.Count) component refs."
}

Write-AgentSection "Prefab Graph Audit"
Write-Host "Root: $Root"

$files = @()
$prefabRoot = Join-Path $Root "Assets\prefabs"
if (Test-Path -LiteralPath $prefabRoot) {
    $files += @(Get-ChildItem -LiteralPath $prefabRoot -Recurse -File -Filter "*.prefab")
}
$sceneRoot = Join-Path $Root "Assets\scenes"
if (Test-Path -LiteralPath $sceneRoot) {
    $files += @(Get-ChildItem -LiteralPath $sceneRoot -Recurse -File -Filter "*.scene")
}

$script:protectedModels = Get-MaterialProtectedModels -Root $Root
if ($script:protectedModels.Count -gt 0) {
    Add-AgentIssue $issues "Info" "Material Override" "" "Protected multi-material model(s): $($script:protectedModels.Keys -join ', ')."
}

foreach ($file in $files) {
    Test-GraphFile -Path $file.FullName
}

if ($files.Count -eq 0) {
    Add-AgentIssue $issues "Error" "Prefab Graph" "" "No prefabs or scenes were found to audit." "Check the project root."
}
elseif (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Prefab Graph" "" "Checked $($files.Count) prefab/scene file(s) with no broken graph references."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
