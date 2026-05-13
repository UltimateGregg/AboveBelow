param(
    [string]$Root = "",
    [ValidateSet("", "weapon", "drone", "character", "environment")]
    [string]$Category = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

function Get-InferredConfigCategories {
    param(
        [System.IO.FileInfo]$Config,
        [string]$RawContent
    )

    $haystack = (($Config.FullName + " " + $RawContent).Replace("\", "/")).ToLowerInvariant()
    $patterns = @{
        weapon = @("gun", "rifle", "shotgun", "smg", "grenade", "m4", "mp7", "jammer", "transmitter")
        drone = @("drone", "fpv", "propeller", "quadcopter")
        character = @("character", "soldier", "pilot", "fps_arms", "arms", "glove", "sleeve")
        environment = @("environment", "terrain", "watertower", "house", "berm", "hill", "plateau", "trench")
    }

    $categories = @()
    foreach ($categoryName in @("weapon", "drone", "character", "environment")) {
        foreach ($pattern in $patterns[$categoryName]) {
            if ($haystack -match "(^|[^a-z0-9])$([regex]::Escape($pattern))([^a-z0-9]|$)") {
                $categories += $categoryName
                break
            }
        }
    }

    return @($categories | Select-Object -Unique)
}

function Get-PropertyBool {
    param(
        [object]$Json,
        [string]$Name
    )

    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains $Name)) {
        return $false
    }

    return [bool]$Json.$Name
}

function Resolve-TexturePath {
    param(
        [string]$TexturePath,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($TexturePath)) {
        return [pscustomobject]@{
            FullPath = $null
            Skip = $false
            Reason = "blank"
        }
    }

    $normalized = $TexturePath.Replace("\", "/").TrimStart("/")
    if ($normalized -match "\$\{") {
        return [pscustomobject]@{
            FullPath = $null
            Skip = $true
            Reason = "variable"
        }
    }

    if ($normalized -match "^(https?:|file:|asset:)") {
        return [pscustomobject]@{
            FullPath = $null
            Skip = $true
            Reason = "uri"
        }
    }

    $skipPrefixes = @(
        "materials/default/",
        "materials/dev/",
        "materials/editor/",
        "materials/skybox/",
        "textures/",
        "models/dev/",
        "models/citizen/",
        "models/effects/",
        "models/sbox_props/"
    )

    foreach ($prefix in $skipPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                FullPath = $null
                Skip = $true
                Reason = "known-default"
            }
        }
    }

    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            FullPath = (Join-Path $Root $normalized)
            Skip = $false
            Reason = "project"
        }
    }

    $projectPrefixes = @("materials/", "models/", "sounds/", "scenes/", "ui/", "prefabs/")
    foreach ($prefix in $projectPrefixes) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                FullPath = (Join-Path (Join-Path $Root "Assets") $normalized)
                Skip = $false
                Reason = "project"
            }
        }
    }

    return [pscustomobject]@{
        FullPath = $null
        Skip = $false
        Reason = "unresolved"
    }
}

function Test-TextureReference {
    param(
        [string]$TexturePath,
        [string]$MaterialRelative,
        [string]$TextureKey
    )

    if ([string]::IsNullOrWhiteSpace($TexturePath)) {
        Add-AgentIssue $issues "Error" "Material Texture" $MaterialRelative "$TextureKey is blank." "Assign a real project texture or remove the invalid texture entry."
        return
    }

    $resolved = Resolve-TexturePath -TexturePath $TexturePath -Root $Root
    if ($resolved.Skip) {
        return
    }

    if ($null -eq $resolved.FullPath) {
        Add-AgentIssue $issues "Error" "Material Texture" $MaterialRelative "$TextureKey references unresolved texture '$TexturePath'." "Use a project resource path or a known engine/default texture prefix."
        return
    }

    if (-not (Test-Path -LiteralPath $resolved.FullPath)) {
        Add-AgentIssue $issues "Error" "Material Texture" $MaterialRelative "$TextureKey references missing texture '$TexturePath'." "Create the texture file or update the .vmat reference."
    }
}

Write-AgentSection "Material Texture Audit"
Write-Host "Root: $Root"
if (-not [string]::IsNullOrWhiteSpace($Category)) {
    Write-Host "Category: $Category"
}

$profilePath = Join-Path $Root "scripts\asset_quality_profiles.json"
if (-not (Test-Path -LiteralPath $profilePath)) {
    Add-AgentIssue $issues "Error" "Material Texture" "scripts/asset_quality_profiles.json" "Asset quality profiles file is missing." "Restore scripts/asset_quality_profiles.json."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $profiles = Read-AgentJson -Path $profilePath
}
catch {
    Add-AgentIssue $issues "Error" "Material Texture" "scripts/asset_quality_profiles.json" $_.Exception.Message "Fix invalid JSON."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$configFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue)
$configsInspected = 0
$remapsChecked = 0
$materialsChecked = 0
$textureReferencesChecked = 0
$seenMaterials = New-Object System.Collections.Generic.HashSet[string]

