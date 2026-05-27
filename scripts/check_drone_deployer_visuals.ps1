param(
    [string]$Root = ""
)

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$errors = New-Object System.Collections.Generic.List[string]

function Add-Error {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
}

function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Error "Missing required file: $RelativePath"
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Read-Json {
    param([string]$RelativePath)
    $text = Read-Text $RelativePath
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return $text | ConvertFrom-Json
    }
    catch {
        Add-Error "Invalid JSON in ${RelativePath}: $($_.Exception.Message)"
        return $null
    }
}

function Get-GameObjects {
    param($Object)
    if ($null -eq $Object) {
        return @()
    }

    $objects = @($Object)
    foreach ($child in @($Object.Children)) {
        $objects += Get-GameObjects $child
    }

    return $objects
}

function Get-ChildByName {
    param(
        $Object,
        [string]$Name
    )

    foreach ($child in @($Object.Children)) {
        if ($child.Name -eq $Name) {
            return $child
        }
    }

    return $null
}

function Get-ComponentByType {
    param(
        $Object,
        [string]$Type
    )

    foreach ($component in @($Object.Components)) {
        if ($Type -eq "Sandbox.ModelRenderer" -and $component.PSObject.Properties.Name -contains "Model") {
            return $component
        }
        if ($Type -eq "DroneVsPlayers.DroneController" -and
            $component.PSObject.Properties.Name -contains "MaxSpeed" -and
            $component.PSObject.Properties.Name -contains "PropellerSpinDegreesPerSecond") {
            return $component
        }
        if ($Type -eq "DroneVsPlayers.DroneDeployer" -and
            $component.PSObject.Properties.Name -contains "GpsHeldDroneModelPath" -and
            $component.PSObject.Properties.Name -contains "FpvHeldDroneModelPath") {
            return $component
        }
        if ($Type -eq "DroneVsPlayers.DroneCamera" -and
            $component.PSObject.Properties.Name -contains "CameraToggleInput" -and
            $component.PSObject.Properties.Name -contains "ChaseDistance" -and
            $component.PSObject.Properties.Name -contains "ChaseHeight") {
            return $component
        }

        $typeProperty = $component.PSObject.Properties["__type"]
        if ($null -ne $typeProperty -and [string]$typeProperty.Value -eq $Type) {
            return $component
        }
    }

    return $null
}

function Require-Pattern {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        Add-Error $Message
    }
}

function Assert-TruthyJsonOption {
    param(
        [string]$RelativePath,
        [string]$PropertyName
    )

    $json = Read-Json $RelativePath
    if ($null -eq $json) {
        return
    }

    if (-not ($json.PSObject.Properties.Name -contains $PropertyName) -or $json.$PropertyName -ne $true) {
        Add-Error "$RelativePath must set $PropertyName to true so drone material slots are checked against exported FBX data."
    }
}

$deployer = Read-Text "Code\Player\DroneDeployer.cs"
$viewmodel = Read-Text "Code\Player\FirstPersonViewmodel.cs"
$droneCamera = Read-Text "Code\Drone\DroneCamera.cs"
$droneController = Read-Text "Code\Drone\DroneController.cs"
$gameSetup = Read-Text "Code\Game\GameSetup.cs"
$roundFlow = Read-Text "Code\Game\RoundFlowDebugCommands.cs"

Require-Pattern $viewmodel 'HiddenStaticVisualRoot' `
    "FirstPersonViewmodel needs a hidden static visual root so a launched/stowed hand drone cannot stay visible as a floating first-person copy."
Require-Pattern $viewmodel 'IsSameOrDescendant\(' `
    "FirstPersonViewmodel static copies must skip renderers under hidden held-item visual roots."
