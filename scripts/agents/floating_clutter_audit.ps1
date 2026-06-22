param(
    [string]$Root = "",
    [string]$ScenePath = "Assets/scenes/main.scene",
    [string]$TerrainAssetPath = "Assets/terrain/arena_floor.terrain",
    [string]$McpUri = "http://localhost:29015/mcp",
    [double]$Tolerance = 48,
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$issues = New-Object System.Collections.Generic.List[object]

Write-AgentSection "Floating Clutter Audit"
Write-Host "Root: $Root"

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

function Get-VectorZ {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0.0
    }

    $parts = $Value.ToString().Split(",")
    if ($parts.Count -lt 3) {
        return 0.0
    }

    $parsed = 0.0
    if ([double]::TryParse($parts[2].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    return 0.0
}

function Find-ObjectWorldZ {
    param(
        [object[]]$Objects,
        [string]$Name,
        [double]$ParentZ = 0.0
    )

    foreach ($object in @($Objects | Where-Object { $null -ne $_ })) {
        $localZ = Get-VectorZ -Value (Get-JsonPropertyValue -Object $object -Name "Position")
        $worldZ = $ParentZ + $localZ

        if ([string](Get-JsonPropertyValue -Object $object -Name "Name") -eq $Name) {
            return $worldZ
        }

        $children = @(Get-JsonPropertyValue -Object $object -Name "Children" | Where-Object { $null -ne $_ })
        if ($children.Count -gt 0) {
            $found = Find-ObjectWorldZ -Objects $children -Name $Name -ParentZ $worldZ
            if ($null -ne $found) {
                return $found
            }
        }
    }

    return $null
}

function Invoke-McpTool {
    param(
        [string]$Name,
        [hashtable]$Arguments = @{},
        [int]$TimeoutSec = 20
    )

    $payload = @{
        jsonrpc = "2.0"
        id = 1
        method = "tools/call"
        params = @{
            name = $Name
            arguments = $Arguments
        }
    } | ConvertTo-Json -Depth 8 -Compress

    $response = Invoke-WebRequest -Uri $McpUri -Method POST -Body $payload -ContentType "application/json" -UseBasicParsing -TimeoutSec $TimeoutSec
    return ($response.Content | ConvertFrom-Json)
}

function Get-McpObjectZ {
    param([object]$Object)

    $value = $Object.position.z
    if ($value -is [array]) {
        $value = $value[0]
    }

    return [double]$value
}

$fullScenePath = if ([System.IO.Path]::IsPathRooted($ScenePath)) { $ScenePath } else { Join-Path $Root $ScenePath }
$sceneRelative = ConvertTo-AgentRelativePath -Path $fullScenePath -Root $Root
$fullTerrainPath = if ([System.IO.Path]::IsPathRooted($TerrainAssetPath)) { $TerrainAssetPath } else { Join-Path $Root $TerrainAssetPath }
$terrainRelative = ConvertTo-AgentRelativePath -Path $fullTerrainPath -Root $Root

if (-not (Test-Path -LiteralPath $fullScenePath)) {
    Add-AgentIssue $issues "Error" "Floating Clutter" $sceneRelative "Scene file is missing." "Restore the scene before checking live painted clutter placement."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

if (-not (Test-Path -LiteralPath $fullTerrainPath)) {
    Add-AgentIssue $issues "Error" "Floating Clutter" $terrainRelative "Terrain asset is missing." "Restore the terrain asset before checking live painted clutter placement."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    $scene = Read-AgentJson -Path $fullScenePath
    $terrainAsset = Read-AgentJson -Path $fullTerrainPath
}
catch {
    Add-AgentIssue $issues "Error" "Floating Clutter" $sceneRelative $_.Exception.Message "Fix scene or terrain JSON before checking live painted clutter placement."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$arenaFloorWorldZ = Find-ObjectWorldZ -Objects @(Get-JsonPropertyValue -Object $scene -Name "GameObjects") -Name "ArenaFloor"
if ($null -eq $arenaFloorWorldZ) {
    Add-AgentIssue $issues "Error" "Floating Clutter" $sceneRelative "ArenaFloor object was not found." "Keep ArenaFloor as the terrain anchor so clutter grounding can be audited."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$terrainHeight = [double](Get-JsonPropertyValue -Object $terrainAsset -Name "TerrainHeight")
if ($terrainHeight -le 0) {
    Add-AgentIssue $issues "Error" "Floating Clutter" $terrainRelative "TerrainHeight is not positive." "Fix the terrain asset before checking clutter grounding."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

try {
    Invoke-McpTool -Name "console_run" -Arguments @{ command = "dvp_dump_terrain_height" } -TimeoutSec 5 | Out-Null
    Start-Sleep -Milliseconds 700
}
catch {
    Add-AgentIssue $issues "Info" "Floating Clutter" $McpUri "Editor MCP was unavailable; live painted clutter grounding was skipped." "Run this audit with the S&Box editor and MCP server running for live clutter proof."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$terrainDumpPath = Join-Path $Root ".tmp/terrain_world_raise_result.txt"
if (-not (Test-Path -LiteralPath $terrainDumpPath)) {
    Add-AgentIssue $issues "Error" "Floating Clutter" ".tmp/terrain_world_raise_result.txt" "Terrain height dump result was not written." "Run dvp_dump_terrain_height in the editor and retry."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$terrainDump = Get-Content -LiteralPath $terrainDumpPath -Raw
$maxMatch = [regex]::Match($terrainDump, "max=(\d+)")
if (-not $maxMatch.Success) {
    Add-AgentIssue $issues "Error" "Floating Clutter" ".tmp/terrain_world_raise_result.txt" "Could not parse terrain height max from '$terrainDump'." "Keep dvp_dump_terrain_height output in the expected format."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$maxHeightValue = [double]$maxMatch.Groups[1].Value
$terrainMaxWorldZ = $arenaFloorWorldZ + (($maxHeightValue / [double][UInt16]::MaxValue) * $terrainHeight)
$allowedMaxWorldZ = $terrainMaxWorldZ + $Tolerance

try {
    $clutterResponse = Invoke-McpTool -Name "scene_find_by_tag" -Arguments @{ tag = "clutter_painted" } -TimeoutSec 30
    $parsedClutter = $clutterResponse.result.content[0].text | ConvertFrom-Json
    $clutterObjects = @($parsedClutter | ForEach-Object { $_ })
}
catch {
    Add-AgentIssue $issues "Error" "Floating Clutter" $McpUri "Could not read live clutter_painted objects: $($_.Exception.Message)" "Keep the editor MCP scene tag tools available for live clutter checks."
    Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
    exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
}

$targetObjects = @($clutterObjects | Where-Object { $_.name -match "(grass|bush|shrub)" })
$offenders = @($targetObjects | Where-Object { (Get-McpObjectZ -Object $_) -gt $allowedMaxWorldZ } | Sort-Object { Get-McpObjectZ -Object $_ } -Descending)

if ($offenders.Count -gt 0) {
    $examples = @($offenders | Select-Object -First 8 | ForEach-Object {
        "$($_.name) z=$([Math]::Round((Get-McpObjectZ -Object $_), 1))"
    }) -join "; "
    Add-AgentIssue $issues "Error" "Floating Clutter" "Assets/scenes/main.scene" "$($offenders.Count) painted grass/bush clutter object(s) are above the terrain max world Z $([Math]::Round($terrainMaxWorldZ, 1)) plus tolerance $Tolerance. Examples: $examples" "Run the painted clutter grounding fix in the editor, then save the scene."
}

if ($ShowInfo) {
    Add-AgentIssue $issues "Info" "Floating Clutter" $sceneRelative "Checked $($targetObjects.Count) painted grass/bush clutter object(s); terrainMaxWorldZ=$([Math]::Round($terrainMaxWorldZ, 2)); allowedMaxWorldZ=$([Math]::Round($allowedMaxWorldZ, 2))." ""
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
