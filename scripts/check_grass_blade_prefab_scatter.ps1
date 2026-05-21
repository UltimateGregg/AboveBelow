param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([string]$Message)
    $issues.Add($Message) | Out-Null
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Issue "Missing file: $(Resolve-Path -LiteralPath (Split-Path -Parent $Path) -ErrorAction SilentlyContinue)\$(Split-Path -Leaf $Path)"
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        Add-Issue "Invalid JSON in $Path`: $($_.Exception.Message)"
        return $null
    }
}

function Get-Children {
    param([object]$Node)
    if ($null -eq $Node -or $null -eq $Node.Children) { return @() }
    return @($Node.Children)
}

function Get-Components {
    param([object]$Node)
    if ($null -eq $Node -or $null -eq $Node.Components) { return @() }
    return @($Node.Components)
}

function Test-RendererComponent {
    param([object]$Component)
    if ($null -eq $Component) { return $false }
    $names = @($Component.PSObject.Properties.Name)
    return ($names -contains "Model") -and ($names -contains "MaterialOverride")
}

function Test-ColliderComponent {
    param([object]$Component)
    if ($null -eq $Component) { return $false }
    $names = @($Component.PSObject.Properties.Name)
    return ($names -contains "IsTrigger") -and ($names -contains "Static") -and ($names -contains "Scale") -and -not (Test-RendererComponent $Component)
}

function Walk-Objects {
    param([object]$Node)
    @($Node)
    foreach ($child in Get-Children $Node) {
        Walk-Objects $child
    }
}

function Find-ObjectByName {
    param(
        [object[]]$Objects,
        [string]$Name
    )

    foreach ($object in $Objects) {
        foreach ($node in Walk-Objects $object) {
            if ($node.Name -eq $Name) {
                return $node
            }
        }
    }

    return $null
}

function Test-YAxisUprightRotation {
    param([string]$Rotation)
    $rotationParts = @([string]$Rotation -split "," | ForEach-Object { [double]$_ })
    return $rotationParts.Count -eq 4 -and [math]::Abs($rotationParts[1]) -ge 0.65
}

function Get-VectorParts {
    param([string]$Vector)
    return @([string]$Vector -split "," | ForEach-Object { [double]$_ })
}

$materialPath = Join-Path $Root "Assets\materials\arena\grass_blade_card.vmat"
$prefabPath = Join-Path $Root "Assets\prefabs\environment\grass_clump.prefab"
$scenePath = Join-Path $Root "Assets\scenes\main.scene"

if (-not (Test-Path -LiteralPath $materialPath)) {
    Add-Issue "Missing grass blade material: Assets/materials/arena/grass_blade_card.vmat"
}
else {
    $materialText = Get-Content -LiteralPath $materialPath -Raw
    foreach ($required in @(
        '"TextureColor"\s*"materials/arena/grass_blade_card_color.png"',
        '"TextureTranslucency"\s*"materials/arena/grass_blade_card_trans.png"',
        '"F_ALPHA_TEST"\s*"1"'
    )) {
        if ($materialText -notmatch $required) {
            Add-Issue "grass_blade_card.vmat is missing expected entry matching $required"
        }
    }

    foreach ($texture in @("grass_blade_card_color.png", "grass_blade_card_trans.png")) {
        $texturePath = Join-Path $Root "Assets\materials\arena\$texture"
        if (-not (Test-Path -LiteralPath $texturePath)) {
            Add-Issue "Missing grass blade texture: Assets/materials/arena/$texture"
        }
    }
}

