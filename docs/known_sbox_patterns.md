# Known S&Box Patterns & Gotchas

This document covers S&Box-specific patterns, quirks, and solutions used in this project.

## Networking Quirks

### [Sync] Replication Timing

**Issue:** [Sync] properties don't replicate instantly; they're queued for next network tick.

**Pattern:** Expect 1-2 frame delay (at 30 Hz network, ~33-66ms) between host mutation and client update.

**Solution:**
- Never assume client has latest state immediately
- Use RPC for urgent notifications (OnKilled events)
- Use [Sync] for state that can tolerate slight delay (health, position)

### Broadcast RPC on Non-Host

**Issue:** [Rpc.Broadcast] methods execute on all peers, but host logic may run twice.

**Pattern:** If host calls a [Rpc.Broadcast] method, it fires both locally AND broadcasts to clients.

**Solution:**
- Do actual logic on host (before RPC call)
- Use RPC only for callbacks/notifications
- Guard with if (!Networking.IsHost) return; inside RPC if needed

Example:
`csharp
// Host-side
if (!Networking.IsHost) return;
Health.TakeDamage(damageInfo);  // Host applies damage
BroadcastKilled(attackerId);     // Notify all peers
`

### Host RPC for Hitscan Fire Requests

**Pattern:** Player fire input should send weapon intent to the host, not resolved hit data.

**Workflow:**
- Use a `[Rpc.Host]` request for `HitscanWeapon.RequestFire`.
- Pass only bounded intent data such as the requested muzzle/eye origin and aim direction.
- On the host, validate the origin against the server-known player eye, enforce cooldown/ammo/selection, run `Scene.Trace`, and apply damage.
- Broadcast only visual/audio results such as tracers, muzzle flash, bullet path, and impact effects.
- Run `scripts/agents/networking_review_audit.ps1` after weapon authority changes; it fails if `HitscanWeapon.RequestFire` drifts back to `[Rpc.Broadcast]` or accepts resolved hit objects.

### Network Ownership Changes

**Issue:** When Network.Owner is null, the object may not sync properly.

**Pattern:** Always set Network.Owner immediately after spawning.

**Solution:**
`csharp
var pawn = prefab.Clone(spawn);
pawn.NetworkSpawn(connection);  // Sets Network.Owner = connection
// Now [Sync] works correctly
`

## Component Lifecycle Quirks

### Component-First Engine Research Intake

**Pattern:** Current S&Box guidance should be reduced to this project's component-first workflow before it becomes standing agent advice.

**Workflow:**
- Verify volatile engine claims against official S&Box docs, the public engine source, local `API.json`, or current local project patterns before updating docs.
- For gameplay, prefer `Sandbox.Component` subclasses with `[Property]` tunables, `[Sync]` replicated state, and RPCs for validated requests or notifications.
- Treat older Source 1 or legacy S&Box examples as migration context, not implementation authority. In particular, do not revive `[Net]`, `.qc` model scripts, entity/I/O gameplay, or manual `.vmdl` text editing as active defaults.
- Capture useful research in `docs/sbox_engine_llm_reference.md`; use `scripts/agents/sbox_api_lookup.ps1` for exact local API symbols and run `scripts/agents/run_agent_checks.ps1 -Suite docs` after docs or agent-routing changes.

### Official S&Box Docs Source Intake

**Pattern:** `Facepunch/sbox-docs` is the official markdown source for `sbox.game/dev/doc`, and it is usually a better inventory surface than scraping rendered pages.

**Workflow:**
- Use `.agents/sbox/sbox-docs-source-agent.md` when a task asks to train on the official docs repo or when broad docs coverage matters.
- Refresh the source snapshot under `.tmpbuild/sbox-docs` with `scripts\agents\sbox_docs_source_audit.ps1 -Refresh -ShowInfo`.
- Use `.tmpbuild/sbox-docs-source-index.md`, `toc.yml` files, and `rg` over the snapshot to locate relevant pages; do not vendor the full docs tree into this repo.
- Record the reviewed commit/date in `docs/sbox_engine_llm_reference.md` before turning a docs sweep into standing guidance.
- Verify exact C# symbols through local `API.json` or existing code before implementation.

### Official S&Box Public Source Intake

**Pattern:** `Facepunch/sbox-public` is useful engine source context, but a latest source checkout is not automatically the active engine used by this game's C# and MCP projects.

**Workflow:**
- Use `.agents/sbox/sbox-public-source-agent.md` when a task asks to install, refresh, or train from `https://github.com/Facepunch/sbox-public`.
- Keep the project-local clone at `tools/sbox-public`, verify upstream `master`, and run `cmd /c Bootstrap.bat` there after updates so managed assemblies and `sbox-dev.exe` exist.
- Do not reset or overwrite dirty sibling engine checkouts such as `C:\Programming\sbox-public`; this repo's current project and MCP project references still compile against that sibling path.
- Do not reroute project references to `tools/sbox-public` unless a separate scoped migration proves the latest public distribution exposes compatible editor project references or intentionally converts those references to verified DLL references.
- After source updates, prove MCP health with `.mcp.json`, the native `control_plane_status` or `tools/list` MCP call when the editor is running, and `dotnet build Libraries\jtc.mcp-server\Editor\mcp-server.editor.csproj --no-restore`.
- Run `scripts\agents\sbox_public_source_audit.ps1 -Root . -RequireLatest -ShowInfo` or `scripts\agents\run_agent_checks.ps1 -Suite sbox-public -ShowInfo` before claiming the public-source snapshot is current and MCP-safe.

### Official S&Box Release Notes Intake

**Pattern:** Official release notes are the best way to spot new engine features, but they are dated change logs, not direct implementation proof.

**Workflow:**
- Use `.agents/sbox/sbox-release-notes-agent.md` when a task asks for S&Box patch notes, release notes, update posts, or API changes.
- Review `https://sbox.game/release-notes`, relevant `https://sbox.game/news/...` update posts, and `https://sbox.game/api/changes`; record the review date and source update date before changing standing guidance.
- Promote recurring lessons into `docs/sbox_engine_llm_reference.md`, agents, hooks, or focused audits. Do not copy every note into docs.
- Verify exact C# symbols through `scripts\agents\sbox_api_lookup.ps1`, official API pages, or existing code before editing gameplay, UI, asset, or editor code.
- If a fresh release note names a symbol that local `API.json` does not expose yet, keep it as volatile guidance and do not implement against it until the local dump, official API page, or editor/build proof confirms the signature.
- The 26.06.17 notes added recurring workflow guidance for this project: mounted games/maps are now platform-visible and multiplayer-sensitive; the refreshed local API exposes `PhysicsBody.ComputePenetration` and `Collider.ComputePenetration` as candidate depenetration/collision-authoring tools; terrain traces and terrain enable/disable behavior need editor proof after terrain changes; publish/package work should check Cloud Asset license warnings; and asset QA should use model/texture preview selectors for LOD, material group, and mip inspection.
- The 26.06.10 notes added recurring workflow guidance for this project: account for precompiled DLLs loading from manifests, mounted scenes/maps, the restored Twitch/Streamer API, new or reworked terrain rendering/sampling/collision behavior, `TargetMixer` on DSP volumes, per-object render callbacks, and new editor/inspector quality-of-life APIs such as `[Uniform]`, light contribution settings, `TextureGenerator.FormatOverride`, and `AssetType` icon colors.
- The 26.06.03 notes added recurring guidance for this project: keep `Connection.Name` for networking/internal identity and `Connection.DisplayName` for UI text; account for physical sound simulation during audio proof; use newly supported S&Box UI CSS features where they replace layout hacks; and treat `Mesh.AddSubMesh` as pending until exact API shape is verified locally.
- Run `scripts\agents\sbox_release_notes_audit.ps1 -Root . -ShowInfo` or `scripts\agents\run_agent_checks.ps1 -Suite release-notes -ShowInfo` after changing release-note-derived guidance.

### S&Box Code Search Intake

**Pattern:** `https://sbox.game/codesearch` searches the source of published packages and is useful for finding real package usage patterns, but package code is example material rather than authoritative project guidance.

**Workflow:**
- Use `.agents/sbox/sbox-code-search-agent.md` when a task needs practical examples for an S&Box type, method, editor surface, UI pattern, sound workflow, physics call, or test setup.
- Filter by package type, code type, and year when the distinction matters; prefer recent game code for runtime behavior and editor code for tooling.
- Compare multiple packages before adopting a pattern. Do not vendor package source into this repo.
- Verify exact C# symbols through local `API.json`, official API pages, docs source, or existing project code before implementation.
- Run `scripts\agents\sbox_code_search_audit.ps1 -Root . -ShowInfo` or `scripts\agents\run_agent_checks.ps1 -Suite code-search -ShowInfo` after changing Code Search-derived guidance.

### S&Box Learn Tutorial Intake

**Pattern:** S&Box Learn pages are useful day-to-day context, but most are community-written tutorials. Convert them into project behavior only through a small researched workflow.