Require-Pattern $viewmodel 'Key\s*=\s*\$"deployer:\{deployer\.GameObject\.Id\}:\{chosenDrone\}:\{deployer\.DroneInFlight\}"' `
    "DroneDeployer viewmodel keys must include the selected drone type and launch state so the copied visual rebuilds when those states change."

Require-Pattern $deployer 'LeftHandIkFpOffset' `
    "DroneDeployer needs a separate LeftHandIkFpOffset so the controller grip target is not forced to the controller model origin."
Require-Pattern $deployer 'RightHandIkFpOffset' `
    "DroneDeployer needs a separate RightHandIkFpOffset so the drone grip target is not forced to the drone model origin."
Require-Pattern $deployer 'LeftHandIkTpLocalPos' `
    "DroneDeployer needs a separate LeftHandIkTpLocalPos so third-person controller grip targets can differ from visuals."
Require-Pattern $deployer 'RightHandIkTpLocalPos' `
    "DroneDeployer needs a separate RightHandIkTpLocalPos so third-person drone grip targets can differ from visuals."
Require-Pattern $deployer 'chosenDrone\s+switch[\s\S]*DroneType\.Gps\s*=>\s*GpsHeldDroneModelPath[\s\S]*DroneType\.Fpv\s*=>\s*FpvHeldDroneModelPath[\s\S]*DroneType\.FiberOpticFpv\s*=>\s*FiberHeldDroneModelPath' `
    "DroneDeployer must select the held drone visual from PilotSoldier.ChosenDrone instead of always showing the FPV model."
Require-Pattern $deployer 'GpsHeldDroneModelPath\s*\{\s*get;\s*set;\s*\}\s*=\s*"models/drone_high\.vmdl"' `
    "DroneDeployer GPS held visual must use the textured GPS drone model path."
Require-Pattern $deployer 'FpvHeldDroneModelPath\s*\{\s*get;\s*set;\s*\}\s*=\s*"models/drone_fpv\.vmdl"' `
    "DroneDeployer FPV held visual must use the textured FPV drone model path."
Require-Pattern $deployer 'FiberHeldDroneModelPath\s*\{\s*get;\s*set;\s*\}\s*=\s*"models/drone_fpv_fiber\.vmdl"' `
    "DroneDeployer Fiber FPV held visual must use the distinct Fiber FPV model path."
Require-Pattern $deployer 'GpsHeldPropellerModelPath\s*\{\s*get;\s*set;\s*\}\s*=\s*"models/drone_gps_prop\.vmdl"' `
    "DroneDeployer GPS held propellers must use the separate textured GPS propeller model path."
Require-Pattern $deployer 'FpvHeldPropellerModelPath\s*\{\s*get;\s*set;\s*\}\s*=\s*"models/drone_fpv_prop\.vmdl"' `
    "DroneDeployer needs a held FPV propeller model path so the first-person FPV/Fiber preview includes props."
Require-Pattern $deployer 'DroneType\.Gps\s*=>\s*GpsHeldPropellerModelPath' `
    "DroneDeployer must choose the GPS propeller model for GPS held previews instead of reusing the FPV propeller model."
Require-Pattern $deployer 'new\(\s*"HeldPropeller_FL",\s*new Vector3\(\s*58\.36f,\s*86\.4f,\s*6\.6f\s*\)' `
    "DroneDeployer GPS held propellers must use the separate GPS prop model at the converted Blender motor-cap positions."
Require-Pattern $deployer 'GpsHeldDroneFpRotationOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*new\(\s*0f,\s*-90f,\s*0f\s*\)' `
    "DroneDeployer GPS held first-person preview must rotate the Blender +X camera/nose axis to face away from the player."
Require-Pattern $deployer 'GetHeldDroneFpRotation\(\s*chosenDrone\s*\)' `
    "DroneDeployer must apply a variant-specific held first-person rotation so GPS orientation does not inherit the FPV axis."
Require-Pattern $deployer 'EnsureHeldPropellerVisuals\(' `
    "DroneDeployer should create or resolve held propeller children for prefab compatibility."
