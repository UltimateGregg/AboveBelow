param(
    [string]$Root = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning,
    [switch]$OnlyLineRendererSerialization
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$issues = New-Object System.Collections.Generic.List[object]

function Test-Prefab {
    param(
        [string]$Path,
        [string[]]$RequiredComponents,
        [string[]]$RequiredNodes,
        [hashtable]$PropertyChecks = @{}
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Required prefab is missing." "Restore the prefab or update GameSetup and AutoWire intentionally."
        return
    }

    $raw = Get-Content -LiteralPath $fullPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -notmatch '"RootObject"\s*:') {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Prefab has no RootObject." "Regenerate or repair the prefab JSON."
        return
    }

    foreach ($type in $RequiredComponents) {
        if ($raw -notmatch ('"__type"\s*:\s*"' + [regex]::Escape($type) + '"')) {
            Add-AgentIssue $issues "Error" "Prefab" $Path "Missing required component '$type'." "Keep prefab component layouts aligned with AGENTS.md and WIRING.md."
        }
    }

    foreach ($name in $RequiredNodes) {
        if ($raw -notmatch ('"Name"\s*:\s*"' + [regex]::Escape($name) + '"')) {
            Add-AgentIssue $issues "Error" "Prefab" $Path "Missing required child GameObject '$name'." "Add the expected child or extend AutoWire if the structure changed intentionally."
        }
    }

    foreach ($type in $PropertyChecks.Keys) {
        foreach ($check in @($PropertyChecks[$type])) {
            $propertyName = $check.Property
            $pattern = '"__type"\s*:\s*"' + [regex]::Escape($type) + '"[\s\S]*?"' + [regex]::Escape($propertyName) + '"\s*:\s*"?'+ [regex]::Escape([string]$check.Expected) + '"?'
            if ($raw -notmatch $pattern) {
                Add-AgentIssue $issues "Error" "Prefab" $Path "$type.$propertyName expected '$($check.Expected)'." $check.Recommendation
            }
        }
    }

    Add-AgentIssue $issues "Info" "Prefab" $Path "Prefab structure check completed."
}

function Find-PrefabNodeByName {
    param(
        [object]$Node,
        [string]$Name
    )

    if ($null -eq $Node) {
        return $null
    }

    if (($Node.PSObject.Properties.Name -contains "Name") -and $Node.Name -eq $Name) {
        return $Node
    }

    if (-not ($Node.PSObject.Properties.Name -contains "Children") -or $null -eq $Node.Children) {
        return $null
    }

    foreach ($child in @($Node.Children)) {
        $found = Find-PrefabNodeByName -Node $child -Name $Name
        if ($null -ne $found) {
            return $found
        }
    }

    return $null
}

function Read-PrefabJson {
    param(
        [string]$Path,
        [string]$FailureContext
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    }
    catch {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Prefab JSON failed to parse while checking $FailureContext." "Fix invalid prefab JSON before relying on prefab structure checks."
        return $null
    }
}

function Get-ComponentTypeName {
    param(
        [object]$Component
    )

    if ($null -eq $Component) {
        return ""
    }

    $property = $Component.PSObject.Properties["__type"]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function Test-HumanBodyRenderer {
    param(
        [string]$Path
    )

    $json = Read-PrefabJson -Path $Path -FailureContext "human body renderer"
    if ($null -eq $json) {
        return
    }

    $body = Find-PrefabNodeByName -Node $json.RootObject -Name "Body"
    if ($null -eq $body) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Missing Body node while checking human body renderer." "Keep player and dummy human meshes on the Body child."
        return
    }

    $renderer = $null
    foreach ($component in @($body.Components)) {
        if ($component.PSObject.Properties.Name -contains "Model") {
            $renderer = $component
            break
        }
    }

    if ($null -eq $renderer) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Body node is missing Sandbox.SkinnedModelRenderer." "Use the human Citizen body renderer on the Body child."
        return
    }

    if ([string]$renderer.Model -ne $humanBodyModel) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Human body renderer model expected '$humanBodyModel'." "Use the human Citizen body model instead of the stylized default citizen body."
    }

    if ([string]$renderer.BodyGroups -ne [string]$humanBodyDefaultBodyGroups) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Human body renderer BodyGroups expected '$humanBodyDefaultBodyGroups'." "Use the sane Citizen default bodygroup mask so alternate heads/body parts do not overlap."
    }
}

