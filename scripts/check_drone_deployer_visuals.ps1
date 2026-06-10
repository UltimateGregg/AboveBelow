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

function Assert-DeployerUsesStockViewmodelArms {
    param([string]$RelativePath)

    $raw = Read-Text $RelativePath
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return
    }

    # The rejected citizen-body-hands path is gone: the pilot deployer now shares
    # the stock first-person viewmodel arms (with per-hand grip IK) in first person.
    if ($raw -match '"UsePilotBodyHands"') {
        Add-Error "$RelativePath must not serialize the removed UsePilotBodyHands flag; the pilot deployer uses the stock first-person viewmodel arms in first person."
    }
}

function Assert-DeployerFirstPersonIkOffsets {
    param([string]$RelativePath)

    $raw = Read-Text $RelativePath
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return
    }

    if ($raw -notmatch '"__type"\s*:\s*"DroneVsPlayers\.DroneDeployer"[\s\S]*?"LeftHandIkFpOffset"\s*:\s*"8,-14,2"') {
        Add-Error "$RelativePath DroneDeployer LeftHandIkFpOffset should stay at 8,-14,2 so the controller-side hand remains visible in first person."
    }

    if ($raw -notmatch '"__type"\s*:\s*"DroneVsPlayers\.DroneDeployer"[\s\S]*?"RightHandIkFpOffset"\s*:\s*"37,13,-4"') {
        Add-Error "$RelativePath DroneDeployer RightHandIkFpOffset should stay at 37,13,-4 so the drone-side hand remains visible in first person."
    }
}

$deployer = Read-Text "Code\Player\DroneDeployer.cs"
$viewmodel = Read-Text "Code\Player\FirstPersonViewmodel.cs"
foreach ($partial in Get-ChildItem -Path (Join-Path $Root "Code\Player\FirstPersonViewmodel.*.cs") -ErrorAction SilentlyContinue) {
    $viewmodel += "`n" + (Get-Content -LiteralPath $partial.FullName -Raw)
}
$controller = Read-Text "Code\Player\GroundPlayerController.cs"
$droneCamera = Read-Text "Code\Drone\DroneCamera.cs"
$droneController = Read-Text "Code\Drone\DroneController.cs"
$gameSetup = Read-Text "Code\Game\GameSetup.cs"
foreach ($partial in Get-ChildItem -Path (Join-Path $Root "Code\Game\GameSetup.*.cs") -ErrorAction SilentlyContinue) {
    $gameSetup += "`n" + (Get-Content -LiteralPath $partial.FullName -Raw)
}
$roundFlow = Read-Text "Code\Game\RoundFlowDebugCommands.cs"

Require-Pattern $viewmodel 'HiddenStaticVisualRoot' `
    "FirstPersonViewmodel needs a hidden static visual root so a launched/stowed hand drone cannot stay visible as a floating first-person copy."
Require-Pattern $viewmodel 'IsSameOrDescendant\(' `
    "FirstPersonViewmodel static copies must skip renderers under hidden held-item visual roots."
Require-Pattern $viewmodel 'Key\s*=\s*\$"deployer:\{deployer\.GameObject\.Id\}:\{chosenDrone\}:\{deployer\.DroneInFlight\}"' `
    "DroneDeployer viewmodel keys must include the selected drone type and launch state so the copied visual rebuilds when those states change."
# Pilot deployer first-person hands: the rejected citizen-body-hands path is gone.
# The deployer now uses the shared stock first-person viewmodel arms (static
# fallback) with per-hand IK so the left hand grips the controller and the right
# hand grips the held drone, while third-person/remote still use Citizen hands.
if ($viewmodel -match 'UsesPilotHumanBodyHands') {
    Add-Error "FirstPersonViewmodel must not keep the rejected UsesPilotHumanBodyHands citizen-body-hands path; the pilot deployer uses the stock first-person viewmodel arms."
}
Require-Pattern $viewmodel 'RenderMode\s*=\s*ViewmodelRenderMode\.StaticFallback' `
    "Pilot deployer first-person visuals must use the stock first-person arms static-fallback path so the hands match the hunter weapon viewmodel arms."
