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

$pilotSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Pilot"').Count
$soldierSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"[\s\S]{0,500}?"Role"\s*:\s*"Soldier"').Count
$allSpawns = [regex]::Matches($raw, '"__type"\s*:\s*"DroneVsPlayers\.PlayerSpawn"').Count

if ($pilotSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Pilot PlayerSpawn components found." "Add at least one pilot spawn point."
}
if ($soldierSpawns -lt 1) {
    Add-AgentIssue $issues "Error" "Spawns" $relative "No Soldier PlayerSpawn components found." "Add at least one soldier spawn point."
}
if ($allSpawns -gt ($pilotSpawns + $soldierSpawns)) {
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
