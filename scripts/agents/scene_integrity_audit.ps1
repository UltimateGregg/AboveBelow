param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Scene Integrity Audit"
Write-Host "Root: $Root"

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$relative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Scene" $relative "Scene file is missing." "Restore the startup scene or update the audit scene path."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues)
}

$raw = Get-Content -LiteralPath $fullScenePath -Raw
if ($null -eq $raw) {
    $raw = ""
}

$sceneJson = $null
try {
    $sceneJson = $raw | ConvertFrom-Json
}
catch {
    Add-AgentIssue $issues "Warning" "Scene JSON" $relative "Could not parse scene JSON: $($_.Exception.Message)" "Fix scene JSON before relying on structured scene audits."
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

function Test-JsonBoolValue {
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

    $text = $Value.ToString().Trim()
    if ($Expected) {
        return $text.Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
    }

    return $text.Equals("false", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ObjectChildren {
    param([object]$Object)

    $children = Get-JsonPropertyValue -Object $Object -Name "Children"
    if ($null -eq $children) {
        return @()
    }

    return @($children)
}

function Get-ObjectComponents {
    param([object]$Object)

    $components = Get-JsonPropertyValue -Object $Object -Name "Components"
    if ($null -eq $components) {
        return @()
    }

    return @($components)
}

function Get-AllSceneObjects {
    param([object]$Object)

    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @(Get-ObjectChildren -Object $Object)) {
        $objects += @(Get-AllSceneObjects -Object $child)
    }

    return $objects
}

function Find-SceneObjectsByName {
    param(
        [object[]]$Objects,
        [string]$Name
    )

    return @($Objects | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq $Name })
}

function Get-SceneComponentByContract {
    param(
        [object]$Object,
        [ValidateSet("ModelRenderer", "BoxCollider", "SelectedHierarchyColliderViewer")]
        [string]$Contract
    )

    foreach ($component in @(Get-ObjectComponents -Object $Object)) {
        $componentType = [string](Get-JsonPropertyValue -Object $component -Name "__type")
        if (-not [string]::IsNullOrWhiteSpace($componentType) -and $componentType.EndsWith($Contract, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $component
        }

        if ($Contract -eq "ModelRenderer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Model") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "RenderType")) {
            return $component
        }

        if ($Contract -eq "BoxCollider" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Center") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IsTrigger") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "Scale")) {
            return $component
        }

        if ($Contract -eq "SelectedHierarchyColliderViewer" -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "AlwaysDraw") -and
            $null -ne (Get-JsonPropertyValue -Object $component -Name "IncludeTriggers")) {
            return $component
        }
    }

    return $null
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
        [hashtable]$ProtectedModels
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
                Add-AgentIssue $issues "Error" "Scene Material Overrides" $relative "$objectName overrides materials on protected multi-material model '$model' from $sourceConfig." "Clear MaterialOverride and Materials.indexed; fix material slots through the asset config, FBX, and VMDL instead."
            }
        }
    }

    if ($Object.PSObject.Properties.Name -contains "Children" -and $null -ne $Object.Children) {
        foreach ($child in @($Object.Children)) {
            Test-MaterialOverridesOnObject -Object $child -ProtectedModels $ProtectedModels
        }
    }
}