function Test-NoLegacyFirstPersonArms {
    param(
        [string]$Path
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }

    $legacyComponentName = "Fpv" + "Arms"
    $legacyAssetName = "fps" + "_arms"
    $legacyModelPath = "models/" + $legacyAssetName + ".vmdl"
    $legacyPattern = "(?i)" + [regex]::Escape($legacyComponentName) + "|" + [regex]::Escape($legacyModelPath) + "|" + [regex]::Escape($legacyAssetName)

    $raw = Get-Content -LiteralPath $fullPath -Raw
    if ($raw -match $legacyPattern) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Prefab still references the removed first-person arms viewmodel path." "Remove the legacy object/component and use human body arms with Citizen IK targets."
    }
}

function Test-HeldItemTargets {
    param(
        [string]$Path,
        [string[]]$HeldItemNames
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }

    $json = Read-PrefabJson -Path $Path -FailureContext "held-item IK targets"
    if ($null -eq $json) {
        return
    }

    foreach ($heldItemName in $HeldItemNames) {
        $heldItem = Find-PrefabNodeByName -Node $json.RootObject -Name $heldItemName
        if ($null -eq $heldItem) {
            Add-AgentIssue $issues "Error" "Prefab" $Path "Missing held-item node '$heldItemName'." "Restore the expected held item or update the prefab audit intentionally."
            continue
        }

        $childNames = @()
        if (($heldItem.PSObject.Properties.Name -contains "Children") -and $null -ne $heldItem.Children) {
            $childNames = @($heldItem.Children | ForEach-Object { $_.Name })
        }

        foreach ($targetName in @("LeftHandIk", "RightHandIk")) {
            if ($childNames -notcontains $targetName) {
                Add-AgentIssue $issues "Error" "Prefab" $Path "$heldItemName is missing child GameObject '$targetName'." "Add stable Citizen IK targets so the human character arms hold selected items in first person and third person."
                continue
            }

            $target = @($heldItem.Children | Where-Object { $_.Name -eq $targetName } | Select-Object -First 1)[0]
            $position = [string]$target.Position
            if ($invalidHeldItemIkPositions -contains $position) {
                Add-AgentIssue $issues "Error" "Prefab" $Path "$heldItemName/$targetName still uses placeholder IK position '$position'." "Move the target onto a real grip/support point for the held item."
            }
        }
    }
}

function Test-LineRendererColorSerialization {
    param(
        [string]$Path
    )

    $fullPath = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }

    $raw = Get-Content -LiteralPath $fullPath -Raw
    $legacyColorPattern = '"__type"\s*:\s*"Sandbox\.LineRenderer"[\s\S]*?"Color"\s*:\s*\{[\s\S]*?"useGradient"\s*:'
    if ($raw -match $legacyColorPattern) {
        Add-AgentIssue $issues "Error" "Prefab" $Path "Sandbox.LineRenderer.Color uses the legacy object format that current S&Box fails to deserialize." "Serialize LineRenderer.Color as a gradient frame array, or omit it and configure the gradient from runtime code."
    }
}

function Test-AllLineRendererColorSerialization {
    $prefabRoot = Join-Path $Root "Assets\prefabs"
    if (-not (Test-Path -LiteralPath $prefabRoot)) {
        return
    }

    foreach ($prefab in @(Get-ChildItem -LiteralPath $prefabRoot -Recurse -File -Filter "*.prefab")) {
        $relative = ConvertTo-AgentRelativePath -Path $prefab.FullName -Root $Root
        Test-LineRendererColorSerialization -Path $relative
    }
}

Write-AgentSection "Prefab and Wiring Audit"
Write-Host "Root: $Root"