**Workflow:**
- Use `.agents/sbox/sbox-learn-intake-agent.md` to decide whether a tutorial lesson should become docs, an audit, a hook, or a routing card.
- Use `.agents/sbox/ui-razor-reactivity-agent.md` for Learn lessons about Razor refresh, `[Sync]` values in UI, or `BuildHash()`.
- Keep source URLs and review dates in `docs/sbox_engine_llm_reference.md`.
- Run `scripts\agents\run_agent_checks.ps1 -Suite learn -ShowInfo` after changing Learn-derived guidance.

### Valve Source 2 Asset Pipeline Intake

**Pattern:** Valve Developer Community Source 2 docs are useful for asset-system mental models, but they must be translated into this project's S&Box asset pipeline before becoming standing guidance.

**Workflow:**
- Treat source/content files such as `.vmdl`, `.vmat`, `.vmap`, `.vpcf`, and `.vtex` as editable source resources, and compiled `_c` files such as `.vmdl_c` or `.vmat_c` as generated output.
- Fix missing models, grey materials, and bad texture output by repairing the raw source file, asset config, VMDL/VMAT/TMAT source, or material remap. Do not edit or commit compiled cache files as the durable fix.
- For ModelDoc material groups, keep the first group aligned with the default material list and require every alternate group to have the same material count. Use material groups for deliberate skin/variant behavior, not to hide mismatched FBX slots.
- For collision on model assets, prefer authored simple physics meshes, hulls, or primitive shapes. Static render-mesh collision is acceptable only when the shape and performance cost are intentionally verified; dynamic props need hulls or simple shapes.
- After Source 2 asset-pipeline research changes, update `docs/sbox_engine_llm_reference.md` with source/date context and run `scripts\agents\run_agent_checks.ps1 -Suite docs -ShowInfo`.

### Valve Nav Mesh Docs Are Legacy For S&Box

**Pattern:** Valve `Nav Mesh` and `Nav_Mesh_Editing` pages describe Source/Counter-Strike `.nav` files and console commands. They are not the implementation path for S&Box Recast navigation.

**Workflow:**
- Do not add `nav_generate`, `nav_edit`, `.nav` file authoring, or place-name painting as active S&Box guidance unless the task explicitly targets legacy Source/CS tooling.
- For this project, use S&Box navigation docs and local API lookup: `Scene.NavMesh`, NavMesh Agent, areas, costs/filters, obstacles, links, and `Scene.NavMesh.SetDirty()` when appropriate.
- Treat Valve nav-editing lessons as QA concepts only: check walkable coverage, orphaned regions, one-way/blocked links, stairs/ramps, and ladder/path edge cases with the current S&Box editor and playtest.
- Remember that S&Box NavMesh is generated from the PhysicsWorld, so collision authoring and terrain setup are navigation prerequisites.

### Editor Node Tool Scaffolding

**Pattern:** S&Box Node Editor work is an editor-tooling surface, not runtime gameplay UI. Custom graph tools should live under `Editor/` or a library `Editor/` folder and be verified separately from gameplay components.

**Workflow:**
- Split the tool into an `[EditorApp]` widget, a `GraphView`, a properties/inspector widget if needed, an `IGraph` data container, `INode` implementations, `INodeType` factories, and `IPlug`/`IPlugIn`/`IPlugOut` plug models.
- Use `[Title]`, `[Icon]`, `[Description]`, `[Hide]`, `[ReadOnly]`, and `DisplayInfo` to drive node menus, labels, tooltips, and property sheets instead of duplicating display strings in several places.
- Initialize node `Inputs` and `Outputs` to empty or reflected plug collections before `NodeUI` renders. Null plug collections can fail before a tool does anything visible.
- Replace tutorial `NotImplementedException` placeholders with safe no-op or null-returning defaults before testing. Paint, hover, context menu, selection, and plug callbacks can run immediately.
- Add real type checks when connecting plugs; the calculator tutorial demonstrates value propagation but intentionally does not enforce type compatibility.
- Run `scripts\agents\editor_node_tool_audit.ps1 -Root . -ShowInfo`, then manually open the tool from the editor Tools tab and test node creation, selection, properties, and connections.

### Sandbox Entity .sent Resources

**Pattern:** A Sandbox Entity `.sent` is a spawn-menu resource that points to a prefab; the prefab contains the actual GameObjects, Components, model renderer, physics, and custom behavior.

**Workflow:**
- Implement the behavior as a normal `Component` subclass first.
- Put tunables on `[Property]` members; use `[ClientEditable]` only for values that Sandbox-mode players should be able to change from the context menu.
- Use `TimeSince` for simple elapsed-time timers instead of manually tracking `Time.Now` deltas.
- For physics-driven entities, run impulse and movement work from `OnFixedUpdate`, skip proxy execution before mutating physics, and validate `Rigidbody` before applying force.
- Author the prefab with the renderer, `Rigidbody`, and behavior component, then create the `.sent` resource through the Sandbox Entity asset workflow with prefab, title, description, category, and IncludeCode when custom C# is required.
- Verify unfamiliar exact symbols with `scripts/agents/sbox_api_lookup.ps1`; `ClientEditableAttribute` and `TimeSince` are C# API symbols in the local dump, while `ScriptedEntity` may be an editor/resource concept rather than a gameplay component type.

### Drone Variant Visual Identity

**Pattern:** A gameplay variant can share controller code and propeller models while still needing a separate visible body model.

**Workflow:**
- Give the variant its own `.blend`, asset-pipeline config, FBX, VMDL, and variant-specific material remaps when the silhouette or accent color should differ from the base drone.
- Wire the prefab `Visual` renderer and any held/selection preview path to the variant VMDL, not the base FPV body.
- Run `scripts\agents\drone_variant_visual_audit.ps1 -ShowInfo` with the asset-production checks before accepting the change.

### OnAwake vs OnStart

**Pattern:**
- OnAwake: Runs before scene fully initializes (all components not ready)
- OnStart: Runs after scene ready (safe to reference other components)

**Solution:**
- Initialize collections in OnAwake (they may be null after deserialization)
- Reference other components in OnStart
- Auto-wire from GameManager in OnStart

### Component Creation During Gameplay

**Issue:** Creating components during active gameplay can cause networking issues.

**Pattern:** Always create networked components during initialization, not runtime.

**Solution:** Use prefab instantiation (Clone) with NetworkSpawn, not manual Component creation.

## Scene Query Performance

### GetAllComponents<T> is Slow

**Pattern:** Scene queries allocate a new list each time.

**Solution:**
- Call once per frame, not per method
- Cache result in local variable
- Use in OnFixedUpdate (30 Hz) not OnUpdate (60 Hz)

Example:
`csharp
// GOOD
void OnFixedUpdate()
{
    var allHealth = Scene.GetAllComponents<Health>().ToList();
    foreach (var health in allHealth) { ... }
}

// BAD
void OnUpdate()
{
    for (int i = 0; i < 100; i++)
    {
        var health = Scene.GetAllComponents<Health>()[i];  // Allocates 100 times!
    }
}
`

### FindByName Caching

**Pattern:** Scene.FindByName() searches the entire scene tree.

**Solution:**
- Cache on first call
- Store in field, not local variable

Example:
`csharp
private GameRules _cachedRules;

protected override void OnStart()
{
    if (!_cachedRules.IsValid())
        _cachedRules = Scene.FindByName("GameManager")?.Components.Get<GameRules>();
}
`

## Prefab & Inspector Quirks

### [Property] Serialization

**Pattern:** [Property] fields are serialized to inspector but NOT networked.

**Solution:**
- Use [Property] for configuration (prefab references, speeds)
- Use [Sync] for runtime state changes

### Component References Can Break

**Issue:** If you delete/recreate a GameObject, component references become null.

**Pattern:** Always check IsValid() before using cached components.

**Solution:**
`csharp
if (!_cachedRules.IsValid())
{
    _cachedRules = Scene.FindByName("GameManager")?
        .Components.Get<GameRules>();
}
`

### Prefab Variant Issues

**Pattern:** Changes to parent prefab don't always cascade to variants.

**Solution:**
- Test prefabs in isolation
- Use explicit prefab references, not prefab variants
- Keep prefab structure flat (avoid deep hierarchies)

### Code-Driven Child Objects

**Pattern:** Components that scan child names need the driven objects authored in every prefab variant that enables the behavior.

**Workflow:**
- Drone propeller motion is driven by `DroneController`, which scans descendants whose names start with `Propeller`.
- GPS, FPV, and Fiber FPV drone prefabs should all include four visible propeller children in the prefab hierarchy.
- Prefer the shared corner naming pattern `Propeller_FL`, `Propeller_FR`, `Propeller_BL`, `Propeller_BR` so audits and future tooling can reason about all variants consistently.
- Run `scripts/agents/prefab_wiring_audit.ps1` after drone prefab edits; it catches missing code-driven propeller children before playtesting.

