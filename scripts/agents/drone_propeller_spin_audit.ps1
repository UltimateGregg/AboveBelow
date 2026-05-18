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

if (@($issues | Where-Object { $_.Severity -eq "Error" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Drone Propellers" "Code/Drone/DroneController.cs" "Propeller axis and motor direction checks passed."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