$prefab = Read-JsonFile $prefabPath
if ($null -ne $prefab) {
    $rootObject = $prefab.RootObject
    if ($rootObject.Name -ne "GrassClump_CrossCards") {
        Add-Issue "grass_clump.prefab root should be GrassClump_CrossCards, found '$($rootObject.Name)'"
    }

    $prefabObjects = @(Walk-Objects $rootObject)
    $colliders = @($prefabObjects | ForEach-Object { Get-Components $_ } | Where-Object { Test-ColliderComponent $_ })
    if ($colliders.Count -ne 0) {
        Add-Issue "grass_clump.prefab should be visual-only, found $($colliders.Count) collider component(s)"
    }

    $renderers = @($prefabObjects | ForEach-Object { Get-Components $_ } | Where-Object { Test-RendererComponent $_ })
    if ($renderers.Count -lt 3) {
        Add-Issue "grass_clump.prefab should contain at least 3 crossed-card renderers, found $($renderers.Count)"
    }

    foreach ($renderer in $renderers) {
        if ($renderer.Model -ne "models/dev/plane.vmdl") {
            Add-Issue "grass_clump.prefab renderer uses unexpected model '$($renderer.Model)'"
        }
        if ($renderer.MaterialOverride -ne "materials/arena/grass_blade_card.vmat") {
            Add-Issue "grass_clump.prefab renderer uses unexpected material '$($renderer.MaterialOverride)'"
        }
    }

    $firstCard = @(Get-Children $rootObject | Where-Object { $_.Name -eq "BladeCard_A_Front" } | Select-Object -First 1)
    if ($firstCard.Count -ne 1) {
        Add-Issue "grass_clump.prefab is missing BladeCard_A_Front."
    }
    else {
        if (-not (Test-YAxisUprightRotation $firstCard[0].Rotation)) {
            Add-Issue "BladeCard_A_Front should use Y-axis upright plane rotation so blade texture runs vertically; found '$($firstCard[0].Rotation)'"
        }

        $positionParts = Get-VectorParts $firstCard[0].Position
        $scaleParts = Get-VectorParts $firstCard[0].Scale
        if ($positionParts.Count -lt 3 -or $positionParts[2] -gt 7.5) {
            Add-Issue "BladeCard_A_Front should be one-third height with center Z <= 7.5, found position '$($firstCard[0].Position)'"
        }
        if ($scaleParts.Count -lt 1 -or $scaleParts[0] -gt 0.15) {
            Add-Issue "BladeCard_A_Front should be one-third height with local X scale <= 0.15, found scale '$($firstCard[0].Scale)'"
        }
    }
}

