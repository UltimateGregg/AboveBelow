# Procedural Texture Transfer Agent

## Purpose

Move Blender procedural material looks into S&Box without relying on viewport-only appearance, scene material overrides, or guessed `.vmat` replacements.

Use this when a Blender model looks correct but the S&Box model shows flat/default/wrong materials, especially when Blender materials use Noise, Voronoi, ColorRamp, object coordinates, or other procedural nodes instead of image textures.

## Review Rules

- Inspect Blender material nodes before changing S&Box materials. If the source look is procedural and has no Image Texture node to copy, bake the procedural color to project PNGs.
- Prefer background Blender for baking or inspection. Avoid long live-editor/visible-Blender bake loops that can freeze the user's interactive session.
- Bake one representative object per material slot when the material is shared across repeated mesh parts.
- Keep baked textures under `Assets/materials/<category>/` and point the owning `.vmat` `TextureColor` at those images.
- Multi-material assets must bind through the asset config, FBX material slots, and generated `.vmdl` remaps. Do not fix a bad bind with scene or prefab `MaterialOverride`.
- For strict multi-material assets, set `vmdl_material_source_suffix`, `vmdl_use_global_default`, and `strict_vmdl_material_sources` deliberately, then verify the generated `.vmdl` and the exported FBX material slots.
- Clear `MaterialOverride` and `Materials.indexed` on scene and prefab `ModelRenderer` components for protected multi-material models.
- Treat S&Box console texture errors during recompile as provisional until the compiled `.vmat_c`, `.vtex_c`, and `.vmdl_c` files are checked after the compile settles.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/material_texture_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/modeldoc_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/fbx_material_slot_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
```

## Output Shape

Report the material source type, bake target textures, config/VMDL binding state, prefab/scene override state, and any runtime log caveats separately. A Blender preview alone is not evidence that S&Box is using the intended material.
