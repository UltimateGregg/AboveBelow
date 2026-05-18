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

### ModelRenderer Material Overrides

**Pattern:** Renderer-level `MaterialOverride` paths are reliable for single-material blockout props and playtest spot checks. They are unsafe as a durable fix for multi-material foliage: overriding the renderer can collapse bark and foliage card slots to one material. Generated ModelDoc material remaps may compile down to `materials/default.vmat` if the model compiler does not match the source FBX material names exactly.

**Workflow:**
- For quick visible in-game texture validation on a single-material prop, put an explicit `MaterialOverride` on the `ModelRenderer`.
- For multi-material foliage, fix the Blender material names, exported FBX slots, asset config, and `.vmdl` remaps instead of adding scene `MaterialOverride` or `Materials.indexed`.
- For live editor scenes, set the override on the currently loaded object with the bridge and then save only after confirming no runtime transform drift is being persisted.
- Check the live component with `component_get` and expect `MaterialOverride` to show as `Material:<name>` when the override is loaded.

### Held-Item Slot Visibility

**Pattern:** Every visible held-item renderer needs to be hidden at the item root when its loadout slot is not selected. Hiding only a named visual child can leave extra mesh children visible or casting shadows.

**Workflow:**
- Soldier classes keep primary weapons in slot 1 and grenades/equipment in slot 2.
- Pilot ground avatars currently keep the drone controller/deployer in slot 1 and the MP7 in slot 2.
- Held-item components should call the shared `WeaponPose.SetVisibility(GameObject, selected)` root helper when stowed.
- Run `.\scripts\check_loadout_slots.ps1` after prefab slot edits to catch duplicate or reversed slot assignments before playtesting.

### MCP Component Value Conversion

**Pattern:** MCP `component_set` must know how to parse every simple inspector value type it edits. Missing converters can make a property look editable in the inspector but fail through automation.

**Workflow:**
- `Vector2`, `Vector3`, `Angles`, `Color`, primitive values, models, and materials should be supported by the MCP component setter.
- If an editor property fails with an invalid cast, add the converter in `Libraries/jtc.mcp-server/Editor/Handlers/ComponentHandler.cs` before working around it manually.

### Authored Prop Collision Alignment

**Pattern:** A prop can look correctly rotated while its collision still uses an older transform if the visible `Visual` child is rotated locally and sibling `Collision_*` children remain unrotated. The water tower reproduced this: the rendered mesh had the new yaw, but tank/platform/leg collision still lived under the parent root's old yaw.

**Workflow:**
- Keep visible mesh, solid collision, ladder triggers, and helper volumes under a shared prop root.
- Rotate or move the prop root for scene placement. Do not rotate the `Visual` child to orient a prop that has sibling `Collision_*` children.
- For open-base props like the water tower, do not fill empty visual space with broad frame wall colliders. Keep tank/platform/legs solid, keep ladder volumes as triggers, and only add narrow brace collision when it matches visible geometry.
- For climbable props, keep ladder volumes as trigger colliders with `LadderVolume`; keep physical blockers as non-trigger `BoxCollider` children.
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
- Run `scripts\agents\run_agent_checks.ps1 -Suite sound -ShowInfo` after wiring changes so local wrappers, direct mounted-reference bans, and raw source files stay aligned.

### Attached Held-Item Sounds

**Pattern:** Sounds owned by a player-held item should not be started as bare `Sound.Play(sound, worldPosition)` calls. If the local player moves while a shot, reload, dry-fire click, jammer loop, or throw cue is still audible, a world-position one-shot can sound like it was left behind in the map.

**Workflow:**
- Use `SoundPlayback.PlayAttached` for muzzle, reload, dry-fire, jammer-loop, and throw cues so the `SoundHandle` is parented to the weapon or player object and its position starts at the correct point.
- Keep impact, explosion, bullet-whip, ambient, and UI/hitmarker cues as world or listener sounds; those are intentionally not attached to the shooter.
- Run `scripts\agents\run_agent_checks.ps1 -Suite sound -ShowInfo` after sound-behavior changes. The suite now includes `sound_playback_audit.ps1` for held-item playback routing.

---

Last Updated: May 18, 2026
Version: 1.7 - Added host-authoritative hitscan and code-driven child object guidance
