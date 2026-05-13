# Claude Code Automation Hooks

This document describes the automated workflows provided by Claude Code hooks in the ABOVE/BELOW project.

## Overview

Claude Code hooks are declarative automation triggers that respond to file changes, time-based events, or manual triggers. This project uses hooks to automate the Blender → S&Box asset export pipeline, eliminating manual script execution and reducing friction in the art iteration workflow.

**Benefit:** ~35-second time savings per asset iteration (eliminates manual `asset_pipeline.ps1` invocation + context switching)

## Codex Lifecycle Hooks

Codex lifecycle hooks live under `.codex/` and run during Codex sessions rather than on file-save events.

- `.codex/config.toml` enables lifecycle hooks for this project with `[features].hooks = true`.
- `.codex/hooks.json` registers the project hooks shown in the Codex app Hooks settings page.
- `.codex/hooks/sbox_session_start.ps1` injects a short S&Box project reminder when a session starts, resumes, or clears.
- `.codex/hooks/sbox_pre_tool_guard.ps1` blocks broad destructive cleanup commands such as `git reset --hard`, `git clean`, recursive deletes, and path reverts unless the workflow is changed explicitly.

These hooks are intentionally conservative. They do not compile the project, mutate prefabs, or auto-approve permission requests.

## Primary Hook: Asset Auto-Export (Any .blend File)

### Configuration

**File:** `./.claude/settings.json`

```json
{
  "id": "blend-auto-export",
  "name": "Auto-Export Blender Assets",
  "description": "Runs asset pipeline when any .blend file is saved",
  "enabled": true,
  "trigger": {
    "type": "file_pattern_change",
    "patterns": [
      "**/*.blend",
      "**/*.blend.blend"
    ],
    "events": ["modified", "saved"],
    "debounce_ms": 2000
  },
  "action": {
    "type": "script",
    "command": "powershell",
    "args": [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      ".\\scripts\\smart_asset_export.ps1",
      "-BlendFilePath",
      "${FILE_PATH}"
    ],
    "cwd": "${WORKSPACE_ROOT}",
    "timeout_seconds": 300,
    "capture_output": true,
    "on_success": {
      "notify": true,
      "message": "Asset exported successfully",
      "level": "info"
    },
    "on_failure": {
      "notify": true,
      "message": "Asset export failed - check logs",
      "level": "error"
    }
  }
}
```

### How It Works

1. **File Monitoring**: Claude Code monitors ALL `.blend` files for changes (both `*.blend` and `*.blend.blend` patterns)
2. **Debounce**: Waits 2 seconds after file modification to ensure Blender has fully flushed the save
3. **Smart Config Detection**: Invokes `smart_asset_export.ps1` which:
   - Detects which `.blend` file changed
   - Checks for asset-specific config (e.g., `drone_asset_pipeline.json` for `drone.blend`)
   - Falls back to generic config (`asset_pipeline_generic.json`) if no specific config exists
   - Passes detected config to asset pipeline
4. **Pipeline Execution**:
   - PowerShell wrapper (`asset_pipeline.py`) uses detected config
   - Python launches Blender in background mode (`blender --background`)
   - Blender exports asset geometry to FBX format
   - Python generates VMDL wrapper document (using variable substitution: `${ASSET_NAME}`, `${BLEND_FILE}`)
   - Python updates S&Box prefab JSON with model reference
5. **Notification**: Claude Code displays success or error notification in the UI
6. **Auto-Reload**: S&Box editor detects `.vmdl` and `.prefab` changes and automatically reloads

### Developer Workflow

#### Before (Manual)
```
1. Edit any.blend in Blender
2. Save file
3. Switch to PowerShell terminal
4. Run: .\scripts\asset_pipeline.ps1 --config .\scripts\some_config.json
5. Wait 10-30 seconds for Blender background export
6. Switch back to S&Box editor
7. Refresh asset browser or reload scene
8. Test changes
```
**Total Time:** ~45 seconds per asset