### Held Equipment Visibility

**Pattern:** Held weapons, grenades, and pilot equipment should stay enabled for input, cooldowns, and networking, but their renderers must be turned fully off when their loadout slot is not selected.

**Workflow:**
- Put slot ownership on the item component (`Slot = 1` for primary, `Slot = 2` for equipment).
- Have the item call `WeaponPose.SetVisibility()` from startup and update paths.
- Let `SoldierLoadout` run the central held-item visibility sweep every frame so startup, proxy, and slot-change ordering cannot leave an unselected item visible.
- Use `ModelRenderer.ShadowRenderType.Off` for hidden held items so stowed equipment does not cast shadows around the player.

### Pilot Ground Controls vs Drone-View Controls

**Pattern:** Pilot ground input and drone-view input share the same physical buttons, but they are different control modes. Do not move a drone-view action into `DroneDeployer` unless the desired behavior is explicitly ground-side.

**Workflow:**
- `DroneDeployer` owns ground-side slot 1: first LMB launches the selected drone; second LMB or `F` enters drone control once the drone is airborne.
- `DroneWeapon` owns drone-view combat input: FPV and Fiber FPV are kamikaze-only, so slot 1/LMB detonates only while the pilot is already in drone view.
- `RemoteController.HasLinkedDrone()` and `PilotSoldier.ResolveDrone()` should treat dead linked drones as unavailable so the deployer can start cooldown and return to the ground-side flow.
- Run `.\scripts\agents\gameplay_regression_guard.ps1` after touching `DroneWeapon`, `DroneDeployer`, `RemoteController`, `PilotSoldier`, the pilot/drone HUD loadout, or FPV drone prefabs.

## Physics & Collision Quirks

### Native Terrain Floor

**Pattern:** Use `Sandbox.Terrain` for arena floor surfaces that need heightmap/sculpt editing. A scaled dev plane plus `BoxCollider` cannot preserve terrain height edits or make collision follow sculpted ground.

**Workflow:**
- Keep `ArenaFloor` as the stable scene anchor in `Assets/scenes/main.scene`.
- The object should have exactly one `Sandbox.Terrain` component, no dev-plane `ModelRenderer`, and no broad floor `BoxCollider`.
- Link `Terrain.Storage` to `terrain/arena_floor.terrain`; initial values are `Resolution = 512`, `TerrainSize = 21600`, and `TerrainHeight = 512`.
- `Sandbox.Terrain` is corner-origin, unlike the old centered dev plane. For the 21600-unit arena floor, place `ArenaFloor` at `-10800,-10800,-8` so the terrain stays centered on the arena.
- Use `.tmat` layers such as `materials/arena/grass_ground.tmat` and `materials/arena/terrain_dirt_patch.tmat` for terrain paint materials. `terrain_dirt_patch.tmat` is intentionally grass-textured for this terrain pass so elevated areas stay grassy instead of reading as dirt. The generated control map keeps road and building samples flat/base-painted while adding grass variation overlay to open terrain.
- In `.tmat` files, texture slots must be omitted or point at real project textures. Do not leave `AlbedoImage`, `RoughnessImage`, `NormalImage`, `AOImage`, or `HeightImage` as empty strings; S&Box passes blank slots to the texture compiler and can spam resource-compile failures.
- If a hand-authored `.terrain` JSON will not load, repair it through the editor command `dvp_link_arena_terrain`; it uses `AssetSystem` and `TerrainStorage.SaveToDisk` so the resource matches the engine serializer.
- To regenerate the current procedural rolling heightmap and splat layer, run the editor command `dvp_generate_arena_terrain_variance`; it keeps protected masks around `RoadCorridor_Main` and the six house footprints.
- Run `scripts\agents\run_agent_checks.ps1 -Suite terrain -ShowInfo` after terrain, floor, or heightmap edits.

### Dev Box Collider Scale

**Issue:** The editor may show a selected blockout object with a light green collision box much larger than the visible box.

**Cause:** `BoxCollider.Scale` is local to the GameObject. S&Box applies the GameObject transform scale to both `ModelRenderer` and `BoxCollider`. For `models/dev/box.vmdl`, the visible model local bounds are 50 x 50 x 50 units. If the collider is authored as the final world size, such as `320,16,192`, S&Box scales that collider again and the collision outline becomes oversized.

**Pattern:** For scaled `models/dev/box.vmdl` objects:

- `ModelRenderer.Model`: `models/dev/box.vmdl`
- `BoxCollider.Center`: `0,0,0`
- `BoxCollider.Scale`: `50,50,50`
- The GameObject transform `Scale` controls the final visible and physical size.

**Workflow:** Run the collider sync pipeline after map or composed-prefab edits:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_box_colliders_to_renderers.ps1 -All -Apply
```

Reload the scene afterward if the editor still shows a stale selection gizmo.

### Custom Rigidbody Settings

**Pattern:** Some settings (Gravity, Damping) don't sync across network.

**Solution:**
- Set non-networked properties in OnStart
- DroneController manually disables gravity, applies hover force

Example (DroneController):
`csharp
// Must set Gravity=false in inspector or code
Body.Gravity = false;  // Custom hover physics
`

### CharacterController vs Rigidbody

**Pattern:** CharacterController (kinematic) for player movement, Rigidbody for physics objects.

**Solution:**
- Soldiers use CharacterController (predictable, responsive)
- Drone uses Rigidbody (custom velocity control)
- Don't mix both on same GameObject

### Climbable Ladder Volumes

**Pattern:** Use a non-blocking `BoxCollider` trigger with `LadderVolume` for climbable ladders, and let `GroundPlayerController` own the movement mode.

**Workflow:**
- Keep the ladder collider as `IsTrigger = true`; solid ladder boxes block the character controller before climb movement can attach.
- Place the climb volume just outside blocking deck/platform collision, then set `TopExitLocalOffset` onto a nearby solid walking surface.
- Keep nearby tank/deck collision explicit and simple; the top exit should not place the player inside adjacent blocking colliders.

### Selected Hierarchy Collider Gizmos

**Pattern:** For composed props with collision on child GameObjects, add `SelectedHierarchyColliderViewer` to the root so selecting the root or visual child draws the whole prop's collider stack.

**Workflow:**
- Put the viewer on the root that owns the collision children, not on a separate manager object.
- Use solid-color wireframes for blocking colliders and trigger-color wireframes for trigger volumes.
- Keep the visual transform at the root/prefab origin when possible; if a scene instance needs scaling or rotation, apply it to the root so visual and collision children stay aligned.

### Cosmetic Jigglebone ModelDoc Setup

**Pattern:** Cosmetic jigglebones are local ModelDoc physics for skinned, bone-merged attachments. They need a citizen or human skeleton binding, extra jiggle bones parented to that skeleton, primitive `PhysicsShape` nodes, and joints with correctly placed anchors. This is separate from world collision and cannot be proven by a static asset audit alone.

**Workflow:**
- Skin the cosmetic to the main citizen or human skeleton and to the extra jiggle bones, then test it as a bone-merged skinned model on a citizen or human.
- Add at least one solid attachment `PhysicsShape` to a stable body bone such as spine, head, or hand, then add primitive shapes to each jiggle bone. Prefer boxes, spheres, or capsules over hull collision unless the shape truly needs it.
- Pick the joint by motion: conical for hanging swing with limits, weld for configurable position and rotation stiffness, spherical for unrestricted flop controlled mostly by collision.
- Move each joint anchor to the intended pivot. If twist or swing limits are enabled, use nonzero values; zeroed limits do not clamp as expected.
- For weld joints, tune linear and angular behavior separately. Higher position frequency keeps the part attached, lower frequency feels weaker, and higher damping creates more lag with less spring.
- Playtest in the editor with an animation or body parameter moving the citizen or human. Unattached jiggle bones can fall away during play, and bad anchors show up as pivot drift or stretching.
- Route future work through `.agents\sbox\jigglebone-cosmetic-agent.md`, then run `scripts\agents\run_agent_checks.ps1 -Suite modeldoc` and `-Suite asset-production` before final editor proof.

### Animated Model Import

**Pattern:** Animated Blender/FBX/VMDL assets need editor-first playback proof before gameplay wiring. A generated VMDL proves the model document exists; it does not prove imported clips are visible to S&Box, playable in AnimGraph tooling, or connected to the owning component.

**Workflow:**
- Start with `.agents\sbox\editor-first-workflow-agent.md`, check the live editor control plane, and inspect ModelDoc or AnimGraph tooling before static file edits when the editor is available.
- Open the generated VMDL or AnimGraph surface and play each imported clip by name. Record the clip names checked in the handoff.
- Use `SkinnedModelRenderer.Sequence` with `UseAnimGraph` disabled for simple direct sequence playback.
- Use AnimGraph parameters, `Parameters.Set`, a state machine, or a 1D blendspace for locomotion and stateful character animation.
- Use `AnimGraphDirectPlayback` or `Parameters.Set` bool triggers for one-shot actions such as attack, reload, deploy, death, or hit reactions.
- For first-person animation, inspect `FirstPersonViewmodel` first; it already owns stock animation drivers, custom visual copies, `Parameters.Set`, and hand IK.
- Route future work through `.agents\sbox\animated-model-intake-agent.md`, then run `scripts\agents\animated_model_intake_audit.ps1 -ShowInfo` or `scripts\agents\run_agent_checks.ps1 -Suite animated-model -ShowInfo`.

## Event & Callback Quirks

### Memory Leaks from Event Subscriptions

**Issue:** Subscribing without unsubscribing causes memory leaks.

**Pattern:** Always unsubscribe in OnDestroy.

**Solution:**
`csharp
protected override void OnStart()
{
    health.OnKilled += HandleDeath;
}

