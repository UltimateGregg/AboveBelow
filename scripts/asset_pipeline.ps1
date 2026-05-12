param(
    [string]$Config,
    [switch]$DryRun,
    [switch]$SkipExport,
    [switch]$SkipPrefab,
    [switch]$RemoveCompiledCache,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "asset_pipeline.py"
$argsList = @($script)

if (-not $Config) {
    $Config = Join-Path $PSScriptRoot "drone_asset_pipeline.json"
}

if ($Config) {
    $argsList += @("--config", $Config)
}
if ($DryRun) {
    $argsList += "--dry-run"
}
if ($SkipExport) {
    $argsList += "--skip-export"
}
if ($SkipPrefab) {
    $argsList += "--skip-prefab"
}
if ($RemoveCompiledCache) {
    $argsList += "--remove-compiled-cache"
}
if ($ExtraArgs) {
    $argsList += $ExtraArgs
}

& python @argsList
exit $LASTEXITCODE
