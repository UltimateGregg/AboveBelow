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

function Get-Vector3 {
    param(
        [string]$Value,
        [string]$Context
    )

    $parts = @($Value -split ',' | ForEach-Object { $_.Trim() })
    if ($parts.Count -ne 3) {
        Add-Error "$Context must be a Vector3 string, got '$Value'."
        return $null
    }

    $values = New-Object double[] 3
    for ($i = 0; $i -lt 3; $i++) {
        $parsed = 0.0
        if (-not [double]::TryParse($parts[$i], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            Add-Error "$Context contains a non-numeric coordinate '$($parts[$i])'."
            return $null
        }
        $values[$i] = $parsed
    }

    return $values
}

function Has-M4Visual {
    param($Weapon)

    foreach ($child in @($Weapon.Children)) {
        if ($child.Name -ne "WeaponVisual") {
            continue
        }

        foreach ($component in @($child.Components)) {
            if ($component.Model -eq "models/weapons/assault_rifle_m4.vmdl") {
                return $true
            }
        }
    }

    return $false
}

function Has-VisualModel {
    param(
        $Weapon,
        [string]$ModelPath
    )

    foreach ($child in @($Weapon.Children)) {
        if ($child.Name -ne "WeaponVisual") {
            continue
        }

        foreach ($component in @($child.Components)) {
            if ($component.Model -eq $ModelPath) {
                return $true
            }
        }
    }

    return $false
}

function Assert-M4HandguardGripAnchor {
    param([string]$RelativePath)

    $prefab = Read-Json $RelativePath
    if ($null -eq $prefab -or $null -eq $prefab.RootObject) {
        return
    }

    $m4Weapons = @(Get-GameObjects $prefab.RootObject | Where-Object {
        $_.Name -eq "Weapon" -and (Has-M4Visual $_)
    })

    if ($m4Weapons.Count -eq 0) {
        Add-Error "$RelativePath should contain an M4 Weapon object for first-person handguard anchoring."
        return
    }

    foreach ($weapon in $m4Weapons) {
        $leftHand = @($weapon.Children | Where-Object { $_.Name -eq "LeftHandIk" } | Select-Object -First 1)
        if ($leftHand.Count -eq 0) {
            Add-Error "$RelativePath M4 weapon is missing LeftHandIk."
            continue
        }

        $position = Get-Vector3 $leftHand[0].Position "$RelativePath M4 LeftHandIk.Position"
        if ($null -eq $position) {
            continue
        }

        if ($position[0] -lt 6 -or $position[0] -gt 13 -or $position[2] -lt 0.5 -or $position[2] -gt 2.5) {
            Add-Error "$RelativePath M4 LeftHandIk should sit on the handguard grip zone (x 6-13, z 0.5-2.5), got '$($leftHand[0].Position)'."
        }
    }
}

function Assert-PilotMp7HeldScale {
    $relativePath = "Assets\prefabs\pilot_ground.prefab"
    $prefab = Read-Json $relativePath
    if ($null -eq $prefab -or $null -eq $prefab.RootObject) {
        return
    }

    $mp7Weapons = @(Get-GameObjects $prefab.RootObject | Where-Object {
        $_.Name -eq "Weapon" -and (Has-VisualModel $_ "models/weapons/smg_mp7.vmdl")
    })

    if ($mp7Weapons.Count -eq 0) {
        Add-Error "$relativePath should contain the pilot MP7 Weapon object."
        return
    }

    foreach ($weapon in $mp7Weapons) {
        if (-not ($weapon.PSObject.Properties.Name -contains "Scale")) {
            Add-Error "$relativePath pilot MP7 Weapon should declare Scale 0.5,0.5,0.5 so the held model and IK/muzzle sockets shrink together."
            continue
        }

        if ($weapon.Scale -ne "0.5,0.5,0.5") {
            Add-Error "$relativePath pilot MP7 Weapon Scale should be 0.5,0.5,0.5, got '$($weapon.Scale)'."
        }
    }
}

function Assert-M4ModelDocScale {
    $relativePath = "Assets\models\weapons\assault_rifle_m4.vmdl"
    $raw = Read-Text $relativePath
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return
    }

    $scaleMatch = [regex]::Match($raw, 'import_scale\s*=\s*([0-9.]+)')
    if (-not $scaleMatch.Success) {
        Add-Error "$relativePath must declare RenderMeshFile import_scale so the M4 does not silently reimport at source scale."
        return
    }

    $scale = 0.0
    if (-not [double]::TryParse($scaleMatch.Groups[1].Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$scale)) {
        Add-Error "$relativePath import_scale is not numeric: '$($scaleMatch.Groups[1].Value)'."
        return
    }

    if ([Math]::Abs($scale - 0.013) -gt 0.000001) {
        Add-Error "$relativePath import_scale should stay at 0.013 for first-person M4 camera clearance, got '$($scaleMatch.Groups[1].Value)'."
    }
}