protected override void OnDestroy()
{
    health.OnKilled -= HandleDeath;  // Unsubscribe!
}
`

### Lambda Captures

**Pattern:** Lambdas capture variables by reference, not value.

**Issue:** Variable changes after subscription affect callback behavior.

**Solution:**
- Avoid closures in event handlers
- Use explicit method delegates instead
- Or capture value in local variable first

### Broadcast RPC Timing

**Pattern:** [Rpc.Broadcast] callbacks may fire on same frame as mutation.

**Solution:**
- Don't assume order (host changes state, then RPC broadcasts)
- Use state flags to prevent double-processing
- Example: Track which deaths have been recorded to avoid duplicates

## Multiplayer Testing Gotchas

### Host Always Connected

**Issue:** Host can't properly test disconnect scenarios.

**Pattern:** Host is always "connected" and can't disconnect.

**Solution:**
- Test disconnection with actual clients
- Use separate instances for dedicated server testing
- Mirror behavior on multiple clients to verify replication

### Network Lag Doesn't Appear in Single-Player

**Pattern:** Editor playtest has no network latency.

**Solution:**
- Test multiplayer with actual network players
- Assume 50-100ms latency in design
- Use prediction/interpolation for smooth movement

### [Sync] Property Initialization

**Pattern:** [Sync] properties may be null after network deserialization.

**Solution:**
- Initialize in OnAwake: PlayerKills ??= new NetDictionary<Guid, int>()
- Never assume [Sync] collection is populated

## Common Workarounds

### Razor BuildHash Reactivity

**Pattern:** Razor panels only rebuild when the UI system sees a state change. Dynamic markup that displays C# values, synced state, parent-bound properties, status text, ammo, health, timers, or team scores should override `BuildHash()` and combine every value that can affect the rendered result.

**Workflow:**
- Use `[Sync]` on the gameplay/component state that must replicate, then read that state from Razor through an explicit `[Property]` component reference or an existing local HUD lookup.
- In the Razor file, return `HashCode.Combine(...)` with every rendered value that can change. For collections, include stable count/version values or a compact hash of the displayed fields.
- Avoid `StateHasChanged()` from `Tick()` as a general refresh fix. It hides missing hash inputs and rebuilds the panel every frame.
- Run `scripts\agents\ui_flow_audit.ps1 -FailOnWarning` after Razor changes; it warns on dynamic output without `BuildHash()` and per-frame `StateHasChanged()` calls.

### PanelComponent Stylesheet Lookup

**Pattern:** When a Razor `PanelComponent` also has a partial `.cs` class, s&box may look for a stylesheet using the class file name, such as `ui/hudpanel.cs.scss`, instead of only `HudPanel.razor.scss`.

**Solution:**
- Keep a matching `.cs.scss` stylesheet alias beside the partial class for each styled panel
- If UI appears as tiny unstyled text in the top-left, check the editor console for a missing stylesheet path first
- Keep startup UI in `scenes/main.scene` unless a dedicated menu scene is intentionally reintroduced

### Accessing Local Player

**Pattern:** Find pawn by Network.Owner == Connection.Local.Id

**Solution:**
`csharp
var allHealth = Scene.GetAllComponents<Health>();
foreach (var health in allHealth)
{
    if (health.GameObject.Network.Owner?.Id == Connection.Local?.Id)
    {
        // This is the local player
    }
}
`

### Detecting Non-Owner Instances

**Pattern:** Use IsProxy to skip input on non-owner replicas.

**Solution:**
`csharp
if (IsProxy) return;  // Skip input on clients
// Input logic here (host only)
`

### Host-Only Logic in Shared Methods

**Pattern:** Need to run logic only on host.

**Solution:**
`csharp
public void TakeDamage(DamageInfo info)
{
    if (!Networking.IsHost) return;
    
    CurrentHealth -= info.Amount;
    // Rest of logic runs only on host
}
`

## Performance Tips

- Keep scene queries to OnFixedUpdate (30 Hz)
- Cache component lookups (FindByName, GetComponent)
- Unsubscribe from events to prevent memory leaks
- Avoid creating networked objects during gameplay
- Profile with Networking.Statistics to check bandwidth

## Debugging Tips

- Check editor console for networking errors
- Use Log.Info() to trace execution flow
- Verify [Sync] properties replicate (watch client-side changes)
- Test with 2+ clients to catch multiplayer bugs
- Use if (!Networking.IsHost) guards to find permission issues

### MCP Bridge Diagnostics

**Pattern:** The in-editor MCP bridge reports tool-call failures in the bridge panel, but `editor_console_output` can return an empty line list even when the panel log shows recent MCP entries.

**Workflow:**
- Treat every MCP tool JSON result as the real-time source of truth; read failed tool responses immediately instead of assuming the panel log is available through `editor_console_output`.
- Call `component_list` before `component_get` or `component_set`. The bridge often expects short component names such as `ModelRenderer`, not full type names such as `Sandbox.ModelRenderer`.
- Use `get_server_status` to confirm the bridge is listening and request counts are changing.
- Still call `editor_console_output` after risky editor operations, but if it returns `[]`, rely on the MCP call result plus the visible editor console/panel.

### Native MCP Tool Exposure

**Pattern:** The project-level `.mcp.json` is the right place to advertise editor MCP servers to clients that load local MCP manifests. The S&Box editor MCP Server dock listens at `http://localhost:29015/mcp`; ClaudeBridge is a separate file-based IPC bridge and should not be treated as the primary scene/component mutation path.

**Workflow:**
- Keep the S&Box MCP Server dock running in the editor.
- Register the HTTP MCP endpoint in `.mcp.json` under `mcpServers.sbox`.
- Start a new Codex/agent session after changing `.mcp.json`; native tools are usually loaded at session start.
- If native `mcp__sbox__...` tools are not exposed in a session, use the HTTP JSON-RPC fallback against `http://localhost:29015/mcp`.
- Use ClaudeBridge only as a fallback after checking its handler surface for the exact operation needed.

### Editor-First Command Routing

**Pattern:** When a task can be performed in the S&Box editor, the agent should start from live editor state and only fall back to static file edits after checking the native MCP surface.

**Workflow:**
- Route through `.agents/sbox/editor-first-workflow-agent.md` for scene, prefab, component, asset, sound, screenshot, playtest, terrain, or editor-tooling work.
- Start with `control_plane_status`, then `tools/list` or `control_plane_capabilities` so the agent uses tools that are actually exposed in the running editor.
- Inspect with `editor_scene_info`, `scene_get_hierarchy`, `scene_find_objects`, `scene_list_objects`, `component_list`, and `component_get` before mutation.
- Prefer editor mutations such as `scene_create_object`, `component_set`, `asset_*`, and `sound_*`; save live changes with `editor_save_scene`.
- Verify live state and saved files after editor edits, and use `editor_take_screenshot`, `editor_play`, and `editor_console_output` when visual or runtime behavior matters.
- Run `scripts\agents\run_agent_checks.ps1 -Suite editor-first -ShowInfo` after workflow, agent, hook, or control-plane routing changes.

### ModelRenderer Material Overrides

**Pattern:** Renderer-level `MaterialOverride` paths are reliable for single-material blockout props and playtest spot checks. They are unsafe as a durable fix for multi-material foliage: overriding the renderer can collapse bark and foliage card slots to one material. Generated ModelDoc material remaps may compile down to `materials/default.vmat` if the model compiler does not match the source FBX material names exactly.

**Workflow:**
- For quick visible in-game texture validation on a single-material prop, put an explicit `MaterialOverride` on the `ModelRenderer`.
- For multi-material foliage, fix the Blender material names, exported FBX slots, asset config, and `.vmdl` remaps instead of adding scene `MaterialOverride` or `Materials.indexed`.
- For live editor scenes, set the override on the currently loaded object with the bridge and then save only after confirming no runtime transform drift is being persisted.
- Check the live component with `component_get` and expect `MaterialOverride` to show as `Material:<name>` when the override is loaded.

### Metallic Materials Render Black Without Reflections