Require-Pattern $viewmodel 'UseEyeArmsAnchor\s*=\s*true' `
    "Pilot deployer must anchor the stock first-person arms near the camera (eye anchor) so the forearms read as first-person arms while the hands IK to the controller/drone grips."
Require-Pattern $viewmodel 'LeftHandTarget\s*=\s*deployer\.LeftHandIkTarget' `
    "Pilot deployer must drive the stock left arm IK from the controller-side grip target."
Require-Pattern $viewmodel 'RightHandTarget\s*=\s*deployer\.RightHandIkTarget' `
    "Pilot deployer must drive the stock right arm IK from the held-drone-side grip target."
if ($controller -match 'ShouldShowPilotBodyHands') {
    Add-Error "GroundPlayerController must not keep the rejected ShouldShowPilotBodyHands citizen-body-hands exception; first-person body hands are hidden whenever the local viewmodel arms are active."
}
Require-Pattern $controller 'hideBodyHands\s*=\s*handsOnly\s*&&\s*UseLocalFirstPersonViewmodel\b' `
    "GroundPlayerController must hide the Citizen body hands in first person whenever the local viewmodel arms are active (weapons, grenades, and the pilot deployer)."
Require-Pattern $controller '"Chest",\s*handsOnly\s*\?\s*CitizenBodyGroupHidden\s*:\s*CitizenBodyGroupVisible' `
    "GroundPlayerController must hide the Citizen Chest bodygroup in first person now that the pilot deployer uses stock viewmodel arms instead of body forearms."
Require-Pattern $controller '"Hands",\s*hideBodyHands\s*\?\s*CitizenBodyGroupHidden\s*:\s*CitizenBodyGroupVisible' `
    "GroundPlayerController must still hide body hands when local viewmodel arms are active for weapons, grenades, and the pilot deployer."
Assert-DeployerUsesStockViewmodelArms "Assets\prefabs\pilot_ground.prefab"
Assert-DeployerUsesStockViewmodelArms "Assets\prefabs\items\pilot_drone_deployer_held.prefab"
Assert-DeployerFirstPersonIkOffsets "Assets\prefabs\pilot_ground.prefab"
Assert-DeployerFirstPersonIkOffsets "Assets\prefabs\items\pilot_drone_deployer_held.prefab"

Require-Pattern $deployer 'LeftHandIkFpOffset' `
    "DroneDeployer needs a separate LeftHandIkFpOffset so the controller grip target is not forced to the controller model origin."
Require-Pattern $deployer 'RightHandIkFpOffset' `
    "DroneDeployer needs a separate RightHandIkFpOffset so the drone grip target is not forced to the drone model origin."
Require-Pattern $deployer 'var\s+rightTarget\s*=\s*RightHandIkTarget\.IsValid\(\)\s*\?\s*RightHandIkTarget\s*:\s*RightHandVisual' `
    "DroneDeployer must drive the right pilot hand from the explicit IK grip target instead of the held drone model origin."
Require-Pattern $deployer 'PilotHandHoldType' `
    "DroneDeployer needs a pilot-only hand hold type so drone-controller grip poses can be tuned without changing hunter weapons or grenades."
Require-Pattern $deployer 'helper\.HoldType\s*=\s*PilotHandHoldType' `
    "DroneDeployer must apply the pilot-only hand hold type to the citizen hand helper."
Require-Pattern $deployer 'UseVisualRelativeFirstPersonIkTargets' `
    "DroneDeployer first-person pilot hand IK should be anchored to the held controller/drone visuals so hands stay connected while moving and turning."
Require-Pattern $deployer 'firstPersonIkAnchor\.WorldTransform\.PointToWorld\(\s*ikFpOffset\s*\)' `
    "DroneDeployer must resolve first-person IK target position from the held visual transform, not only from independent eye-space offsets."
Require-Pattern $deployer 'firstPersonIkAnchor\.WorldTransform\.RotationToWorld\(\s*ikFpRot\.ToRotation\(\)\s*\)' `
    "DroneDeployer must resolve first-person IK target rotation from the held visual transform so grip anchors rotate with the controller/drone."
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
Require-Pattern $deployer 'HeldPropellerPrefabPath\s*=\s*"prefabs/items/held_drone_propeller\.prefab"' `
    "DroneDeployer should resolve held drone propeller preview children from a reusable prefab before creating fallback objects."
Require-Pattern $deployer 'GameObject\.GetPrefab\(\s*HeldPropellerPrefabPath\s*\)' `
    "DroneDeployer held propeller previews should use the reusable held_drone_propeller prefab path."
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
Require-Pattern $roundFlow 'dvp_pilot_deployer_visual_probe' `
    "RoundFlowDebugCommands needs a ground-side pilot deployer visual proof command for GPS, FPV, and Fiber pilots."
Require-Pattern $roundFlow 'deployer\.DroneInFlight\s*=\s*false' `
    "Pilot deployer visual proof must keep the held drone in hand instead of switching to launched-drone state."