#### After (Automated)
```
1. Edit any.blend in Blender
2. Save file (Ctrl+S)
3. See notification in Claude Code within 2-5 seconds: "Asset exported successfully"
4. Stay in S&Box editor (assets already updated)
5. Test changes immediately
```
**Total Time:** ~5-10 seconds per asset

## Manual Map Maintenance: Blockout Collider Sync

The Blender auto-export hook does not manage composed-box map geometry. For scene and prefab objects that use `models/dev/box.vmdl`, run the collider sync pipeline after map edits, prefab cloning, or transform resizing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1 -All -Apply
```

Why this exists:

- `models/dev/box.vmdl` has 50 x 50 x 50 local bounds.
- S&Box applies the GameObject scale to both the renderer and the collider.
- Matching blockout collision therefore uses `BoxCollider.Center = 0,0,0` and `BoxCollider.Scale = 50,50,50`.
- Authoring the collider as the final world size makes selected collision outlines appear too large.

This step is intentionally manual rather than a scene-save hook so it does not fight in-editor collision edits or trigger while a prefab editor tab is active. Preferred workflow:

1. Save the current scene in S&Box.
2. Run the collider sync command.
3. Reopen `Assets/scenes/main.scene`.
4. Check the editor console.

## Setting Up New Assets

### Quick Start: Use Generic Config

For any new `.blend` file, just save it and the hook will automatically export using `asset_pipeline_generic.json`:

1. Create your Blender model in a new `.blend` file (e.g., `soldier_model.blend/soldier.blend`)
2. Save the file
3. Hook detects the save and exports:
   - FBX → `Assets/models/soldier.fbx`
   - VMDL → `Assets/models/soldier.vmdl`
   - Prefab → `Assets/prefabs/soldier.prefab`
4. S&Box automatically detects and loads the new assets

**No configuration needed** — the generic config handles it all.

### Custom Config: Per-Asset Customization

If an asset needs special handling (custom material remaps, specific export settings, etc.), create a matching config file:

**Asset File:** `soldier_model.blend/soldier.blend`  
**Config File:** `scripts/soldier_asset_pipeline.json`

```json
{
  "source_blend": "soldier_model.blend/soldier.blend",
  "root_object": "SoldierRig",
  "target_fbx": "Assets/models/soldier.fbx",
  "target_vmdl": "Assets/models/soldier.vmdl",
  "model_resource_path": "models/soldier.vmdl",
  "prefab": "Assets/prefabs/soldier.prefab",
  "material_remap": {
    "ClothMaterial": "materials/cloth.vmat",
    "SkinMaterial": "materials/skin.vmat"
  },
  "global_scale": 2.5
}
```

**How it works:**
1. Save `soldier.blend` → hook triggers
2. `smart_asset_export.ps1` detects the asset name: `soldier`
3. Looks for `soldier_asset_pipeline.json` config
4. Finds it and uses the custom config instead of generic
5. Exports with custom settings (material remaps, scaling, etc.)

### Config Naming Convention

| File | Config Used |
|------|-------------|
| `drone_model.blend/drone.blend` | `drone_asset_pipeline.json` (specific) |
| `soldier_model.blend/soldier.blend` | `soldier_asset_pipeline.json` (specific) or `asset_pipeline_generic.json` (fallback) |
| `props_model.blend/barrel.blend` | `barrel_asset_pipeline.json` (specific) or `asset_pipeline_generic.json` (fallback) |

**Pattern:** `{blend_filename_without_extension}_asset_pipeline.json`

### Generic Config Variables

The generic config supports variable substitution:

| Variable | Replaced With | Example |
|----------|---------------|---------|
| `${BLEND_FILE}` | Full path to the .blend being exported | `drone_model.blend/drone.blend.blend` |
| `${ASSET_NAME}` | Filename without extension | `drone` (from `drone.blend.blend`) |

Example generic config:
```json
{
  "source_blend": "${BLEND_FILE}",
  "target_fbx": "Assets/models/${ASSET_NAME}.fbx",
  "target_vmdl": "Assets/models/${ASSET_NAME}.vmdl",
  "prefab": "Assets/prefabs/${ASSET_NAME}.prefab"
}
```

When `soldier.blend` is saved, variables expand to:
```json
{
  "source_blend": "soldier_model.blend/soldier.blend",
  "target_fbx": "Assets/models/soldier.fbx",
  "target_vmdl": "Assets/models/soldier.vmdl",
  "prefab": "Assets/prefabs/soldier.prefab"
}
```

### File Paths Referenced

| Path | Purpose |
|------|---------|
| `drone_model.blend/drone.blend.blend` | Source Blender file being monitored |
| `scripts/asset_pipeline.ps1` | PowerShell wrapper (invoked by hook) |
| `scripts/asset_pipeline.py` | Core Python pipeline logic |
| `scripts/drone_asset_pipeline.json` | Configuration for drone export |
| `Assets/models/drone_high.fbx` | Exported FBX geometry |
| `Assets/models/drone_high.vmdl` | S&Box model wrapper document |
| `Assets/prefabs/drone.prefab` | Prefab updated with model reference |

## Hook Configuration Reference

### Trigger Types

#### `file_change`
Monitors specific files for modifications.

```json
{
  "type": "file_change",
  "paths": [
    "drone_model.blend/drone.blend.blend",
    "other_file.blend"
  ],
  "events": ["modified", "saved"],
  "debounce_ms": 2000
}
```

**Parameters:**
- `paths` (array): Exact file paths to monitor
- `events` (array): `modified` (any change) or `saved` (write completed)
- `debounce_ms` (number): Wait time after last change before firing (prevents rapid double-triggers)

#### `file_pattern_change`
Monitors file patterns (globs) for modifications.

```json
{
  "type": "file_pattern_change",
  "patterns": ["Code/**/*.cs", "Assets/**/*.prefab"],
  "events": ["modified"],
  "debounce_ms": 3000
}
```

**Parameters:**
- `patterns` (array): Glob patterns (e.g., `**/*.cs`, `Code/Game/*.cs`)
- `events` (array): Change event types
- `debounce_ms` (number): Debounce delay

### Action Types

#### `script`
Executes a shell script or command.

```json
{
  "type": "script",
  "command": "powershell",
  "args": ["-File", ".\\script.ps1", "--param", "value"],
  "env": {"KEY": "VALUE"},
  "cwd": "${WORKSPACE_ROOT}",
  "timeout_seconds": 300,
  "capture_output": true,
  "on_success": {
    "notify": true,
    "message": "Success",
    "level": "info"
  },
  "on_failure": {
    "notify": true,
    "message": "Failed",
    "level": "error"
  }
}
```

**Parameters:**
- `command` (string): Shell command (`powershell`, `python`, `node`, `bash`, etc.)
- `args` (array): Command-line arguments
- `env` (object): Environment variables to set
- `cwd` (string): Working directory (`${WORKSPACE_ROOT}` = project root)
- `timeout_seconds` (number): Max execution time before killing process
- `capture_output` (boolean): Capture stdout/stderr for logging
- `on_success.notify` (boolean): Show notification on success
- `on_failure.notify` (boolean): Show notification on failure

## Managing Hooks

### Enable / Disable

To temporarily disable the hook:

```json
{
  "id": "blend-auto-export",
  "enabled": false,
  ...
}
```

Save the file and the hook becomes inactive. No manual runs are affected—you can still run `asset_pipeline.ps1` directly from PowerShell.

### Modify Configuration

To change the trigger path (e.g., monitor a different `.blend` file):

```json
{
  "trigger": {
    "paths": [
      "other_drone.blend/model.blend"
    ],
    ...
  }
}
```

Changes take effect immediately; no restart required.

### Debugging

#### Hook Doesn't Fire

1. Verify `.claude/settings.json` exists and is valid JSON
2. Check that `"enabled": true` in the hook definition
3. Verify the file path matches exactly (case-sensitive on Linux/Mac)
4. Check that the file actually changed (touch the file if testing)

#### Export Fails

1. **Check hook logs**: Claude Code stores logs of each hook execution (UI menu → View → Logs)
2. **Run pipeline manually**: `.\scripts\asset_pipeline.ps1 --config .\scripts\drone_asset_pipeline.json`
3. **Verify Blender is installed**: Hook relies on `blender` command in PATH
4. **Check Blender version**: Must be a version that supports `--background` flag (4.0+)
5. **Inspect asset pipeline output**: Run script directly to see detailed error messages

#### Timeout Errors

If the hook times out (300 seconds default):

1. Check if Blender is responsive: `blender --version`
2. Profile Blender export: `blender drone_model.blend/drone.blend.blend --background -o /tmp/test.fbx -F FBX -x`
3. If export is slow, increase timeout: Change `"timeout_seconds": 600` in hook config
4. Consider simplifying the model or splitting into multiple blend files

## Future Hooks (Not Yet Enabled)

The following hooks have been designed but are disabled by default. They can be enabled as needed:

### `code-compile-validate`

Validates prefabs after C# code changes.

**Purpose:** Catch prefab/component mismatches early  
**Trigger:** Changes to `Code/**/*.cs`  
**Action:** Run `scripts/validate_prefabs.ps1`
- Verify `drone.prefab` has `ModelRenderer` component
- Check model path points to valid VMDL
- Flag JSON syntax errors

**To Enable:** Create `scripts/validate_prefabs.ps1` and add hook to settings.json

### `game-change-validate`

Validates component wiring after gameplay changes.

**Purpose:** Detect [Sync] property mismatches  
**Trigger:** Changes to `Code/Game/*.cs` or `Code/Drone/*.cs`  
**Action:** Run `scripts/validate_components.ps1`
- Parse C# for `[Sync]` attributes
- Cross-reference prefab JSON component names
- Flag wiring regressions

**To Enable:** Create `scripts/validate_components.ps1` and add hook to settings.json

## Performance Impact

- **Hook Monitoring:** Negligible (file system events, <1ms per check)
- **Hook Execution:** ~10-30 seconds (Blender background export + FBX generation)
- **UI Responsiveness:** No impact; hooks run async in background
- **CI/CD:** Hooks only run in Claude Code CLI environment; not in CI pipelines

## Best Practices

1. **Keep Debounce Reasonable**: 2 seconds is typical for file saves; increases prevent rapid cascades
2. **Timeout Should Match Workload**: 300 seconds for Blender export; adjust if models are very large
3. **Enable Only When Needed**: Disable validation hooks until a pain point emerges
4. **Review Hook Output**: Check logs periodically to ensure hooks are firing correctly
5. **Version Control**: Commit `.claude/settings.json` so all developers inherit the same hooks

## Troubleshooting Matrix

| Symptom | Cause | Fix |
|---------|-------|-----|
| Hook never fires | `enabled: false` or file path mismatch | Check settings.json; verify file path |
| Export times out | Blender is slow or hanging | Simplify model; increase timeout; check Blender installation |
| Notification shows "failed" | PowerShell execution policy | Run: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser` |
| S&Box doesn't reload model | Asset browser not refreshing | Manually reload prefab in S&Box or restart editor |
| Multiple exports on one save | Debounce too short | Increase `debounce_ms` from 2000 to 3000+ |

## FAQ

**Q: Do hooks run in CI/CD pipelines?**  
A: No. Hooks are Claude Code-specific and only execute in the Claude Code harness. CI/CD must invoke scripts directly.

**Q: Can I hook other .blend files?**  
A: Yes. Add multiple file paths to the trigger configuration or create separate hooks for each asset.

**Q: What if the export fails silently?**  
A: Check hook logs in Claude Code UI (Menu → View → Logs). The `capture_output` flag ensures all output is logged.

**Q: Can hooks modify files?**  
A: Yes, hooks can run any script. The asset pipeline hook uses Python to update JSON files (prefabs).

**Q: How do I test a hook locally?**  
A: Run the command manually from PowerShell to verify it works. If the command succeeds manually, the hook should also succeed.