**Pattern:** A `complex.shader` material with `g_flMetalness` at or near `1.0` is a *pure* metal with no diffuse albedo, so it shows **only** environment reflections. In scene areas without reflection-probe / strong ambient-specular coverage (open terrain, plateaus), those surfaces render solid black while dielectric materials (metalness 0) right next to them light normally. This is the usual cause of "the silver/steel parts of my prop are black in-game."

**Workflow:**
- Keep prop "metal" materials at **partial** metalness, not `1.0`. Every working metal in this project does: `materials/arena/metal_pad.vmat` 0.30, `materials/environment/watertower_roof.vmat` 0.25, `materials/environment/watertower_tank.vmat` 0.65. Partial metalness retains enough dielectric diffuse to catch sun/ambient light and stay visible everywhere.
- Suggested ranges by look: matte cast iron / painted metal `0.25–0.40` (roughness `0.6–0.8`); galvanized / brushed steel `0.45–0.55` (roughness `0.5–0.6`); polished metal `0.6–0.7` (roughness `0.25–0.35`). Reserve `>0.8` only for surfaces with guaranteed reflection-probe coverage.
- The scalar form (`TextureColor` + `g_flMetalness`/`g_flRoughness`, no normal/rough/AO textures) is fine for flat-color props — `metal_pad` and `watertower_roof` use exactly that. The black comes from the metalness value, not the missing maps.
- After editing a `.vmat`, delete its compiled `Assets/.../<name>.vmat_c` to force a clean recompile; the editor regenerates it on viewport focus.
- Campstove fix (2026-06): steel grate/burner/tank were authored at metalness `1.0` and rendered black on the plateau; dropped to `0.50`/`0.35`/`0.65` to match the project convention.

### Editor-Native Cover Props

**Pattern:** Small tactical cover made from S&Box editor primitives should stay scene-native when the user asks for a fast map prop and explicitly avoids Blender.

**Workflow:**
- Query the active editor scene before file edits; unsaved user deletions can be present only in live editor state.
- Preserve missing primitive children unless the user asks to restore them. Do not recreate deleted seam strips or detail pieces during a tightening or material pass.
- Use local material/texture assets and `ModelRenderer.MaterialOverride` for single-material primitive groups that need to read as sandbags, crates, barricades, or tarp-covered shapes.
- When using MCP `scene_create_object` under a parent, pass a world position. The saved scene stores the child as a local offset, so grouped scene assets need `parentWorld + intendedLocalOffset` during creation and a saved-JSON check afterward.
- Validate repeated cover pieces with a focused row-spacing and bounds audit, then verify with a live editor save/screenshot.
- Route future work through `.agents/sbox/editor-native-cover-agent.md` and run focused guards such as `scripts/agents/sandbag_cover_audit.ps1 -ShowInfo` or `scripts/agents/burnt_vehicle_block_audit.ps1 -ShowInfo` for current editor-native cover contracts.

### AAA Blender Asset Quality Gate

**Pattern:** High-polish Blender assets need a concrete quality target before modeling starts. A passing export, `.vmdl`, or Blender preview only proves the pipeline moved data; it does not prove the result has strong references, material separation, readable silhouette, authored sockets, or in-engine presentation.

**Workflow:**
- Start with `.agents/sbox/aaa-asset-quality-agent.md` and generate a brief with `scripts/agents/new_asset_brief.ps1` so reference requirements, Production Quality Targets, material roles, sockets, scale, and visual review checks are explicit.
- Run `scripts/agents/aaa_asset_quality_audit.ps1 -ShowInfo` before detailed asset work and keep it in the `asset-production` proof stack.
- For final proof, combine Blender quality, material/texture, visual preview/contact sheet, asset pipeline, ModelDoc, FBX material-slot, prefab graph, and an S&Box editor or prefab screenshot when the user needs visual approval.
- Do not accept a single flattering Blender render for assets that must read in first person, third person, drone-height, or scene-placement views.

### Held-Item Slot Visibility

**Pattern:** Every visible held-item renderer needs to be hidden at the item root when its loadout slot is not selected. Hiding only a named visual child can leave extra mesh children visible or casting shadows.

**Workflow:**
- Soldier classes keep primary weapons in slot 1 and grenades/equipment in slot 2.
- Pilot ground avatars currently keep the drone controller/deployer in slot 1 and the MP7 in slot 2.
- Held-item components should call the shared `WeaponPose.SetVisibility(GameObject, selected)` root helper when stowed.
- Selected held-item components should also call `WeaponPose.ApplyHandPose(...)` with item-owned `LeftHandIk` and `RightHandIk` child targets so the human body hands have stable places to attach.
- Stowed held items should clear only the IK targets they own; do not wipe another selected item's hand pose.
- Run `.\scripts\check_loadout_slots.ps1` after prefab slot edits to catch duplicate or reversed slot assignments before playtesting.

### Human First-Person Arms And Held-Item IK

**Pattern:** Player-facing first-person arms come from the real human body renderer plus Citizen IK. Do not add a separate arms-only viewmodel path for the local player.

**Workflow:**
- Keep `GroundPlayerController` body rendering visible in first person unless a local-only clipping fix is explicitly needed.
- Put `LeftHandIk` and `RightHandIk` child GameObjects directly under every active held item: `Weapon`, `Grenade`, and `DroneDeployer` where present.
- Use `Rifle` / `Both` for hitscan rifles and the drone jammer, `Shotgun` / `Both` for shotgun, `HoldItem` / `Right` for grenades, and `HoldItem` / `Both` for the pilot deployer.
- If editor playtest shows head or torso self-occlusion, fix local body/head visibility in the human body path rather than bringing back a separate arms model.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite prefab -ShowInfo` after held-item prefab edits so missing hand targets are caught before playtesting.

### First-Person Grip Anchor Tuning

**Pattern:** First-person hand IK targets should behave like authored grip anchors on the visible held item. If the controller, weapon, drone, or prop moves with eye sway, slot state, variant selection, or launch state, the hand target should move from that visual's transform rather than from a separate eye-space position.

**Workflow:**
- Use the S&Box editor as the tuning surface: start play mode, spawn or select the target pawn, inspect the held item with `scene_find_objects` / `scene_find_by_component` and `component_get`, and make temporary pose changes with `component_set`.
- For controller, weapon, and drone grips, prefer visual-relative local offsets or child grip GameObjects under the held item. ModelDoc attachments can own the same concept for model-level anchors when the asset itself should expose them, but prefab/component anchors are usually faster for team-specific gameplay poses.
- Keep team-specific first-person visuals separated. Pilot controller/drone hand paths should not reuse hunter weapon or grenade viewmodel arms, hold types, or animation assumptions unless the shared behavior is intentional and covered by an audit.
- Capture editor screenshots before persisting values to prefabs or reusable held-item templates. Static prefab JSON can prove the targets exist, but it cannot prove the thumb/finger silhouette reads correctly from the active first-person camera.
- When a live proof command or selector fails, verify the live component type names with `component_list` / `scene_get_object` and check play/hotload state before continuing with more offset guesses.

### Reusable Held-Item Prefabs

**Pattern:** Active class and pilot prefabs still own runtime loadout behavior, but weapon/equipment child graphs should also have standalone reusable prefab templates so item visuals, sockets, IK targets, sounds, and component tuning can be inspected and reused without digging through a character prefab.

**Workflow:**
- Reusable held-item templates live in `Assets/prefabs/items/` and are generated from the active `Weapon`, `Grenade`, and `DroneDeployer` child graphs.
- The pilot drone deployer also uses `Assets/prefabs/items/held_drone_propeller.prefab` as the reusable runtime propeller preview object; `DroneDeployer` clones it and assigns the selected GPS/FPV propeller model.
- `FirstPersonViewmodel` clones `Assets/prefabs/items/local_first_person_viewmodel.prefab` for the shared local-only root, `Assets/prefabs/items/viewmodel_arms.prefab` for the reusable arms child, `Assets/prefabs/items/viewmodel_stock_weapon.prefab` for visible stock weapons or hidden custom-weapon animation drivers, and `Assets/prefabs/items/viewmodel_custom_visual.prefab` / `Assets/prefabs/items/viewmodel_static_item.prefab` for the runtime custom/static visual containers. The custom/static visual container prefabs own a `Sandbox.ModelRenderer` for model-path fallback setup; copied source-renderer children remain runtime/per-item because their count, transform, model, and material come from the selected held item.
- Use `.\scripts\agents\sync_held_item_prefab_templates.ps1` after intentional held-item prefab edits.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite held-items -ShowInfo` and `.\scripts\agents\run_agent_checks.ps1 -Suite viewmodel-prefab -ShowInfo` to prove templates match the active loadout sources and the first-person root prefab path still exists.
- Do not treat the visual-only asset pipeline prefabs (`assault_rifle_m4.prefab`, `smg_mp7.prefab`) as complete held-item prefabs; the held-item templates include gameplay components, sockets, IK targets, and item-specific sounds.

### Reusable Scene Marker Prefabs

