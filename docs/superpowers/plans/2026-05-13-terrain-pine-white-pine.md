# Terrain Pine White Pine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing simple tree model with a tall white-pine-style environment asset.

**Architecture:** Keep existing scene placements stable, but use the editor-visible model path that matches the Blender source name: `models/terrain_assets.vmdl`. Update the Blender generator as the source of truth, add a dedicated pipeline config for repeatable terrain-assets export, and validate through the asset-production tools.

**Tech Stack:** Blender Python, FBX, S&Box VMDL, PowerShell agent wrappers, existing asset quality scripts.

---

## File Structure

- Modify `scripts/create_environment_proxy_assets.py`: generate a root empty, thin trunk, branch cylinders, lower dead stubs, and flattened needle clumps.
- Create `scripts/terrain_assets_asset_pipeline.json`: export `TerrainPine_Root` from the shared terrain blend to the terrain-assets FBX/VMDL.
- Modify generated assets: `environment_model.blend/terrain_assets.blend`, `Assets/models/terrain_assets.fbx`, `Assets/models/terrain_assets.vmdl`.
- Update documentation: `docs/assets/briefs/terrain_assets.md`, `docs/superpowers/specs/2026-05-13-terrain-pine-white-pine-design.md`.

## Task 1: Source Generator and Config

- [ ] Add Blender helper functions for cylinder alignment and flattened needle ellipsoid creation.
- [ ] Replace `create_pine()` with a white-pine structure: `TerrainPine_Root`, `TerrainPine_Trunk`, branch meshes, dead lower stubs, and multiple `TerrainPine_Needles_*` clumps.
- [ ] Add `scripts/terrain_assets_asset_pipeline.json` with `root_object` set to `TerrainPine_Root`, `target_fbx` set to `Assets/models/terrain_assets.fbx`, and existing bark/needle material remaps.
- [ ] Run `python -m py_compile scripts/create_environment_proxy_assets.py`.

## Task 2: Generate and Export Asset

- [ ] Run Blender background mode on `scripts/create_environment_proxy_assets.py` to regenerate the terrain asset blend and model files.
- [ ] Run `python scripts/asset_pipeline.py --config scripts/terrain_assets_asset_pipeline.json` to verify tree export selection and material remaps.
- [ ] Confirm `Assets/scenes/main.scene` tree renderers reference `models/terrain_assets.vmdl`.

## Task 3: Asset Verification

- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/agents/blender_quality_audit.ps1 -Category environment -Blend environment_model.blend/terrain_assets.blend -ShowInfo -TimeoutSeconds 240`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -Category environment -ShowInfo`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_visual_review.ps1 -Blend environment_model.blend/terrain_assets.blend -ShowInfo -TimeoutSeconds 240`.
- [ ] Inspect the generated preview and iterate if the model does not match the approved direction.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/agents/asset_pipeline_audit.ps1 -ShowInfo`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/agents/build_log_sentinel.ps1`.
