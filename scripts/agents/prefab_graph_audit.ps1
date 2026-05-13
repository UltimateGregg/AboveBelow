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

function Get-RegexValues {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Group = "value"
    )

    return @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups[$Group].Value })
}

function Test-GraphFile {
    param([string]$Path)

    $relative = ConvertTo-AgentRelativePath -Path $Path -Root $Root
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) {
        $raw = ""
    }

    $guidDefs = @(Get-RegexValues -Text $raw -Pattern '"__guid"\s*:\s*"(?<value>[^"]+)"')
    $guidSet = @{}
    foreach ($guid in $guidDefs) {
        if ($guidSet.ContainsKey($guid)) {
            $guidSet[$guid] += 1
        }
        else {
            $guidSet[$guid] = 1
        }
    }

    foreach ($entry in $guidSet.GetEnumerator()) {
        if ($entry.Value -gt 1) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "Duplicate GUID definition '$($entry.Key)' appears $($entry.Value) times." "Duplicate GUIDs can break references after editor load."
        }
    }

    $goRefs = @(Get-RegexValues -Text $raw -Pattern '"go"\s*:\s*"(?<value>[^"]+)"')
    foreach ($go in ($goRefs | Select-Object -Unique)) {
        if (-not $guidSet.ContainsKey($go)) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "GameObject reference points to missing GUID '$go'." "Repair the prefab or scene reference in the editor."
        }
    }

    $componentRefs = @(Get-RegexValues -Text $raw -Pattern '"component_id"\s*:\s*"(?<value>[^"]+)"')
    foreach ($component in ($componentRefs | Select-Object -Unique)) {
        if (-not $guidSet.ContainsKey($component)) {
            Add-AgentIssue $issues "Error" "Prefab Graph" $relative "Component reference points to missing GUID '$component'." "Repair the component reference in the editor or update AutoWire."
        }
    }

    $resourceValues = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @(
        '"prefab"\s*:\s*"(?<value>[^"]+)"',
        '"(?:Model|MaterialOverride|FireSound|FireSoundFirstPerson|ReloadSound|MagDropSound|MagInsertSound|BoltRackSound|EmptyClickSound|LoopSound|ThrowSound|DetonateSound|FootstepSound|JumpSound|LandSound|PropellerSound|SkyMaterial)"\s*:\s*"(?<value>[^"]+)"',
        '"(?<value>(?:prefabs|models|materials|sounds|scenes|ui)/[^"]+)"'
    )) {
        foreach ($value in Get-RegexValues -Text $raw -Pattern $pattern) {
            $resourceValues.Add($value)
        }
    }

    foreach ($resource in ($resourceValues | Select-Object -Unique)) {
        $resolved = Resolve-AgentResourcePath -ResourcePath $resource -Root $Root
        if ($null -ne $resolved -and -not (Test-Path -LiteralPath $resolved)) {
            Add-AgentIssue $issues "Error" "Resource Reference" $relative "Resource '$resource' does not exist at expected path." "Fix the path, restore the asset, or mark it as an engine resource in the audit if appropriate."
        }
    }

    Add-AgentIssue $issues "Info" "Prefab Graph" $relative "Checked $($guidDefs.Count) GUID definitions, $($goRefs.Count) GameObject refs, $($componentRefs.Count) component refs."
}

Write-AgentSection "Prefab Graph Audit"
Write-Host "Root: $Root"

$files = @()
$prefabRoot = Join-Path $Root "Assets\prefabs"
if (Test-Path -LiteralPath $prefabRoot) {
    $files += @(Get-ChildItem -LiteralPath $prefabRoot -Recurse -File -Filter "*.prefab")
}
$sceneRoot = Join-Path $Root "Assets\scenes"
if (Test-Path -LiteralPath $sceneRoot) {
    $files += @(Get-ChildItem -LiteralPath $sceneRoot -Recurse -File -Filter "*.scene")
}

foreach ($file in $files) {
    Test-GraphFile -Path $file.FullName
}

if ($files.Count -eq 0) {
    Add-AgentIssue $issues "Error" "Prefab Graph" "" "No prefabs or scenes were found to audit." "Check the project root."
}
elseif (@($issues | Where-Object { $_.Severity -ne "Info" }).Count -eq 0) {
    Add-AgentIssue $issues "Info" "Prefab Graph" "" "Checked $($files.Count) prefab/scene file(s) with no broken graph references."
}

Write-AgentIssues -Issues $issues -ShowInfo:$ShowInfo
exit (Get-AgentExitCode -Issues $issues -FailOnWarning:$FailOnWarning)