Require-Pattern $roundFlow 'remote\.DroneViewActive\s*=\s*false' `
    "Pilot deployer visual proof must stay in ground first-person mode, not drone-camera mode."
Require-Pattern $roundFlow 'loadout\.SelectSlot\(\s*SoldierLoadout\.PrimarySlot\s*\)' `
    "Pilot deployer visual proof must select the deployer slot so the left controller and right held drone are visible together."
Require-Pattern $gameSetup 'DebugSpawnPilotPawnForProbe[\s\S]{0,260}RequireRoleChoice\s*=\s*false' `
    "Pilot deployer visual proof must suppress the loadout picker through the forced pilot spawn helper so screenshots show the first-person held controller and drone."
Require-Pattern $roundFlow 'setup\.DebugSpawnPilotPawnForProbe\(\s*local,\s*selectedType\s*\)' `
    "Pilot deployer visual proof must use the forced pilot spawn helper instead of racing the normal loadout selection timing."
Require-Pattern $roundFlow 'DestroyExtraLocalPilotPawns' `
    "Pilot deployer visual proof must remove stale same-owner pilot pawns so screenshots do not include duplicate pilot bodies."
Require-Pattern $roundFlow 'controller\.FirstPerson\s*=\s*true' `
    "Pilot deployer visual proof must force the local pilot controller into first-person mode."
Require-Pattern $viewmodel 'CopyRenderer\.Model\s*=\s*visual\.Source\.Model' `
    "FirstPersonViewmodel static copies must refresh renderer models from the source so GPS propeller copies update after DroneDeployer switches the serialized FPV fallback to GPS."
Require-Pattern $droneCamera 'ShowVisualInFirstPerson\s*\{\s*get;\s*set;\s*\}\s*=\s*true' `
    "DroneCamera needs first-person self-visual rendering enabled by default so FPV pilots can see the full textured drone model."
Require-Pattern $droneCamera 'SetPilotVisualHidden\(\s*firstPersonActive\s*&&\s*!ShowVisualInFirstPerson\s*\)' `
    "DroneCamera must not force the drone Visual to ShadowsOnly in first-person mode when ShowVisualInFirstPerson is enabled."
Require-Pattern $droneController 'VisualRotationOffset\s*\{\s*get;\s*set;\s*\}' `
    "DroneController needs a visual rotation offset so GPS can face the root flight direction without fighting ApplyVisualTilt."
Require-Pattern $droneController 'var\s+pitch\s*=\s*\(\s*localVel\.x\s*/\s*Math\.Max\(\s*MaxSpeed,\s*1f\s*\)\s*\)\s*\*\s*VisualTiltDegrees' `
    "DroneController.ApplyVisualTilt must pitch the visual nose-down for positive forward velocity and nose-up for backward velocity."
Require-Pattern $droneController 'tilt\s*\*\s*VisualRotationOffset\.ToRotation\(\)' `
    "DroneController.ApplyVisualTilt must apply movement tilt in the drone root frame before the GPS visual yaw offset, otherwise GPS forward/back motion leans on the wrong axis."
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
$heldPropellerPrefab = Read-Json "Assets\prefabs\items\held_drone_propeller.prefab"
if ($null -ne $heldPropellerPrefab -and $null -ne $heldPropellerPrefab.RootObject) {
    if ([string]$heldPropellerPrefab.RootObject.Name -ne "HeldDronePropeller") {
        Add-Error "Assets/prefabs/items/held_drone_propeller.prefab root object should be named HeldDronePropeller."
    }

    $propellerRenderer = Get-ComponentByType $heldPropellerPrefab.RootObject "Sandbox.ModelRenderer"
    if ($null -eq $propellerRenderer) {
        Add-Error "Assets/prefabs/items/held_drone_propeller.prefab must carry a ModelRenderer so DroneDeployer only needs to assign the selected propeller model."
    }
}

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
