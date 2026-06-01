# S&Box Engine LLM Reference

Verified against official sources on 2026-05-20:

- https://sbox.game/dev/doc
- https://sbox.game/dev/doc/scene/components/component-methods
- https://sbox.game/dev/doc/networking/networked-objects
- https://sbox.game/dev/doc/networking/sync-properties
- https://sbox.game/dev/doc/networking/rpc-messages
- https://sbox.game/dev/doc/editor/model-editor
- https://github.com/Facepunch/sbox-public

Official editor docs reviewed on 2026-05-25:

- https://sbox.game/dev/doc/editor/
- https://sbox.game/dev/doc/editor/editor-project
- https://sbox.game/dev/doc/editor/editor-tools
- https://sbox.game/dev/doc/editor/editor-tools/component-editor-tools
- https://sbox.game/dev/doc/editor/editor-events
- https://sbox.game/dev/doc/editor/editor-widgets
- https://sbox.game/dev/doc/editor/custom-editors
- https://sbox.game/dev/doc/editor/asset-previews
- https://sbox.game/dev/doc/editor/property-attributes
- https://sbox.game/dev/doc/editor/texture-generators
- https://sbox.game/dev/doc/editor/undo-system
- https://sbox.game/dev/doc/editor/mapping/
- https://sbox.game/dev/doc/editor/mapping/shortcuts

Official docs source repo reviewed on 2026-05-27:

- https://github.com/Facepunch/sbox-docs
- commit `9ce559cf0b18b687db02ade27cc35b65a56b3049`
- `docfx.json` builds `docs/**/*.md` and `docs/**/toc.yml` into the published docs site
- top-level docs sections include actiongraph, animation, assets, code, editor, exporting, gameplay, networking, physics, rendering, scene, sound, and ui

Official S&Box release notes reviewed on 2026-05-28:

- https://sbox.game/release-notes
- https://sbox.game/news/update-26-05-20
- https://sbox.game/api/changes
- latest reviewed release block: `26.05.27` (27 May 2026)
- recent API-change highlights include `Mesh.AddMorph`, `MorphDelta`, `Editor.CreateModelFromMeshDialog`, `ResourceWriter.AddExternalReference`, and service organization/package-type helpers

Official S&Box Code Search reviewed on 2026-05-30:

- https://sbox.game/codesearch
- Code Search describes itself as: "Search the source of every published package."
- The page exposes package type, code type, and year filters for narrowing package examples.
- Use `.agents/sbox/sbox-code-search-agent.md` before turning public package examples into durable project guidance.
- Protect this routing with `scripts/agents/sbox_code_search_audit.ps1` or `scripts/agents/run_agent_checks.ps1 -Suite code-search`.

Valve Developer Community Source 2 docs reviewed on 2026-05-27:

- https://developer.valvesoftware.com/wiki/Category:Source_2
- https://developer.valvesoftware.com/wiki/List_of_Source_2_asset_types
- https://developer.valvesoftware.com/wiki/Resourcecompiler
- https://developer.valvesoftware.com/wiki/ModelDoc_Editor
- https://developer.valvesoftware.com/wiki/Source_2_Model_Editor
- https://developer.valvesoftware.com/wiki/Source_2_Model_Editor/Docs/Model_Menu
- https://developer.valvesoftware.com/wiki/VMDL/MaterialGroups
- https://developer.valvesoftware.com/wiki/Material_Editor_%28Source_2%29
- https://developer.valvesoftware.com/wiki/Source_2/Docs/Level_Design/Lighting
- https://developer.valvesoftware.com/wiki/Counter-Strike_2_Workshop_Tools/Level_Design/Lighting
- https://developer.valvesoftware.com/wiki/Counter-Strike_2_Workshop_Tools/Postprocessing
- https://developer.valvesoftware.com/wiki/Env_light_probe_volume
- https://developer.valvesoftware.com/wiki/Nav_Mesh_Editing
- https://developer.valvesoftware.com/wiki/Nav_mesh

Adjacent Source 2 references reviewed during the same pass:

- https://developer.valvesoftware.com/wiki/Asset_System
- https://developer.valvesoftware.com/wiki/VMAT
- https://developer.valvesoftware.com/wiki/Postprocessing_Editor
- https://developer.valvesoftware.com/wiki/Env_combined_light_probe_volume
- https://developer.valvesoftware.com/wiki/Half-Life%3A_Alyx_Workshop_Tools/Modeling/Simple_Static_Prop
- https://developer.valvesoftware.com/wiki/Half-Life%3A_Alyx_Workshop_Tools/Modeling/Physics_Prop

Official Facepunch Learn tutorial reviewed on 2026-05-23:

- https://sbox.game/learn/facepunch/creating-an-entity-for-sandbox

Secondary community tutorial context reviewed on 2026-05-23:

- https://sbox.game/learn
- https://sbox.game/learn/tesa/ui-buildhash
- https://sbox.game/learn/shadb/jiggle-101
- https://sbox.game/learn/gibbard/networked-variable-ui
- https://sbox.game/learn/brax/ide-setup
- https://sbox.game/learn/frxxks/beginner-resources
- https://sbox.game/learn/aqua/node-editor-01
- https://github.com/internetfishy/Node-Editor-Calculator

Use `.agents/sbox/sbox-docs-source-agent.md` before broad official docs source sweeps or when `Facepunch/sbox-docs` is provided as training input. Refresh `.tmpbuild/sbox-docs` with `scripts/agents/sbox_docs_source_audit.ps1 -Refresh -ShowInfo`, use `.tmpbuild/sbox-docs-source-index.md`, the source `toc.yml` files, and `rg` for inventory, and record the reviewed commit/date before promoting durable lessons. Use `.agents/sbox/sbox-learn-intake-agent.md` before turning Learn tutorials or broad official editor-doc sweeps into standing project guidance. Use `.agents/sbox/ui-razor-reactivity-agent.md` for tutorials or bugs about Razor refresh behavior.
Use `.agents/sbox/sbox-release-notes-agent.md` before turning official S&Box patch notes, release notes, or API-change entries into standing project guidance. Prefer `https://sbox.game/release-notes` for dated release summaries and `https://sbox.game/api/changes` plus local `API.json` lookup for exact C# symbol shape.
Use `.agents/sbox/sbox-code-search-agent.md` before relying on `https://sbox.game/codesearch` examples. Treat public package source as pattern discovery, compare multiple recent packages, and verify exact symbols through local `API.json`, official API pages, docs source, or local project code before implementation.

This is a working reference for agents editing this repo. It is intentionally short. If a task depends on exact API shape, check the current docs, API reference, public source, the local API dump, or local project patterns before changing code.

## Local API Dump

The project root can contain the official S&Box API dump as `API.json` or `api.json`. Agents should treat it as the fastest local source for exact type, method, property, attribute, and summary checks before using an unfamiliar S&Box symbol.