**Pattern:** Scene markers are gameplay objects too. Repeated `PlayerSpawn` and `TrainingDummySpawn` authoring should start from marker prefabs instead of hand-built empty GameObjects.

**Workflow:**
- Marker templates live in `Assets/prefabs/markers/`.
- `player_spawn_soldier.prefab` keeps the legacy `PlayerSpawn` tag and `PlayerSpawn.Role = Soldier`.
- `player_spawn_pilot.prefab` keeps the legacy `DroneSpawn` tag and `PlayerSpawn.Role = Pilot`.
- `training_dummy_spawn.prefab` carries `TrainingDummySpawn.PreferredRole = Spectator` for neutral solo-practice placement.
- Use `.\scripts\agents\migrate_scene_markers_to_prefab_instances.ps1 -DryRun` to preview direct `PlayerSpawn` and `TrainingDummySpawn` placements that can be converted to prefab instances, then run it without `-DryRun` to rewrite saved placements through the engine's `__Prefab` / patch / GUID-map instance format.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite scene-markers -ShowInfo` after marker prefab edits.

### Terrain Scene Prefab Drift

**Pattern:** Shape-matching terrain, landform, grass, trench, skyline, and level-design scene objects should not stay expanded in `main.scene` once a reusable prefab template exists.

**Workflow:**
- Run `.\scripts\agents\migrate_terrain_scene_objects_to_prefab_instances.ps1 -Root . -DryRun` to preview scene objects that can safely become prefab instances.
- Run the migration without `-DryRun` only for intentional prefab instance rewrites, then run `.\scripts\agents\run_agent_checks.ps1 -Suite terrain-scene-prefabs -ShowInfo` and `.\scripts\agents\run_agent_checks.ps1 -Suite prefab-graph -ShowInfo`.
- If the migration skips an object because its shape does not match an existing template, either leave it direct as hand-authored scene content or create a distinct prefab contract before migrating it.

### Scene Prefab Coverage

**Pattern:** Component-bearing objects saved in `main.scene` should be prefab instances unless they are truly scene-local metadata or the unique terrain floor. Empty organizational containers can stay direct.

**Workflow:**
- Keep `Scene Information` direct with only `Sandbox.SceneInformation`.
- Keep `BlockoutMap/ArenaFloor` direct with only `Sandbox.Terrain` because it binds the scene's authored terrain resource.
- Everything else that owns components should be prefab-backed or covered by a deliberately narrow exception in `scripts/agents/scene_prefab_coverage_audit.ps1`.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite scene-prefab-coverage -ShowInfo` after scene or migration edits.

### Reusable Stock Scene Prop Prefabs

**Pattern:** Mounted stock models that appear as gameplay-cover or dressing objects in `main.scene` should have reusable project prefabs before they are copied around as direct model props.

**Workflow:**
- Stock prop templates live in `Assets/prefabs/environment/stock/`.
- Use `.\scripts\agents\sync_stock_scene_prop_prefabs.ps1` after intentional template changes.
- Use `.\scripts\agents\migrate_stock_scene_props_to_prefab_instances.ps1 -DryRun` to preview direct scene placements that can be converted to prefab instances, then run the same script without `-DryRun` to rewrite the saved scene through the engine's `__Prefab` / patch / GUID-map instance format.
- The migration template list also carries `bouneurmaum_park_sign.prefab`, a custom-authored (non-stock) static prefab. It is deliberately absent from `sync_stock_scene_prop_prefabs.ps1` so the sync generator can never overwrite the hand-authored Visual-child/static-collider structure; only the migrate script and the editor commands reference it.
- The migration rewrite preserves the saved scene's on-disk formatting (CRLF line endings, missing trailing newline, and ulong `BodyGroups` values that `JSON.parse` would mangle), so a migration pass only diffs the migrated nodes.
- Run `.\scripts\agents\stock_scene_prop_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated` to prove the stock prop prefab templates are present and that the saved scene now references those templates as prefab instances.
- Use the editor commands `dvp_preview_stock_scene_prop_prefab_migration` and `dvp_migrate_stock_scene_props_to_prefabs` after `Editor/StockScenePropPrefabEditorCommands.cs` is hotloaded to replace direct placements through the S&Box prefab clone API.
- The non-strict audit reports direct scene uses as migration work. When live scene edits are allowed, prefer editor-owned scene work; static JSON migration is acceptable only when it follows current engine prefab serialization evidence and is verified by reloading the scene in the editor.
- If `prefab_graph_audit.ps1` reports a direct scene stock path as missing, mount the required Facepunch package, restore the local asset, or intentionally replace the model before treating its prefab template as integrated.

### Reusable Arena Boundary Wall Prefab

**Pattern:** Treat arena edge blockers like Source 2 clip brushes: solid invisible collision first, with terrain, rocks, trees, berms, or other arted dressing used only when the playable edge needs a believable visual reason to turn the player around. The four invisible blockers should share one prefab contract instead of carrying repeated direct renderer, collider, and wireframe component settings in `main.scene`.

**Workflow:**
- The boundary wall template lives at `Assets/prefabs/environment/arena_boundary_wall.prefab`.
- Keep exactly one saved scene prefab instance each for `NorthBoundary`, `SouthBoundary`, `EastBoundary`, and `WestBoundary`.
- The prefab owns the hidden `models/dev/box.vmdl` renderer, static non-trigger `50,50,50` box collider, and selection-only `SelectedHierarchyColliderViewer`; scene instances should only override placement and name.
- Do not make these boundaries visible as white dev walls in normal editor/play views. Select the object or enable collision debug tooling when the clip boundary needs inspection.
- Use `.\scripts\agents\migrate_arena_boundaries_to_prefab_instances.ps1 -DryRun` to preview direct boundary wall placements that can be converted, then run it without `-DryRun` to rewrite them as prefab instances.
- Run `.\scripts\agents\scene_integrity_audit.ps1 -Root . -ShowInfo` after boundary prefab or scene edits. It validates the prefab contract and rejects scene instances that override renderer visibility or material state.

### Reusable Terrain Scene Object Prefabs

**Pattern:** Repeated terrain trees, simple rocks, model-collider exterior rocks, full or partial grass-card clumps, ground-polish patches, berm soft caps, shape-matching landforms, and trench segment roots should use local environment prefabs so trunk, branch, viewer, rock collision, card-crossing, material patch, soft-cap, berm/plateau, and trench berm/endcap contracts live in one template instead of hundreds of scene-authored children or renderers.

**Workflow:**
- Terrain object templates live at `Assets/prefabs/environment/terrain_assets.prefab`, `terrain_pine.prefab`, `terrain_pine_broad.prefab`, `terrain_pine_windswept.prefab`, `terrain_rock.prefab`, `terrain_rock_model_collider.prefab`, `grass_clump.prefab`, `grass_clump_single_card.prefab`, `grass_clump_five_card.prefab`, `ground_grass_clump_patch.prefab`, `ground_worn_path_patch.prefab`, `berm_soft_cap.prefab`, `Berm.prefab`, `Hill.prefab`, `hill_central_north_box.prefab`, `Plateau.prefab`, `plateau_east_north_terrain.prefab`, and `TrenchSegment.prefab`.
- Use `.\scripts\agents\migrate_terrain_scene_objects_to_prefab_instances.ps1 -DryRun` to preview direct tree, simple rock, model-collider exterior rock, full or partial grass-card clump, ground-polish patch, berm soft-cap, landform, and trench segment placements whose child/component shape matches the local prefab, then run it without `-DryRun` to rewrite them as saved-scene prefab instances. Exact-name bespoke landform templates such as `hill_central_north_box.prefab` and `plateau_east_north_terrain.prefab` should be listed before the generic `Hill.prefab` / `Plateau.prefab` templates.
- The migration intentionally skips unknown shape-mismatched rocks, foliage, hills, or plateaus so hand-edited collision stays direct until a new prefab contract is created for that shape.
- `tree_collision_audit.ps1` resolves terrain tree prefab instances back to their templates, so prefab-backed scene trees still count toward trunk and branch collider coverage.
- Run `.\scripts\agents\tree_collision_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\prefab_graph_audit.ps1 -ShowInfo`, and `.\scripts\agents\scene_integrity_audit.ps1 -Root . -ShowInfo` after terrain prefab or scene-placement edits.

### Composed Environment Prop Prefab Instances

**Pattern:** Scene-authored composed props should become prefab instances once their visual, solid collision, trigger, and helper children settle into a reusable contract. The prefab owns the child graph; the scene instance owns only placement.

**Workflow:**
- `Assets/prefabs/environment/WaterTower.prefab` owns the tower visual, static `ModelCollider` mesh collision on the `Visual` child, ladder trigger, `LadderVolume`, and `SelectedHierarchyColliderViewer`.
- `Assets/prefabs/environment/burnt_car_wreck.prefab` owns the destroyed pickup's 60 primitive child pieces. `CenterLane_DestroyedPickup_North` should be a scene prefab instance that overrides the root name and transform, not a hand-expanded scene group.
- `Assets/prefabs/environment/house_large_playable.prefab`, `Assets/prefabs/environment/house_small_playable.prefab`, and `Assets/prefabs/environment/house_small_collision_playable.prefab` own the playable house visual, solid collision, ladder, and `Zone_*` helper child contracts. `House_Large_01`, `House_Large_02`, `House_Small_01`, `House_Small_02`, `House_Small_03`, and `House_Small_04` should be scene prefab instances that override placement and any per-placement `Model_Visual` offset/scale instead of hand-expanded scene groups.
- `Assets/prefabs/environment/road_sandbag_cover_mid.prefab` owns the 18 solid sandbag bodies for the road cover. `RoadSandbagCover_Mid` should be a scene prefab instance after the spacing and height checks pass.
- `Assets/prefabs/environment/road_cover_northwest_barrier.prefab` owns the northwest road barrier's 10 solid primitive body pieces and 9 visual detail pieces. `RoadCover_Northwest_Barrier` should be a scene prefab instance after the barrier audit passes.
- `Assets/prefabs/environment/road_surface.prefab`, `road_shoulder.prefab`, and `road_curb.prefab` own the base road renderer/material contracts. `RoadSurface_Main`, both shoulders, and both curbs should be scene prefab instances.
- `Assets/prefabs/environment/road_lane_dash.prefab` owns the visual-only centerline dash renderer. The 41 `RoadDash_##` placements should be scene prefab instances that preserve the audit's 260-unit spacing contract.
- `Assets/prefabs/environment/road_edge_wear_patch.prefab` owns the visual-only road-edge wear plane renderer and material. The 24 road-edge wear scene placements should be prefab instances that only override root name, position, rotation, and scale.
- `Assets/prefabs/environment/blockout_cover_box.prefab` owns the shared `models/dev/box.vmdl` renderer plus static `BoxCollider` shape for repeated `LevelDesignPass_AboveBelow` cover, operator-nest, asset-placeholder blocks, `DroneLaunchPad`, and `NorthLowCover`. Scene instances should override root name, transform, material, and tint instead of duplicating the renderer/collider pair.
- `Assets/prefabs/environment/skyline_model_collider_box.prefab` owns the shared `models/dev/box.vmdl` renderer plus `ModelCollider` shape for skyline dev boxes that need model collision instead of a `BoxCollider`. Scene instances should override root name, transform, material, and tint instead of duplicating the renderer/collider pair.
- `Assets/prefabs/environment/visual_dev_box.prefab` owns the shared renderer-only `models/dev/box.vmdl` shape for glow markers, skyline tower masses, and skyline window bands. Scene instances should override root name, transform, material, and tint instead of duplicating visual-only renderer objects.
- `Assets/prefabs/environment/operator_signal_light.prefab`, `Assets/prefabs/environment/launch_pad_glow_light.prefab`, and `Assets/prefabs/environment/perch_marker_light.prefab` own reusable `PointLight` readability markers. Scene instances should override root name, placement, light radius/color, and glow-marker scale/tint rather than leaving loose direct light roots in `main.scene`.
- `Assets/prefabs/environment/ambient_sound_point.prefab` owns the reusable `AmbientSound` emitter contract. Scene instances should override root name, placement, sound event, loop timing, and volume instead of leaving repeated ambient emitters as direct scene roots.
- Keep the WaterTower prefab root at `0,0,0`, identity rotation, and `1,1,1` scale. Scene placements should override the root name, position, rotation, and scale instead of baking placement into the prefab.
- Keep the destroyed pickup prefab root named `BurntCarWreck`; the scene instance should rename it to `CenterLane_DestroyedPickup_North` through the prefab patch.
- Keep playable house prefab roots named `HouseLargePlayable`, `HouseSmallPlayable`, and `HouseSmallCollisionPlayable`; scene instances should use their placed house names through the prefab patch.
- Keep the sandbag cover prefab root named `RoadSandbagCoverMid`; the scene instance should rename it to `RoadSandbagCover_Mid` through the prefab patch.
- Keep the road-cover barrier prefab root named `RoadCoverNorthwestBarrier`; the scene instance should rename it to `RoadCover_Northwest_Barrier` through the prefab patch.
- Keep road base prefab roots named `RoadSurface`, `RoadShoulder`, and `RoadCurb`; scene instances should use `RoadSurface_Main`, `RoadShoulder_West`, `RoadShoulder_East`, `RoadCurb_West`, and `RoadCurb_East` names through the prefab patch.
- Keep the road lane dash prefab root named `RoadLaneDash`; scene instances should use `RoadDash_##` names through the prefab patch.
- Keep the road-edge wear prefab root named `RoadEdgeWearPatch`; scene instances should use `RoadEdgeWear_West_##` and `RoadEdgeWear_East_##` names through the prefab patch.
- Keep the blockout cover prefab root named `BlockoutCoverBox`; scene instances should use their lane, nest, placeholder, launch-pad, or low-cover names through the prefab patch.
- Keep the skyline model-collider prefab root named `SkylineModelColliderBox`; scene instances should use their skyline mass names through the prefab patch.
- Keep the visual dev-box prefab root named `VisualDevBox`; scene instances should use their marker or skyline names through the prefab patch.
- Keep readability light prefab roots named `OperatorSignalLight`, `LaunchPadGlowLight`, and `PerchMarkerLight`; scene instances should use their placed signal/glow/perch marker names through the prefab patch.
- Keep the ambient sound prefab root named `AmbientSoundPoint`; scene instances should use their placed ambient sound names through the prefab patch.
- Do not migrate composed buildings or props just because a similarly named prefab exists. First compare child collider counts, visual scale, helper components, and audit expectations; if the scene contract differs, update or create the prefab contract before replacing the scene object with a prefab instance. Use `.\scripts\agents\migrate_building_scene_objects_to_prefab_instances.ps1 -DryRun` before changing playable house placements.
- Run `.\scripts\agents\scene_integrity_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\collision_authoring_agent.ps1 -Root . -ShowInfo`, `.\scripts\agents\building_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated`, `.\scripts\agents\readability_light_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated`, `.\scripts\agents\ambient_sound_scene_prefab_audit.ps1 -Root . -ShowInfo -RequireMigrated`, `.\scripts\agents\destroyed_pickup_scene_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\sandbag_cover_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\road_cover_barrier_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\road_lane_marking_audit.ps1 -Root . -ShowInfo`, `.\scripts\agents\road_edge_wear_audit.ps1 -Root . -ShowInfo`, and `.\scripts\agents\prefab_graph_audit.ps1 -Root . -ShowInfo` after composed-prop prefab or scene-instance edits.