Require-Pattern $deployer 'UpdateHeldPropellerVisuals\(' `
    "DroneDeployer should update held propeller visibility when the selected drone variant changes."
Require-Pattern $deployer 'chosenDrone\s+is\s+DroneType\.Gps\s+or\s+DroneType\.Fpv\s+or\s+DroneType\.FiberOpticFpv' `
    "DroneDeployer held propellers should be visible for GPS, FPV, and Fiber FPV so the first-person drone preview is the full model."
Require-Pattern $deployer 'if\s*\(\s*!DroneInFlight\s*&&\s*pilot\.ResolveDrone\(\)\.IsValid\(\)\s*\)[\s\S]{0,180}DroneInFlight\s*=\s*true' `
    "DroneDeployer must promote DroneInFlight when the pilot already has a linked live drone so debug/probe-spawned drones cannot allow a second deploy."
Require-Pattern $deployer 'DroneInFlight\s*\|\|\s*pilot\.ResolveDrone\(\)\.IsValid\(\)' `
    "DroneDeployer.ServerLaunchDrone must reject launches when the pilot already has any linked live drone, not only when DroneInFlight is true."
Require-Pattern $roundFlow 'Where\(\s*drone\s*=>\s*IsProbeDroneLinkedTo\(\s*drone,\s*pilot,\s*local\.Id\s*\)\s*\)' `
    "dvp_fpv_visual_probe must find every drone linked to the local pilot, not only PilotSoldier.ResolveDrone, so repeated probes cannot leave duplicate flyable drones."
Require-Pattern $roundFlow 'linkedDrone\.GameObject\.Destroy\(\)' `
    "dvp_fpv_visual_probe must destroy extra linked drones before creating or reusing the proof drone."
Require-Pattern $roundFlow 'deployer\.DroneInFlight\s*=\s*true' `
    "dvp_fpv_visual_probe must mark DroneDeployer.DroneInFlight so the pilot cannot deploy a second drone from the loadout slot during proof."
Require-Pattern $viewmodel 'CopyRenderer\.Model\s*=\s*visual\.Source\.Model' `
    "FirstPersonViewmodel static copies must refresh renderer models from the source so GPS propeller copies update after DroneDeployer switches the serialized FPV fallback to GPS."
Require-Pattern $droneCamera 'ShowVisualInFirstPerson\s*\{\s*get;\s*set;\s*\}\s*=\s*true' `
    "DroneCamera needs first-person self-visual rendering enabled by default so FPV pilots can see the full textured drone model."
Require-Pattern $droneCamera 'SetPilotVisualHidden\(\s*firstPersonActive\s*&&\s*!ShowVisualInFirstPerson\s*\)' `
    "DroneCamera must not force the drone Visual to ShadowsOnly in first-person mode when ShowVisualInFirstPerson is enabled."
Require-Pattern $droneController 'VisualRotationOffset\s*\{\s*get;\s*set;\s*\}' `
    "DroneController needs a visual rotation offset so GPS can face the root flight direction without fighting ApplyVisualTilt."
Require-Pattern $droneController 'VisualRotationOffset\.ToRotation\(\)\s*\*\s*tilt' `
    "DroneController.ApplyVisualTilt must preserve the configured visual rotation offset while adding cosmetic tilt."
Require-Pattern $deployer 'pilot\.LinkedDroneId\s*=\s*clone\.Id' `
    "DroneDeployer should be the code path that links a launched drone to the pilot."
Require-Pattern $deployer 'DroneInFlight\s*=\s*true' `
    "DroneDeployer should set DroneInFlight only after a manual launch clone is created."

