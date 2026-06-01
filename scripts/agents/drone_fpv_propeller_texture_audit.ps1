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

Write-AgentSection "FPV Propeller Texture Audit"
Write-Host "Root: $Root"

$propModel = "models/drone_fpv_prop.vmdl"
$propMaterial = "materials/drone_fpv_propeller.vmat"
$propTexture = "materials/drone_fpv_propeller_color.png"
$expectedPropellers = @("Propeller_FL", "Propeller_FR", "Propeller_BL", "Propeller_BR")

function Get-ChildNodeByName {
    param(
        [object]$Node,
        [string]$Name
    )

    if ($null -eq $Node) {
        return $null
    }

    if (($Node.PSObject.Properties.Name -contains "Name") -and [string]$Node.Name -eq $Name) {
        return $Node
    }

    if ($Node.PSObject.Properties.Name -contains "Children") {
        foreach ($child in @($Node.Children)) {
            $match = Get-ChildNodeByName -Node $child -Name $Name
            if ($null -ne $match) {
                return $match
            }
        }
    }

    return $null
}

function Get-RendererModel {
    param([object]$Node)

    if ($null -eq $Node -or -not ($Node.PSObject.Properties.Name -contains "Components")) {
        return $null
    }

    foreach ($component in @($Node.Components)) {
        $properties = @($component.PSObject.Properties.Name)
        $componentType = if ($properties -contains "__type") { [string]$component.__type } else { "" }
        if (($properties -contains "Model") -and
            ([string]::IsNullOrWhiteSpace($componentType) -or $componentType -eq "Sandbox.ModelRenderer")) {
            return [string]$component.Model
        }
    }

    return $null
}

function Test-PropellerPrefab {
    param([string]$RelativePath)

    $prefabPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $prefabPath)) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" $RelativePath "FPV drone prefab is missing." "Restore the prefab or update this audit intentionally."
        return
    }

    try {
        $prefab = Get-Content -LiteralPath $prefabPath -Raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" $RelativePath "Prefab JSON failed to parse: $($_.Exception.Message)" "Fix invalid prefab JSON."
        return
    }

    foreach ($propellerName in $expectedPropellers) {
        $propeller = Get-ChildNodeByName -Node $prefab.RootObject -Name $propellerName
        if ($null -eq $propeller) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" $RelativePath "$propellerName is missing." "Keep all four FPV propeller render nodes visible on the prefab."
            continue
        }

        if (($propeller.PSObject.Properties.Name -contains "Enabled") -and -not [bool]$propeller.Enabled) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" $RelativePath "$propellerName is disabled." "Enable the propeller so the shared textured model is visible in-editor and in play."
        }

        $model = Get-RendererModel -Node $propeller
        if ($model -ne $propModel) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" $RelativePath "$propellerName renders '$model', expected '$propModel'." "Point every FPV propeller renderer at the shared textured FPV propeller model."
        }
    }
}

function Get-VmatTextureColor {
    param([string]$RelativePath)

    $materialPath = Join-Path $Root ("Assets/" + $RelativePath.TrimStart("/").Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $materialPath)) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $RelativePath) "Propeller material is missing." "Create the FPV propeller .vmat and point it at a project-owned color texture."
        return $null
    }

    $materialText = Get-Content -LiteralPath $materialPath -Raw
    $match = [regex]::Match($materialText, '"TextureColor"\s*"([^"]+)"')
    if (-not $match.Success) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $RelativePath) "TextureColor is missing." "Assign the black/orange propeller color texture."
        return $null
    }

    return $match.Groups[1].Value
}

