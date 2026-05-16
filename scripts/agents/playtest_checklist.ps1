param(
    [string]$Root = "",
    [ValidateSet("All", "Gameplay", "Networking", "Prefab", "Asset", "UI", "Balance")]
    [string]$ChangeArea = "All",
    [string]$OutFile = ""
)

. "$PSScriptRoot\agent_common.ps1"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-AgentProjectRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Text = ""
    )
    $Lines.Add($Text)
}

function Include-Area {
    param([string]$Area)
    return $ChangeArea -eq "All" -or $ChangeArea -eq $Area
}

$lines = New-Object System.Collections.Generic.List[string]
Add-Line $lines "# Playtest QA Checklist"
Add-Line $lines ""
Add-Line $lines "Change area: $ChangeArea"
Add-Line $lines "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Line $lines ""
Add-Line $lines "## Always Run"
Add-Line $lines ""
Add-Line $lines '- [ ] `dotnet build Code\dronevsplayers.csproj --no-restore` succeeds with no new warnings.'
Add-Line $lines '- [ ] Open `Assets/scenes/main.scene` in the S&Box editor.'
Add-Line $lines "- [ ] Press Play once in editor and confirm there are no new red console errors."
Add-Line $lines "- [ ] Confirm the HUD class/variant picker still appears for the local player."
Add-Line $lines ""

if (Include-Area "Gameplay") {
    Add-Line $lines "## Gameplay"
    Add-Line $lines ""
    Add-Line $lines "- [ ] Assault, Counter-UAV, Heavy, GPS, FPV, and Fiber FPV can each be selected."
    Add-Line $lines "- [ ] Soldier movement, sprint, jump, crouch/slide, and ladder movement still respond."
    Add-Line $lines "- [ ] Pilot ground avatar can deploy or control the selected drone."
    Add-Line $lines "- [ ] FPV and Fiber FPV: first ground-side LMB launches, second ground-side LMB or F enters drone control, and LMB while in drone view detonates."
    Add-Line $lines "- [ ] FPV and Fiber FPV detonation starts redeploy cooldown and does not prematurely end the round before the intended drone death state is reached."
    Add-Line $lines "- [ ] Killing all members of one team ends the round with the expected winner."
    Add-Line $lines ""
}

if (Include-Area "Networking") {
    Add-Line $lines "## Networking"
    Add-Line $lines ""
    Add-Line $lines "- [ ] Run a 2-client local playtest."
    Add-Line $lines "- [ ] Host spawns and state mutations happen only on the host."
    Add-Line $lines "- [ ] `[Sync]` values visible in HUD or gameplay replicate to the second client."
    Add-Line $lines "- [ ] Broadcast RPC effects are visible on both peers without double-applying damage or jam."
    Add-Line $lines "- [ ] Disconnecting one client during a round does not leave the game in a broken state."
    Add-Line $lines ""
}

if (Include-Area "Prefab") {
    Add-Line $lines "## Prefab and Scene"
    Add-Line $lines ""
    Add-Line $lines '- [ ] `scripts\agents\prefab_wiring_audit.ps1` passes.'
    Add-Line $lines '- [ ] New or changed prefab references are either inspector-wired or handled by `Code/code/Wiring/AutoWire.cs`.'
    Add-Line $lines "- [ ] Soldier prefabs have Body, Eye, Weapon or DroneDeployer, and expected held equipment children."
    Add-Line $lines "- [ ] Drone prefabs have Visual, CameraSocket, MuzzleSocket, and the correct variant identity component."
    Add-Line $lines ""
}

if (Include-Area "Asset") {
    Add-Line $lines "## Assets"
    Add-Line $lines ""
    Add-Line $lines '- [ ] `scripts\agents\asset_pipeline_audit.ps1` passes.'
    Add-Line $lines '- [ ] `scripts\agents\fbx_material_slot_audit.ps1 -ShowInfo` passes for strict material configs.'
    Add-Line $lines '- [ ] Saving the edited `.blend` runs the configured export pipeline or a manual dry run succeeds.'
    Add-Line $lines '- [ ] Exported `.fbx`, `.vmdl`, `.vmat`, and `.prefab` paths are under the expected `Assets/` folders.'
    Add-Line $lines "- [ ] S&Box editor reloads the changed asset without a missing model or error material."
    Add-Line $lines "- [ ] Multi-material foliage has no scene `MaterialOverride` or `Materials.indexed`, and the editor inspector does not show `materials/default.vmat_c` for the tree model."
    Add-Line $lines ""
}

if (Include-Area "UI") {
    Add-Line $lines "## UI"
    Add-Line $lines ""
    Add-Line $lines "- [ ] Main menu shows only live actions; no passive card looks clickable."
    Add-Line $lines "- [ ] `Play` opens the team/class picker."
    Add-Line $lines "- [ ] Above/Below team choices appear only after `Play`, and both choices respond."
    Add-Line $lines "- [ ] Every visible button or card that looks clickable has visible behavior when clicked."
    Add-Line $lines "- [ ] HUD text fits at 1280x720 and at the target desktop resolution."
    Add-Line $lines "- [ ] Class picker buttons, loadout slots, health, timer, scoreboard, and kill feed remain readable."
    Add-Line $lines "- [ ] UI changes do not hide the playfield or input feedback during combat."
    Add-Line $lines ""
}

if (Include-Area "Balance") {
    Add-Line $lines "## Balance"
    Add-Line $lines ""
    Add-Line $lines '- [ ] Generate a fresh tuning report with `scripts\agents\balance_tuning_report.ps1`.'
    Add-Line $lines "- [ ] Counter-UAV still beats GPS with line of sight."
    Add-Line $lines "- [ ] Heavy still has the clearest answer to normal FPV dive paths."
    Add-Line $lines "- [ ] Assault still has the clearest answer to fiber FPV."
    Add-Line $lines "- [ ] Fiber FPV still ignores RF jamming unless the balance spec was intentionally changed."
    Add-Line $lines ""
}

$text = $lines -join [Environment]::NewLine
if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $target = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $Root $OutFile }
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    $text | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Host "Wrote playtest checklist: $(ConvertTo-AgentRelativePath -Path $target -Root $Root)"
}
else {
    Write-Host $text
}