$spawnPilotStart = $gameSetup.IndexOf("void SpawnPilotPawn")
$spawnSoldierStart = if ($spawnPilotStart -ge 0) { $gameSetup.IndexOf("void SpawnSoldierPawn", $spawnPilotStart) } else { -1 }
if ($spawnPilotStart -lt 0 -or $spawnSoldierStart -lt 0) {
    Add-Error "GameSetup SpawnPilotPawn/SpawnSoldierPawn boundaries could not be found for the no-auto-launch guard."
}
else {
    $spawnPilotBody = $gameSetup.Substring($spawnPilotStart, $spawnSoldierStart - $spawnPilotStart)
    foreach ($forbidden in @("ResolveDronePrefab", "LinkedDroneId\s*=", "_drones\s*\[")) {
        if ($spawnPilotBody -match $forbidden) {
            Add-Error "GameSetup.SpawnPilotPawn must not auto-spawn, track, or link a drone; launch should stay manual through DroneDeployer.ServerLaunchDrone."
            break
        }
    }
}

$pilotPrefab = Read-Json "Assets\prefabs\pilot_ground.prefab"
if ($null -ne $pilotPrefab -and $null -ne $pilotPrefab.RootObject) {
    $droneDeployerObject = @(Get-GameObjects $pilotPrefab.RootObject | Where-Object { $_.Name -eq "DroneDeployer" } | Select-Object -First 1)
    if ($droneDeployerObject.Count -eq 0) {
        Add-Error "Assets/prefabs/pilot_ground.prefab is missing the DroneDeployer object."
    }
    else {
        $deployerComponent = Get-ComponentByType $droneDeployerObject[0] "DroneVsPlayers.DroneDeployer"
        if ($null -ne $deployerComponent) {
            if (-not ($deployerComponent.PSObject.Properties.Name -contains "FiberHeldDroneModelPath") -or
                [string]$deployerComponent.FiberHeldDroneModelPath -ne "models/drone_fpv_fiber.vmdl") {
                Add-Error "pilot_ground DroneDeployer must serialize FiberHeldDroneModelPath as models/drone_fpv_fiber.vmdl so Fiber pilots preview the correct model before launch."
            }
        }

        $rightHand = Get-ChildByName $droneDeployerObject[0] "RightHand"
        if ($null -eq $rightHand) {
            Add-Error "pilot_ground DroneDeployer is missing the RightHand held-drone visual."
        }
        else {
            $renderer = Get-ComponentByType $rightHand "Sandbox.ModelRenderer"
            if ($null -eq $renderer) {
                Add-Error "pilot_ground DroneDeployer/RightHand needs a ModelRenderer."
            }
            elseif ([string]$renderer.Tint -ne "1,1,1,1") {
                Add-Error "pilot_ground DroneDeployer/RightHand should use neutral tint 1,1,1,1; gray tint makes the selected held drone read as untextured."
            }

            foreach ($propellerName in @("HeldPropeller_FL", "HeldPropeller_FR", "HeldPropeller_BL", "HeldPropeller_BR")) {
                $propeller = Get-ChildByName $rightHand $propellerName
                if ($null -eq $propeller) {
                    Add-Error "pilot_ground DroneDeployer/RightHand is missing $propellerName, so the first-person FPV/Fiber held drone can render without propellers."
                    continue
                }

                $propellerRenderer = Get-ComponentByType $propeller "Sandbox.ModelRenderer"
                if ($null -eq $propellerRenderer -or [string]$propellerRenderer.Model -ne "models/drone_fpv_prop.vmdl") {
                    Add-Error "pilot_ground DroneDeployer/RightHand/$propellerName must render models/drone_fpv_prop.vmdl."
                }
            }
        }
    }
}