function Assert-M4AssetPipelineScale {
    $relativePath = "scripts\assault_rifle_m4_asset_pipeline.json"
    $config = Read-Json $relativePath
    if ($null -eq $config) {
        return
    }

    if (-not ($config.PSObject.Properties.Name -contains "vmdl_import_scale")) {
        Add-Error "$relativePath must declare vmdl_import_scale 0.013 so a future M4 export cannot restore the oversized ModelDoc scale."
        return
    }

    $configuredScale = [double]$config.vmdl_import_scale
    if ([Math]::Abs($configuredScale - 0.013) -gt 0.000001) {
        Add-Error "$relativePath vmdl_import_scale should be 0.013, got '$($config.vmdl_import_scale)'."
    }

    $pipeline = Read-Text "scripts\asset_pipeline.py"
    Require-Pattern $pipeline 'vmdl_import_scale' "scripts\asset_pipeline.py must write the configured vmdl_import_scale instead of hardcoding import_scale = 1.0."
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

$viewmodel = Read-Text "Code\Player\FirstPersonViewmodel.cs"
$controller = Read-Text "Code\Player\GroundPlayerController.cs"
$hitscan = Read-Text "Code\Player\HitscanWeapon.cs"
$shotgun = Read-Text "Code\Player\ShotgunWeapon.cs"
$jammer = Read-Text "Code\Player\DroneJammerGun.cs"
$grenade = Read-Text "Code\Equipment\ThrowableGrenade.cs"
$deployer = Read-Text "Code\Player\DroneDeployer.cs"
Require-Pattern $viewmodel 'sealed\s+class\s+FirstPersonViewmodel' "FirstPersonViewmodel component is required."
Require-Pattern $viewmodel 'ViewmodelRootPrefabPath\s*=\s*"prefabs/items/local_first_person_viewmodel\.prefab"' "FirstPersonViewmodel must use a reusable prefab for the local viewmodel root."
Require-Pattern $viewmodel 'GameObject\.GetPrefab\(\s*ViewmodelRootPrefabPath\s*\)' "FirstPersonViewmodel must resolve the local viewmodel root prefab before falling back to procedural creation."
Require-Pattern $viewmodel 'ViewmodelArmsPrefabPath\s*=\s*"prefabs/items/viewmodel_arms\.prefab"' "FirstPersonViewmodel must use a reusable prefab for the local viewmodel arms child."
Require-Pattern $viewmodel 'GameObject\.GetPrefab\(\s*ViewmodelArmsPrefabPath\s*\)' "FirstPersonViewmodel must resolve the local viewmodel arms prefab before falling back to procedural creation."
Require-Pattern $viewmodel 'ViewmodelStockWeaponPrefabPath\s*=\s*"prefabs/items/viewmodel_stock_weapon\.prefab"' "FirstPersonViewmodel must use a reusable prefab for stock first-person weapon animation drivers."
Require-Pattern $viewmodel 'GameObject\.GetPrefab\(\s*ViewmodelStockWeaponPrefabPath\s*\)' "FirstPersonViewmodel must resolve the stock weapon animation driver prefab before falling back to procedural creation."
Require-Pattern $viewmodel 'ViewmodelCustomVisualPrefabPath\s*=\s*"prefabs/items/viewmodel_custom_visual\.prefab"' "FirstPersonViewmodel must use a reusable prefab for custom first-person visual roots."
Require-Pattern $viewmodel 'CreateViewmodelContainer\(\s*ViewmodelCustomVisualPrefabPath' "FirstPersonViewmodel must resolve the custom visual root prefab before falling back to procedural creation."
Require-Pattern $viewmodel 'ViewmodelStaticItemPrefabPath\s*=\s*"prefabs/items/viewmodel_static_item\.prefab"' "FirstPersonViewmodel must use a reusable prefab for static fallback first-person item roots."
Require-Pattern $viewmodel 'CreateViewmodelContainer\(\s*ViewmodelStaticItemPrefabPath' "FirstPersonViewmodel must resolve the static item root prefab before falling back to procedural creation."
Require-Pattern $viewmodel 'GameObject\.GetPrefab\(\s*prefabPath\s*\)' "FirstPersonViewmodel container roots must resolve their prefab path before falling back to procedural creation."
Require-Pattern $viewmodel 'NetworkMode\s*=\s*NetworkMode\.Never' "First-person spawned viewmodel objects must be local-only NetworkMode.Never."
Require-Pattern $viewmodel 'SkinnedModelRenderer' "FirstPersonViewmodel must create skinned renderers for Facepunch weapon/arms animation drivers."
Require-Pattern $viewmodel 'ModelRenderer' "FirstPersonViewmodel must support visible custom/static item visuals."
Require-Pattern $viewmodel 'BoneMergeTarget\s*=' "FirstPersonViewmodel must bonemerge arms onto stock weapon animation drivers."
Require-Pattern $viewmodel 'Cloud\.Model\s*\(' "Stock first-person assets must be loaded through Facepunch cloud identifiers, not guessed local paths."
if ($viewmodel -match 'Cloud\.Model\s*\(\s*ident\s*\)') {
    Add-Error "Cloud.Model calls must use string literals; S&Box editor codegen rejects variable cloud identifiers."
}
Require-Pattern $viewmodel 'facepunch/v_first_person_arms_human' "FirstPersonViewmodel should default to the Facepunch human first-person arms cloud asset."
Require-Pattern $viewmodel 'facepunch/v_m4a1' "M4 and jammer should keep the Facepunch M4A1 viewmodel as the stock animation driver."
Require-Pattern $viewmodel 'facepunch/v_spaghellim4' "Shotgun should keep the Facepunch Spaghelli viewmodel as the stock animation driver."
Require-Pattern $viewmodel 'facepunch/v_mp5' "Pilot SMG should keep the Facepunch ViewModel MP5 as a hidden animation driver."
Require-Pattern $viewmodel 'facepunch/v_he_grenade' "Frag grenade should map to the Facepunch ViewModel HE Grenade cloud asset."
Require-Pattern $viewmodel 'facepunch/v_smoke_grenade' "Chaff grenade should map to the Facepunch ViewModel Smoke Grenade cloud asset."
Require-Pattern $viewmodel 'facepunch/v_decoy_grenade' "EMP grenade should map to a Facepunch throwable viewmodel cloud asset."
Require-Pattern $viewmodel 'enum\s+ViewmodelRenderMode' "FirstPersonViewmodel must distinguish stock-visible, stock-animated custom-visible, and static fallback render paths."
Require-Pattern $viewmodel 'CustomVisibleStockAnimated' "Custom M4, shotgun, and jammer must use a custom-visible stock-animated render path."
Require-Pattern $viewmodel 'BuildCustomAnimatedViewmodel' "FirstPersonViewmodel must build visible custom weapons on top of hidden stock animation drivers."
Require-Pattern $viewmodel 'HideStockAnimationDriver\s*\(' "Custom stock-animation drivers must use a dedicated hide helper so the stock weapon mesh stays animation-only."
Require-Pattern $viewmodel 'RenderType\s*=\s*ModelRenderer\.ShadowRenderType\.Off' "Stock animation drivers for custom weapons must keep RenderType off as a secondary hide guard."
Require-Pattern $viewmodel 'SceneObject\s*\?\s*\.RenderingEnabled\s*=\s*false|SceneObject\s+is\s+\{\s*\}\s+\w+[\s\S]{0,160}RenderingEnabled\s*=\s*false' "Stock animation drivers must explicitly disable SceneObject.RenderingEnabled; RenderType.Off alone is not enough."
Require-Pattern $viewmodel 'TryGetCustomAnimatedVisualAnchor\s*\(' "Custom animated weapons need a guarded anchor fallback instead of blindly using the stock driver root."
Require-Pattern $viewmodel 'VisualTarget' "Custom animated weapons must copy the intended WeaponVisual target instead of every renderer under the weapon root."
Require-Pattern $viewmodel 'AddCustomAnimatedVisualCopies\s*\(' "Custom animated weapons need a separate copy path that normalizes weapon-root renderers for first-person use."
Require-Pattern $viewmodel 'sourceIsWeaponRoot\s*=\s*source\.GameObject\s*==\s*item\.Root' "Custom animated visual copy path must detect renderers that live directly on the weapon root."
Require-Pattern $viewmodel 'LocalPosition\s*=\s*sourceIsWeaponRoot\s*\?\s*Vector3\.Zero' "Custom animated root-level renderers must be copied at local zero, not at the third-person weapon root offset."
Require-Pattern $viewmodel 'TryGetCustomHandAnchoredPose\s*\(' "Custom animated weapons must align their held-item IK targets to the stock animated hand bones."
Require-Pattern $viewmodel 'TryGetOneHandCustomVisualPose\s*\(' "One-handed custom weapons must solve a dedicated hand-grip pose so the visible model moves in sync with the gripping hand."
Require-Pattern $viewmodel 'oneHandWeaponAnchor\.Rotation\s*\*\s*item\.CustomViewmodelRotation\.ToRotation\(\)' "One-handed custom weapons must keep the stable stock weapon orientation instead of rotating the whole weapon from the wrist bone."
if ($viewmodel -match 'oneHandAnchor\.Rotation\s*\*\s*item\.CustomViewmodelRotation\.ToRotation\(\)') {
    Add-Error "One-handed custom weapons must not rotate the entire visible model directly from the hand bone; align the grip point to the hand and keep stock weapon orientation."
}
Require-Pattern $viewmodel 'TryGetStockHandAnchor\s*\(' "Custom animated weapon placement must read stock left/right hand bone transforms."
Require-Pattern $viewmodel 'LocalPointToWorldOffset\s*\(' "Custom animated weapon placement must transform local held-item hand offsets into viewmodel space."
Require-Pattern $viewmodel 'if\s*\(\s*!item\.TwoHanded\s*\)[\s\S]{0,360}TryGetStockHandAnchor\(\s*true' "One-handed custom weapons such as the pilot MP7 must anchor to the right hand instead of averaging both hand targets."
Require-Pattern $viewmodel 'models/weapons/assault_rifle_m4\.vmdl' "Assault rifle first-person custom path must reference the Blender M4 model."
Require-Pattern $viewmodel 'models/weapons/smg_mp7\.vmdl' "Pilot SMG first-person custom path must reference the Blender MP7 model."
Require-Pattern $viewmodel 'models/shotgun\.vmdl' "Shotgun first-person custom path must reference the Blender shotgun model."
Require-Pattern $viewmodel 'models/jammer_gun\.vmdl' "Jammer first-person custom path must reference the Blender jammer model."
Require-Pattern $viewmodel 'StockViewmodelOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*new\(\s*(?:[6-9]|[1-9][0-9]+)f,\s*0f,\s*0f\s*\)' "First-person viewmodel root needs positive forward camera clearance so held items do not clip through the camera."
Require-Pattern $viewmodel 'CustomM4ViewmodelOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*new\(\s*(?:[1-9]|[1-9][0-9]+)f,\s*0f,\s*0f\s*\)' "Custom M4 viewmodel needs a non-zero forward offset after hand anchoring."
Require-Pattern $viewmodel 'CustomSmgViewmodelOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*(?:Vector3\.Zero|new\(\s*0f,\s*0f,\s*0f\s*\))' "Pilot MP7 viewmodel must not add a secondary offset after grip anchoring; camera clearance belongs on the shared stock viewmodel root."
Require-Pattern $viewmodel 'CustomSmgViewmodelScale\s*\{\s*get;\s*set;\s*\}\s*=\s*new\(\s*0\.5f,\s*0\.5f,\s*0\.5f\s*\)' "Pilot MP7 first-person custom viewmodel scale should stay at 50% so it fits the pilot hand."
Require-Pattern $viewmodel 'CustomShotgunViewmodelOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*new\(\s*(?:[1-9]|[1-9][0-9]+)f,\s*0f,\s*0f\s*\)' "Custom shotgun viewmodel needs a non-zero forward offset after hand anchoring."
Require-Pattern $viewmodel 'CustomJammerViewmodelOffset\s*\{\s*get;\s*set;\s*\}\s*=\s*(?:Vector3\.Zero|new\(\s*0f,\s*0f,\s*0f\s*\))' "Custom jammer viewmodel should not add a secondary forward offset after hand anchoring; tune its foregrip and pistol-grip IK targets instead."
Require-Pattern $viewmodel 'CustomModelPath\s*=\s*isSmg\s*\?\s*PilotSmgCustomModelPath\s*:\s*AssaultRifleCustomModelPath' "Pilot SMG first-person viewmodel must copy the Blender MP7 visual instead of the assault rifle fallback."
Require-Pattern $viewmodel 'Key\s*=\s*\$"hitscan:\{weapon\.GameObject\.Id\}:\{\(isSmg\s*\?\s*"mp7"\s*:\s*"m4a1"\)\}"' "Pilot SMG viewmodel cache key must identify the visible custom MP7, not the old MP5 stock mesh."
if ($viewmodel -match 'RenderMode\s*=\s*isSmg\s*\?\s*ViewmodelRenderMode\.StockVisible') {
    Add-Error "Pilot SMG must not render the stock MP5 as the visible first-person weapon."
}
Require-Pattern $viewmodel 'TryGetStockWeaponAnchor' "Custom visible weapons must follow a stock animated attachment or bone anchor."
Require-Pattern $viewmodel 'GetAttachment\s*\(' "Custom visible weapons should try stock viewmodel attachments before falling back to bones/root transform."
Require-Pattern $viewmodel 'TryGetBoneTransform\s*\(' "Custom visible weapons should fall back to stock viewmodel bones when attachments are unavailable."
Require-Pattern $viewmodel 'JammerStockAnimationPath\s*=>\s*AssaultRifleViewmodelPath|JammerStockAnimationPath\s*=\s*AssaultRifleViewmodelPath' "Jammer should use the stock M4A1 rifle animation profile."
Require-Pattern $viewmodel 'SetIk\s*\(' "Custom/static item fallback must drive hand IK targets."
Require-Pattern $viewmodel 'Parameters\.Set\s*\(' "Stock viewmodels must receive animgraph parameters."
Require-Pattern $viewmodel 'FindSelectedHeldItem' "FirstPersonViewmodel must choose the currently selected held item."
Require-Pattern $viewmodel 'HasVisibleViewmodel\s*\(' "World-held items must only be hidden after the spawned viewmodel has visible renderers."
Require-Pattern $viewmodel 'GetStaticArmsAnchor' "Static fallback arms must anchor to hand targets/held visuals instead of the player-root/feet."

foreach ($missingPath in @(
    'models/weapons/v_m4a1',
    'models/weapons/v_mp5',
    'models/weapons/v_spas12',
    'models/weapons/sbox_grenade_smoke',
    'models/first_person/v_first_person_arms_human'
)) {
    if ($viewmodel -match [regex]::Escape($missingPath)) {
        Add-Error "FirstPersonViewmodel must not default to unresolved local stock path: $missingPath"
    }
}

$viewmodelRootPrefab = Read-Json "Assets\prefabs\items\local_first_person_viewmodel.prefab"
if ($null -ne $viewmodelRootPrefab -and $null -ne $viewmodelRootPrefab.RootObject) {
    if ([string]$viewmodelRootPrefab.RootObject.Name -ne "LocalFirstPersonViewmodel") {
        Add-Error "Assets\prefabs\items\local_first_person_viewmodel.prefab root object must be named LocalFirstPersonViewmodel."
    }

    if ([string]$viewmodelRootPrefab.RootObject.NetworkMode -ne "2") {
        Add-Error "Assets\prefabs\items\local_first_person_viewmodel.prefab root object must stay local-only NetworkMode 2."
    }
}

$viewmodelArmsPrefab = Read-Json "Assets\prefabs\items\viewmodel_arms.prefab"
if ($null -ne $viewmodelArmsPrefab -and $null -ne $viewmodelArmsPrefab.RootObject) {
    if ([string]$viewmodelArmsPrefab.RootObject.Name -ne "ViewmodelArms") {
        Add-Error "Assets\prefabs\items\viewmodel_arms.prefab root object must be named ViewmodelArms."
    }

    if ([string]$viewmodelArmsPrefab.RootObject.NetworkMode -ne "2") {
        Add-Error "Assets\prefabs\items\viewmodel_arms.prefab root object must stay local-only NetworkMode 2."
    }

    $viewmodelArmsPrefabRaw = Read-Text "Assets\prefabs\items\viewmodel_arms.prefab"
    if ($viewmodelArmsPrefabRaw -notmatch '"__type"\s*:\s*"Sandbox\.SkinnedModelRenderer"') {
        Add-Error "Assets\prefabs\items\viewmodel_arms.prefab must include a Sandbox.SkinnedModelRenderer component for runtime arms setup."
    }
}

$viewmodelStockWeaponPrefab = Read-Json "Assets\prefabs\items\viewmodel_stock_weapon.prefab"
if ($null -ne $viewmodelStockWeaponPrefab -and $null -ne $viewmodelStockWeaponPrefab.RootObject) {
    if ([string]$viewmodelStockWeaponPrefab.RootObject.Name -ne "ViewmodelStockWeapon") {
        Add-Error "Assets\prefabs\items\viewmodel_stock_weapon.prefab root object must be named ViewmodelStockWeapon."
    }

    if ([string]$viewmodelStockWeaponPrefab.RootObject.NetworkMode -ne "2") {
        Add-Error "Assets\prefabs\items\viewmodel_stock_weapon.prefab root object must stay local-only NetworkMode 2."
    }

    $viewmodelStockWeaponPrefabRaw = Read-Text "Assets\prefabs\items\viewmodel_stock_weapon.prefab"
    if ($viewmodelStockWeaponPrefabRaw -notmatch '"__type"\s*:\s*"Sandbox\.SkinnedModelRenderer"') {
        Add-Error "Assets\prefabs\items\viewmodel_stock_weapon.prefab must include a Sandbox.SkinnedModelRenderer component for runtime stock weapon setup."
    }
}

foreach ($viewmodelContainerPrefab in @(
    @{ Path = "Assets\prefabs\items\viewmodel_custom_visual.prefab"; RootName = "ViewmodelCustomVisual" },
    @{ Path = "Assets\prefabs\items\viewmodel_static_item.prefab"; RootName = "ViewmodelStaticItem" }
)) {
    $prefab = Read-Json $viewmodelContainerPrefab.Path
    if ($null -eq $prefab -or $null -eq $prefab.RootObject) {
        continue
    }

    if ([string]$prefab.RootObject.Name -ne $viewmodelContainerPrefab.RootName) {
        Add-Error "$($viewmodelContainerPrefab.Path) root object must be named $($viewmodelContainerPrefab.RootName)."
    }

    if ([string]$prefab.RootObject.NetworkMode -ne "2") {
        Add-Error "$($viewmodelContainerPrefab.Path) root object must stay local-only NetworkMode 2."
    }
}

Require-Pattern $controller 'UseLocalFirstPersonViewmodel' "GroundPlayerController must expose the local first-person viewmodel toggle."
Require-Pattern $controller 'LocalFirstPersonViewmodelActive' "GroundPlayerController must track active local first-person viewmodel state."
Require-Pattern $controller 'EnsureLocalFirstPersonViewmodel' "GroundPlayerController must create the local viewmodel component."
Require-Pattern $controller 'SetBodyGroup\(\s*"Hands"\s*,\s*handsOnly\s*&&\s*UseLocalFirstPersonViewmodel\s*\?' "Local body hands must be hidden while first-person viewmodels are enabled."
Require-Pattern $deployer 'hideForFirstPersonViewmodel' "DroneDeployer must keep updating hidden first-person hand visuals for copied viewmodel fallback."
Require-Pattern $deployer 'WeaponPose\.SetVisibility\(\s*LeftHandVisual\s*,\s*!hideForFirstPersonViewmodel' "DroneDeployer left-hand visual should hide renderers but keep transforms updating for fallback copies."

foreach ($entry in @(
    @{ Path = "Code\Player\HitscanWeapon.cs"; Text = $hitscan },
    @{ Path = "Code\Player\ShotgunWeapon.cs"; Text = $shotgun },
    @{ Path = "Code\Player\DroneJammerGun.cs"; Text = $jammer },
    @{ Path = "Code\Equipment\ThrowableGrenade.cs"; Text = $grenade },
    @{ Path = "Code\Player\DroneDeployer.cs"; Text = $deployer }
)) {
    Require-Pattern $entry.Text 'FirstPersonViewmodel\.ShouldHideWorldHeldItem' "$($entry.Path) must hide its old local world-held visual when the spawned viewmodel is active."
}

Assert-M4HandguardGripAnchor "Assets\prefabs\soldier_assault.prefab"
Assert-M4HandguardGripAnchor "Assets\prefabs\soldier.prefab"
Assert-PilotMp7HeldScale
Assert-M4ModelDocScale
Assert-M4AssetPipelineScale

if ($errors.Count -gt 0) {
    Write-Host "First-person viewmodel spawn guard failed:"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "First-person viewmodel spawn guard passed."