function Test-WaterTowerLadderAuthoringText {
    param(
        [string]$Text,
        [string]$Path,
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    if ($Text -notmatch '"Name"\s*:\s*"WaterTower"') {
        return
    }

    $pattern = '"Name"\s*:\s*"WaterTower"[\s\S]{0,70000}?"Name"\s*:\s*"Collision_Ladder"[\s\S]{0,3000}?"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,1000}?"IsTrigger"\s*:\s*true[\s\S]{0,2000}?"__type"\s*:\s*"DroneVsPlayers\.LadderVolume"'
    if ($Text -notmatch $pattern) {
        Add-AgentIssue $issues "Error" "Water Tower Ladder" $Path "$Context water tower has no Collision_Ladder child with a trigger BoxCollider and DroneVsPlayers.LadderVolume." "Add a Collision_Ladder child with a trigger BoxCollider and LadderVolume so soldiers can climb the tower."
    }
}

function Test-WaterTowerSolidCollisionAuthoringText {
    param(
        [string]$Text,
        [string]$Path,
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch '"Name"\s*:\s*"WaterTower"') {
        return
    }

    $requiredSolidColliders = @(
        "Collision_Tank",
        "Collision_Roof",
        "Collision_Platform",
        "Collision_Leg_NorthWest",
        "Collision_Leg_NorthEast",
        "Collision_Leg_SouthWest",
        "Collision_Leg_SouthEast"
    )

    $solidColliderTypePattern = 'Sandbox\.(?:BoxCollider|CapsuleCollider|HullCollider)'
    foreach ($colliderName in $requiredSolidColliders) {
        $pattern = '"Name"\s*:\s*"' + [regex]::Escape($colliderName) + '"[\s\S]{0,2500}?"__type"\s*:\s*"' + $solidColliderTypePattern + '"[\s\S]{0,1000}?"IsTrigger"\s*:\s*false'
        if ($Text -notmatch $pattern) {
            Add-AgentIssue $issues "Error" "Water Tower Collision" $Path "$Context water tower is missing solid collider child '$colliderName'." "Keep tank, roof, platform, and leg collision as non-trigger collider children so the prop blocks soldiers and drones without closing the open base."
        }
    }
}

function Test-WaterTowerOpenBaseCollisionText {
    param(
        [string]$Text,
        [string]$Path,
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch '"Name"\s*:\s*"WaterTower"') {
        return
    }

    $frameMatches = [regex]::Matches($Text, '"Name"\s*:\s*"(?<name>Collision_Frame_[^"]+)"[\s\S]{0,3500}?"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,1800}?"Scale"\s*:\s*"(?<scale>[^"]+)"')
    foreach ($match in $frameMatches) {
        $scaleParts = @($match.Groups["scale"].Value -split "," | ForEach-Object {
            $parsed = 0.0
            if ([double]::TryParse($_.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
                $parsed
            }
        })

        if ($scaleParts.Count -ne 3) {
            continue
        }

        $x = [Math]::Abs($scaleParts[0])
        $y = [Math]::Abs($scaleParts[1])
        $z = [Math]::Abs($scaleParts[2])
        $isBroadWall = (($x -ge 500 -and $y -ge 40) -or ($y -ge 500 -and $x -ge 40)) -and $z -ge 300
        if ($isBroadWall) {
            Add-AgentIssue $issues "Error" "Water Tower Collision" $Path "$Context water tower has broad lower-frame blocker '$($match.Groups["name"].Value)' with scale '$($match.Groups["scale"].Value)'." "Remove broad lower-frame wall colliders from the open base; keep only tank, platform, legs, and the ladder trigger unless a narrow visible brace collider is explicitly authored."
        }
    }
}

function Test-WaterTowerVisualAlignmentText {
    param(
        [string]$Text,
        [string]$Path,
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch '"Name"\s*:\s*"WaterTower"') {
        return
    }

    $visualRotationMatches = [regex]::Matches($Text, '"Name"\s*:\s*"WaterTower"[\s\S]{0,5000}?"Name"\s*:\s*"Visual"[\s\S]{0,1000}?"Rotation"\s*:\s*"(?<rotation>[^"]+)"')
    foreach ($match in $visualRotationMatches) {
        $rotation = $match.Groups["rotation"].Value.Replace(" ", "")
        if ($rotation -ne "0,0,0,1") {
            Add-AgentIssue $issues "Error" "Water Tower Collision" $Path "$Context water tower Visual has local rotation '$($match.Groups["rotation"].Value)', so child collision no longer lines up with the rendered model." "Keep the Visual child at identity rotation and rotate the WaterTower root so collision, ladder, and render mesh share one transform."
        }
    }
}

function Test-BoundaryWireframeContract {
    param(
        [object]$SceneJson,
        [string]$Path
    )

    $boundaryPrefabInstancePath = "prefabs/environment/arena_boundary_wall.prefab"
    $boundaryPrefabSceneUses = [regex]::Matches($raw, '"__Prefab"\s*:\s*"prefabs/environment/arena_boundary_wall\.prefab"')
    if ($boundaryPrefabSceneUses.Count -gt 0) {
        $boundaryPrefabPath = Join-Path $Root "Assets\prefabs\environment\arena_boundary_wall.prefab"
        $boundaryPrefabRelative = ConvertTo-AgentRelativePath -Path $boundaryPrefabPath -Root $Root
        if (-not (Test-Path -LiteralPath $boundaryPrefabPath)) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $boundaryPrefabRelative "Arena boundary wall prefab is missing, but main.scene references it." "Restore Assets/prefabs/environment/arena_boundary_wall.prefab or replace boundary wall scene instances intentionally."
        }
        else {
            $boundaryPrefabText = Get-Content -LiteralPath $boundaryPrefabPath -Raw
            $prefabChecks = @(
                @{
                    Pattern = '"Name"\s*:\s*"ArenaBoundaryWall"'
                    Message = "Arena boundary prefab root name should be ArenaBoundaryWall."
                },
                @{
                    Pattern = '"__type"\s*:\s*"Sandbox\.ModelRenderer"[\s\S]{0,300}?"__enabled"\s*:\s*false[\s\S]{0,1200}?"Model"\s*:\s*"models/dev/box\.vmdl"[\s\S]{0,1200}?"RenderType"\s*:\s*"Off"'
                    Message = "Arena boundary prefab should keep its dev-box ModelRenderer disabled and hidden."
                },
                @{
                    Pattern = '"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,1800}?"IsTrigger"\s*:\s*false[\s\S]{0,1800}?"Scale"\s*:\s*"50,50,50"[\s\S]{0,1800}?"Static"\s*:\s*true'
                    Message = "Arena boundary prefab should keep a solid static 50,50,50 BoxCollider."
                },
                @{
                    Pattern = '"__type"\s*:\s*"DroneVsPlayers\.SelectedHierarchyColliderViewer"[\s\S]{0,800}?"AlwaysDraw"\s*:\s*false[\s\S]{0,800}?"IncludeTriggers"\s*:\s*true'
                    Message = "Arena boundary prefab should include a selection-only SelectedHierarchyColliderViewer."
                }
            )

            foreach ($check in $prefabChecks) {
                if ($boundaryPrefabText -notmatch $check.Pattern) {
                    Add-AgentIssue $issues "Error" "Boundary Walls" $boundaryPrefabRelative $check.Message "Keep boundary walls collider-backed and fully hidden unless a designer intentionally selects the object."
                }
            }
        }

        if ($boundaryPrefabSceneUses.Count -ne 4) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "Expected four arena boundary prefab instances; found $($boundaryPrefabSceneUses.Count)." "Keep one prefab instance each for NorthBoundary, SouthBoundary, EastBoundary, and WestBoundary."
        }

        foreach ($boundaryName in @("NorthBoundary", "SouthBoundary", "EastBoundary", "WestBoundary")) {
            $namePattern = '"__Prefab"\s*:\s*"' + [regex]::Escape($boundaryPrefabInstancePath) + '"[\s\S]{0,2200}?"Property"\s*:\s*"Name"[\s\S]{0,300}?"Value"\s*:\s*"' + [regex]::Escape($boundaryName) + '"'
            $nameMatches = [regex]::Matches($raw, $namePattern)
            if ($nameMatches.Count -ne 1) {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "Expected exactly one $boundaryName arena boundary prefab instance; found $($nameMatches.Count)." "Keep the four named boundary wall prefab instances auditable through Name property overrides."
            }
        }

        $unsafeOverridePattern = '"__Prefab"\s*:\s*"' + [regex]::Escape($boundaryPrefabInstancePath) + '"[\s\S]{0,3200}?"Property"\s*:\s*"(RenderType|MaterialOverride|Materials)"'
        if ($raw -match $unsafeOverridePattern) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "An arena boundary prefab instance overrides renderer visibility or material state." "Keep renderer visibility/materials owned by the shared arena boundary prefab."
        }

        Add-AgentIssue $issues "Info" "Boundary Walls" $Path "Found $($boundaryPrefabSceneUses.Count) arena boundary prefab instance(s) using Assets/prefabs/environment/arena_boundary_wall.prefab."

        return
    }

    if ($null -eq $SceneJson) {
        Add-AgentIssue $issues "Warning" "Boundary Walls" $Path "Could not parse scene JSON for boundary wireframe checks." "Fix scene JSON before relying on invisible boundary wall validation."
        return
    }

    $allObjects = @()
    foreach ($rootObject in @($SceneJson.GameObjects)) {
        $allObjects += @(Get-AllSceneObjects -Object $rootObject)
    }

    if (@(Find-SceneObjectsByName -Objects $allObjects -Name "BlockoutMap").Count -lt 1) {
        return
    }

    foreach ($boundaryName in @("NorthBoundary", "SouthBoundary", "EastBoundary", "WestBoundary")) {
        $matches = @(Find-SceneObjectsByName -Objects $allObjects -Name $boundaryName)
        if ($matches.Count -ne 1) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "Expected exactly one $boundaryName object; found $($matches.Count)." "Keep the four named boundary walls authored under BlockoutMap so the invisible edge contract remains auditable."
            continue
        }

        $boundary = $matches[0]
        $renderer = Get-SceneComponentByContract -Object $boundary -Contract "ModelRenderer"
        $collider = Get-SceneComponentByContract -Object $boundary -Contract "BoxCollider"
        $viewer = Get-SceneComponentByContract -Object $boundary -Contract "SelectedHierarchyColliderViewer"

        if ($null -eq $renderer) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName has no ModelRenderer component." "Keep a hidden dev-box renderer on the boundary so the editor object remains inspectable."
        }
        else {
            $model = [string](Get-JsonPropertyValue -Object $renderer -Name "Model")
            if ($model -ne "models/dev/box.vmdl") {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName uses renderer model '$model' instead of models/dev/box.vmdl." "Use the existing dev-box boundary authoring pattern unless the boundary system is intentionally redesigned."
            }

            $renderType = [string](Get-JsonPropertyValue -Object $renderer -Name "RenderType")
            if ($renderType -ne "Off") {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName RenderType is '$renderType'; expected Off." "Boundary walls should not render as solid geometry in play; use editor wireframes for visibility."
            }
        }

        if ($null -eq $collider) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName has no BoxCollider component." "Keep boundary collision active while hiding the renderer."
        }
        else {
            if (-not (Test-JsonBoolValue -Value (Get-JsonPropertyValue -Object $collider -Name "IsTrigger") -Expected $false)) {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName collider is configured as a trigger." "Boundary wall colliders must remain solid blockers."
            }

            if (-not (Test-JsonBoolValue -Value (Get-JsonPropertyValue -Object $collider -Name "Static") -Expected $true)) {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName collider is not static." "Boundary wall colliders should remain static scene blockers."
            }

            $colliderScale = [string](Get-JsonPropertyValue -Object $collider -Name "Scale")
            if ($colliderScale.Replace(" ", "") -ne "50,50,50") {
                Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName collider scale is '$colliderScale'; expected local 50,50,50." "Keep dev-box collider scale local so the GameObject transform defines the world-size boundary."
            }
        }

        if ($null -eq $viewer) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName has no SelectedHierarchyColliderViewer component." "Add SelectedHierarchyColliderViewer so hidden boundary walls remain inspectable when selected."
        }
        elseif (-not (Test-JsonBoolValue -Value (Get-JsonPropertyValue -Object $viewer -Name "AlwaysDraw") -Expected $false)) {
            Add-AgentIssue $issues "Error" "Boundary Walls" $Path "$boundaryName SelectedHierarchyColliderViewer always draws." "Keep AlwaysDraw disabled so players and normal editor viewport work cannot see the arena blocker."
        }
    }
}