$gpsPrefab = Read-Json "Assets\prefabs\drone_gps.prefab"
if ($null -ne $gpsPrefab -and $null -ne $gpsPrefab.RootObject) {
    $gpsController = Get-ComponentByType $gpsPrefab.RootObject "DroneVsPlayers.DroneController"
    if ($null -eq $gpsController) {
        Add-Error "Assets/prefabs/drone_gps.prefab is missing DroneController."
    }
    else {
        if (-not ($gpsController.PSObject.Properties.Name -contains "VisualRotationOffset") -or
            [string]$gpsController.VisualRotationOffset -ne "0,-90,0") {
            Add-Error "drone_gps DroneController must serialize VisualRotationOffset as 0,-90,0 so the launched GPS drone camera/nose faces away from the pilot instead of left."
        }
    }

    $gpsCamera = Get-ComponentByType $gpsPrefab.RootObject "DroneVsPlayers.DroneCamera"
    if ($null -eq $gpsCamera) {
        Add-Error "Assets/prefabs/drone_gps.prefab is missing DroneCamera."
    }
    else {
        if ([string]$gpsCamera.ChaseDistance -ne "135" -or [string]$gpsCamera.ChaseHeight -ne "30") {
            Add-Error "drone_gps DroneCamera must keep third-person proof framing at ChaseDistance 135 and ChaseHeight 30 so the GPS drone rotors are visible in the lower third."
        }
    }
}

$gpsPrefab = Read-Json "Assets\prefabs\drone_gps.prefab"
if ($null -ne $gpsPrefab -and $null -ne $gpsPrefab.RootObject) {
    $gpsVisual = @(Get-GameObjects $gpsPrefab.RootObject | Where-Object { $_.Name -eq "Visual" } | Select-Object -First 1)
    if ($gpsVisual.Count -eq 0) {
        Add-Error "Assets/prefabs/drone_gps.prefab is missing the Visual object."
    }
    else {
        foreach ($node in @(Get-GameObjects $gpsVisual[0])) {
            $renderer = Get-ComponentByType $node "Sandbox.ModelRenderer"
            if ($null -eq $renderer) {
                continue
            }

            if ([string]$renderer.Model -in @("models/drone_high.vmdl", "models/drone_gps_prop.vmdl") -and
                [string]$renderer.Tint -ne "1,1,1,1") {
                Add-Error "GPS drone visual renderer '$($node.Name)' must use neutral tint 1,1,1,1 so the textured Blender model is not washed green in game."
            }

            if ($node.Name -like "Propeller_*" -and [string]$renderer.Model -ne "models/drone_gps_prop.vmdl") {
                Add-Error "GPS drone propeller '$($node.Name)' must render the separate textured GPS propeller model, not the FPV propeller fallback."
            }

            if ($node.Name -like "Propeller_*" -and [string]$node.Scale -ne "1,1,1") {
                Add-Error "GPS drone propeller '$($node.Name)' must use normal Scale 1,1,1 like the working FPV separate-prop model setup."
            }
        }

        $expectedGpsMotorSockets = @{
            "FL" = "21.59,14.6,1.65"
            "FR" = "21.59,-14.6,1.65"
            "BL" = "-21.59,14.6,1.65"
            "BR" = "-21.59,-14.6,1.65"
        }
        $expectedGpsPropOffsets = @{
            "FL" = "-7,7,0"
            "FR" = "-7,-7,0"
            "BL" = "7,7,0"
            "BR" = "7,-7,0"
        }
        foreach ($corner in $expectedGpsMotorSockets.Keys) {
            $socketName = "MotorSocket_$corner"
            $propellerName = "Propeller_$corner"
            $socket = Get-ChildByName $gpsVisual[0] $socketName
            if ($null -eq $socket) {
                Add-Error "GPS drone Visual is missing motor socket child '$socketName'."
                continue
            }

            if ([string]$socket.Position -ne $expectedGpsMotorSockets[$corner]) {
                Add-Error "GPS drone motor socket '$socketName' must be positioned at '$($expectedGpsMotorSockets[$corner])' from the exported GPS MotorCap center/top coordinates."
            }

            $propeller = Get-ChildByName $socket $propellerName
            if ($null -eq $propeller) {
                Add-Error "GPS drone motor socket '$socketName' is missing attached propeller child '$propellerName'."
                continue
            }

            if ([string]$propeller.Position -ne $expectedGpsPropOffsets[$corner]) {
                Add-Error "GPS drone propeller '$propellerName' must use local mesh-origin compensation '$($expectedGpsPropOffsets[$corner])' under '$socketName' so the blades stay centered on the motor cap."
            }
        }
    }
}

