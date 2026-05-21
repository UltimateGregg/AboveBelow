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
$collisionObjectCount = 0
$buildingObjectCount = 0
$scannedFileCount = 0
$environmentBlenderCollisionModels = @{}

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

function Get-ObjectComponents {
    param([object]$Object)

    $components = Get-JsonPropertyValue -Object $Object -Name "Components"
    if ($null -eq $components) {
        return @()
    }

    return @($components)
}

function Get-ObjectChildren {
    param([object]$Object)

    $children = Get-JsonPropertyValue -Object $Object -Name "Children"
    if ($null -eq $children) {
        return @()
    }

    return @($children)
}

function Get-ComponentByTypeName {
    param(
        [object]$Object,
        [string]$TypeName
    )

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = Get-JsonPropertyValue -Object $component -Name "__type"
        if ($componentType -and $componentType.EndsWith($TypeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        # Windows PowerShell's ConvertFrom-Json treats __type as metadata and
        # can omit it from the object. Fall back to stable component property
        # signatures that survive parsing.
        if ($TypeName -eq "BoxCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale")) {
            return $component
        }

        if ($TypeName -eq "ModelRenderer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")) {
            return $component
        }

        if ($TypeName -eq "LadderVolume" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "AutoConfigureCollider") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "TopExitLocalOffset")) {
            return $component
        }
    }

    return $null
}

function Test-JsonBool {
    param(
        [object]$Value,
        [bool]$Expected
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value -eq $Expected
    }

    $text = $Value.ToString()
    if ($Expected) {
        return $text -match "^(?i:true)$"
    }

    return $text -match "^(?i:false)$"
}