$requiredComponents = @(
    "DroneVsPlayers.GameRules",
    "DroneVsPlayers.GameStats",
    "DroneVsPlayers.GameSetup",
    "DroneVsPlayers.RoundManager",
    "DroneVsPlayers.AutoWireHelper",
    "DroneVsPlayers.HudPanel"
)

foreach ($type in $requiredComponents) {
    if ($raw -notmatch ('"__type"\s*:\s*"' + [regex]::Escape($type) + '"')) {
        Add-AgentIssue $issues "Error" "Scene Components" $relative "Missing required scene component '$type'." "Restore the GameManager/ScreenPanel setup in the editor."
    }
}

$inlinePilotSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Pilot"').Count
$inlineSoldierSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Soldier"').Count
$inlineSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"').Count
$prefabPilotSpawns = [regex]::Matches($raw, '"__Prefab"\s*:\s*"prefabs/markers/player_spawn_pilot\.prefab"').Count
$prefabSoldierSpawns = [regex]::Matches($raw, '"__Prefab"\s*:\s*"prefabs/markers/player_spawn_soldier\.prefab"').Count
$pilotSpawns = $inlinePilotSpawns + $prefabPilotSpawns
$soldierSpawns = $inlineSoldierSpawns + $prefabSoldierSpawns
$allSpawns = $inlineSpawns + $prefabPilotSpawns + $prefabSoldierSpawns

