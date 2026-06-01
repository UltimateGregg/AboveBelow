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

Write-AgentSection "Navigation / Collision QA Audit"
Write-Host "Root: $Root"

function Get-ProjectText {
    param([string]$Relative)

    $path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $path)) {
        Add-AgentIssue $issues "Error" "Navigation QA" $Relative "Required file is missing."
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Require-Pattern {
    param(
        [string]$Relative,
        [string]$Text,
        [string]$Pattern,
        [string]$Message,
        [string]$Recommendation
    )

    if ($Text -notmatch $Pattern) {
        Add-AgentIssue $issues "Error" "Navigation QA" $Relative $Message $Recommendation
    }
}

$dummy = Get-ProjectText "Code/Game/TrainingDummy.cs"
$engineRef = Get-ProjectText "docs/sbox_engine_llm_reference.md"
$patterns = Get-ProjectText "docs/known_sbox_patterns.md"

Require-Pattern "Code/Game/TrainingDummy.cs" $dummy '\bNavMeshAgent\b' "Training dummy does not use a NavMeshAgent." "Route solo target movement through NavMeshAgent.WishVelocity when navmesh data is available."
Require-Pattern "Code/Game/TrainingDummy.cs" $dummy '\bUseNavMeshNavigation\b' "Training dummy lacks an explicit navmesh opt-in." "Keep navmesh movement property-gated so prefab authors can disable it per target."
Require-Pattern "Code/Game/TrainingDummy.cs" $dummy 'Scene\.NavMesh\.GetRandomPoint' "Training dummy does not sample reachable navmesh targets." "Use Scene.NavMesh.GetRandomPoint for patrol targets instead of only raw XY offsets."
Require-Pattern "Code/Game/TrainingDummy.cs" $dummy '\bPressureNearestEnemy\b' "Training dummy lacks enemy-pressure practice behavior." "Let solo bots pressure the nearest opposing pawn inside a bounded radius."
Require-Pattern "Code/Game/TrainingDummy.cs" $dummy '\bNavAgent\.WishVelocity\b' "Training dummy does not feed NavMeshAgent wish velocity into movement." "Drive CharacterController.Accelerate from NavMeshAgent.WishVelocity so collision and navmesh stay aligned."

Require-Pattern "docs/sbox_engine_llm_reference.md" $engineRef 'Scene\.NavMesh' "Engine reference is missing Scene.NavMesh guidance." "Keep S&Box navigation guidance grounded in Scene.NavMesh rather than legacy Source nav tools."
Require-Pattern "docs/known_sbox_patterns.md" $patterns 'S&Box navigation' "Known patterns are missing S&Box navigation notes." "Document that collision authoring and terrain setup are navigation prerequisites."

if ($issues.Count -eq 0) {
    Add-AgentIssue $issues "Info" "Navigation QA" "Code/Game/TrainingDummy.cs" "NavMesh training dummy and navigation QA surfaces are present."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
