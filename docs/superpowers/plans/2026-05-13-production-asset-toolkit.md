# Production Asset Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared asset-production toolkit for high-quality Blender models, textures, exports, previews, and S&Box integration across weapons/equipment, drones, characters, and environment props.

**Architecture:** Keep the existing `smart_asset_export.ps1` and `asset_pipeline.py` export path. Add pre-export quality gates, category profiles, material/texture checks, preview review tooling, and agent docs that plug into `scripts/agents/run_agent_checks.ps1`.

**Tech Stack:** PowerShell agent wrappers, Python 3, Blender background Python, JSON profile data, Markdown agent docs, existing S&Box asset pipeline scripts.

---

## File Structure

Create:

- `scripts/asset_quality_profiles.json`: category-specific quality rules for `weapon`, `drone`, `character`, and `environment`.
- `scripts/agents/new_asset_brief.ps1`: creates a Markdown asset brief from a category profile.
- `.agents/sbox/asset-brief-agent.md`: operating guide for asset briefs.
- `scripts/blender_asset_audit.py`: Blender-headless source scene audit.
- `scripts/agents/blender_quality_audit.ps1`: PowerShell wrapper for `blender_asset_audit.py`.
- `.agents/sbox/blender-quality-agent.md`: operating guide for Blender quality checks.
- `scripts/agents/material_texture_audit.ps1`: VMAT and texture completeness audit.
- `.agents/sbox/material-texture-agent.md`: operating guide for material checks.
- `scripts/render_asset_preview.py`: Blender preview render helper.
- `scripts/agents/asset_visual_review.ps1`: PowerShell wrapper for preview generation and review notes.
- `.agents/sbox/visual-review-agent.md`: operating guide for visual review.

Modify:

- `scripts/agents/run_agent_checks.ps1`: add `asset-production` suite.
- `scripts/agents/test_full_automation_layer.ps1`: include the new asset-production scripts in automation self-test.
- `scripts/agents/feature_readiness_report.ps1`: classify the new asset tooling scripts as asset pipeline work.
- `.agents/sbox/README.md`: route the new agents.
- `.agents/sbox/asset-pipeline-agent.md`: reference the production lane before export.
- `docs/agent_toolkit.md`: document new commands and workflow.
- `docs/asset_pipeline.md`: add the production asset workflow.
- `docs/automation.md`: note that the `.blend` save hook remains export-only and quality gates are run manually or by suite.
- `.gitignore`: add `.superpowers/` so browser companion state is not accidentally staged.

## Task 1: Profiles and Asset Briefs

**Files:**

- Create: `scripts/asset_quality_profiles.json`
- Create: `scripts/agents/new_asset_brief.ps1`
- Create: `.agents/sbox/asset-brief-agent.md`
- Modify: `.gitignore`

- [ ] **Step 1: Add `.superpowers/` to `.gitignore`**

Add this line under the local agent/editor state section:

```gitignore
.superpowers/
```

- [ ] **Step 2: Create `scripts/asset_quality_profiles.json`**

Use this exact top-level structure:

```json
{
  "weapon": {
    "display_name": "Weapon and Equipment",
    "required_material_roles": ["metal", "polymer"],
    "optional_texture_maps": ["TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"],
    "required_name_hints": ["muzzle", "grip"],
    "scale_note": "Confirm first-person and world scale against the owning weapon prefab.",
    "acceptance_checks": [
      "Muzzle or effect origin is documented when the asset fires or emits effects.",
      "Grip and attachment orientation are documented for soldier mounting.",
      "Standalone prefab target is recorded for attachable equipment."
    ]
  },
  "drone": {
    "display_name": "Drone",
    "required_material_roles": ["frame", "motor", "camera"],
    "optional_texture_maps": ["TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"],
    "required_name_hints": ["prop", "motor", "camera"],
    "scale_note": "Confirm visual bounds against DroneController prefab scale and flight readability.",
    "acceptance_checks": [
      "Silhouette is readable from gameplay distance.",
      "Variant identity is distinct for GPS, FPV, or fiber FPV.",
      "Collision and gameplay components remain owned by prefab/code."
    ]
  },
  "character": {
    "display_name": "Soldier and Character",
    "required_material_roles": ["body", "gear"],
    "optional_texture_maps": ["TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"],
    "required_name_hints": ["root", "body"],
    "scale_note": "Confirm proportions against existing GroundPlayerController and first-person visibility assumptions.",
    "acceptance_checks": [
      "Rig, armature, or attachment readiness is documented when animation is expected.",
      "Class or team material groups are documented when relevant.",
      "Existing SoldierBase prefab identities remain unchanged."
    ]
  },
  "environment": {
    "display_name": "Environment and Prop",
    "required_material_roles": ["surface"],
    "optional_texture_maps": ["TextureNormal", "TextureRoughness", "TextureAmbientOcclusion"],
    "required_name_hints": ["root"],
    "scale_note": "Confirm origin and dimensions are sensible for scene placement.",
    "acceptance_checks": [
      "Collision expectations are documented separately from visual mesh export.",
      "Repeated props have stable names and avoid giant bounds.",
      "Blockout dev-box collider sync remains a separate workflow."
    ]
  }
}
```

