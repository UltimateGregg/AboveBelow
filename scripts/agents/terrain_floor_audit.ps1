param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [string]$TerrainAssetPath = "Assets/terrain/arena_floor.terrain",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Terrain Floor Audit"
Write-Host "Root: $Root"

function Get-JsonPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or $null -eq $Object.PSObject) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    return $null -ne $Object -and $null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-ObjectComponents {
    param([object]$Object)

    $components = Get-JsonPropertyValue -Object $Object -Name "Components"
    if ($null -eq $components) {
        return @()
    }

    return @($components)
}

function Get-ComponentKind {
    param([object]$Component)

    $explicitType = [string](Get-JsonPropertyValue -Object $Component -Name "__type")
    if (-not [string]::IsNullOrWhiteSpace($explicitType)) {
        return $explicitType
    }

    if ((Test-JsonProperty -Object $Component -Name "Storage") -and
        (Test-JsonProperty -Object $Component -Name "TerrainSize") -and
        (Test-JsonProperty -Object $Component -Name "TerrainHeight") -and
        (Test-JsonProperty -Object $Component -Name "ClipMapLodLevels")) {
        return "Sandbox.Terrain"
    }

    if ($null -ne (Get-JsonPropertyValue -Object $Component -Name "Model") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "RenderType") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "Tint")) {
        return "Sandbox.ModelRenderer"
    }

    if ($null -ne (Get-JsonPropertyValue -Object $Component -Name "Center") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "Scale") -and
        $null -ne (Get-JsonPropertyValue -Object $Component -Name "Static")) {
        return "Sandbox.BoxCollider"
    }

    return ""
}

function Get-AllSceneObjects {
    param([object]$Scene)

    $objects = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]

    foreach ($rootObject in @(Get-JsonPropertyValue -Object $Scene -Name "GameObjects")) {
        if ($null -ne $rootObject) {
            $stack.Push($rootObject)
        }
    }

    while ($stack.Count -gt 0) {
        $object = $stack.Pop()
        $objects.Add($object)

        foreach ($child in @(Get-JsonPropertyValue -Object $object -Name "Children")) {
            if ($null -ne $child) {
                $stack.Push($child)
            }
        }
    }

    return $objects.ToArray()
}

function Convert-AgentPathToResource {
    param([string]$Path)

    $normalized = $Path.Replace("\", "/").TrimStart("/")
    if ($normalized.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalized.Substring("Assets/".Length)
    }

    return $normalized
}

function Test-TerrainMaterialFile {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$MaterialPath,
        [string]$MaterialRelative,
        [bool]$HeightBlendEnabled,
        [string]$Root
    )

    try {
        $terrainMaterial = Read-AgentJson -Path $MaterialPath
        $heightImage = [string](Get-JsonPropertyValue -Object $terrainMaterial -Name "HeightImage")
        if ($HeightBlendEnabled -and [string]::IsNullOrWhiteSpace($heightImage)) {
            Add-AgentIssue $Issues "Error" "Terrain Material" $MaterialRelative "HeightBlendEnabled is true but HeightImage is blank." "Provide a neutral height texture or disable terrain height blending to avoid repeated terrain material compiler failures."
        }

        foreach ($textureProperty in @("AlbedoImage", "RoughnessImage", "NormalImage", "AOImage", "HeightImage")) {
            $hasTextureProperty = Test-JsonProperty -Object $terrainMaterial -Name $textureProperty
            $texture = [string](Get-JsonPropertyValue -Object $terrainMaterial -Name $textureProperty)
            if ([string]::IsNullOrWhiteSpace($texture)) {
                if ($hasTextureProperty) {
                    Add-AgentIssue $Issues "Error" "Terrain Material" $MaterialRelative "$textureProperty is present but blank." "Remove the blank texture slot or point it at an existing texture; blank strings are passed to the terrain texture compiler."
                }

                continue
            }

            $texturePath = Resolve-AgentResourcePath -ResourcePath $texture -Root $Root
            if ($null -eq $texturePath -or -not (Test-Path -LiteralPath $texturePath)) {
                Add-AgentIssue $Issues "Error" "Terrain Material" $MaterialRelative "$textureProperty references missing texture '$texture'." "Restore the texture or update the terrain material to point at an existing project texture."
            }
        }
    }
    catch {
        Add-AgentIssue $Issues "Error" "Terrain Material" $MaterialRelative "Could not parse terrain material JSON: $($_.Exception.Message)" "Fix the .tmat JSON before opening it in the editor."
    }
}