if ($pilotSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Pilot PlayerSpawn components found." "Add at least one pilot spawn point."
}
if ($soldierSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Soldier PlayerSpawn components found." "Add at least one soldier spawn point."
}
if ($inlineSpawns -gt ($inlinePilotSpawns + $inlineSoldierSpawns)) {
    Add-AgentIssue $issues "Warning" "Spawns" $relative "Some PlayerSpawn components do not declare Pilot or Soldier role." "Check spawn roles in the editor."
}

$devBoxBlocks = [regex]::Matches($raw, '"Model"\s*:\s*"models/dev/box\.vmdl"[\s\S]{0,1800}?"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,500}?"Scale"\s*:\s*"(?<scale>[^"]+)"')
$badColliderScales = 0
foreach ($match in $devBoxBlocks) {
    $scale = $match.Groups["scale"].Value
    if ($scale -ne "50,50,50") {
        $badColliderScales += 1
    }
}

if ($badColliderScales -gt 0) {
    Add-AgentIssue $issues "Warning" "Dev Box Colliders" $relative "$badColliderScales dev-box collider block(s) do not use local scale 50,50,50." "Run scripts/sync_box_colliders_to_renderers.ps1 -All -Apply after confirming these are blockout colliders."
}
else {
    Add-AgentIssue $issues "Info" "Dev Box Colliders" $relative "No obvious dev-box collider scale drift found."
}