function Test-PropellerTextureColors {
    param([string]$TextureResource)

    $texturePath = Join-Path $Root ("Assets/" + $TextureResource.TrimStart("/").Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $texturePath)) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) "Propeller color texture is missing." "Generate the project-owned black/orange propeller texture."
        return
    }

    try {
        Add-Type -AssemblyName System.Drawing
        $bitmap = [System.Drawing.Bitmap]::new($texturePath)
    }
    catch {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) "Failed to read texture: $($_.Exception.Message)" "Save the texture as a readable PNG."
        return
    }

    try {
        $blackPixels = 0
        $orangePixels = 0
        $tipPixels = 0
        $tipOrangePixels = 0
        $rootPixels = 0
        $rootOrangePixels = 0
        $centerPixels = 0
        $centerBlackPixels = 0
        $centerOrangePixels = 0
        $totalPixels = $bitmap.Width * $bitmap.Height

        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                $color = $bitmap.GetPixel($x, $y)
                $isBlack = $color.R -le 48 -and $color.G -le 48 -and $color.B -le 56
                $isOrange = $color.R -ge 190 -and $color.G -ge 70 -and $color.G -le 170 -and $color.B -le 70 -and $color.R -gt ($color.G + 45)
                # The FPV propeller UVs put the outer blade-tip cap in the central
                # UV island, not the left/right image edges. In image coordinates
                # this is roughly U 0.34-0.66 and V 0.50-0.75.
                $isTip = $x -ge ($bitmap.Width * 0.34) -and $x -lt ($bitmap.Width * 0.66) -and
                    $y -ge ($bitmap.Height * 0.25) -and $y -lt ($bitmap.Height * 0.50)
                $isRoot = (($x -ge ($bitmap.Width * 0.08) -and $x -lt ($bitmap.Width * 0.25)) -or
                    ($x -ge ($bitmap.Width * 0.75) -and $x -lt ($bitmap.Width * 0.92))) -and
                    $y -ge ($bitmap.Height * 0.25) -and $y -lt ($bitmap.Height * 0.50)
                $isCenter = $x -ge ($bitmap.Width * 0.25) -and $x -lt ($bitmap.Width * 0.75)

                if ($isBlack) { $blackPixels++ }
                if ($isOrange) { $orangePixels++ }
                if ($isTip) {
                    $tipPixels++
                    if ($isOrange) { $tipOrangePixels++ }
                }
                if ($isRoot) {
                    $rootPixels++
                    if ($isOrange) { $rootOrangePixels++ }
                }
                if ($isCenter) {
                    $centerPixels++
                    if ($isBlack) { $centerBlackPixels++ }
                    if ($isOrange) { $centerOrangePixels++ }
                }
            }
        }

        $blackRatio = $blackPixels / $totalPixels
        $orangeRatio = $orangePixels / $totalPixels
        $tipOrangeRatio = if ($tipPixels -gt 0) { $tipOrangePixels / $tipPixels } else { 0 }
        $rootOrangeRatio = if ($rootPixels -gt 0) { $rootOrangePixels / $rootPixels } else { 0 }
        $centerBlackRatio = if ($centerPixels -gt 0) { $centerBlackPixels / $centerPixels } else { 0 }
        $centerOrangeRatio = if ($centerPixels -gt 0) { $centerOrangePixels / $centerPixels } else { 0 }

        if ($blackRatio -lt 0.70) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Texture is not predominantly black enough ({0:P1} black pixels)." -f $blackRatio) "Make the propeller body black while keeping only the tips orange."
        }

        if ($orangeRatio -lt 0.06 -or $orangeRatio -gt 0.18) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Texture does not contain enough orange tip coverage ({0:P1} orange pixels)." -f $orangeRatio) "Add visible orange regions at the propeller tip UV bands."
        }

        if ($tipOrangeRatio -lt 0.65) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Texture blade-tip UV island is not orange enough ({0:P1} orange)." -f $tipOrangeRatio) "Put the orange color on the central blade-tip UV island, not on the root edge bands."
        }

        if ($rootOrangeRatio -gt 0.08) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Texture root UV bands are too orange ({0:P1} orange)." -f $rootOrangeRatio) "Keep the blade roots near the hub black; reserve orange for the outer tips."
        }

        if ($centerBlackRatio -lt 0.60 -or $centerOrangeRatio -lt 0.08 -or $centerOrangeRatio -gt 0.25) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Texture center is {0:P1} black and {1:P1} orange." -f $centerBlackRatio, $centerOrangeRatio) "Keep the middle/body UV region black, with orange reserved for the tips."
        }

        Add-AgentIssue $issues "Info" "FPV Propeller Texture" ("Assets/" + $TextureResource) ("Color ratios: {0:P1} black, {1:P1} orange, {2:P1} orange in tip island, {3:P1} orange in root bands." -f $blackRatio, $orangeRatio, $tipOrangeRatio, $rootOrangeRatio)
    }
    finally {
        $bitmap.Dispose()
    }
}

$configPath = Join-Path $Root "scripts\drone_fpv_prop_asset_pipeline.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    Add-AgentIssue $issues "Error" "FPV Propeller Texture" "scripts/drone_fpv_prop_asset_pipeline.json" "FPV propeller asset config is missing." "Restore the config so the propeller export keeps its material remap."
}
else {
    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if (-not ($config.PSObject.Properties.Name -contains "material_remap") -or
            $null -eq $config.material_remap -or
            -not ($config.material_remap.PSObject.Properties.Name -contains "Propeller_Plastic") -or
            [string]$config.material_remap.Propeller_Plastic -ne $propMaterial) {
            Add-AgentIssue $issues "Error" "FPV Propeller Texture" "scripts/drone_fpv_prop_asset_pipeline.json" "Propeller_Plastic does not remap to '$propMaterial'." "Keep the Blender propeller material slot mapped to the black/orange S&Box material."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" "scripts/drone_fpv_prop_asset_pipeline.json" "Config JSON failed to parse: $($_.Exception.Message)" "Fix invalid JSON."
    }
}

$modeldocPath = Join-Path $Root "Assets\models\drone_fpv_prop.vmdl"
if (-not (Test-Path -LiteralPath $modeldocPath)) {
    Add-AgentIssue $issues "Error" "FPV Propeller Texture" "Assets/models/drone_fpv_prop.vmdl" "FPV propeller modeldoc is missing." "Run the propeller asset export."
}
else {
    $modeldocText = Get-Content -LiteralPath $modeldocPath -Raw
    if ($modeldocText -notmatch 'from\s*=\s*"Propeller_Plastic"' -or
        $modeldocText -notmatch ('to\s*=\s*"' + [regex]::Escape($propMaterial) + '"')) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" "Assets/models/drone_fpv_prop.vmdl" "Modeldoc does not remap Propeller_Plastic to '$propMaterial'." "Regenerate the VMDL from scripts/drone_fpv_prop_asset_pipeline.json."
    }
}

$textureColor = Get-VmatTextureColor -RelativePath $propMaterial
if ($null -ne $textureColor) {
    if ($textureColor -ne $propTexture) {
        Add-AgentIssue $issues "Error" "FPV Propeller Texture" ("Assets/" + $propMaterial) "TextureColor is '$textureColor', expected '$propTexture'." "Use the dedicated FPV propeller color texture."
    }

    Test-PropellerTextureColors -TextureResource $textureColor
}

foreach ($prefab in @("Assets/prefabs/drone_fpv.prefab", "Assets/prefabs/drone_fpv_fiber.prefab")) {
    Test-PropellerPrefab -RelativePath $prefab
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