### Transient Combat Prefabs

**Pattern:** Runtime-only combat objects should still have prefab templates when their behavior is shared across multiple weapons or item classes.

**Workflow:**
- `MuzzleFlashVisual.Spawn(...)` first clones `Assets/prefabs/effects/muzzle_flash.prefab`, then falls back to constructing the object if the prefab is unavailable.
- Soldier, pilot, and drone hitscan tracers should use the shared `Assets/prefabs/tracer_default.prefab` before falling back to `BallisticTracerRenderer`; that fallback should first clone `Assets/prefabs/effects/ballistic_tracer.prefab`, then construct the same local-only object only if the prefab is unavailable.
- `Assets/prefabs/effects/muzzle_flash.prefab` should own `MuzzleFlashVisual`, `SpriteRenderer`, and `PointLight`. `MuzzleFlashVisual` still configures size, color, sprite texture, and fade at spawn time, but component creation should be a repair fallback for damaged prefabs only.
- `Assets/prefabs/effects/chaff_burst.prefab`, `emp_burst.prefab`, and `frag_burst.prefab` should own their particle burst children and `Explosion Light` child. `GrenadeEffectVisual` still configures kind-specific count, scale, color, radius, and lifetime at spawn time, but should reuse prefab-authored child objects/components before creating repair fallbacks.
- Project-owned scene singleton roots and reusable engine roots should be prefab-backed when they carry reusable gameplay, UI, camera, lighting, or skybox components. `GameManager`, `HUD`, `BlindingSun_WestSky`, `Sun`, `2D Skybox`, and `Camera` should remain saved prefab instances of `Assets/prefabs/systems/game_manager.prefab`, `Assets/prefabs/ui/hud.prefab`, `Assets/prefabs/environment/blinding_sun_glare.prefab`, `Assets/prefabs/environment/sun_directional.prefab`, `Assets/prefabs/environment/skybox_2d.prefab`, and `Assets/prefabs/systems/main_camera.prefab`; use `scripts/agents/migrate_scene_singletons_to_prefab_instances.ps1 -DryRun` and `scene_singleton_prefab_audit.ps1 -RequireMigrated` after scene saves. Keep `Scene Information` direct because it is main-scene metadata rather than a reusable object contract.
- `TracerLifetime` first clones `Assets/prefabs/effects/tracer_bullet_glow.prefab` for the moving head glow, then falls back to constructing the same sprite child if the prefab is unavailable.
- `DroneJammerGun` first clones `Assets/prefabs/effects/jammer_beam.prefab` for its local LineRenderer beam, then falls back to constructing the same local-only beam object if the prefab is unavailable.
- `FiberCable.DetachFromLiveEndpoints()` first clones `Assets/prefabs/effects/detached_fiber_cable.prefab` for the persistent local wire, then falls back to constructing a local-only LineRenderer object if the prefab is unavailable.
- Chaff, EMP, and frag detonation visuals first clone `Assets/prefabs/effects/chaff_burst.prefab`, `Assets/prefabs/effects/emp_burst.prefab`, or `Assets/prefabs/effects/frag_burst.prefab`, then configure the shared `GrenadeEffectVisual` with the grenade-specific kind and radius.
- `ThrowableGrenade` first clones `Assets/prefabs/items/thrown_grenade_projectile.prefab`, then applies the grenade-specific model, velocity, fuse, collider, and physics tuning. The prefab should own `ModelRenderer`, `CapsuleCollider`, `Rigidbody`, and wired `ThrownGrenadeProjectile.Body` / `.Collider` refs; runtime component creation is only a repair fallback.
- Keep procedural fallbacks in these paths so combat still functions if an asset reference is temporarily broken during editor iteration.
- Runtime `new GameObject` creation in `Code/` should be rare and classified. Prefer a prefab first, then a repair fallback for broken assets; keep only intentionally dynamic per-item copies as direct runtime children. Run `.\scripts\agents\run_agent_checks.ps1 -Suite runtime-prefab-fallbacks -ShowInfo` after adding a new runtime object path.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite ballistic-tracers -ShowInfo` after changing fallback ballistic tracer spawning. Run `.\scripts\agents\run_agent_checks.ps1 -Suite transient-combat -ShowInfo` after changing broader muzzle flash, tracer, grenade, cable, or thrown projectile spawning.

### Team Voice Prefab Ownership

**Pattern:** Spawned player pawns should carry their shared team voice routing component in the prefab contract, with `GameSetup` keeping a repair fallback for legacy or broken prefabs.

**Workflow:**
- `Assets/prefabs/soldier.prefab`, `soldier_assault.prefab`, `soldier_heavy.prefab`, and `pilot_ground.prefab` should carry `DroneVsPlayers.TeamVoice` on the root with team-only, role-aware routing defaults.
- Keep `GameSetup.EnsureTeamVoice(...)` as a fallback that finds prefab-authored `TeamVoice`, creates one only if missing, assigns `Setup`, and reapplies the routing profile after spawn.
- `Assets/prefabs/systems/game_manager.prefab` should carry `DroneVsPlayers.TeamComms` with team chat enabled and `[TEAM]` prefix defaults. Keep `GameSetup.EnsureTeamComms()` as a fallback that finds prefab-authored `TeamComms`, creates one only if missing, and assigns `Setup`.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite team-voice-prefabs -ShowInfo` after changing character voice prefab ownership.