function Test-NumericValue {
    param(
        [object]$Value,
        [double]$Expected,
        [double]$Tolerance = 0.01
    )

    if ($null -eq $Value) {
        return $false
    }

    $parsed = 0.0
    if (-not [double]::TryParse($Value.ToString(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $false
    }

    return [Math]::Abs($parsed - $Expected) -le $Tolerance
}

function Test-VectorValue {
    param(
        [object]$Value,
        [double[]]$Expected,
        [double]$Tolerance = 0.01
    )

    if ($null -eq $Value) {
        return $false
    }

    $parts = $Value.ToString().Split(",")
    if ($parts.Count -ne $Expected.Count) {
        return $false
    }

    for ($i = 0; $i -lt $parts.Count; $i++) {
        $parsed = 0.0
        if (-not [double]::TryParse($parts[$i].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            return $false
        }

        if ([Math]::Abs($parsed - $Expected[$i]) -gt $Tolerance) {
            return $false
        }
    }

    return $true
}

function Expand-DeflatedBytes {
    param([string]$Base64)

    $compressed = [Convert]::FromBase64String($Base64)
    $inputStream = [System.IO.MemoryStream]::new($compressed)
    $outputStream = [System.IO.MemoryStream]::new()
    $deflateStream = [System.IO.Compression.DeflateStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)

    try {
        $deflateStream.CopyTo($outputStream)
        return ,$outputStream.ToArray()
    }
    finally {
        $deflateStream.Dispose()
        $inputStream.Dispose()
        $outputStream.Dispose()
    }
}

function Get-UInt16At {
    param(
        [byte[]]$Bytes,
        [int]$Index
    )

    return [BitConverter]::ToUInt16($Bytes, $Index * 2)
}

function Get-UInt32At {
    param(
        [byte[]]$Bytes,
        [int]$Index
    )

    return [BitConverter]::ToUInt32($Bytes, $Index * 4)
}

function Limit-IntValue {
    param(
        [int]$Value,
        [int]$Min,
        [int]$Max
    )

    if ($Value -lt $Min) {
        return $Min
    }

    if ($Value -gt $Max) {
        return $Max
    }

    return $Value
}

function Get-TerrainSampleIndex {
    param(
        [double]$WorldX,
        [double]$WorldY,
        [double]$OriginX = -10800,
        [double]$OriginY = -10800,
        [double]$TerrainSize = 21600,
        [int]$Resolution = 512
    )

    $u = ($WorldX - $OriginX) / $TerrainSize
    $v = ($WorldY - $OriginY) / $TerrainSize
    $x = Limit-IntValue -Value ([int][Math]::Round($u * ($Resolution - 1))) -Min 0 -Max ($Resolution - 1)
    $y = Limit-IntValue -Value ([int][Math]::Round($v * ($Resolution - 1))) -Min 0 -Max ($Resolution - 1)
    return $x + ($y * $Resolution)
}

function Convert-HeightValueToUnits {
    param(
        [UInt16]$Value,
        [double]$TerrainHeight = 512
    )

    return ([double]$Value / [double][UInt16]::MaxValue) * $TerrainHeight
}

function Get-CompactTerrainMaterialInfo {
    param([UInt32]$Packed)

    return [pscustomobject]@{
        Base = [int]($Packed -band 0x1F)
        Overlay = [int](($Packed -shr 5) -band 0x1F)
        Blend = [int](($Packed -shr 10) -band 0xFF)
        Hole = ((($Packed -shr 18) -band 0x1) -ne 0)
    }
}

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$sceneRelative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root
$fullTerrainPath = if ([System.IO.Path]::IsPathRooted($TerrainAssetPath)) { $TerrainAssetPath } else { Join-Path $Root $TerrainAssetPath }
$terrainRelative = ConvertTo-AgentRelativePath -Path $fullTerrainPath -Root $Root
$terrainResourcePath = Convert-AgentPathToResource -Path $TerrainAssetPath

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Terrain Scene" $sceneRelative "Scene file is missing." "Restore Assets/scenes/main.scene before terrain validation."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
}
catch {
    Add-AgentIssue $issues "Error" "Terrain Scene" $sceneRelative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before terrain validation."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$allObjects = @(Get-AllSceneObjects -Scene $scene)
$arenaFloors = @($allObjects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "ArenaFloor" })

if ($arenaFloors.Count -ne 1) {
    Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "Expected exactly one ArenaFloor object, found $($arenaFloors.Count)." "Keep the floor as one stable scene anchor so terrain tooling has a predictable target."
}
else {
    $arenaFloor = $arenaFloors[0]
    if (-not (Test-VectorValue -Value (Get-JsonPropertyValue -Object $arenaFloor -Name "Position") -Expected @(-10800, -10800, -8))) {
        Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "ArenaFloor terrain origin is not centered at -10800,-10800,-8." "Sandbox.Terrain is corner-origin; offset the object by half of TerrainSize so it covers the centered arena terrain footprint."
    }

    $components = @(Get-ObjectComponents -Object $arenaFloor)
    $terrainComponents = @($components | Where-Object { (Get-ComponentKind -Component $_) -eq "Sandbox.Terrain" })
    $legacyPlaneRenderers = @($components | Where-Object {
        (Get-ComponentKind -Component $_) -eq "Sandbox.ModelRenderer" -and
        [string](Get-JsonPropertyValue -Object $_ -Name "Model") -eq "models/dev/plane.vmdl"
    })
    $legacyBoxColliders = @($components | Where-Object { (Get-ComponentKind -Component $_) -eq "Sandbox.BoxCollider" })

    if ($terrainComponents.Count -ne 1) {
        Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "ArenaFloor must have exactly one Sandbox.Terrain component; found $($terrainComponents.Count)." "Replace the dev-plane ModelRenderer and broad BoxCollider with asset-backed Sandbox.Terrain."
    }

    if ($legacyPlaneRenderers.Count -gt 0) {
        Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "ArenaFloor still renders models/dev/plane.vmdl." "Use Sandbox.Terrain so the editor can sculpt and save heightmap data."
    }

    if ($legacyBoxColliders.Count -gt 0) {
        Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "ArenaFloor still uses a BoxCollider floor." "Let Sandbox.Terrain own collision so height adjustments match gameplay collision."
    }

    if ($terrainComponents.Count -eq 1) {
        $terrain = $terrainComponents[0]
        $storage = [string](Get-JsonPropertyValue -Object $terrain -Name "Storage")
        if ([string]::IsNullOrWhiteSpace($storage) -or $storage.Replace("\", "/").TrimStart("/") -ne $terrainResourcePath) {
            Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "Sandbox.Terrain Storage is '$storage', expected '$terrainResourcePath'." "Link ArenaFloor to the repo-owned terrain asset so heightmap edits are source-controlled."
        }

        $enableCollision = Get-JsonPropertyValue -Object $terrain -Name "EnableCollision"
        if ($null -ne $enableCollision -and $enableCollision -is [bool] -and -not $enableCollision) {
            Add-AgentIssue $issues "Error" "ArenaFloor" $sceneRelative "Sandbox.Terrain collision is disabled." "Enable terrain collision before relying on the floor for traversal and drones."
        }

        if (-not (Test-NumericValue -Value (Get-JsonPropertyValue -Object $terrain -Name "TerrainSize") -Expected 21600)) {
            Add-AgentIssue $issues "Warning" "ArenaFloor" $sceneRelative "Sandbox.Terrain TerrainSize is not 21600." "Keep the terrain footprint aligned with the current arena floor."
        }

        if (-not (Test-NumericValue -Value (Get-JsonPropertyValue -Object $terrain -Name "TerrainHeight") -Expected 512)) {
            Add-AgentIssue $issues "Warning" "ArenaFloor" $sceneRelative "Sandbox.Terrain TerrainHeight is not 512." "Use a conservative editable height range unless the arena design calls for taller terrain."
        }
    }
}

if (-not (Test-Path -LiteralPath $fullTerrainPath)) {
    Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "Terrain asset is missing." "Create Assets/terrain/arena_floor.terrain as the source-controlled terrain storage asset."
}
else {
    try {
        $terrainAsset = Read-AgentJson -Path $fullTerrainPath
        if ([int](Get-JsonPropertyValue -Object $terrainAsset -Name "Resolution") -ne 512) {
            Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "Terrain resolution must be 512 for the initial arena floor." "Keep the base heightmap high enough for editing without making the asset unnecessarily large."
        }

        if (-not (Test-NumericValue -Value (Get-JsonPropertyValue -Object $terrainAsset -Name "TerrainSize") -Expected 21600)) {
            Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "TerrainSize must be 21600 to match the current arena footprint." "Preserve the doubled playable footprint for the native terrain floor."
        }

        if (-not (Test-NumericValue -Value (Get-JsonPropertyValue -Object $terrainAsset -Name "TerrainHeight") -Expected 512)) {
            Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "TerrainHeight must be 512 for the initial editable range." "Use a modest initial vertical range; expand only with a deliberate terrain pass."
        }

        $maps = Get-JsonPropertyValue -Object $terrainAsset -Name "Maps"
        foreach ($mapName in @("heightmap", "splatmap")) {
            $mapValue = Get-JsonPropertyValue -Object $maps -Name $mapName
            if ([string]::IsNullOrWhiteSpace([string]$mapValue)) {
                Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "Terrain asset is missing Maps.$mapName." "Keep the native terrain storage maps present so editor sculpt and paint tools can save changes."
            }
        }

        $materialSettings = Get-JsonPropertyValue -Object $terrainAsset -Name "MaterialSettings"
        $heightBlendEnabled = $false
        $heightBlendValue = Get-JsonPropertyValue -Object $materialSettings -Name "HeightBlendEnabled"
        if ($heightBlendValue -is [bool]) {
            $heightBlendEnabled = $heightBlendValue
        }

        $materials = @(Get-JsonPropertyValue -Object $terrainAsset -Name "Materials")
        if ($materials.Count -eq 0) {
            Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "Terrain asset has no terrain materials." "Add at least the grass terrain material so the floor renders with project-owned ground textures."
        }

        $validatedTerrainMaterialPaths = @{}
        foreach ($expectedMaterial in @("materials/arena/grass_ground.tmat", "materials/arena/terrain_dirt_patch.tmat")) {
            if (-not ($materials | Where-Object { [string]$_ -eq $expectedMaterial })) {
                Add-AgentIssue $issues "Error" "Terrain Material" $terrainRelative "Terrain asset is missing material layer '$expectedMaterial'." "Keep both the grass base and grass variation layer available so the splatmap has a real overlay to paint."
            }

            $expectedMaterialPath = Resolve-AgentResourcePath -ResourcePath $expectedMaterial -Root $Root
            if ($null -ne $expectedMaterialPath -and (Test-Path -LiteralPath $expectedMaterialPath)) {
                $expectedMaterialKey = $expectedMaterialPath.ToLowerInvariant()
                if (-not $validatedTerrainMaterialPaths.ContainsKey($expectedMaterialKey)) {
                    $validatedTerrainMaterialPaths[$expectedMaterialKey] = $true
                    $expectedMaterialRelative = ConvertTo-AgentRelativePath -Path $expectedMaterialPath -Root $Root
                    Test-TerrainMaterialFile -Issues $issues -MaterialPath $expectedMaterialPath -MaterialRelative $expectedMaterialRelative -HeightBlendEnabled:$heightBlendEnabled -Root $Root
                }
            }
        }

        foreach ($material in $materials) {
            $materialResource = [string]$material
            $materialPath = Resolve-AgentResourcePath -ResourcePath $materialResource -Root $Root
            $materialRelative = if ($null -ne $materialPath) { ConvertTo-AgentRelativePath -Path $materialPath -Root $Root } else { $materialResource }

            if ([string]::IsNullOrWhiteSpace($materialResource)) {
                Add-AgentIssue $issues "Error" "Terrain Material" $terrainRelative "Terrain asset contains a blank material reference." "Use a project-owned .tmat resource path for every terrain layer."
                continue
            }

            if ($null -eq $materialPath -or -not (Test-Path -LiteralPath $materialPath)) {
                Add-AgentIssue $issues "Error" "Terrain Material" $materialRelative "Terrain material '$materialResource' is missing." "Restore or regenerate the referenced terrain material before opening the terrain in the editor."
                continue
            }

            if (-not $materialResource.EndsWith(".tmat", [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-AgentIssue $issues "Warning" "Terrain Material" $materialRelative "Terrain material '$materialResource' is not a .tmat asset." "Prefer .tmat assets for Sandbox.Terrain layers so the terrain compiler has the expected texture pack inputs."
                continue
            }

            $materialKey = $materialPath.ToLowerInvariant()
            if (-not $validatedTerrainMaterialPaths.ContainsKey($materialKey)) {
                $validatedTerrainMaterialPaths[$materialKey] = $true
                Test-TerrainMaterialFile -Issues $issues -MaterialPath $materialPath -MaterialRelative $materialRelative -HeightBlendEnabled:$heightBlendEnabled -Root $Root
            }
        }

        try {
            $heightmapText = [string](Get-JsonPropertyValue -Object $maps -Name "heightmap")
            $splatmapText = [string](Get-JsonPropertyValue -Object $maps -Name "splatmap")
            $heightBytes = Expand-DeflatedBytes -Base64 $heightmapText
            $controlBytes = Expand-DeflatedBytes -Base64 $splatmapText
            $expectedResolution = 512
            $expectedPixels = $expectedResolution * $expectedResolution

            if ($heightBytes.Length -ne ($expectedPixels * 2)) {
                Add-AgentIssue $issues "Error" "Terrain Heightmap" $terrainRelative "Heightmap data length is $($heightBytes.Length), expected $($expectedPixels * 2) bytes." "Regenerate the terrain through S&Box TerrainStorage so the compressed native map matches the terrain resolution."
            }

            if ($controlBytes.Length -ne ($expectedPixels * 4)) {
                Add-AgentIssue $issues "Error" "Terrain Splatmap" $terrainRelative "Splatmap data length is $($controlBytes.Length), expected $($expectedPixels * 4) bytes." "Regenerate the terrain through S&Box TerrainStorage so the compressed native map matches the terrain resolution."
            }

            if ($heightBytes.Length -eq ($expectedPixels * 2) -and $controlBytes.Length -eq ($expectedPixels * 4)) {
                $maxHeight = 0.0
                $raisedPixels = 0
                $grassOverlayPixels = 0

                for ($i = 0; $i -lt $expectedPixels; $i++) {
                    $heightUnits = Convert-HeightValueToUnits -Value (Get-UInt16At -Bytes $heightBytes -Index $i)
                    if ($heightUnits -gt $maxHeight) {
                        $maxHeight = $heightUnits
                    }

                    if ($heightUnits -gt 1.5) {
                        $raisedPixels++
                    }

                    $materialInfo = Get-CompactTerrainMaterialInfo -Packed (Get-UInt32At -Bytes $controlBytes -Index $i)
                    if ($materialInfo.Overlay -eq 1 -and $materialInfo.Blend -gt 16) {
                        $grassOverlayPixels++
                    }
                }

                if ($maxHeight -lt 140) {
                    Add-AgentIssue $issues "Error" "Terrain Heightmap" $terrainRelative "Heightmap max height is only $([Math]::Round($maxHeight, 2)) units." "Generate visible rolling height variance outside the protected road and building pads."
                }

                if ($raisedPixels -lt 1000) {
                    Add-AgentIssue $issues "Error" "Terrain Heightmap" $terrainRelative "Heightmap only has $raisedPixels raised pixels." "Keep enough non-flat terrain samples to prove the floor is no longer a flat native terrain."
                }

                if ($grassOverlayPixels -lt 1000) {
                    Add-AgentIssue $issues "Error" "Terrain Splatmap" $terrainRelative "Splatmap only has $grassOverlayPixels grass-overlay pixels." "Paint enough grass variation into the control map for the splat layer to be meaningful."
                }

                $protectedSamples = @(
                    [pscustomobject]@{ Name = "Road south"; X = 416.190948; Y = -5200 },
                    [pscustomobject]@{ Name = "Road south end center"; X = 416.190948; Y = -5460 },
                    [pscustomobject]@{ Name = "Road south end west edge"; X = 56.190948; Y = -5460 },
                    [pscustomobject]@{ Name = "Road south end east edge"; X = 776.190948; Y = -5460 },
                    [pscustomobject]@{ Name = "Road center"; X = 416.190948; Y = 0 },
                    [pscustomobject]@{ Name = "Road north"; X = 416.190948; Y = 5200 },
                    [pscustomobject]@{ Name = "Road north end center"; X = 416.190948; Y = 5460 },
                    [pscustomobject]@{ Name = "Road north end west edge"; X = 56.190948; Y = 5460 },
                    [pscustomobject]@{ Name = "Road north end east edge"; X = 776.190948; Y = 5460 },
                    [pscustomobject]@{ Name = "House_Large_01"; X = -1680; Y = 1520 },
                    [pscustomobject]@{ Name = "House_Large_02"; X = -1740; Y = -1540 },
                    [pscustomobject]@{ Name = "House_Small_01"; X = 1120; Y = 1680 },
                    [pscustomobject]@{ Name = "House_Small_02"; X = 1340; Y = -1660 },
                    [pscustomobject]@{ Name = "House_Small_03"; X = 2050; Y = 620 },
                    [pscustomobject]@{ Name = "House_Small_04"; X = -2220; Y = 620 }
                )

                foreach ($sample in $protectedSamples) {
                    $index = Get-TerrainSampleIndex -WorldX $sample.X -WorldY $sample.Y
                    $heightUnits = Convert-HeightValueToUnits -Value (Get-UInt16At -Bytes $heightBytes -Index $index)
                    $materialInfo = Get-CompactTerrainMaterialInfo -Packed (Get-UInt32At -Bytes $controlBytes -Index $index)

                    if ($heightUnits -gt 1.25) {
                        Add-AgentIssue $issues "Error" "Terrain No-Clip Mask" $terrainRelative "$($sample.Name) has $([Math]::Round($heightUnits, 2)) units of terrain lift." "Keep the generated heightmap flat under road and building footprint samples to avoid visible clipping."
                    }

                    if ($materialInfo.Blend -gt 8) {
                        Add-AgentIssue $issues "Warning" "Terrain Splatmap" $terrainRelative "$($sample.Name) has splat overlay blend $($materialInfo.Blend)." "Keep protected road/building samples mostly on the base layer so paint does not bleed through authored surfaces."
                    }
                }
            }
        }
        catch {
            Add-AgentIssue $issues "Error" "Terrain Maps" $terrainRelative "Could not decode compressed terrain maps: $($_.Exception.Message)" "Regenerate the terrain through S&Box TerrainStorage before relying on heightmap or splatmap validation."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Terrain Asset" $terrainRelative "Could not parse terrain JSON: $($_.Exception.Message)" "Fix the terrain asset JSON before opening it in the editor."
    }
}

if ($ShowInfo -and $issues.Count -eq 0) {
    Add-AgentIssue $issues "Info" "Terrain Floor" $sceneRelative "ArenaFloor is backed by Sandbox.Terrain and $terrainResourcePath." ""
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