$scene = Read-JsonFile $scenePath
if ($null -ne $scene) {
    $roots = @($scene.GameObjects)
    $blockoutMap = Find-ObjectByName -Objects $roots -Name "BlockoutMap"
    if ($null -eq $blockoutMap) {
        Add-Issue "BlockoutMap was not found in Assets/scenes/main.scene"
    }
    else {
        $scatter = Find-ObjectByName -Objects @($blockoutMap) -Name "GrassClumpScatter_ArenaFloor"
        if ($null -eq $scatter) {
            Add-Issue "Missing GrassClumpScatter_ArenaFloor scene group under BlockoutMap"
        }
        else {
            $directPatches = @(Get-Children $scatter | Where-Object { $_.Name -match "^GrassBladePatch_[0-9]{3}$" })
            $clusters = @(Get-Children $scatter | Where-Object { $_.Name -match "^GrassCluster_" })
            if ($clusters.Count -gt 0) {
                Add-Issue "GrassClumpScatter_ArenaFloor should use separated direct floor coverage, found $($clusters.Count) GrassCluster_* group(s)"
            }

            $patches = @(Walk-Objects $scatter | Where-Object { $_.Name -match "^GrassBladePatch_[0-9]{3}$" })
            if ($patches.Count -lt 180 -or $patches.Count -gt 360) {
                Add-Issue "GrassClumpScatter_ArenaFloor should contain 180-360 separated grass blade patches for broad floor coverage, found $($patches.Count)"
            }
            if ($directPatches.Count -ne $patches.Count) {
                Add-Issue "GrassClumpScatter_ArenaFloor should keep grass blade patches directly under the coverage group, found $($directPatches.Count) direct of $($patches.Count) total patch object(s)"
            }

            if ($directPatches.Count -gt 0) {
                $patchPositions = @($directPatches | ForEach-Object {
                    $positionParts = Get-VectorParts $_.Position
                    [pscustomobject]@{
                        Name = $_.Name
                        X = $positionParts[0]
                        Y = $positionParts[1]
                    }
                })

                $minX = ($patchPositions | Measure-Object -Property X -Minimum).Minimum
                $maxX = ($patchPositions | Measure-Object -Property X -Maximum).Maximum
                $minY = ($patchPositions | Measure-Object -Property Y -Minimum).Minimum
                $maxY = ($patchPositions | Measure-Object -Property Y -Maximum).Maximum
                if ($minX -gt -4300 -or $maxX -lt 4300 -or $minY -gt -4300 -or $maxY -lt 4300) {
                    Add-Issue "Grass blade coverage should span the arena floor to at least +/-4300 on X/Y, found X $minX..$maxX and Y $minY..$maxY"
                }

                $quadrants = @{
                    "NW" = @($patchPositions | Where-Object { $_.X -lt 0 -and $_.Y -gt 0 }).Count
                    "NE" = @($patchPositions | Where-Object { $_.X -gt 0 -and $_.Y -gt 0 }).Count
                    "SW" = @($patchPositions | Where-Object { $_.X -lt 0 -and $_.Y -lt 0 }).Count
                    "SE" = @($patchPositions | Where-Object { $_.X -gt 0 -and $_.Y -lt 0 }).Count
                }
                foreach ($quadrant in $quadrants.Keys) {
                    if ($quadrants[$quadrant] -lt 35) {
                        Add-Issue "Grass blade coverage should be distributed across every arena quadrant; $quadrant has only $($quadrants[$quadrant]) patch object(s)"
                    }
                }
            }

            $sceneObjects = @(Walk-Objects $scatter)
            $sceneColliders = @($sceneObjects | ForEach-Object { Get-Components $_ } | Where-Object { Test-ColliderComponent $_ })
            if ($sceneColliders.Count -ne 0) {
                Add-Issue "GrassClumpScatter_ArenaFloor should be visual-only, found $($sceneColliders.Count) collider component(s)"
            }

            foreach ($patch in $patches) {
                $cards = @(Get-Children $patch)
                if ($cards.Count -lt 3) {
                    Add-Issue "$($patch.Name) should contain at least 3 crossed blade cards, found $($cards.Count)"
                }

                $frontCard = @($cards | Where-Object { $_.Name -eq "$($patch.Name)_BladeCard_A_Front" } | Select-Object -First 1)
                if ($frontCard.Count -ne 1) {
                    Add-Issue "$($patch.Name) is missing its A-front upright blade card."
                }
                elseif (-not (Test-YAxisUprightRotation $frontCard[0].Rotation)) {
                    Add-Issue "$($frontCard[0].Name) should use Y-axis upright plane rotation in the saved scene; found '$($frontCard[0].Rotation)'"
                }

                if ($frontCard.Count -eq 1) {
                    $positionParts = Get-VectorParts $frontCard[0].Position
                    $scaleParts = Get-VectorParts $frontCard[0].Scale
                    if ($positionParts.Count -lt 3 -or $positionParts[2] -gt 7.5) {
                        Add-Issue "$($frontCard[0].Name) should be one-third height with center Z <= 7.5 in the saved scene; found position '$($frontCard[0].Position)'"
                    }
                    if ($scaleParts.Count -lt 1 -or $scaleParts[0] -gt 0.15) {
                        Add-Issue "$($frontCard[0].Name) should be one-third height with local X scale <= 0.15 in the saved scene; found scale '$($frontCard[0].Scale)'"
                    }
                }
            }
        }
    }
}

if ($issues.Count -gt 0) {
    Write-Host "Grass blade prefab/scatter check failed:"
    foreach ($issue in $issues) {
        Write-Host " - $issue"
    }
    exit 1
}

Write-Host "Grass blade prefab/scatter check passed."
