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
Require-Pattern $viewmodel 'facepunch/v_mp5' "Pilot SMG should map to the Facepunch ViewModel MP5 cloud asset."
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
Require-Pattern $viewmodel 'TryGetStockHandAnchor\s*\(' "Custom animated weapon placement must read stock left/right hand bone transforms."
Require-Pattern $viewmodel 'LocalPointToWorldOffset\s*\(' "Custom animated weapon placement must transform local held-item hand offsets into viewmodel space."
Require-Pattern $viewmodel 'models/weapons/assault_rifle_m4\.vmdl' "Assault rifle first-person custom path must reference the Blender M4 model."
Require-Pattern $viewmodel 'models/shotgun\.vmdl' "Shotgun first-person custom path must reference the Blender shotgun model."
Require-Pattern $viewmodel 'models/jammer_gun\.vmdl' "Jammer first-person custom path must reference the Blender jammer model."
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

if ($errors.Count -gt 0) {
    Write-Host "First-person viewmodel spawn guard failed:"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "First-person viewmodel spawn guard passed."