function Test-IdentityRotationText {
    param([object]$Rotation)

    if ($null -eq $Rotation) {
        return $true
    }

    $text = $Rotation.ToString().Replace(" ", "")
    if ($text -eq "0,0,0,1") {
        return $true
    }

    $parts = @($text -split "," | ForEach-Object {
        $parsed = 0.0
        if ([double]::TryParse($_, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            $parsed
        }
        else {
            $null
        }
    })

    if ($parts.Count -ne 4 -or $parts -contains $null) {
        return $false
    }

    return ([Math]::Abs($parts[0]) -lt 0.0001 -and
        [Math]::Abs($parts[1]) -lt 0.0001 -and
        [Math]::Abs($parts[2]) -lt 0.0001 -and
        [Math]::Abs($parts[3] - 1.0) -lt 0.0001)
}

function Convert-AgentVectorText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $parts = @($Value.ToString() -split "," | ForEach-Object {
        $parsed = 0.0
        if ([double]::TryParse($_.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            $parsed
        }
        else {
            $null
        }
    })

    if ($parts.Count -ne 3 -or $parts -contains $null) {
        return $null
    }

    return $parts
}

function Convert-AgentResourcePath {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace("\", "/").TrimStart("/")
}

function Get-ModelResourcePathFromConfig {
    param([object]$Json)

    if ($null -eq $Json -or $null -eq $Json.PSObject) {
        return $null
    }

    if ($Json.PSObject.Properties.Name -contains "model_resource_path" -and -not [string]::IsNullOrWhiteSpace([string]$Json.model_resource_path)) {
        return Convert-AgentResourcePath -Value $Json.model_resource_path
    }

    if (-not ($Json.PSObject.Properties.Name -contains "target_vmdl")) {
        return $null
    }

    $target = Convert-AgentResourcePath -Value $Json.target_vmdl
    if ([string]::IsNullOrWhiteSpace($target) -or $target -match "\$\{") {
        return $null
    }

    if ($target.StartsWith("Assets/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $target.Substring("Assets/".Length)
    }

    return $target
}

function Get-EnvironmentBlenderCollisionModels {
    param([string]$Root)

    $models = @{}
    $configDir = Join-Path $Root "scripts"
    if (Test-Path -LiteralPath $configDir) {
        foreach ($config in Get-ChildItem -LiteralPath $configDir -File -Filter "*_asset_pipeline.json" -ErrorAction SilentlyContinue) {
            try {
                $json = Read-AgentJson -Path $config.FullName
            }
            catch {
                continue
            }

            $sourceBlend = Convert-AgentResourcePath -Value (Get-JsonPropertyValue -Object $json -Name "source_blend")
            if (-not $sourceBlend.StartsWith("environment_model.blend/", [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $modelPath = Get-ModelResourcePathFromConfig -Json $json
            if ([string]::IsNullOrWhiteSpace($modelPath)) {
                continue
            }

            $models[$modelPath] = ConvertTo-AgentRelativePath -Path $config.FullName -Root $Root
        }
    }

    foreach ($fallback in @("models/terrain_rock.vmdl", "models/terrain_pine.vmdl")) {
        $fullPath = Join-Path $Root ("Assets\" + $fallback.Replace("/", "\"))
        if ((Test-Path -LiteralPath $fullPath) -and -not $models.ContainsKey($fallback)) {
            $models[$fallback] = ConvertTo-AgentRelativePath -Path $fullPath -Root $Root
        }
    }

    return $models
}

function Test-ObjectHasBoxCollider {
    param([object]$Object)

    return $null -ne (Get-ComponentByTypeName -Object $Object -TypeName "BoxCollider")
}

function Get-DirectColliderComponent {
    param([object]$Object)

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = Get-JsonPropertyValue -Object $component -Name "__type"
        if ($componentType -and $componentType.EndsWith("Collider", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        # ConvertFrom-Json can hide S&Box type metadata. Count direct collider
        # components by the stable shape properties that survive parsing.
        if ($null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger")) {
            $hasBoxShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
                (
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "BoxSize")
                )
            $hasCapsuleShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "Radius") -and
                (
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Height") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "Start") -or
                    $null -ne (Get-JsonPropertyValue -Object $component -Name "End")
                )

            if ($hasBoxShape -or $hasCapsuleShape) {
                return $component
            }

            $hasModelShape = $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
                $null -ne (Get-JsonPropertyValue -Object $component -Name "Static")
            if ($hasModelShape) {
                return $component
            }
        }
    }

    return $null
}

function Test-ObjectHasDirectCollider {
    param([object]$Object)

    return $null -ne (Get-DirectColliderComponent -Object $Object)
}

function Test-ObjectHasCollisionCoverage {
    param([object]$Object)

    if (Test-ObjectHasDirectCollider -Object $Object) {
        return $true
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $childName = Get-JsonPropertyValue -Object $child -Name "Name"
        if ($childName -and
            $childName.StartsWith("Collision_", [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-ObjectHasDirectCollider -Object $child)) {
            return $true
        }

        if (Test-ObjectHasCollisionCoverage -Object $child) {
            return $true
        }
    }

    return $false
}

function Get-ObjectModelRendererCount {
    param([object]$Object)

    $count = 0
    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        if ($null -ne (Get-JsonPropertyValue -Object $component -Name "Model")) {
            $count++
        }
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $count += Get-ObjectModelRendererCount -Object $child
    }

    return $count
}

function Get-ObjectColliderCount {
    param([object]$Object)

    $count = 0
    if (Test-ObjectHasDirectCollider -Object $Object) {
        $count++
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $count += Get-ObjectColliderCount -Object $child
    }

    return $count
}

function Test-ParentHasCollisionCoverage {
    param([object]$Parent)

    if ($null -eq $Parent) {
        return $false
    }

    foreach ($child in @(Get-ObjectChildren -Object $Parent)) {
        $childName = Get-JsonPropertyValue -Object $child -Name "Name"
        if ($childName -and
            $childName.StartsWith("Collision_", [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-ObjectHasDirectCollider -Object $child)) {
            return $true
        }
    }

    return $false
}

function Test-BuildingCollisionCoverage {
    param(
        [object]$Object,
        [object]$Parent,
        [string]$Path,
        [string]$ObjectPath
    )

    $name = Get-JsonPropertyValue -Object $Object -Name "Name"
    $parentName = Get-JsonPropertyValue -Object $Parent -Name "Name"
    $isBuildingRoot = $parentName -eq "Buildings" -or
        ($name -and $name -match "^(House|Building|Warehouse|Garage|Apartment|Barracks|Office)_")
    if (-not $isBuildingRoot) {
        return
    }

    $modelRendererCount = Get-ObjectModelRendererCount -Object $Object
    if ($modelRendererCount -eq 0) {
        return
    }

    $script:buildingObjectCount++
    if (-not (Test-ObjectHasCollisionCoverage -Object $Object)) {
        Add-AgentIssue $issues "Error" "Building Collision" $Path "$ObjectPath renders building geometry but has no direct collider or Collision_* coverage under the building root." "Add static Collision_* collider children or a deliberate direct collider on the building root. Keep Model_Visual renderer-only when sibling collision children own the blocking shape."
        return
    }

    $colliderCount = Get-ObjectColliderCount -Object $Object
    Add-AgentIssue $issues "Info" "Building Collision" $Path "$ObjectPath has building collision coverage ($colliderCount collider component(s), $modelRendererCount model renderer(s))." "Evaluate building collision from the root object, not from the selected Model_Visual child alone."
}

function Test-SolidCollisionObject {
    param(
        [object]$Object,
        [string]$Path,
        [string]$ObjectPath
    )

    $name = Get-JsonPropertyValue -Object $Object -Name "Name"
    if ([string]::IsNullOrWhiteSpace($name) -or -not $name.StartsWith("Collision_", [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $script:collisionObjectCount++
    $collider = Get-DirectColliderComponent -Object $Object
    $boxCollider = Get-ComponentByTypeName -Object $Object -TypeName "BoxCollider"
    $modelRenderer = Get-ComponentByTypeName -Object $Object -TypeName "ModelRenderer"
    $ladderVolume = Get-ComponentByTypeName -Object $Object -TypeName "LadderVolume"

    if ($null -eq $collider) {
        Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is named like a collision helper but has no collider component." "Add a solid S&Box collider or rename the object if it is not collision."
        return
    }

    if ($null -ne $modelRenderer) {
        Add-AgentIssue $issues "Warning" "Collision Authoring" $Path "$ObjectPath has both ModelRenderer and collision-helper naming." "Keep visible mesh children separate from Collision_* helper objects."
    }

    $isLadder = $name -match "Ladder" -or $null -ne $ladderVolume
    $isTrigger = Get-JsonPropertyValue -Object $collider -Name "IsTrigger"
    $isStatic = Get-JsonPropertyValue -Object $collider -Name "Static"

    if ($isLadder) {
        if ($null -eq $boxCollider) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is a ladder volume but has no BoxCollider." "Add a trigger BoxCollider to define the climbable volume."
        }
        if ($null -eq $ladderVolume) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is ladder-named collision but has no LadderVolume." "Add DroneVsPlayers.LadderVolume or rename the object if it is a normal solid collider."
        }
        if (-not (Test-JsonBool -Value $isTrigger -Expected $true)) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is a ladder volume but its BoxCollider is not a trigger." "Set IsTrigger true so player movement can enter ladder mode."
        }
    }
    else {
        if (-not (Test-JsonBool -Value $isTrigger -Expected $false)) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is a solid collision helper but its collider is a trigger." "Set IsTrigger false for physical blockers."
        }
        if (-not (Test-JsonBool -Value $isStatic -Expected $true)) {
            Add-AgentIssue $issues "Warning" "Collision Authoring" $Path "$ObjectPath is a non-trigger collision helper but is not marked static." "Mark authored prop/map collision static unless it is intentionally dynamic."
        }
    }
}

function Test-VisualCollisionAlignment {
    param(
        [object]$Object,
        [string]$Path,
        [string]$ObjectPath
    )

    $children = @(Get-ObjectChildren -Object $Object)
    if ($children.Count -eq 0) {
        return
    }

    $collisionChildren = @($children | Where-Object {
        $childName = Get-JsonPropertyValue -Object $_ -Name "Name"
        $childName -and $childName.StartsWith("Collision_", [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($collisionChildren.Count -eq 0) {
        return
    }

    $visualChildren = @($children | Where-Object {
        (Get-JsonPropertyValue -Object $_ -Name "Name") -eq "Visual"
    })

    foreach ($visual in $visualChildren) {
        $rotation = Get-JsonPropertyValue -Object $visual -Name "Rotation"
        if (-not (Test-IdentityRotationText -Rotation $rotation)) {
            $severity = if ((Get-JsonPropertyValue -Object $Object -Name "Name") -eq "WaterTower") { "Error" } else { "Warning" }
            Add-AgentIssue $issues $severity "Collision Alignment" $Path "$ObjectPath has sibling Collision_* objects, but its Visual child has local rotation '$rotation'." "Rotate the prop root instead of the Visual child so visible mesh and colliders stay aligned."
        }
    }
}

function Test-WaterTowerCollisionContract {
    param(
        [object]$Object,
        [string]$Path,
        [string]$ObjectPath
    )

    if ((Get-JsonPropertyValue -Object $Object -Name "Name") -ne "WaterTower") {
        return
    }

    $required = @(
        "Collision_Tank",
        "Collision_Roof",
        "Collision_Platform",
        "Collision_Leg_NorthWest",
        "Collision_Leg_NorthEast",
        "Collision_Leg_SouthWest",
        "Collision_Leg_SouthEast",
        "Collision_Ladder"
    )

    $children = @(Get-ObjectChildren -Object $Object)
    foreach ($requiredName in $required) {
        $child = @($children | Where-Object {
            (Get-JsonPropertyValue -Object $_ -Name "Name") -eq $requiredName
        }) | Select-Object -First 1

        if ($null -eq $child) {
            Add-AgentIssue $issues "Error" "Water Tower Collision" $Path "$ObjectPath is missing '$requiredName'." "Keep the water tower tank, roof, platform, legs, and ladder collision authored as children of the WaterTower root."
        }
    }
}

function Test-WaterTowerOpenBaseContract {
    param(
        [object]$Object,
        [string]$Path,
        [string]$ObjectPath
    )

    if ((Get-JsonPropertyValue -Object $Object -Name "Name") -ne "WaterTower") {
        return
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $name = Get-JsonPropertyValue -Object $child -Name "Name"
        if ([string]::IsNullOrWhiteSpace($name) -or -not $name.StartsWith("Collision_Frame_", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $boxCollider = Get-ComponentByTypeName -Object $child -TypeName "BoxCollider"
        if ($null -eq $boxCollider) {
            continue
        }

        $scaleParts = Convert-AgentVectorText -Value (Get-JsonPropertyValue -Object $boxCollider -Name "Scale")
        if ($null -eq $scaleParts) {
            continue
        }

        $x = [Math]::Abs($scaleParts[0])
        $y = [Math]::Abs($scaleParts[1])
        $z = [Math]::Abs($scaleParts[2])
        $isBroadWall = (($x -ge 500 -and $y -ge 40) -or ($y -ge 500 -and $x -ge 40)) -and $z -ge 300
        if ($isBroadWall) {
            Add-AgentIssue $issues "Error" "Water Tower Collision" $Path "$ObjectPath/$name is a broad lower-frame wall collider with scale '$($scaleParts -join ",")'." "Remove broad lower-frame wall colliders from the open base; keep only collision that matches visible solid pieces."
        }
    }
}

function Test-BlenderModelCollisionCoverage {
    param(
        [object]$Object,
        [object]$Parent,
        [string]$Path,
        [string]$ObjectPath
    )

    if ($script:environmentBlenderCollisionModels.Count -eq 0) {
        return
    }

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $model = Convert-AgentResourcePath -Value (Get-JsonPropertyValue -Object $component -Name "Model")
        if ([string]::IsNullOrWhiteSpace($model) -or -not $script:environmentBlenderCollisionModels.ContainsKey($model)) {
            continue
        }

        if ((Test-ObjectHasCollisionCoverage -Object $Object) -or (Test-ParentHasCollisionCoverage -Parent $Parent)) {
            continue
        }

        $source = [string]$script:environmentBlenderCollisionModels[$model]
        Add-AgentIssue $issues "Error" "Blender Model Collision" $Path "$ObjectPath renders environment Blender model '$model' from $source without any direct collider or Collision_* coverage." "Add a direct collider or a Collision_* helper under the model's prop root. For Visual children, keep sibling Collision_* helpers under the same parent root."
    }
}

function Visit-CollisionObject {
    param(
        [object]$Object,
        [object]$Parent,
        [string]$Path,
        [string]$ObjectPath
    )

    if ($null -eq $Object) {
        return
    }

    $name = Get-JsonPropertyValue -Object $Object -Name "Name"
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "<unnamed>"
    }

    $currentPath = if ([string]::IsNullOrWhiteSpace($ObjectPath)) { $name } else { "$ObjectPath/$name" }

    Test-SolidCollisionObject -Object $Object -Path $Path -ObjectPath $currentPath
    Test-VisualCollisionAlignment -Object $Object -Path $Path -ObjectPath $currentPath
    Test-WaterTowerCollisionContract -Object $Object -Path $Path -ObjectPath $currentPath
    Test-WaterTowerOpenBaseContract -Object $Object -Path $Path -ObjectPath $currentPath
    Test-BlenderModelCollisionCoverage -Object $Object -Parent $Parent -Path $Path -ObjectPath $currentPath
    Test-BuildingCollisionCoverage -Object $Object -Parent $Parent -Path $Path -ObjectPath $currentPath

    $boxCollider = Get-ComponentByTypeName -Object $Object -TypeName "BoxCollider"
    $ladderVolume = Get-ComponentByTypeName -Object $Object -TypeName "LadderVolume"
    if ($null -ne $ladderVolume -and $null -eq $boxCollider) {
        Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$currentPath has LadderVolume but no BoxCollider." "Add a trigger BoxCollider to define the climbable volume."
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        Visit-CollisionObject -Object $child -Parent $Object -Path $Path -ObjectPath $currentPath
    }
}

function Test-CollisionFile {
    param([System.IO.FileInfo]$File)

    $relative = ConvertTo-AgentRelativePath -Path $File.FullName -Root $Root
    $script:scannedFileCount++

    $assetsRoot = (Join-Path $Root "Assets")
    if ($File.Extension -eq ".scene" -and $File.Directory.FullName.TrimEnd("\") -eq $assetsRoot.TrimEnd("\")) {
        Add-AgentIssue $issues "Warning" "Scene Path" $relative "Scene file is directly under Assets instead of Assets/scenes." "Save authored game scenes under Assets/scenes/ to avoid testing or shipping an accidental Save As duplicate."
        return
    }

    try {
        $json = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Error" "Collision Authoring" $relative "Could not parse JSON: $($_.Exception.Message)" "Fix the scene or prefab JSON before relying on collision audits."
        return
    }

    $rootObject = Get-JsonPropertyValue -Object $json -Name "RootObject"
    if ($null -ne $rootObject) {
        Visit-CollisionObject -Object $rootObject -Parent $null -Path $relative -ObjectPath ""
        return
    }

    $gameObjects = Get-JsonPropertyValue -Object $json -Name "GameObjects"
    foreach ($object in @($gameObjects)) {
        Visit-CollisionObject -Object $object -Parent $null -Path $relative -ObjectPath ""
    }
}

Write-AgentSection "Collision Authoring Agent"
Write-Host "Root: $Root"
$environmentBlenderCollisionModels = Get-EnvironmentBlenderCollisionModels -Root $Root

$assetRoot = Join-Path $Root "Assets"
if (-not (Test-Path -LiteralPath $assetRoot)) {
    Add-AgentIssue $issues "Error" "Collision Authoring" "Assets" "Assets directory not found." "Run this agent from the S&Box project root."
}
else {
    $files = @(Get-AgentFiles -Root $assetRoot -Include @("*.scene", "*.prefab"))
    foreach ($file in $files) {
        Test-CollisionFile -File $file
    }
}

Add-AgentIssue $issues "Info" "Collision Authoring" "" "Scanned $scannedFileCount scene/prefab file(s), $collisionObjectCount Collision_* object(s), and $buildingObjectCount building object(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