### Training Dummy Prefab Ownership

**Pattern:** Training dummy navigation should be prefab-authored, with runtime repair only as a compatibility fallback.

**Workflow:**
- `Assets/prefabs/training_dummy.prefab` should carry `Sandbox.NavMeshAgent` on the root and wire `TrainingDummy.NavAgent` to that component.
- Keep `TrainingDummy.ConfigureNavAgent()` able to find or create a missing `NavMeshAgent` so legacy or temporarily damaged prefabs still move.
- Run `.\scripts\agents\run_agent_checks.ps1 -Suite training-dummy-prefab -ShowInfo` after changing the training dummy prefab or nav ownership.

### MCP Component Value Conversion

**Pattern:** MCP `component_set` must know how to parse every simple inspector value type it edits. Missing converters can make a property look editable in the inspector but fail through automation.

**Workflow:**
- `Vector2`, `Vector3`, `Angles`, `Color`, primitive values, models, and materials should be supported by the MCP component setter.
- If an editor property fails with an invalid cast, add the converter in `Libraries/jtc.mcp-server/Editor/Handlers/ComponentHandler.cs` before working around it manually.

### Authored Prop Collision Alignment

**Pattern:** A prop can look correctly rotated while helper volumes still use an older transform if the visible `Visual` child is rotated locally and sibling trigger/helper children remain unrotated. The water tower originally reproduced this with hand-authored tank/platform/leg collision; the current contract uses a `ModelCollider` on `Visual` for body collision and keeps only trigger/helper volumes as siblings.

**Workflow:**
- Keep visible mesh collision, ladder triggers, and helper volumes under a shared prop root.
- Rotate or move the prop root for scene placement. Do not rotate the `Visual` child to orient a prop that has sibling trigger/helper children.
- For buildings, evaluate collision on the house/building root, not just the selected `Model_Visual` child. `Model_Visual` can remain renderer-only when sibling `Collision_*` children under the root provide the floors, walls, roof, stairs, and cover collision.
- For open-base props like the water tower, do not fill empty visual space with broad frame wall colliders. Use mesh collision through `ModelCollider` for the visible body and keep ladder volumes as triggers.
- For climbable props, keep ladder volumes as trigger colliders with `LadderVolume`; keep physical blockers as non-trigger `BoxCollider` children.
- Scene-placed environment Blender models should not silently remain non-solid. If a local model from `environment_model.blend` is placed directly in `main.scene`, add a direct `BoxCollider`, a `Collision_*` child, or sibling `Collision_*` helpers under the same prop root. Use narrow trunk blockers for trees and low body blockers for rocks instead of broad leaf or scenery volumes.
- After Save As or MCP scene edits, verify both saved JSON and the live editor hierarchy. The editor can keep a stale in-memory scene even after the file is patched.
- Run `scripts\agents\collision_authoring_agent.ps1 -ShowInfo` and then do a short editor playtest walking into the prop from multiple sides.
- For broad or risky collision work, route through `.agents\sbox\collision-chain-agent.md` so a Codex explorer defines the collision contract, an implementer makes scoped edits, a verifier proves the result, and a critic can pass defects back down before handoff.

### SoundEvent Source Selection

**Pattern:** Local procedural WAVs are acceptable as fallbacks, but common cues should use stock/editor recordings imported into local `.sound` wrappers when the S&Box install already provides usable source audio. Direct mounted package SoundEvent paths looked valid statically but produced editor `.sound_c` file-open errors in this project, so gameplay code, prefabs, and scenes should reference local `Assets/sounds` wrappers.

**Workflow:**
- Search stock/editor audio before generating: weapon shots/reloads, dry fire, hitmarkers, movement, wind, drone hum, and explosions often have usable recordings under the S&Box download asset tree.
- Keep gameplay-facing references as `.sound` resource paths. Do not point C# or prefab properties at raw `.wav` files.
- Import or copy usable stock WAVs into `Assets/sounds/`, wrap them in local `.sound` files, and reference `sounds/example.sound` from C#, prefabs, and scenes.
- For project-specific local fallbacks, run `python scripts/audio/generate_project_sounds.py --root .`. The generator imports known stock WAVs first, then uses deterministic layered synthesis, filtered noise, envelopes, and per-cue peak targets instead of one-off broad-spectrum noise bursts.
- Ambient scene beds need extra restraint: keep intentional wind and bird cues, but avoid always-on broad hiss layers and stock MP3 ambience in `main.scene`. `ambient_light_wind.sound` should use the local guarded WAV source, and bird ambience should not carry a continuous synthetic noise bed behind the chirps.
- For ambient beds with obvious loop seams, use `AmbientSound.LoopDurationSeconds` and `LoopOverlapSeconds` on the scene emitter so the next pass starts under the end of the current pass. Keep the values aligned with the source WAV length and guarded by `ambient_noise_audit.ps1`.
- Run `scripts\agents\run_agent_checks.ps1 -Suite sound -ShowInfo` after wiring changes so local wrappers, ambient-noise guards, direct mounted-reference bans, and raw source files stay aligned.

### Attached Held-Item Sounds

**Pattern:** Sounds owned by a player-held item should not be started as bare `Sound.Play(sound, worldPosition)` calls. If the local player moves while a shot, reload, dry-fire click, jammer loop, or throw cue is still audible, a world-position one-shot can sound like it was left behind in the map.

**Workflow:**
- Use `SoundPlayback.PlayAttached` for muzzle, reload, dry-fire, jammer-loop, and throw cues so the `SoundHandle` is parented to the weapon or player object and its position starts at the correct point.
- Keep impact, explosion, bullet-whip, ambient, and UI/hitmarker cues as world or listener sounds; those are intentionally not attached to the shooter.
- Run `scripts\agents\run_agent_checks.ps1 -Suite sound -ShowInfo` after sound-behavior changes. The suite now includes `sound_playback_audit.ps1` for held-item playback routing.

---

Last Updated: June 17, 2026
Version: 1.16 - Added 26.06.17 release-note workflow guidance