if ($OnlyLineRendererSerialization) {
    Test-AllLineRendererColorSerialization
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$soldierBase = @(
    "Sandbox.CharacterController",
    "DroneVsPlayers.GroundPlayerController",
    "DroneVsPlayers.Health",
    "DroneVsPlayers.SoldierLoadout"
)

$humanBodyModel = "models/citizen_human/citizen_human_male.vmdl"
$humanBodyDefaultBodyGroups = 341
$invalidHeldItemIkPositions = @(
    "0,0,0",
    "0,-4,0",
    "0,4,0"
)
$humanBodyCheck = @{
    "Sandbox.SkinnedModelRenderer" = @(
        @{ Property = "Model"; Expected = $humanBodyModel; Recommendation = "Use the human Citizen body model instead of the stylized default citizen body." }
    )
}

$pilotGroundCheck = @{
    "Sandbox.SkinnedModelRenderer" = @(
        @{ Property = "Model"; Expected = $humanBodyModel; Recommendation = "Use the human Citizen body model instead of the stylized default citizen body." }
    )
    "DroneVsPlayers.DroneDeployer" = @(
        @{ Property = "LeftHandFpRotation"; Expected = "0,180,0"; Recommendation = "Keep the pilot's first-person RC transmitter screen facing back toward the player." }
    )
}

Test-Prefab -Path "Assets/prefabs/soldier.prefab" `
    -RequiredComponents $soldierBase `
    -RequiredNodes @("Body", "Eye", "Weapon", "MuzzleSocket", "WeaponVisual", "LeftHandIk", "RightHandIk") `
    -PropertyChecks $humanBodyCheck
Test-NoLegacyFirstPersonArms -Path "Assets/prefabs/soldier.prefab"
Test-HumanBodyRenderer -Path "Assets/prefabs/soldier.prefab"
Test-HeldItemTargets -Path "Assets/prefabs/soldier.prefab" -HeldItemNames @("Weapon")

Test-Prefab -Path "Assets/prefabs/soldier_assault.prefab" `
    -RequiredComponents ($soldierBase + @("DroneVsPlayers.AssaultSoldier", "DroneVsPlayers.HitscanWeapon", "DroneVsPlayers.ChaffGrenade")) `
    -RequiredNodes @("Body", "Eye", "Weapon", "Grenade", "MuzzleSocket", "WeaponVisual", "LeftHandIk", "RightHandIk") `
    -PropertyChecks $humanBodyCheck
Test-NoLegacyFirstPersonArms -Path "Assets/prefabs/soldier_assault.prefab"
Test-HumanBodyRenderer -Path "Assets/prefabs/soldier_assault.prefab"
Test-HeldItemTargets -Path "Assets/prefabs/soldier_assault.prefab" -HeldItemNames @("Weapon", "Grenade")

Test-Prefab -Path "Assets/prefabs/soldier_counter_uav.prefab" `
    -RequiredComponents ($soldierBase + @("DroneVsPlayers.CounterUavSoldier", "DroneVsPlayers.DroneJammerGun", "DroneVsPlayers.FragGrenade")) `
    -RequiredNodes @("Body", "Eye", "Weapon", "Grenade", "MuzzleSocket", "LeftHandIk", "RightHandIk") `
    -PropertyChecks $humanBodyCheck
Test-NoLegacyFirstPersonArms -Path "Assets/prefabs/soldier_counter_uav.prefab"
Test-HumanBodyRenderer -Path "Assets/prefabs/soldier_counter_uav.prefab"
Test-HeldItemTargets -Path "Assets/prefabs/soldier_counter_uav.prefab" -HeldItemNames @("Weapon", "Grenade")

Test-Prefab -Path "Assets/prefabs/soldier_heavy.prefab" `
    -RequiredComponents ($soldierBase + @("DroneVsPlayers.HeavySoldier", "DroneVsPlayers.ShotgunWeapon", "DroneVsPlayers.EmpGrenade")) `
    -RequiredNodes @("Body", "Eye", "Weapon", "Grenade", "MuzzleSocket", "LeftHandIk", "RightHandIk") `
    -PropertyChecks $humanBodyCheck
Test-NoLegacyFirstPersonArms -Path "Assets/prefabs/soldier_heavy.prefab"
Test-HumanBodyRenderer -Path "Assets/prefabs/soldier_heavy.prefab"
Test-HeldItemTargets -Path "Assets/prefabs/soldier_heavy.prefab" -HeldItemNames @("Weapon", "Grenade")

Test-Prefab -Path "Assets/prefabs/pilot_ground.prefab" `
    -RequiredComponents @("Sandbox.CharacterController", "DroneVsPlayers.GroundPlayerController", "DroneVsPlayers.Health", "DroneVsPlayers.PilotSoldier", "DroneVsPlayers.RemoteController", "DroneVsPlayers.SoldierLoadout", "DroneVsPlayers.DroneDeployer") `
    -RequiredNodes @("Body", "Eye", "Weapon", "DroneDeployer", "LeftHandIk", "RightHandIk") `
    -PropertyChecks $pilotGroundCheck
Test-NoLegacyFirstPersonArms -Path "Assets/prefabs/pilot_ground.prefab"
Test-HumanBodyRenderer -Path "Assets/prefabs/pilot_ground.prefab"
Test-HeldItemTargets -Path "Assets/prefabs/pilot_ground.prefab" -HeldItemNames @("Weapon", "DroneDeployer")

Test-Prefab -Path "Assets/prefabs/training_dummy.prefab" `
    -RequiredComponents @("Sandbox.CharacterController", "DroneVsPlayers.Health", "DroneVsPlayers.TrainingDummy", "Sandbox.Citizen.CitizenAnimationHelper") `
    -RequiredNodes @("Body") `
    -PropertyChecks $humanBodyCheck
Test-HumanBodyRenderer -Path "Assets/prefabs/training_dummy.prefab"

$droneBase = @(
    "Sandbox.Rigidbody",
    "Sandbox.BoxCollider",
    "DroneVsPlayers.DroneController",
    "DroneVsPlayers.DroneCamera",
    "DroneVsPlayers.Health",
    "DroneVsPlayers.JammingReceiver",
    "DroneVsPlayers.PilotLink"
)

Test-Prefab -Path "Assets/prefabs/drone_gps.prefab" `
    -RequiredComponents ($droneBase + @("DroneVsPlayers.GpsDrone")) `
    -RequiredNodes @("Visual", "CameraSocket", "MuzzleSocket", "Propeller_FL", "Propeller_FR", "Propeller_BL", "Propeller_BR")

Test-Prefab -Path "Assets/prefabs/drone_fpv.prefab" `
    -RequiredComponents ($droneBase + @("DroneVsPlayers.FpvDrone", "DroneVsPlayers.DroneWeapon")) `
    -RequiredNodes @("Visual", "CameraSocket", "MuzzleSocket", "Propeller_FL", "Propeller_FR", "Propeller_BL", "Propeller_BR")

Test-Prefab -Path "Assets/prefabs/drone_fpv_fiber.prefab" `
    -RequiredComponents ($droneBase + @("DroneVsPlayers.FiberOpticFpvDrone", "DroneVsPlayers.DroneWeapon", "DroneVsPlayers.FiberCable", "Sandbox.LineRenderer")) `
    -RequiredNodes @("Visual", "CameraSocket", "MuzzleSocket", "Propeller_FL", "Propeller_FR", "Propeller_BL", "Propeller_BR") `
    -PropertyChecks @{
        "DroneVsPlayers.FiberOpticFpvDrone" = @(
            @{ Property = "JamSusceptibility"; Expected = "0"; Recommendation = "Fiber FPV should stay RF-immune unless the balance design changes." }
        )
    }

Test-AllLineRendererColorSerialization

$scenePath = Join-Path $Root "Assets\scenes\main.scene"
if (Test-Path -LiteralPath $scenePath) {
    $sceneRaw = Get-Content -LiteralPath $scenePath -Raw
    if ($sceneRaw -notmatch "GameManager") {
        Add-AgentIssue $issues "Error" "Scene" "Assets/scenes/main.scene" "main.scene does not contain a GameManager marker." "Restore the main gameplay manager object."
    }
    if ($sceneRaw -notmatch "DroneVsPlayers\.AutoWireHelper") {
        Add-AgentIssue $issues "Warning" "Scene" "Assets/scenes/main.scene" "main.scene does not appear to include AutoWireHelper." "Add AutoWireHelper to GameManager or verify all prefab references manually."
    }
}
else {
    Add-AgentIssue $issues "Error" "Scene" "Assets/scenes/main.scene" "Main scene is missing." "Restore the startup scene path expected by AGENTS.md."
}

$autoWirePath = Join-Path $Root "Code\code\Wiring\AutoWire.cs"
if (Test-Path -LiteralPath $autoWirePath) {
    $autoWire = Get-Content -LiteralPath $autoWirePath -Raw
    $requiredPaths = @(
        "prefabs/soldier_assault.prefab",
        "prefabs/soldier_counter_uav.prefab",
        "prefabs/soldier_heavy.prefab",
        "prefabs/pilot_ground.prefab",
        "prefabs/drone_gps.prefab",
        "prefabs/drone_fpv.prefab",
        "prefabs/drone_fpv_fiber.prefab",
        "prefabs/tracer_default.prefab"
    )
    foreach ($path in $requiredPaths) {
        if ($autoWire -notmatch [regex]::Escape($path)) {
            Add-AgentIssue $issues "Warning" "AutoWire" "Code/code/Wiring/AutoWire.cs" "AutoWire does not reference '$path'." "Extend AutoWire when adding or changing prefab references."
        }
    }
}
else {
    Add-AgentIssue $issues "Error" "AutoWire" "Code/code/Wiring/AutoWire.cs" "AutoWire helper is missing." "Restore the helper or document the replacement wiring flow."
}

$loadoutScript = Join-Path $Root "scripts\check_loadout_slots.ps1"
if (Test-Path -LiteralPath $loadoutScript) {
    Push-Location $Root
    try {
        $loadoutOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $loadoutScript 2>&1
        $loadoutExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($loadoutExit -ne 0) {
        Add-AgentIssue $issues "Error" "Loadout Slots" "scripts/check_loadout_slots.ps1" "Loadout slot audit failed." (($loadoutOutput | Out-String).Trim())
    }
    else {
        Add-AgentIssue $issues "Info" "Loadout Slots" "scripts/check_loadout_slots.ps1" "Loadout slot audit passed."
    }
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