Assert-TruthyJsonOption "scripts\drone_fpv_asset_pipeline.json" "verify_vmdl_sources_against_fbx"
Assert-TruthyJsonOption "scripts\drone_fpv_fiber_asset_pipeline.json" "verify_vmdl_sources_against_fbx"
Assert-TruthyJsonOption "scripts\drone_fpv_prop_asset_pipeline.json" "verify_vmdl_sources_against_fbx"
Assert-TruthyJsonOption "scripts\drone_gps_prop_asset_pipeline.json" "verify_vmdl_sources_against_fbx"

$gpsAssetConfig = Read-Json "scripts\drone_asset_pipeline.json"
if ($null -ne $gpsAssetConfig) {
    if (-not ($gpsAssetConfig.PSObject.Properties.Name -contains "vmdl_use_global_default") -or
        $gpsAssetConfig.vmdl_use_global_default -ne $false) {
        Add-Error "scripts/drone_asset_pipeline.json must disable vmdl_use_global_default so unmapped GPS drone materials cannot silently fall back to default gray."
    }

    if (-not ($gpsAssetConfig.PSObject.Properties.Name -contains "strict_vmdl_material_sources") -or
        $gpsAssetConfig.strict_vmdl_material_sources -ne $true) {
        Add-Error "scripts/drone_asset_pipeline.json must enable strict_vmdl_material_sources for the textured GPS drone material contract."
    }
}

$gpsPropConfig = Read-Json "scripts\drone_gps_prop_asset_pipeline.json"
if ($null -ne $gpsPropConfig) {
    foreach ($expectation in @(
        @{ Name = "source_blend"; Value = "drone_model.blend/drone_gps_prop.blend" },
        @{ Name = "target_fbx"; Value = "Assets/models/drone_gps_prop.fbx" },
        @{ Name = "target_vmdl"; Value = "Assets/models/drone_gps_prop.vmdl" },
        @{ Name = "model_resource_path"; Value = "models/drone_gps_prop.vmdl" }
    )) {
        $name = $expectation.Name
        if (-not ($gpsPropConfig.PSObject.Properties.Name -contains $name) -or [string]$gpsPropConfig.$name -ne $expectation.Value) {
            Add-Error "scripts/drone_gps_prop_asset_pipeline.json must set $name to '$($expectation.Value)'."
        }
    }

    if (-not ($gpsPropConfig.PSObject.Properties.Name -contains "material_remap") -or
        $null -eq $gpsPropConfig.material_remap -or
        -not ($gpsPropConfig.material_remap.PSObject.Properties.Name -contains "PropellerGrey") -or
        [string]$gpsPropConfig.material_remap.PropellerGrey -ne "materials/drone_propeller.vmat") {
        Add-Error "scripts/drone_gps_prop_asset_pipeline.json must remap Blender PropellerGrey to materials/drone_propeller.vmat."
    }

    if (-not ($gpsPropConfig.PSObject.Properties.Name -contains "vmdl_use_global_default") -or
        $gpsPropConfig.vmdl_use_global_default -ne $false) {
        Add-Error "scripts/drone_gps_prop_asset_pipeline.json must disable vmdl_use_global_default so the GPS propeller cannot fall back to default gray."
    }

    if (-not ($gpsPropConfig.PSObject.Properties.Name -contains "strict_vmdl_material_sources") -or
        $gpsPropConfig.strict_vmdl_material_sources -ne $true) {
        Add-Error "scripts/drone_gps_prop_asset_pipeline.json must enable strict_vmdl_material_sources."
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Drone deployer visual guard failed:"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Drone deployer visual guard passed."