foreach ($config in $configFiles) {
    $configRelative = ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root
    $raw = Get-Content -LiteralPath $config.FullName -Raw
    $inferredCategories = @(Get-InferredConfigCategories -Config $config -RawContent $raw)

    if (-not [string]::IsNullOrWhiteSpace($Category) -and $inferredCategories -notcontains $Category) {
        continue
    }

    $configsInspected++
    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Error" "Asset Config" $configRelative "Failed to parse JSON '$configRelative': $($_.Exception.Message)" "Fix invalid JSON."
        continue
    }

    $profileCategories = if ([string]::IsNullOrWhiteSpace($Category)) { $inferredCategories } else { @($Category) }
    $optionalMaps = New-Object System.Collections.Generic.List[string]
    foreach ($profileCategory in $profileCategories) {
        if ($profiles.PSObject.Properties.Name -contains $profileCategory) {
            foreach ($mapName in @($profiles.$profileCategory.optional_texture_maps)) {
                if (-not $optionalMaps.Contains([string]$mapName)) {
                    $optionalMaps.Add([string]$mapName)
                }
            }
        }
    }

    if (-not ($json.PSObject.Properties.Name -contains "material_remap") -or $null -eq $json.material_remap) {
        continue
    }

    $allowDefaultColor = Get-PropertyBool -Json $json -Name "allow_default_color_texture"

    foreach ($remap in $json.material_remap.PSObject.Properties) {
        $remapsChecked++
        $sourceName = [string]$remap.Name
        $targetMaterial = [string]$remap.Value

        if ([string]::IsNullOrWhiteSpace($sourceName)) {
            Add-AgentIssue $issues "Warning" "Material Remap" $configRelative "Material remap source name is blank." "Name the Blender material slot so remaps remain stable."
        }

        $materialFull = Resolve-AgentResourcePath -ResourcePath $targetMaterial -Root $Root
        if ($null -eq $materialFull) {
            Add-AgentIssue $issues "Error" "Material Remap" $configRelative "Material remap '$sourceName' cannot be resolved: '$targetMaterial'." "Use a project material path such as materials/example.vmat."
            continue
        }

        $materialRelative = ConvertTo-AgentRelativePath -Path $materialFull -Root $Root
        if (-not (Test-Path -LiteralPath $materialFull)) {
            Add-AgentIssue $issues "Error" "Material Remap" $configRelative "Material remap '$sourceName' points to missing material '$targetMaterial'." "Create the .vmat file or fix the remap."
            continue
        }

        if ($seenMaterials.Add($materialFull)) {
            $materialsChecked++
        }

        $materialText = Get-Content -LiteralPath $materialFull -Raw
        $textureEntries = [regex]::Matches($materialText, '"(?<key>Texture[^"]*)"\s*"(?<value>[^"]+)"')
        $texturesByKey = @{}

        foreach ($entry in $textureEntries) {
            $key = $entry.Groups["key"].Value
            $value = $entry.Groups["value"].Value
            $texturesByKey[$key] = $value
            $textureReferencesChecked++
            Test-TextureReference -TexturePath $value -MaterialRelative $materialRelative -TextureKey $key
        }

        if (-not $texturesByKey.ContainsKey("TextureColor")) {
            Add-AgentIssue $issues "Error" "Material Texture" $materialRelative "Missing TextureColor." "Assign a color texture to prevent flat-grey materials in playtest."
        }
        elseif (-not $allowDefaultColor -and $texturesByKey["TextureColor"].Replace("\", "/").TrimStart("/").Equals("materials/default/default_color.tga", [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-AgentIssue $issues "Error" "Material Texture" $materialRelative "TextureColor uses materials/default/default_color.tga." "Use a production color texture or set allow_default_color_texture: true in the asset config when intentional."
        }

        $alphaTestEnabled = $materialText -match '"F_ALPHA_TEST"\s*"1"'
        $foliageCardMaterial = $targetMaterial -match '(?i)(leaf|leaves|foliage|needle|needles|card)'

        if ($alphaTestEnabled -and -not $texturesByKey.ContainsKey("TextureTranslucency")) {
            Add-AgentIssue $issues "Error" "Material Texture" $materialRelative "Alpha-tested material is missing TextureTranslucency." "Assign a cutout mask so S&Box can render transparent background pixels."
        }
        elseif ($foliageCardMaterial -and -not $texturesByKey.ContainsKey("TextureTranslucency")) {
            Add-AgentIssue $issues "Warning" "Material Texture" $materialRelative "Foliage/card material has no TextureTranslucency mask." "Transparent tree cards should have a color texture plus a cutout mask, then be reviewed in a texture contact sheet."
        }
        elseif ($texturesByKey.ContainsKey("TextureTranslucency") -and -not $alphaTestEnabled) {
            Add-AgentIssue $issues "Warning" "Material Texture" $materialRelative "TextureTranslucency is set but F_ALPHA_TEST is not enabled." "Enable alpha testing or confirm this material uses a different transparency path."
        }

        foreach ($mapName in @($optionalMaps)) {
            if (-not $texturesByKey.ContainsKey([string]$mapName)) {
                $profileLabel = if ([string]::IsNullOrWhiteSpace($Category)) { ($profileCategories -join ", ") } else { $Category }
                Add-AgentIssue $issues "Warning" "Material Texture" $materialRelative "Missing optional profile texture map '$mapName'." "Add the map when available for the $profileLabel quality profile."
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($Category) -and $configsInspected -eq 0) {
    Add-AgentIssue $issues "Warning" "Material Texture" "" "Category filter '$Category' matched no asset pipeline configs." "Check the category or add category-specific naming/content to the asset config."
}

Add-AgentIssue $issues "Info" "Material Texture" "" "Checked $configsInspected config(s), $remapsChecked material remap(s), $materialsChecked material file(s), and $textureReferencesChecked texture reference(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
