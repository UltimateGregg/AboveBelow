# Coding Rules for ABOVE / BELOW

## C# Style & S&Box Conventions

### Class Structure
- All game components inherit from Component or PanelComponent
- Use [Property] for inspector-exposed fields
- Use [Sync] for networked properties
- Use private/protected for internal state
- Lifecycle: OnAwake, OnStart, OnUpdate, OnFixedUpdate

### Naming Conventions
- PascalCase for classes, enums, properties (GroundPlayerController, PlayerRole, IsDead)
- camelCase for local variables and private fields
- Prefix private fields with underscore (_playerKills, _cachedValue)

### Comments & Documentation
- Use /// <summary> for public methods
- Document parameters and return values
- Add inline comments for complex logic
- XML doc comments are parsed by IDE

## Networking Rules

### Host-Authority Guard (CRITICAL)
- ALWAYS check if ( !Networking.IsHost ) return; before state mutations
- Only host can modify CurrentHealth, IsDead, PlayerKills, etc.
- Clients receive updates via [Sync] properties only

### [Sync] Properties
- Use for replicated state (health, position, ammo, etc.)
- Automatic serialization by S&Box
- Only changed values sent over network
- Initialize in OnAwake for safety: PropertyName ??= new()

### RPC Methods
- [Rpc.Broadcast] fires on all peers
- Use only for notifications (kill events, round end)
- Never send large data via RPC; use [Sync] instead
- Host applies logic; clients just run callbacks

## Performance Rules

### Scene Queries (Expensive!)
- GetAllComponents<T>() is expensive
- Call once per OnFixedUpdate, not per OnUpdate
- Cache results in local variables
- Don't repeat queries in loops

### Memory & Events
- Unsubscribe from events in OnDestroy
- Subscribe once in OnStart
- Memory leaks if you don't unsubscribe

### GameObject Lookups
- Cache FindByName results in fields
- Don't repeat expensive lookups every frame
- Use IsValid() to check component existence

## Architecture Rules

### Component Ownership
- Each networked object has one owner (Connection)
- Check Network.Owner?.Id == Connection.Local?.Id
- Use IsProxy to detect non-owner instances

### No Player-Facing RPCs
- Don't use RPC for data sync; use [Sync]
- RPCs are for state-less notifications only
- Never replace [Sync] properties with manual RPC updates

### Prefab & Scene Rules
- Reference prefabs via [Property], not hardcoded paths
- Use Scene.FindByName("GameManager") for global objects
- Don't create duplicate GameObjects; use collections
- Never rename public classes/prefabs without discussion

## Testing Rules

Before committing:
- Editor playtest (single player)
- Multiplayer test (2+ clients)
- Check console for errors/warnings
- Verify [Sync] properties replicate
- Test host-authoritative behavior

### Compile Errors
- Always resolve before committing
- Use ?.IsValid() for null-safety checks
- Check S&Box docs for API correctness
- Common issue: missing using Sandbox; statement

## Code Review Checklist

- [ ] Naming conventions followed (PascalCase, camelCase)
- [ ] Has [Title], [Category], [Icon] attributes
- [ ] Public methods have XML doc comments
- [ ] All state mutations guarded with if (!Networking.IsHost) return;
- [ ] All [Sync] properties initialized in OnAwake
- [ ] No scene queries in OnUpdate
- [ ] Event subscriptions unsubscribed in OnDestroy
- [ ] No hardcoded paths
- [ ] Compile warnings resolved
- [ ] Tested in editor playtest
- [ ] Tested in multiplayer

---

Version: 1.0 - S&Box Best Practices
