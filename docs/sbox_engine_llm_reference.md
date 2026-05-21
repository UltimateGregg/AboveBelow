# S&Box Engine LLM Reference

Verified against official sources on 2026-05-20:

- https://sbox.game/dev/doc
- https://sbox.game/dev/doc/scene/components/component-methods
- https://sbox.game/dev/doc/networking/networked-objects
- https://sbox.game/dev/doc/networking/sync-properties
- https://sbox.game/dev/doc/networking/rpc-messages
- https://sbox.game/dev/doc/editor/model-editor
- https://github.com/Facepunch/sbox-public

This is a working reference for agents editing this repo. It is intentionally short. If a task depends on exact API shape, check the current docs, API reference, public source, the local API dump, or local project patterns before changing code.

## Local API Dump

The project root can contain the official S&Box API dump as `API.json` or `api.json`. Agents should treat it as the fastest local source for exact type, method, property, attribute, and summary checks before using an unfamiliar S&Box symbol.

Use the lookup helper instead of manually scanning the minified JSON:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Type Sandbox.GameObject -Member NetworkSpawn
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Query SyncAttribute -ShowMembers
```

The API dump is a local reflection/reference surface, not a replacement for runtime proof. Still compile, check logs, and use editor or multiplayer verification when behavior changes.

## Mental Model

S&Box game code is C# on Source 2 technology. The current public engine repository describes S&Box as Source 2 plus the latest .NET technology and lists the .NET 10 SDK as a source-build prerequisite. The official docs describe game and addon authoring as C# with hotloading, and the scene system as similar to Godot and Unity.

For this project, the default unit of gameplay work is:

- a `Sandbox.Component` subclass,
- inspector tunables exposed with `[Property]`,
- runtime state synchronized with `[Sync]` where it must replicate,
- validated requests or notifications sent through RPCs,
- prefab and scene wiring kept explicit and audit-backed.

Do not start from Source 1 or Hammer entity/I/O assumptions for new gameplay. New behavior should live in C# components on GameObjects unless the user explicitly asks for a different authoring surface.

## Components And Scenes

Use the Scene -> GameObject -> Component model. Components own lifecycle work through methods such as `OnValidate`, `OnAwake`, `OnStart`, `OnEnabled`, `OnUpdate`, and `OnFixedUpdate`. Prefer existing project patterns before inventing new base classes or systems.

Keep broad changes phased:

- gameplay logic in `Code/Game`, `Code/Player`, `Code/Drone`, or `Code/Equipment`,
- UI in `Code/UI` and related stylesheets,
- prefab wiring in `Assets/prefabs` and `Code/code/Wiring/AutoWire.cs`,
- scene authoring in `Assets/scenes/main.scene`,
- editor tooling under `Libraries/`, `Editor/`, `mcp/`, or `scripts/agents`.

## Networking

`NetworkSpawn()` makes a GameObject networked so it can use synchronized properties and RPCs. The object owner controls updates for owned state by default. In this repo, security-sensitive gameplay still needs host-authoritative validation.

Use current S&Box networking terms:

- `[Sync]` for replicated component properties.
- `[Rpc.Host]` for client intent that the host must validate.
- `[Rpc.Broadcast]` for visual/audio notifications after host-side resolution.
- `IsProxy` checks at the top of owner-only input or movement code.

Avoid stale `[Net]` guidance. If older examples use `[Net]`, verify against current docs and translate the pattern to `[Sync]` before using it here.

## Assets And ModelDoc

S&Box model authoring uses ModelDoc / Model Editor for `.vmdl` files. Official docs call it the modern equivalent of Source 1 `.QC`, but it is node-based rather than text-command based. In this repo, durable model fixes should go through the asset pipeline, generated source files, and audits instead of blind manual VMDL edits.

Use the existing checks:

- `scripts/agents/modeldoc_audit.ps1`
- `scripts/agents/fbx_material_slot_audit.ps1`
- `scripts/agents/asset_pipeline_audit.ps1`
- `scripts/agents/run_agent_checks.ps1 -Suite asset-production`

For Blender work, verify local config, exported FBX material slots, generated VMDL remaps, prefab renderer state, and a visual editor result before accepting a texture or model fix.

## UI And Sound

UI uses S&Box panels and Razor panels, not web DOM or Panorama. Follow the local `HudPanel` and menu patterns, keep stylesheet aliases where this repo needs them, and run the UI flow audit after interaction changes.

Sound should use local `.sound` wrappers for gameplay-facing references. Search existing stock/editor audio before synthesizing fallback WAVs, but import or wrap sources under `Assets/sounds` before wiring them into C#, prefabs, or scenes.

## Avoid Source 1 Habits

Do not use these as active S&Box implementation guidance:

- Do not use `.qc` model scripts for this project.
- Source 1 entity spawning patterns such as `Entity:Spawn`.
- Hammer entity I/O as the default gameplay logic path.
- Do not hand-author `.vmdl` text as the first fix for model problems.
- Stale `[Net]` examples where current S&Box docs use `[Sync]`.

When a Source 2 or S&Box claim is volatile, write it with a source and date marker. Examples include engine release status, .NET target, public-source licensing, Blender exporter release numbers, and API names.