$ladderBlocks = [regex]::Matches($raw, '"Name"\s*:\s*"(?<name>[^"]*Ladder[^"]*)"[\s\S]{0,3000}?"__type"\s*:\s*"Sandbox\.BoxCollider"[\s\S]{0,1000}?"IsTrigger"\s*:\s*(?<trigger>true|false)[\s\S]{0,2000}?"__type"\s*:\s*"DroneVsPlayers\.LadderVolume"')
$solidLadderVolumes = 0
foreach ($match in $ladderBlocks) {
    if ($match.Groups["trigger"].Value -ne "true") {
        $solidLadderVolumes += 1
    }
}
if ($solidLadderVolumes -gt 0) {
    Add-AgentIssue $issues "Error" "Ladder Volumes" $relative "$solidLadderVolumes LadderVolume block(s) appear to use non-trigger colliders." "Ladder volumes should be trigger colliders so character movement can attach."
}

Test-BoundaryWireframeContract -SceneJson $sceneJson -Path $relative
Test-WaterTowerLadderAuthoringText -Text $raw -Path $relative -Context "Scene"
Test-WaterTowerSolidCollisionAuthoringText -Text $raw -Path $relative -Context "Scene"
Test-WaterTowerOpenBaseCollisionText -Text $raw -Path $relative -Context "Scene"
Test-WaterTowerVisualAlignmentText -Text $raw -Path $relative -Context "Scene"

$waterTowerPrefabPath = Join-Path $Root "Assets\prefabs\environment\WaterTower.prefab"
if (Test-Path -LiteralPath $waterTowerPrefabPath) {
    $waterTowerPrefabRelative = ConvertTo-AgentRelativePath -Path $waterTowerPrefabPath -Root $Root
    try {
        $waterTowerPrefabText = Get-Content -LiteralPath $waterTowerPrefabPath -Raw
        Test-WaterTowerLadderAuthoringText -Text $waterTowerPrefabText -Path $waterTowerPrefabRelative -Context "Prefab"
        Test-WaterTowerSolidCollisionAuthoringText -Text $waterTowerPrefabText -Path $waterTowerPrefabRelative -Context "Prefab"
        Test-WaterTowerOpenBaseCollisionText -Text $waterTowerPrefabText -Path $waterTowerPrefabRelative -Context "Prefab"
        Test-WaterTowerVisualAlignmentText -Text $waterTowerPrefabText -Path $waterTowerPrefabRelative -Context "Prefab"
    }
    catch {
        Add-AgentIssue $issues "Warning" "Water Tower Ladder" $waterTowerPrefabRelative "Could not read water tower prefab: $($_.Exception.Message)" "Fix prefab access before relying on water tower traversal checks."
    }
}

$protectedModels = Get-MaterialProtectedModels -Root $Root
if ($protectedModels.Count -gt 0) {
    if ($null -ne $sceneJson) {
        foreach ($object in @($sceneJson.GameObjects)) {
            Test-MaterialOverridesOnObject -Object $object -ProtectedModels $protectedModels
        }
        Add-AgentIssue $issues "Info" "Scene Material Overrides" $relative "Checked protected multi-material model(s): $($protectedModels.Keys -join ', ')."
    }
    else {
        Add-AgentIssue $issues "Warning" "Scene Material Overrides" $relative "Could not parse scene JSON for protected material override checks." "Fix scene JSON before relying on material override safety checks."
    }
}

Add-AgentIssue $issues "Info" "Spawns" $relative "Found $pilotSpawns pilot spawn(s), $soldierSpawns soldier spawn(s), $allSpawns total PlayerSpawn component(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
