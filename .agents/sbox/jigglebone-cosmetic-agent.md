# Jigglebone Cosmetic Agent

## Purpose

Guide S&Box cosmetic jigglebone work before it is accepted as a reusable asset pattern.

Use this agent when a cosmetic, backpack, charm, strap, cable, cloth-like prop, antenna, tail, or other skinned attachment needs local bone physics through ModelDoc physics shapes and joints.

## Primary Areas

- `*.blend`
- `Assets/models/**/*.fbx`
- `Assets/models/**/*.vmdl`
- `Assets/materials/**/*.vmat`
- `Assets/prefabs/**/*.prefab`
- `scripts/*_asset_pipeline.json`
- `docs/known_sbox_patterns.md`

## Review Rules

- Start from a skinned cosmetic model bound to the citizen or human skeleton plus extra jiggle bones parented under that skeleton.
- Test as a bone-merged cosmetic on a citizen or human in a simple scene before wiring the asset into game prefabs.
- Keep ModelDoc physics authoring distinct from gameplay collision. Jigglebone `PhysicsShape` nodes simulate in the bone-merged model's local physics environment and are not proof of world collision.
- Add at least one solid attachment shape on a stable body bone such as spine, head, or hand. Jiggle bones without a valid joint/attachment can fall away during playtest.
- Put primitive physics shapes on every simulated jiggle bone. Prefer box, sphere, or capsule shapes; use hull collision only with a specific reason.
- Choose joints by desired motion: conical for hanging swing with limit control, weld for configurable position and rotation stiffness, spherical for fully floppy motion that relies on collision.
- Reposition joint anchors to the intended pivot point. Do not trust the default joint origin if it lands at the parent body's center.
- If twist or swing limits are enabled, use nonzero values; zeroed limits do not produce the intended clamp behavior.
- For weld joints, tune linear and angular behavior separately. Higher position frequency keeps the bone close to its attachment; lower frequency feels weaker; higher damping lags and reduces spring.
- Verify with a real editor playtest using animation or parameter changes that move the citizen or human body. Static ModelDoc inspection is not enough.

## Evidence Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite modeldoc
powershell -ExecutionPolicy Bypass -File scripts/agents/run_agent_checks.ps1 -Suite asset-production
powershell -ExecutionPolicy Bypass -File scripts/agents/prefab_graph_audit.ps1
```

After the static checks, open a simple editor scene with a citizen or human and the cosmetic bone-merged to that body. Play the scene, drive an animation or body parameter, and watch every jiggle bone for pivot drift, falling, over-stretching, excessive collision, and material fallback.

## Output Shape

Report the skeleton/bone-merge setup, each simulated bone, each physics shape, each joint type, and the playtest motion used. Separate local jigglebone simulation proof from world-collision, prefab wiring, and multiplayer validation.
