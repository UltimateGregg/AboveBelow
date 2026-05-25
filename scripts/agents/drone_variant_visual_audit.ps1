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

function Read-AgentTextOrIssue {
    param(
        [string]$RelativePath,
        [string]$Area
    )

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Required file is missing." "Restore the file or update the drone variant visual contract."
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw
}

function Test-AgentFileExists {
    param(
        [string]$RelativePath,
        [string]$Area,
        [string]$Recommendation
    )

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-AgentIssue $issues "Error" $Area $RelativePath "Expected file is missing." $Recommendation
    }
}

function Get-PrefabChildByName {
    param(
        [object]$Node,
        [string]$Name
    )

    if ($null -eq $Node) {
        return $null
    }

    if (($Node.PSObject.Properties.Name -contains "Name") -and [string]$Node.Name -eq $Name) {
        return $Node
    }

    if ($Node.PSObject.Properties.Name -contains "Children") {
        foreach ($child in @($Node.Children)) {
            $match = Get-PrefabChildByName -Node $child -Name $Name
            if ($null -ne $match) {
                return $match
            }
        }
    }

    return $null
}

function Get-ModelRendererModels {
    param([object]$Node)

    $models = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node) {
        return @()
    }

    if ($Node.PSObject.Properties.Name -contains "Components") {
        foreach ($component in @($Node.Components)) {
            $propertyNames = @($component.PSObject.Properties.Name)
            $componentType = if ($propertyNames -contains "__type") { [string]$component.__type } else { "" }
            if (($propertyNames -contains "Model") -and
                ([string]::IsNullOrWhiteSpace($componentType) -or $componentType -eq "Sandbox.ModelRenderer")) {
                $models.Add([string]$component.Model)
            }
        }
    }

    if ($Node.PSObject.Properties.Name -contains "Children") {
        foreach ($child in @($Node.Children)) {
            foreach ($model in @(Get-ModelRendererModels -Node $child)) {
                $models.Add([string]$model)
            }
        }
    }

    return @($models)
}

function Test-AssetConfigValue {
    param(
        [object]$Json,
        [string]$ConfigPath,
        [string]$Property,
        [string]$Expected
    )

    if (-not ($Json.PSObject.Properties.Name -contains $Property)) {
        Add-AgentIssue $issues "Error" "Drone Variant Visual" $ConfigPath "Config is missing '$Property'." "Keep the variant asset pipeline explicit so save/export cannot fall back to a shared/base model."
        return
    }

    $actual = [string]$Json.$Property
    if ($actual -ne $Expected) {
        Add-AgentIssue $issues "Error" "Drone Variant Visual" $ConfigPath "$Property is '$actual', expected '$Expected'." "Route the variant through its own source blend, FBX, VMDL, and model resource path."
    }
}

