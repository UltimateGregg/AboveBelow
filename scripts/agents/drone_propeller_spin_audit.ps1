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

Write-AgentSection "Drone Propeller Spin Audit"
Write-Host "Root: $Root"

$controllerPath = Join-Path $Root "Code\Drone\DroneController.cs"
if (-not (Test-Path -LiteralPath $controllerPath)) {
    Add-AgentIssue $issues "Error" "Drone Propellers" "Code/Drone/DroneController.cs" "DroneController.cs is missing." "Restore the drone controller before changing propeller behavior."
}
else {
    $controllerText = Get-Content -LiteralPath $controllerPath -Raw

    if ($controllerText -match 'Rotation\.From\(\s*0f?\s*,\s*0f?\s*,\s*spin') {
        Add-AgentIssue $issues "Error" "Drone Propellers" "Code/Drone/DroneController.cs" "Propellers are spun around the roll axis instead of the motor shaft/up axis." "Use yaw/up-axis rotation for propeller spin."
    }

    if ($controllerText -notmatch 'Rotation\.FromYaw\(') {
        Add-AgentIssue $issues "Error" "Drone Propellers" "Code/Drone/DroneController.cs" "Propeller spin does not use Rotation.FromYaw for local up-axis rotation." "Spin flat propeller meshes around their local up axis."
    }

    if ($controllerText -notmatch 'GetPropellerSpinDirection') {
        Add-AgentIssue $issues "Error" "Drone Propellers" "Code/Drone/DroneController.cs" "Propeller spin direction is not derived per motor." "Alternate diagonal motor directions so quad props do not all spin the same way."
    }
}

$expectedMotors = @("Propeller_FL", "Propeller_FR", "Propeller_BL", "Propeller_BR")
foreach ($relativePrefab in @("Assets/prefabs/drone_fpv.prefab", "Assets/prefabs/drone_fpv_fiber.prefab")) {
    $prefabPath = Join-Path $Root $relativePrefab
    if (-not (Test-Path -LiteralPath $prefabPath)) {
        Add-AgentIssue $issues "Error" "Drone Propellers" $relativePrefab "FPV prefab is missing." "Restore the prefab or update this audit intentionally."
        continue
    }

    $prefabText = Get-Content -LiteralPath $prefabPath -Raw
    foreach ($motorName in $expectedMotors) {
        if ($prefabText -notmatch ('"Name"\s*:\s*"' + [regex]::Escape($motorName) + '"')) {
            Add-AgentIssue $issues "Error" "Drone Propellers" $relativePrefab "Expected motor '$motorName' is missing." "Keep FPV drone props named by corner so spin direction remains deterministic."
        }
    }
}

function Find-ChildNodeByName {
    param(
        [object]$Node,
        [string]$Name
    )

    if ($null -eq $Node -or -not ($Node.PSObject.Properties.Name -contains "Children") -or $null -eq $Node.Children) {
        return $null
    }

    foreach ($child in @($Node.Children)) {
        if (($child.PSObject.Properties.Name -contains "Name") -and [string]$child.Name -eq $Name) {
            return $child
        }
    }

    return $null
}

$gpsPrefab = "Assets/prefabs/drone_gps.prefab"
$gpsPrefabPath = Join-Path $Root $gpsPrefab
if (-not (Test-Path -LiteralPath $gpsPrefabPath)) {
    Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS prefab is missing." "Restore the prefab or update GameSetup and AutoWire intentionally."
}
else {
    try {
        $gpsJson = Get-Content -LiteralPath $gpsPrefabPath -Raw | ConvertFrom-Json
        $gpsRaw = Get-Content -LiteralPath $gpsPrefabPath -Raw
        $visual = Find-ChildNodeByName -Node $gpsJson.RootObject -Name "Visual"
        if ($null -eq $visual) {
            Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS prefab is missing the Visual child." "Keep the GPS visual model and propeller pivots under a shared visual frame."
        }
        else {
            if ([string]$visual.Scale -ne "1,1,1") {
                Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS Visual frame should be unscaled." "Keep Visual at scale 1,1,1 and scale only its Model_Visual body child."
            }

            $bodyVisual = Find-ChildNodeByName -Node $visual -Name "Model_Visual"
            if ($null -eq $bodyVisual) {
                Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS Visual is missing the scaled Model_Visual body child." "Put the GPS body renderer on a Model_Visual child so propeller pivots can share an unscaled tilt frame."
            }
            elseif ([string]$bodyVisual.Scale -ne "0.25,0.25,0.25") {
                Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS Model_Visual body child should have scale 0.25,0.25,0.25." "Apply GPS body scale to Model_Visual, not to the shared Visual frame."
            }

            $expectedGpsSockets = @{
                "Propeller_FL" = "8.5,5.75,0.75"
                "Propeller_FR" = "8.5,-5.75,0.75"
                "Propeller_BL" = "-8.5,5.75,0.75"
                "Propeller_BR" = "-8.5,-5.75,0.75"
            }

            foreach ($motorName in $expectedMotors) {
                $propeller = Find-ChildNodeByName -Node $visual -Name $motorName
                if ($null -eq $propeller) {
                    Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS propeller '$motorName' is not parented under Visual." "Parent GPS propeller pivots under Visual so cosmetic body tilt keeps them attached to the motor sockets."
                    continue
                }

                $expectedPosition = $expectedGpsSockets[$motorName]
                if ([string]$propeller.Position -ne $expectedPosition) {
                    Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS propeller '$motorName' expected Visual-local position '$expectedPosition'." "Use the in-game motor cap coordinates under the unscaled Visual frame."
                }

                $hasScale = $propeller.PSObject.Properties.Name -contains "Scale"
                if ($hasScale -and [string]$propeller.Scale -ne "1,1,1") {
                    Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS propeller '$motorName' has scale '$($propeller.Scale)'." "Do not compensate for a scaled Visual frame; propeller pivots should use normal scale under an unscaled Visual frame."
                }
            }
        }

        if ($gpsRaw -notmatch '"PropellerSpinDegreesPerSecond"\s*:\s*4320') {
            Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS propeller spin speed is not doubled to 4320 degrees per second." "Set DroneController.PropellerSpinDegreesPerSecond to 4320 on the GPS prefab."
        }
    }
    catch {
        Add-AgentIssue $issues "Error" "Drone Propellers" $gpsPrefab "GPS prefab JSON failed to parse." "Fix invalid prefab JSON before relying on propeller placement checks."
    }
}

if (@($issues | Where-Object { $_.Severity -eq "Error" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Drone Propellers" "Code/Drone/DroneController.cs" "Propeller axis and motor direction checks passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
