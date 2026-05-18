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
$scannedFileCount = 0

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
    $boxCollider = Get-ComponentByTypeName -Object $Object -TypeName "BoxCollider"
    $modelRenderer = Get-ComponentByTypeName -Object $Object -TypeName "ModelRenderer"
    $ladderVolume = Get-ComponentByTypeName -Object $Object -TypeName "LadderVolume"

    if ($null -eq $boxCollider) {
        Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is named like a collision helper but has no BoxCollider." "Add a BoxCollider or rename the object if it is not collision."
        return
    }

    if ($null -ne $modelRenderer) {
        Add-AgentIssue $issues "Warning" "Collision Authoring" $Path "$ObjectPath has both ModelRenderer and collision-helper naming." "Keep visible mesh children separate from Collision_* helper objects."
    }

    $isLadder = $name -match "Ladder" -or $null -ne $ladderVolume
    $isTrigger = Get-JsonPropertyValue -Object $boxCollider -Name "IsTrigger"
    $isStatic = Get-JsonPropertyValue -Object $boxCollider -Name "Static"

    if ($isLadder) {
        if ($null -eq $ladderVolume) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is ladder-named collision but has no LadderVolume." "Add DroneVsPlayers.LadderVolume or rename the object if it is a normal solid collider."
        }
        if (-not (Test-JsonBool -Value $isTrigger -Expected $true)) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is a ladder volume but its BoxCollider is not a trigger." "Set IsTrigger true so player movement can enter ladder mode."
        }
    }
    else {
        if (-not (Test-JsonBool -Value $isTrigger -Expected $false)) {
            Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$ObjectPath is a solid collision helper but its BoxCollider is a trigger." "Set IsTrigger false for physical blockers."
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

function Visit-CollisionObject {
    param(
        [object]$Object,
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

    $boxCollider = Get-ComponentByTypeName -Object $Object -TypeName "BoxCollider"
    $ladderVolume = Get-ComponentByTypeName -Object $Object -TypeName "LadderVolume"
    if ($null -ne $ladderVolume -and $null -eq $boxCollider) {
        Add-AgentIssue $issues "Error" "Collision Authoring" $Path "$currentPath has LadderVolume but no BoxCollider." "Add a trigger BoxCollider to define the climbable volume."
    }

    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        Visit-CollisionObject -Object $child -Path $Path -ObjectPath $currentPath
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
        Visit-CollisionObject -Object $rootObject -Path $relative -ObjectPath ""
        return
    }

    $gameObjects = Get-JsonPropertyValue -Object $json -Name "GameObjects"
    foreach ($object in @($gameObjects)) {
        Visit-CollisionObject -Object $object -Path $relative -ObjectPath ""
    }
}

Write-AgentSection "Collision Authoring Agent"
Write-Host "Root: $Root"

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

Add-AgentIssue $issues "Info" "Collision Authoring" "" "Scanned $scannedFileCount scene/prefab file(s) and $collisionObjectCount Collision_* object(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