function Test-DroneVariantVisualContract {
    param([object]$Contract)

    Test-AgentFileExists -RelativePath $Contract.SourceBlend -Area "Drone Variant Visual" -Recommendation "Create or save the variant source blend."
    Test-AgentFileExists -RelativePath $Contract.TargetFbx -Area "Drone Variant Visual" -Recommendation "Run scripts/asset_pipeline.py for the variant config."
    Test-AgentFileExists -RelativePath $Contract.TargetVmdl -Area "Drone Variant Visual" -Recommendation "Run scripts/asset_pipeline.py for the variant config."

    $prefabText = Read-AgentTextOrIssue -RelativePath $Contract.Prefab -Area "Drone Variant Visual"
    if ($null -ne $prefabText) {
        try {
            $prefab = $prefabText | ConvertFrom-Json
            $visual = Get-PrefabChildByName -Node $prefab.RootObject -Name "Visual"
            $visualModels = @(Get-ModelRendererModels -Node $visual)
            if ($visualModels.Count -eq 0) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Prefab "Visual child has no ModelRenderer model." "Keep each drone variant body renderer on the Visual child."
            }
            elseif ($visualModels -notcontains $Contract.ExpectedBodyModel) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Prefab "Visual body model is '$($visualModels -join ', ')', expected '$($Contract.ExpectedBodyModel)'." "Do not reuse the base FPV body when the variant has its own visible identity."
            }

            if ($visualModels -contains $Contract.ForbiddenBodyModel) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Prefab "Variant Visual still references forbidden shared/base body '$($Contract.ForbiddenBodyModel)'." "Wire the variant prefab to its own VMDL."
            }
        }
        catch {
            Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Prefab "Failed to parse prefab JSON: $($_.Exception.Message)" "Fix invalid prefab JSON."
        }
    }

    $configText = Read-AgentTextOrIssue -RelativePath $Contract.Config -Area "Drone Variant Visual"
    if ($null -ne $configText) {
        try {
            $config = $configText | ConvertFrom-Json
            Test-AssetConfigValue -Json $config -ConfigPath $Contract.Config -Property "source_blend" -Expected $Contract.SourceBlend
            Test-AssetConfigValue -Json $config -ConfigPath $Contract.Config -Property "target_fbx" -Expected $Contract.TargetFbx
            Test-AssetConfigValue -Json $config -ConfigPath $Contract.Config -Property "target_vmdl" -Expected $Contract.TargetVmdl
            Test-AssetConfigValue -Json $config -ConfigPath $Contract.Config -Property "model_resource_path" -Expected $Contract.ExpectedBodyModel

            if (-not ($config.PSObject.Properties.Name -contains "material_remap") -or $null -eq $config.material_remap) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Config "Config has no material_remap." "Keep variant visual materials explicit."
            }
            elseif (-not ($config.material_remap.PSObject.Properties.Name -contains "Motor_Aluminum")) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Config "Config has no Motor_Aluminum material remap." "Give the variant motor slot an explicit material."
            }
            elseif ([string]$config.material_remap.Motor_Aluminum -ne $Contract.ExpectedMotorMaterial) {
                Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Config "Motor_Aluminum remaps to '$($config.material_remap.Motor_Aluminum)', expected '$($Contract.ExpectedMotorMaterial)'." "Use a distinct motor material for the variant identity."
            }
        }
        catch {
            Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.Config "Failed to parse config JSON: $($_.Exception.Message)" "Fix invalid config JSON."
        }
    }

    $motorMaterialPath = "Assets/" + $Contract.ExpectedMotorMaterial.TrimStart("/").Replace("/", "\")
    Test-AgentFileExists -RelativePath $motorMaterialPath -Area "Drone Variant Visual" -Recommendation "Create the variant motor .vmat and point it at a real project texture."

    $heldSourceText = Read-AgentTextOrIssue -RelativePath $Contract.HeldSource -Area "Drone Variant Visual"
    if ($null -ne $heldSourceText) {
        $propertyPattern = [regex]::Escape($Contract.HeldModelProperty) + '\s*\{\s*get;\s*set;\s*\}\s*=\s*"' + [regex]::Escape($Contract.ExpectedBodyModel) + '"'
        if ($heldSourceText -notmatch $propertyPattern) {
            Add-AgentIssue $issues "Error" "Drone Variant Visual" $Contract.HeldSource "$($Contract.HeldModelProperty) does not default to '$($Contract.ExpectedBodyModel)'." "Keep first-person held/selection previews on the same variant model as the spawned drone."
        }
    }
}

Write-AgentSection "Drone Variant Visual Audit"
Write-Host "Root: $Root"

$contracts = @(
    [pscustomobject]@{
        Name = "FPV"
        Prefab = "Assets/prefabs/drone_fpv.prefab"
        ExpectedBodyModel = "models/drone_fpv.vmdl"
        ForbiddenBodyModel = "models/drone_high.vmdl"
        Config = "scripts/drone_fpv_asset_pipeline.json"
        SourceBlend = "drone_model.blend/drone_fpv.blend"
        TargetFbx = "Assets/models/drone_fpv.fbx"
        TargetVmdl = "Assets/models/drone_fpv.vmdl"
        ExpectedMotorMaterial = "materials/drone_fpv_motor.vmat"
        HeldSource = "Code/Player/DroneDeployer.cs"
        HeldModelProperty = "FpvHeldDroneModelPath"
    },
    [pscustomobject]@{
        Name = "Fiber FPV"
        Prefab = "Assets/prefabs/drone_fpv_fiber.prefab"
        ExpectedBodyModel = "models/drone_fpv_fiber.vmdl"
        ForbiddenBodyModel = "models/drone_fpv.vmdl"
        Config = "scripts/drone_fpv_fiber_asset_pipeline.json"
        SourceBlend = "drone_model.blend/drone_fpv_fiber.blend"
        TargetFbx = "Assets/models/drone_fpv_fiber.fbx"
        TargetVmdl = "Assets/models/drone_fpv_fiber.vmdl"
        ExpectedMotorMaterial = "materials/drone_fpv_fiber_motor.vmat"
        HeldSource = "Code/Player/DroneDeployer.cs"
        HeldModelProperty = "FiberHeldDroneModelPath"
    }
)

foreach ($contract in $contracts) {
    Test-DroneVariantVisualContract -Contract $contract
}

Add-AgentIssue $issues "Info" "Drone Variant Visual" "" "Checked $($contracts.Count) drone visual variant contract(s)."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
