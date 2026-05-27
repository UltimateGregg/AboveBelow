# Prefab Visual Quality Agent

## Purpose

Keep S&Box-native primitive prefabs from stopping at a valid-but-underbaked blockout. Use this for editor-native props built from dev primitives, especially cover props, wreckage, debris, and placeable environment prefabs.

## Review Rules

- Start in the live editor when possible: check `control_plane_status`, inspect the active scene or prefab, and capture `editor_take_screenshot` proof after the visual pass.
- Judge the object from player height and drone height. A prop should have a readable silhouette from both views before it is treated as done.
- Break up large dev boxes with thinner panels, offsets, rotations, small trim pieces, damage seams, and material/tint variation.
- Avoid floating slabs, oversized simple blocks, one-color massing, and pure-black shapes unless they are small rubber or shadow details.
- Keep collision intentional: major frame/body/wheel pieces get static non-trigger colliders; glass, scratches, small shards, dirt, scrape marks, and micro debris stay visual-only.
- Preserve public prefab paths and names unless the user explicitly asks for a rename.

## Evidence Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_visual_quality_audit.ps1 -ShowInfo
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite prefab -ShowInfo
```

For editor proof, use the native MCP tools:

```json
{ "name": "control_plane_status", "arguments": {} }
{ "name": "editor_take_screenshot", "arguments": { "width": 1920, "height": 1080, "path": "screenshots/prefab_visual_proof.png" } }
```

## Output Shape

Lead with visual blockers first: silhouette, panel thickness, material massing, collision/detail split, and missing proof. Then list objective audit output and the screenshot path used for review.
