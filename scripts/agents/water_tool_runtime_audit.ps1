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

Write-AgentSection "Water Tool Runtime Audit"
Write-Host "Root: $Root"

function Read-WaterToolText {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Water Tool" $RelativePath "Required Water Tool file is missing." "Restore the installed water library file or update this audit if the library layout changed."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
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

function Get-AllSceneObjects {
    param([object]$Scene)

    $objects = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]

    foreach ($rootObject in @(Get-JsonPropertyValue -Object $Scene -Name "GameObjects")) {
        if ($null -ne $rootObject) {
            $stack.Push($rootObject)
        }
    }

    while ($stack.Count -gt 0) {
        $object = $stack.Pop()
        $objects.Add($object)

        foreach ($child in @(Get-JsonPropertyValue -Object $object -Name "Children")) {
            if ($null -ne $child) {
                $stack.Push($child)
            }
        }
    }

    return $objects.ToArray()
}

function Test-RiverWaterSceneState {
    $sceneFullPath = Join-Path $Root $ScenePath
    if (-not (Test-Path -LiteralPath $sceneFullPath)) {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "Main scene is missing." "Restore the scene before auditing the river water setup."
        return
    }

    $scene = Read-AgentJson -Path $sceneFullPath
    $river = @(Get-AllSceneObjects -Scene $scene | Where-Object { [string](Get-JsonPropertyValue -Object $_ -Name "Name") -eq "River_Water" })
    if ($river.Count -ne 1) {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "Expected exactly one River_Water GameObject, found $($river.Count)." "Keep one authored WaterQuad surface for the carved river channel."
        return
    }

    $riverObject = $river[0]
    if ([string](Get-JsonPropertyValue -Object $riverObject -Name "Enabled") -ne "True") {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "River_Water GameObject is disabled." "Enable the GameObject so the water component can run and register with WaterManager."
    }

    $components = @(Get-JsonPropertyValue -Object $riverObject -Name "Components")
    $waterQuad = @($components | Where-Object {
        [string](Get-JsonPropertyValue -Object $_ -Name "__type") -eq "RedSnail.WaterTool.WaterQuad" -or
            (
                $null -ne (Get-JsonPropertyValue -Object $_ -Name "WaterType") -and
                $null -ne (Get-JsonPropertyValue -Object $_ -Name "Material") -and
                $null -ne (Get-JsonPropertyValue -Object $_ -Name "Depth") -and
                $null -ne (Get-JsonPropertyValue -Object $_ -Name "BaseCellSize")
            )
    })
    if ($waterQuad.Count -ne 1) {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "Expected one RedSnail.WaterTool.WaterQuad component on River_Water, found $($waterQuad.Count)." "Restore the WaterQuad component on the river water object."
        return
    }

    $quad = $waterQuad[0]
    if ([string](Get-JsonPropertyValue -Object $quad -Name "__enabled") -eq "False") {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "River_Water WaterQuad component is disabled." "Enable the WaterQuad; disabled components never call OnEnabled and never register for rendering."
    }

    if ([string](Get-JsonPropertyValue -Object $quad -Name "Material") -ne "materials/lakewater.vmat") {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "River_Water WaterQuad material is not materials/lakewater.vmat." "Keep the known Water Tool material assigned until runtime rendering is proven."
    }

    if ([string](Get-JsonPropertyValue -Object $quad -Name "WaterType") -ne "River") {
        Add-AgentIssue $issues "Error" "River Water" $ScenePath "River_Water WaterQuad WaterType is not River." "Use the River profile lane for the carved channel water surface."
    }
}

function Test-RegistrationRetrySignal {
    param(
        [string]$RelativePath,
        [string]$ComponentName
    )

    $text = Read-WaterToolText $RelativePath
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    $hasRetry = $text -match 'TryRegister\s*\(' -and $text -match 'WaterManager\s+m_RegisteredManager'
    if (-not $hasRetry) {
        Add-AgentIssue $issues "Error" $ComponentName $RelativePath "$ComponentName still relies on component enable ordering for WaterManager registration." "Add idempotent registration retry logic in OnUpdate so water renderers register after WaterManager.Current becomes available."
    }
}

Test-RiverWaterSceneState
Test-RegistrationRetrySignal -RelativePath "Libraries/redsnail.watertool/Code/Water/WaterQuad.cs" -ComponentName "WaterQuad"
Test-RegistrationRetrySignal -RelativePath "Libraries/redsnail.watertool/Code/Water/WaterBodyRenderer.cs" -ComponentName "WaterBodyRenderer"

Add-AgentIssue $issues "Info" "Water Tool" "Libraries/redsnail.watertool/Code/Water" "Water runtime registration contract check completed."

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
