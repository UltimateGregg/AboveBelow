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

$pilotPrefab = Read-Json "Assets\prefabs\pilot_ground.prefab"
if ($null -ne $pilotPrefab -and $null -ne $pilotPrefab.RootObject) {
    $droneDeployerObject = @(Get-GameObjects $pilotPrefab.RootObject | Where-Object { $_.Name -eq "DroneDeployer" } | Select-Object -First 1)
    if ($droneDeployerObject.Count -eq 0) {
        Add-Error "Assets/prefabs/pilot_ground.prefab is missing the DroneDeployer object."
    }
    else {
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
        }
    }
}

Assert-TruthyJsonOption "scripts\drone_fpv_asset_pipeline.json" "verify_vmdl_sources_against_fbx"
Assert-TruthyJsonOption "scripts\drone_fpv_prop_asset_pipeline.json" "verify_vmdl_sources_against_fbx"

if ($errors.Count -gt 0) {
    Write-Host "Drone deployer visual guard failed:"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Drone deployer visual guard passed."
