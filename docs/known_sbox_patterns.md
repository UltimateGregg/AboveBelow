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

---

Last Updated: May 6, 2026
Version: 1.0 - Standardized Patterns
