param(
    [string]$Root = "",
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [ValidateSet("weapon", "drone", "character", "environment")]
    [string]$Category,
    [string]$Prefab = "",
    [string]$Model = "",
    [string]$OutFile = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$profilesPath = Join-Path $Root "scripts\asset_quality_profiles.json"
if (-not (Test-Path -LiteralPath $profilesPath)) {
    throw "Asset quality profiles file is missing: scripts/asset_quality_profiles.json"
}

$profiles = Read-AgentJson -Path $profilesPath
$profile = $profiles.$Category
if ($null -eq $profile) {
    throw "Asset quality profile '$Category' was not found."
}

if (
    [string]::IsNullOrWhiteSpace($Name) -or
    $Name -notmatch "^[A-Za-z0-9][A-Za-z0-9_.-]*$" -or
    $Name.Contains("..") -or
    $Name.Contains("/") -or
    $Name.Contains("\")
) {
    throw "Invalid asset brief name '$Name'. Use a filename-safe asset identifier matching ^[A-Za-z0-9][A-Za-z0-9_.-]*$ with no path separators or '..'."
}

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = Join-Path "docs\assets\briefs" "$Name.md"
}

if ([System.IO.Path]::IsPathRooted($OutFile)) {
    $outputPath = $OutFile
}
else {
    $outputPath = Join-Path $Root $OutFile
}

if (Test-Path -LiteralPath $outputPath) {
    $relativeExisting = ConvertTo-AgentRelativePath -Path $outputPath -Root $Root
    throw "Refusing to overwrite existing asset brief: $relativeExisting"
}

$parent = [System.IO.Path]::GetDirectoryName($outputPath)
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
}

function Format-BriefList {
    param([object[]]$Items)

    $values = @($Items)
    if ($values.Count -eq 0) {
        return "- TBD"
    }

    return (($values | ForEach-Object { "- $_" }) -join [Environment]::NewLine)
}

function Format-BriefChecklist {
    param([object[]]$Items)

    $values = @($Items)
    if ($values.Count -eq 0) {
        return "- [ ] TBD"
    }

    return (($values | ForEach-Object { "- [ ] $_" }) -join [Environment]::NewLine)
}

$prefabText = if ([string]::IsNullOrWhiteSpace($Prefab)) { "TBD" } else { $Prefab }
$modelText = if ([string]::IsNullOrWhiteSpace($Model)) { "TBD" } else { $Model }
$materialRoles = Format-BriefList -Items $profile.required_material_roles
$textureMaps = Format-BriefList -Items $profile.optional_texture_maps
$nameHints = Format-BriefList -Items $profile.required_name_hints
$checklist = Format-BriefChecklist -Items $profile.acceptance_checks

$brief = @"
# $Name

## Asset

- Name: $Name
- Category: $Category
- Profile: $($profile.display_name)

## Category Profile

Required material roles:
$materialRoles

Optional texture maps:
$textureMaps

Required name hints:
$nameHints

## S&Box Targets

- Prefab: $prefabText
- Model: $modelText

## Reference Notes

- TBD

## Material Plan

- TBD

## Scale and Orientation

$($profile.scale_note)

## Sockets and Attachments

- TBD

## Acceptance Checklist

$checklist
"@

Set-Content -LiteralPath $outputPath -Value $brief -Encoding UTF8

$relativeOutput = ConvertTo-AgentRelativePath -Path $outputPath -Root $Root
Write-Host "Wrote asset brief: $relativeOutput"
