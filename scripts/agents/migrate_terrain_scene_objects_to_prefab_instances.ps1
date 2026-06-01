param(
    [string]$Root = "",
    [switch]$DryRun
)

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}
else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$nodeScript = Join-Path $PSScriptRoot "migrate_terrain_scene_objects_to_prefab_instances.js"
$arguments = @($nodeScript, "--root", $Root)
if ($DryRun) {
    $arguments += "--dry-run"
}

node @arguments
exit $LASTEXITCODE