- [ ] **Step 3: Create `scripts/agents/new_asset_brief.ps1`**

Implement parameters:

```powershell
param(
    [string]$Root = "",
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [ValidateSet("weapon", "drone", "character", "environment")]
    [string]$Category,
    [string]$Prefab = "",
    [string]$Model = "",
    [string]$OutFile = ""
)
```

Behavior:

- Load `scripts/asset_quality_profiles.json`.
- Write to `docs/assets/briefs/$Name.md` when `-OutFile` is empty.
- Refuse to overwrite unless the generated file does not exist.
- Include sections: `Asset`, `Category Profile`, `S&Box Targets`, `Reference Notes`, `Material Plan`, `Scale and Orientation`, `Sockets and Attachments`, `Acceptance Checklist`.
- Emit `Wrote asset brief: docs/assets/briefs/$Name.md`.

The acceptance checklist must include every profile `acceptance_checks` entry as unchecked Markdown tasks.

- [ ] **Step 4: Create `.agents/sbox/asset-brief-agent.md`**

Include:

```markdown
# Asset Brief Agent

## Purpose

Create and review production asset briefs before Blender modeling or replacement work starts.

## Primary Areas

- `docs/assets/briefs/`
- `scripts/asset_quality_profiles.json`
- `scripts/agents/new_asset_brief.ps1`
- `scripts/*_asset_pipeline.json`
- `Assets/prefabs/`

## Review Rules

- Every production asset should have a category profile: `weapon`, `drone`, `character`, or `environment`.
- Briefs must name the target prefab or explicitly state that the asset is not prefab-mounted yet.
- Replacement assets must record the existing model or prefab they replace.
- Briefs document sockets, attachments, scale, and material roles before export.
- Do not rename public prefabs, components, or assets as part of briefing.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name example_asset -Category weapon
```

## Output Shape

Report the brief path and the category profile used. Treat the brief as planning evidence, not proof that the model is finished.
```

- [ ] **Step 5: Verify brief tooling**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name test_weapon_brief -Category weapon -OutFile .tmpbuild/test_weapon_brief.md
```

Expected:

- Exit code `0`.
- Output contains `Wrote asset brief`.
- `.tmpbuild/test_weapon_brief.md` contains the weapon acceptance checks.

- [ ] **Step 6: Commit Task 1**

```powershell
git add .gitignore scripts/asset_quality_profiles.json scripts/agents/new_asset_brief.ps1 .agents/sbox/asset-brief-agent.md
git commit -m "feat: add asset brief profiles"
```

## Task 2: Blender Quality Audit

**Files:**

- Create: `scripts/blender_asset_audit.py`
- Create: `scripts/agents/blender_quality_audit.ps1`
- Create: `.agents/sbox/blender-quality-agent.md`

- [ ] **Step 1: Implement `scripts/blender_asset_audit.py`**

Use Python `argparse` with:

```python
parser.add_argument("--blend", action="append", default=[])
parser.add_argument("--profiles", default="scripts/asset_quality_profiles.json")
parser.add_argument("--category", choices=["weapon", "drone", "character", "environment"])
parser.add_argument("--blender-exe", default=r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
parser.add_argument("--root", default="")
```

Behavior:

- If no `--blend` is passed, discover `*.blend` files under the project root, excluding `.git`, `.tmpbuild`, `.superpowers`, `bin`, `obj`, and `node_modules`.
- For each `.blend`, run Blender background mode with an embedded inspection script.
- The Blender inspection script must return JSON containing: object count, mesh count, material slots, mesh names, empty names, dimensions, unapplied transforms, uv-less meshes, zero-vertex meshes, root empty candidates, and name hints found.
- Print issues as lines beginning with `[Error]`, `[Warning]`, or `[Info]`.
- Exit `1` if any error exists, otherwise exit `0`.

Error rules:

- Missing `.blend`: error.
- Blender executable missing: error.
- Mesh count is zero: error.
- Zero-vertex mesh: error.

Warning rules:

- Unapplied scale or rotation.
- UV-less mesh when material slots exist.
- More than one top-level mesh and no root empty.
- Missing category name hint.
- Suspicious dimensions below `0.01` or above `10000` in any axis.

- [ ] **Step 2: Implement `scripts/agents/blender_quality_audit.ps1`**

Implement parameters:

```powershell
param(
    [string]$Root = "",
    [ValidateSet("", "weapon", "drone", "character", "environment")]
    [string]$Category = "",
    [string[]]$Blend = @(),
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)
```

Behavior:

- Resolve project root through `agent_common.ps1`.
- Build arguments for `python scripts/blender_asset_audit.py`.
- Pass `--category` only when non-empty.
- Forward `--blend` for each provided blend path.
- Convert non-zero Python exit code to script exit code `1`.

- [ ] **Step 3: Create `.agents/sbox/blender-quality-agent.md`**

Include purpose, primary areas, review rules, and evidence command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Category weapon
```

The guide must state that Blender quality checks do not edit `.blend` files.

- [ ] **Step 4: Verify Blender quality audit on one known blend**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend -Category weapon -ShowInfo
```

Expected:

- Exit code `0` unless the audit surfaces real existing asset quality warnings.
- Output includes a section or line for `assault_rifle_m4.blend`.
- If warnings appear, record them as current quality findings rather than changing the model in this task.

- [ ] **Step 5: Commit Task 2**

```powershell
git add scripts/blender_asset_audit.py scripts/agents/blender_quality_audit.ps1 .agents/sbox/blender-quality-agent.md
git commit -m "feat: add blender asset quality audit"
```

## Task 3: Material and Texture Audit

**Files:**

- Create: `scripts/agents/material_texture_audit.ps1`
- Create: `.agents/sbox/material-texture-agent.md`

- [ ] **Step 1: Implement `scripts/agents/material_texture_audit.ps1`**

Implement parameters:

```powershell
param(
    [string]$Root = "",
    [ValidateSet("", "weapon", "drone", "character", "environment")]
    [string]$Category = "",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)
```

Behavior:

- Load `agent_common.ps1`.
- Load `scripts/asset_quality_profiles.json`.
- Read every `scripts/*_asset_pipeline.json`.
- For each `material_remap`, resolve target `.vmat` with `Resolve-AgentResourcePath`.
- Parse texture entries with regex:

```powershell
'"(?<key>Texture[^"]*)"\s*"(?<value>[^"]+)"'
```

Errors:

- Missing `.vmat` file.
- Missing `TextureColor`.
- `TextureColor` equals `materials/default/default_color.tga` unless config has `allow_default_color_texture: true`.
- Referenced texture file is missing.

Warnings:

- Missing profile optional maps from `optional_texture_maps`.
- Material remap source name is blank.
- Category filter is provided but no configs are inspected.

Info:

- Count of configs, remaps, materials, and texture references checked.

- [ ] **Step 2: Create `.agents/sbox/material-texture-agent.md`**

Include evidence command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -ShowInfo
```

State that this audit catches flat-grey and default-texture failures before playtest.

- [ ] **Step 3: Verify material audit**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -ShowInfo
```

Expected:

- Exit code `0` if current materials are complete.
- Any missing texture output is treated as a real asset finding to record before changing material files.

- [ ] **Step 4: Commit Task 3**

```powershell
git add scripts/agents/material_texture_audit.ps1 .agents/sbox/material-texture-agent.md
git commit -m "feat: add material texture audit"
```

## Task 4: Visual Preview Review

**Files:**

- Create: `scripts/render_asset_preview.py`
- Create: `scripts/agents/asset_visual_review.ps1`
- Create: `.agents/sbox/visual-review-agent.md`

- [ ] **Step 1: Implement `scripts/render_asset_preview.py`**

Use Python `argparse` with:

```python
parser.add_argument("--blend", action="append", required=True)
parser.add_argument("--out-dir", default="screenshots/asset_previews")
parser.add_argument("--blender-exe", default=r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
parser.add_argument("--resolution-x", type=int, default=1400)
parser.add_argument("--resolution-y", type=int, default=900)
```

Behavior:

- For each blend file, run Blender background mode.
- Add a temporary orthographic camera and two lights if the scene has no active camera.
- Frame all mesh objects using their combined bounds.
- Render a PNG named with the asset base name plus `_preview.png`; for `assault_rifle_m4.blend`, write `assault_rifle_m4_preview.png`.
- Write a JSON sidecar named with the asset base name plus `_preview.json`; for `assault_rifle_m4.blend`, write `assault_rifle_m4_preview.json` with mesh count, material count, output path, and render resolution.
- Do not save the `.blend`.

- [ ] **Step 2: Implement `scripts/agents/asset_visual_review.ps1`**

Implement parameters:

```powershell
param(
    [string]$Root = "",
    [string[]]$Blend = @(),
    [string]$OutDir = "screenshots/asset_previews",
    [switch]$ShowInfo,
    [switch]$FailOnWarning
)
```

Behavior:

- Require at least one `-Blend`; if none is passed, emit a warning and exit `0`.
- Invoke `python scripts/render_asset_preview.py` with every blend.
- Check that every expected PNG exists.
- Print output paths.

- [ ] **Step 3: Create `.agents/sbox/visual-review-agent.md`**

Include evidence command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend
```

State that preview images are local review artifacts and are ignored through `screenshots/`.

- [ ] **Step 4: Verify preview review**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend -ShowInfo
```

Expected:

- Exit code `0` if Blender renders successfully.
- Output includes `screenshots/asset_previews/assault_rifle_m4_preview.png`.

- [ ] **Step 5: Commit Task 4**

```powershell
git add scripts/render_asset_preview.py scripts/agents/asset_visual_review.ps1 .agents/sbox/visual-review-agent.md
git commit -m "feat: add asset visual review previews"
```

## Task 5: Runner and Documentation Integration

**Files:**

- Modify: `scripts/agents/run_agent_checks.ps1`
- Modify: `scripts/agents/test_full_automation_layer.ps1`
- Modify: `scripts/agents/feature_readiness_report.ps1`
- Modify: `.agents/sbox/README.md`
- Modify: `.agents/sbox/asset-pipeline-agent.md`
- Modify: `docs/agent_toolkit.md`
- Modify: `docs/asset_pipeline.md`
- Modify: `docs/automation.md`

- [ ] **Step 1: Add `asset-production` suite to `run_agent_checks.ps1`**

Update the `ValidateSet` to include:

```powershell
"asset-production"
```

Add this switch case:

```powershell
"asset-production" {
    $scripts = @(
        @{ Name = "blender_quality_audit.ps1"; Args = $commonArgs },
        @{ Name = "material_texture_audit.ps1"; Args = $commonArgs },
        @{ Name = "asset_pipeline_audit.ps1"; Args = $commonArgs },
        @{ Name = "prefab_graph_audit.ps1"; Args = $commonArgs },
        @{ Name = "feature_readiness_report.ps1"; Args = @("-Root", $Root, "-ShowFiles") }
    )
}
```

- [ ] **Step 2: Update `test_full_automation_layer.ps1`**

Add required scripts:

```powershell
"scripts/agents/blender_quality_audit.ps1",
"scripts/agents/material_texture_audit.ps1",
"scripts/agents/asset_visual_review.ps1"
```

Add runner suite check:

```powershell
"asset-production"
```

Do not run `asset_visual_review.ps1` from self-test unless a blend path is supplied; only verify the script exists.

- [ ] **Step 3: Update `feature_readiness_report.ps1`**

Mark these as `AssetPipeline` and `Tooling`:

```powershell
^scripts/blender_asset_audit\.py$
^scripts/render_asset_preview\.py$
^scripts/asset_quality_profiles\.json$
^scripts/agents/(blender_quality_audit|material_texture_audit|asset_visual_review|new_asset_brief)\.ps1$
```

When `AssetPipeline.Count -gt 0`, add:

```powershell
Add-Line $lines '- [ ] `powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production`'
```

- [ ] **Step 4: Update agent README routing**

Add rows for:

- Asset Brief Agent.
- Blender Quality Agent.
- Material and Texture Agent.
- Visual Review Agent.
- Asset Production Suite.

- [ ] **Step 5: Update docs**

In `docs/agent_toolkit.md`, add commands:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name my_asset -Category weapon
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

In `docs/asset_pipeline.md`, add the production lane before the existing general usage section:

```markdown
## Production Asset Workflow

1. Create or review an asset brief.
2. Audit the Blender source scene.
3. Audit materials and textures.
4. Export through the existing save hook or `asset_pipeline.ps1`.
5. Run the asset-production suite.
6. Perform S&Box editor visual acceptance.
```

In `docs/automation.md`, add that the `.blend` save hook remains export-focused and quality gates can be run manually or through `run_agent_checks.ps1 -Suite asset-production`.

- [ ] **Step 6: Verify runner/docs integration**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite self-test
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite docs
```

Expected:

- `self-test` exits `0`.
- `docs` exits `0` or reports only pre-existing docs drift unrelated to this task.

- [ ] **Step 7: Commit Task 5**

```powershell
git add scripts/agents/run_agent_checks.ps1 scripts/agents/test_full_automation_layer.ps1 scripts/agents/feature_readiness_report.ps1 .agents/sbox/README.md .agents/sbox/asset-pipeline-agent.md docs/agent_toolkit.md docs/asset_pipeline.md docs/automation.md
git commit -m "docs: wire asset production agents"
```

## Task 6: Final Verification

**Files:**

- No new files unless verification output reveals a defect that belongs to Tasks 1-5.

- [ ] **Step 1: Run focused asset checks**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/new_asset_brief.ps1 -Name verification_weapon -Category weapon -OutFile .tmpbuild/verification_weapon.md
powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend -Category weapon -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend weapons_model.blend/assault_rifle_m4.blend -ShowInfo
```

Expected:

- Brief command exits `0`.
- Blender quality command exits `0` or reports existing asset warnings without crashing.
- Material audit exits `0` or reports real material gaps.
- Visual review exits `0` and creates a preview under `screenshots/asset_previews/`.

- [ ] **Step 2: Run production suite**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production -ShowInfo
```

Expected:

- Exit code `0` unless real existing asset quality findings are now surfaced.
- If warnings appear, do not suppress them without documenting why they are current known asset debt.

- [ ] **Step 3: Run automation self-test**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/test_full_automation_layer.ps1
```

Expected:

- Exit code `0`.
- Output confirms the new scripts and `asset-production` suite are discoverable.

- [ ] **Step 4: Run final readiness report**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/feature_readiness_report.ps1 -ShowFiles
```

Expected:

- Output classifies asset production scripts as Tooling and AssetPipeline.
- Required checks include the asset-production suite.

- [ ] **Step 5: Commit verification fixes if needed**

If verification required fixes:

For runner or documentation fixes, run:

```powershell
git add scripts/agents/run_agent_checks.ps1 scripts/agents/test_full_automation_layer.ps1 scripts/agents/feature_readiness_report.ps1 docs/agent_toolkit.md docs/asset_pipeline.md docs/automation.md
git commit -m "fix: stabilize asset production toolkit"
```

For audit-script fixes, run:

```powershell
git add scripts/blender_asset_audit.py scripts/render_asset_preview.py scripts/agents/blender_quality_audit.ps1 scripts/agents/material_texture_audit.ps1 scripts/agents/asset_visual_review.ps1 scripts/agents/new_asset_brief.ps1
git commit -m "fix: stabilize asset production toolkit"
```

If no fixes were required, do not create an empty commit.

## Handoff Notes

- Do not edit existing `.blend` models as part of this toolkit implementation unless a verification failure is caused by broken tooling assumptions.
- Do not run destructive git cleanup.
- Keep generated previews under `screenshots/`, which is already ignored.
- Keep browser companion state under `.superpowers/`, which should be ignored after Task 1.