Use the lookup helper instead of manually scanning the minified JSON:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Type Sandbox.GameObject -Member NetworkSpawn
powershell -ExecutionPolicy Bypass -File scripts/agents/sbox_api_lookup.ps1 -Root . -Query SyncAttribute -ShowMembers
```

The API dump is a local reflection/reference surface, not a replacement for runtime proof. Still compile, check logs, and use editor or multiplayer verification when behavior changes.

## Release Notes Intake

As of the 2026-05-28 review, recent official S&Box release notes affect these recurring project workflows:

- Use `HasTag()` on trace results instead of relying on obsolete trace-result `.Tags` access when checking trace tags in hot paths.
- Platform chat is now a default opt-in/out project feature for existing projects; gameplay-specific chat or command handling should start from the platform chat surface and `IChatEvent` instead of a fully custom chat stack.
- Custom UI panel drawing is available through `IPanelDraw` and `Draw(CommandList)`, but Razor HUD/menu reactivity still uses `BuildHash()` coverage rather than per-frame refresh.
- Voice transmission must route through the Voice Mixer or a child mixer so player voice-volume settings keep working.
- Terrain code should use `TerrainStorage.SetResolution()`; `TerrainStorage.Resolution` is not a public setter workflow.
- `Scene.Trace.Cone` is available for cone queries, and `Rigidbody.SleepThreshold` can tune stacked physics-object sleep behavior.
- Runtime mesh morph work should start by verifying `Mesh.AddMorph` and `MorphDelta` against the current API/reference dump before implementation.
- Mesh-to-model conversion now exposes `Editor.CreateModelFromMeshDialog` collision options; editor tooling should prefer that flow before custom mesh-conversion UI.
- `ResourceWriter.AddExternalReference` can preserve external resource links in generated resources when the exact API shape is verified.
- VMDL writer now also saves the PHYS block when exporting models, so ModelDoc/model export regressions should check generated physics blocks before assuming missing collision is only a prefab issue.
- Recent performance notes reinforce allocation discipline in trace/physics hot paths and the preference for engine batching surfaces such as clutter LOD and instanced clutter collision when authoring dense environment content.

Release notes are not implementation proof by themselves. For each adopted API, query `scripts/agents/sbox_api_lookup.ps1`, compile the relevant project, and verify through the editor when editor, asset, or runtime behavior changes.

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

## Editor Tooling And Inspector Workflows

Editor extensions belong in an editor project or editor-only library. The official editor docs call out that editor projects can access tools and game code and are not sandboxed, so treat generated or third-party editor code as privileged code.

Use current editor extension surfaces instead of ad hoc runtime UI:

- `[EditorApp]` for standalone editor windows.
- `EditorTool` or `EditorTool<TComponent>` for scene-view tools and selected-component tools.
- `Widget`, `Dock`, and `IAssetEditor` for editor UI, not in-game panels.
- `[CustomEditor]`, `[Inspector]`, and `[CanEdit]` for custom inspector/control widgets.
- `AssetPreview` for custom asset thumbnails/previews.
- `TextureGenerator` for editor-generated textures.
- `[Shortcut]` for static or widget-scoped editor shortcuts.

For scene-mutating editor tools, wrap edits in `Scene.Editor?.UndoScope(...)` or `SceneEditorSession.Active.UndoScope(...)`, capture the smallest practical set of GameObject or Component changes, and dispose long-running drag scopes when the interaction ends. Use `AddOverlay(...)` or equivalent cleanup for scene overlay UI so editor widgets do not persist after the tool is disabled.

Prefer `EditorEvent` interfaces for durable editor-event integration. Named string events still exist, but interfaces are easier to discover and refactor. If a non-widget listener is used, explicitly register it with `EditorEvent.Register(...)`.

Use property attributes to make inspector-facing components self-validating and easier to wire: `[RequireComponent]`, `[Range]`, `[Step]`, `[ShowIf]`, `[HideIf]`, `[Validate]`, `[Advanced]`, and asset/input path attributes should be preferred over hidden setup assumptions when the property is meant for repeated authoring.

## Sandbox Entity Resources

For spawn-menu Sandbox entities, treat `.sent` files as `ScriptedEntity` resources that point at prefabs. The prefab still owns the actual GameObjects and Components. Do not try to code against `ScriptedEntity` as a normal gameplay component unless a current API lookup confirms a C# symbol for the exact need.

Entity behavior should stay component-first:

- Put behavior in a `Component` subclass.
- Expose authoring knobs with `[Property]` and range attributes when useful.
- Use `TimeSince` for lightweight elapsed-time timers; assign `0f` to reset.
- For physics impulses or owner-authoritative movement in `OnFixedUpdate`, guard proxy execution first, then get and validate `Rigidbody` before applying force.
- If the entity is meant to be configurable from Sandbox mode's context menu, put `[ClientEditable]` on the intended properties and keep host-authority rules in mind for gameplay state.

Spawn-menu resource setup is an editor/resource workflow: create or update the prefab, create a Sandbox Entity `.sent`, assign the prefab, set title/description/category, and enable IncludeCode when the entity depends on custom C# behavior.

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

Valve's Source 2 asset-system docs are useful mental-model support: source/content files such as `.vmdl`, `.vmat`, `.vmap`, `.vpcf`, and `.vtex` reference raw inputs and compile into game-side `_c` outputs such as `.vmdl_c` and `.vmat_c`. For this repo, treat the editable source asset and its raw inputs as the durable state. Do not fix missing resources by editing compiled `_c` files or committing cache output; repair the source asset, regenerate or recompile, and inspect compiler/editor logs.

`resourcecompiler` is the underlying Source 2 compiler for many source resources and map builds. It can force or shallow-force compiles and it participates in map lighting/VIS/VPK output in Valve workshop tools. In S&Box, prefer the editor/asset-pipeline path first, but use resource-compiler facts to interpret errors: a stale compiled cache, a missing raw input, or a bad source reference should lead back to `.vmdl`, `.vmat`, `.tmat`, FBX, texture, or sound source validation.

ModelDoc pages reinforce a few project rules:

- A ModelDoc document is an outliner of nodes and needs an explicit compile before the compiled preview/game resource reflects the source.
- The legacy Model Editor `Model` menu maps the main asset concerns: mesh, LOD groups, physics meshes, attachments, hitboxes, material groups, and material remaps. Use that as a review checklist for VMDL changes even when S&Box exposes the work through newer ModelDoc UI.
- `RenderMeshFile` references the external FBX/DMX/OBJ source; deleting, renaming, or moving that source breaks the model.
- Static props may use physics mesh nodes, but dynamic props should use hulls or simple physics shapes; complex render mesh collision is a performance and stability risk.
- External attachment and hitbox-list support exists in Source 2 Model Editor docs, but this repo should prefer local prefab/component wiring unless a shared skeleton/model asset intentionally owns that data.
- Material groups are model skins. The first group must match the model's default material list, and every additional group must keep the same material count. Use this only for deliberate skin/variant behavior, not as a workaround for wrong FBX material slots.
- The Source 2 Material Editor and VMAT docs explain material authoring and source-to-compiled `.vmat_c` output. Material Editor can force-compile to disk, shader features gate variable availability, the preview is unavailable until compilation succeeds, and the log commonly points at bad or missing texture paths. Exact S&Box material fields still need S&Box docs, local assets, or editor proof.

Use the existing checks:

- `scripts/agents/modeldoc_audit.ps1`
- `scripts/agents/fbx_material_slot_audit.ps1`
- `scripts/agents/asset_pipeline_audit.ps1`
- `scripts/agents/run_agent_checks.ps1 -Suite asset-production`

For Blender work, verify local config, exported FBX material slots, generated VMDL remaps, prefab renderer state, and a visual editor result before accepting a texture or model fix.

For cosmetic jigglebone work, treat the S&Box Learn jigglebone tutorial as secondary practical context: start from a skinned cosmetic bound to the citizen or human skeleton plus extra jiggle bones, bone-merge it to a body in a simple test scene, author primitive ModelDoc `PhysicsShape` nodes and joints, place joint anchors at the intended pivots, and prove the result in editor play with body motion. This is local bone simulation proof, not world collision proof.

## Lighting, Postprocessing, And Navigation Research

Valve Source 2 lighting docs describe a Hammer-centered pipeline built from lightmap textures, light probe volumes, cubemaps, light sources, and sometimes volumetric fog. The most useful project lesson is proof discipline: preview lighting is not final lighting, dynamic objects need appropriate probe/reflection coverage, and accessible gameplay spaces should be checked for missing probe coverage or sudden ambient-light jumps. CS2-specific entity names, RTX requirements, and tonemapping presets are game/tool context, not S&Box implementation defaults.

Light probe volume docs are still a good QA checklist when a S&Box scene looks wrong: check whether dynamic objects have believable ambient light, whether reflective materials are using the intended local environment, whether overlapping volumes have an explicit priority, and whether bounds cover the playable volume. Verify the current S&Box editor component/entity surface before adding any probe, cubemap, or light entity by name.

Source 2 postprocessing docs describe `.vpost` stacks where tonemapping+bloom and color correction are applied as separate runtime phases. If S&Box postprocessing work appears, verify the current S&Box asset/API shape first, then treat layer order and duplicated tonemapping/bloom layers as things to inspect in the editor rather than copying CS2 workshop settings blindly.

CS2 postprocessing docs add a useful level-design checklist: postprocessing can cover tone mapping/camera exposure, color correction, bloom, screen blur, and LUTs; Hammer uses post-processing volumes including a master volume, nested volumes for transitions, shared `.vpost` resources for consistency, and exposure ranges/speeds that can cause brightness fluctuation. For S&Box, translate this into editor proof: check exposure stability across indoor/outdoor transitions and verify the current S&Box postprocess volume/resource surface before wiring anything by name.

Valve `Nav Mesh` and `Nav_Mesh_Editing` pages are mostly legacy Source/Counter-Strike `.nav` workflows: console commands such as `nav_generate`, `nav_edit`, `nav_save`, manual area splitting, and place-name painting. For this repo, they are not active S&Box navigation implementation guidance. S&Box uses Recast navigation exposed through the scene NavMesh, generated from the PhysicsWorld, with `Scene.NavMesh`, agents, areas, costs/filters, obstacles, and links in the S&Box docs. Use Valve nav pages only as conceptual QA background for walkability, orphaned regions, one-way links, and manual review discipline.

## UI And Sound

UI uses S&Box panels and Razor panels, not web DOM or Panorama. Follow the local `HudPanel` and menu patterns, keep stylesheet aliases where this repo needs them, and run the UI flow audit after interaction changes.

For dynamic Razor UI, treat `BuildHash()` as the normal refresh contract. Include every value that affects rendered markup, especially `[Sync]` values surfaced in HUDs, scoreboards, timers, health, team labels, objective progress, and menu status. Do not solve stale UI by calling `StateHasChanged()` from `Tick()` unless a task has a very specific measured reason.

Sound should use local `.sound` wrappers for gameplay-facing references. Search existing stock/editor audio before synthesizing fallback WAVs, but import or wrap sources under `Assets/sounds` before wiring them into C#, prefabs, or scenes.

## Editor Node Tools

Reviewed against S&Box Learn tutorial context on 2026-05-23: custom node-editor tooling is editor-only scaffolding, not runtime gameplay UI. Keep it under `Editor/` or a library `Editor/` folder, then compile the relevant editor project and open the tool in the visible editor.

The useful mental model is a set of separate pieces: an `[EditorApp]` widget, a `GraphView`, an optional properties/inspector widget, an `IGraph` data container, `INode` implementations, `INodeType` factories, and `IPlug`/`IPlugIn`/`IPlugOut` plug models. The tutorial relies on `DisplayInfo` and attributes such as `[Title]`, `[Icon]`, `[Description]`, `[Hide]`, and `[ReadOnly]` to populate menus, node labels, plug labels, and property sheets.

Do not copy tutorial scaffolding blindly. Node callbacks can be invoked by hover, paint, menus, selection, and connection actions, so replace `throw new NotImplementedException()` placeholders with safe no-op or null-returning defaults before handoff. Initialize input/output plug collections before `NodeUI` renders, show connections explicitly when plugs should draw links, and add type-compatibility checks for real plug connections because the tutorial's calculator example leaves that as follow-up work.

Local `API.json` may not include every editor Node Editor type. If exact editor-node signatures matter, verify against official API pages, the visible editor assemblies, the tutorial source snapshots, or an existing editor-tool pattern before changing code. Run `scripts/agents/editor_node_tool_audit.ps1 -Root . -ShowInfo` for static placement and placeholder checks.

## Avoid Source 1 Habits

Do not use these as active S&Box implementation guidance:

- Do not use `.qc` model scripts for this project.
- Source 1 entity spawning patterns such as `Entity:Spawn`.
- Hammer entity I/O as the default gameplay logic path.
- Do not hand-author `.vmdl` text as the first fix for model problems.
- Stale `[Net]` examples where current S&Box docs use `[Sync]`.

When a Source 2 or S&Box claim is volatile, write it with a source and date marker. Examples include engine release status, .NET target, public-source licensing, Blender exporter release numbers, and API names.
