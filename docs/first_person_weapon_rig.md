# First-person weapon rig — anatomy & ABOVE / BELOW status

A first-person weapon in s&box / Source 2 is more than a skeleton. This doc lists the nine
pieces of a complete FPS weapon setup, then maps each one onto where ABOVE / BELOW actually
stands today so the Track 3 viewmodel work has a clear target.

For how the live system is wired, see the `FirstPersonViewmodel` section in
[`CLAUDE.md`](../CLAUDE.md) (the local-only renderer with three render modes: **StockVisible**,
**CustomVisibleStockAnimated**, **StaticFallback**). The short version: we lean on **Facepunch
stock viewmodels** (`v_m4a1`, `v_mp5`, `v_first_person_arms_human`, the grenades) for skeleton +
animation, and optionally show our **custom weapon model** bone-attached to the stock grip bone.

## The nine pieces

### 1. Skeletal mesh
The model that actually contains the bones — first-person arms, hands, the weapon model. The
skeleton lives inside the mesh.

### 2. Bone hierarchy
Properly named, organized bones: `root → wrist → hand → finger bones`, plus weapon-attachment
bones. Without a clean hierarchy, animations can't be reused across weapons.

### 3. Animation clips
The actual motions, usually imported as separate files: idle, walk, sprint, reload, draw/equip,
fire, inspect.

### 4. Animation graph / state machine
The "brain": which clip plays, blending between clips, layering recoil over reloads, sprint
transitions. In s&box this is a `.vanmgrph` driven by parameters.

### 5. Attachment points
Special bones/attachments for muzzle flash, shell ejection, optics, and the left-hand grip.
Common names: `muzzle`, `shell_eject`, `weapon_root`.

### 6. IK targets (very important for FPS)
The off-hand is driven by IK: the right hand attaches to the weapon, the left hand auto-reaches
the foregrip. This is what prevents hand clipping when swapping weapons.

### 7. Animation events
Markers embedded in the clips that tell the game when to act — play reload sound, spawn/eject
magazine, eject shell, trigger muzzle flash — instead of hard-coding timing in C#.

### 8. Viewmodel camera offsets
Weapon position, FOV, sway, bob, recoil. Even a perfectly animated gun looks wrong with a bad
camera setup.

### 9. Weapon rig (separate from arms)
Weapons are often rigged on their own skeleton so parts move:
```
root
├─ weapon
├─ slide
├─ trigger
├─ magazine
├─ bolt
└─ attachments
```
This enables magazine removal, slide/bolt cycling, and attachment animations.

## Where ABOVE / BELOW stands on each

| # | Piece | Status | Notes |
|---|-------|--------|-------|
| 1 | Skeletal mesh | **✅ via Facepunch** | Arms = `v_first_person_arms_human`; weapon skeleton = stock `v_*` viewmodels. Our custom weapon models (`models/weapons/assault_rifle_m4.vmdl`, `smg_mp7.vmdl`, `models/shotgun.vmdl`, `models/jammer_gun.vmdl`) are **static** — they ride the stock skeleton via bone-attach, they don't carry their own. |
| 2 | Bone hierarchy | **N/A for guns (StockVisible); names verified in appendix** | Bone names were enumerated live (see appendix). An attempt to pin `weapon_root` as the attach/anchor bone was **reverted** — it moved the custom mesh out of frame. The guns were then switched to **StockVisible**, which removes the custom bone-attach entirely. Bone resolution now only matters for the jammer (still custom, original `hand_R` attach). |
| 3 | Animation clips | **✅ via Facepunch / ❌ custom** | Stock viewmodels supply idle/deploy/fire/reload/sprint. No project-authored clips. |
| 4 | Animation graph | **✅ via Facepunch** | Stock weapons run `UseAnimGraph`; `UpdateStockAnimParameters` drives `b_attack`/`b_reload`/`ironsights`/`b_sprint`/`b_empty`/`move_*`. We don't own a custom `.vanmgrph`. |
| 5 | Attachment points | **⚠️ muzzle only** | `MuzzleSocket` resolved by AutoWire; anchor search looks for `muzzle`/`barrel`. **No shell-eject or optics attachments.** |
| 6 | IK targets | **⚠️ split** | Third-person: `WeaponPose.ApplyHandPose` → Citizen `IkLeftHand`/`IkRightHand`. First-person: only the **StaticFallback** path runs explicit `SetIk("hand_L"/"hand_R")`; the bone-merged modes trust the stock animation's hands. **Track 3: confirm off-hand grip per weapon.** |
| 7 | Animation events | **❌ code-timed** | Reload sounds/effects are driven by **C# timers** (e.g. `HitscanWeapon` stepped reload SFX), not anim events. Biggest fidelity gap if we move to custom clips. |
| 8 | Camera offsets | **✅ partial** | Per-weapon `[Property]` offsets on `FirstPersonViewmodel` (`StockViewmodelOffset`, `CustomM4/Smg/Shotgun/JammerViewmodelOffset/Rotation/Scale`), sway/bob lerp, ADS blend, and recoil via `GroundPlayerController._recoilOffset`. **FOV/bob tuning still open.** |
| 9 | Weapon rig (moving parts) | **❌ for custom** | Custom weapons are single static meshes — no slide/trigger/magazine/bolt sub-bones. Stock weapons animate their own parts. |

## Minimum viable setup for ABOVE / BELOW

Per the reference, the floor for a custom-rigged weapon is:

1. First-person arms mesh — **have it** (Facepunch).
2. Hand/finger skeleton — **have it** (Facepunch arms).
3. Weapon skeleton (magazine, slide, trigger) — **missing** for custom weapons.
4. Idle animation — have via stock.
5. Fire animation — have via stock.
6. Reload animation — have via stock.
7. Aim (ADS) animation — have via stock (`ironsights`).
8. Muzzle attachment — **have it** (`MuzzleSocket`).
9. Animation graph — have via stock.

So the **practical gap** is items 3 + 9 *for project-authored weapons*: today we get clips/graph
"for free" from Facepunch and bolt our static gun onto that skeleton. That works and is the
pragmatic path — fully custom rigs (own skeleton + clips + animgraph + anim events + moving
parts) are only worth it where the stock skeleton can't sell the weapon.

## Track 3 priorities (derived from the gaps)

1. ~~**Pin bone names** (#2)~~ — **superseded 2026-06-14.** The pin attempt regressed rendering (custom mesh left the frame) and was reverted; switching the guns to StockVisible removed the need entirely (the stock skeleton drives everything). Verified bone names are kept in the appendix for the jammer / future custom rigs.
2. **Per-weapon alignment** (#8) — dial each `Custom*ViewmodelOffset/Rotation/Scale` so the custom model sits exactly on the grip bone.
3. **Off-hand IK pass** (#6) — make sure each weapon's left hand reaches the foregrip without clipping in first person, and seats in the Citizen's hands in third person.
4. ~~**Decide custom-vs-stock per weapon**~~ — **resolved 2026-06-14.** Rifle / SMG / shotgun → **StockVisible** (Facepunch `v_m4a1` / `v_mp5` / `v_spaghellim4` viewmodels — perfectly aligned, fully animated, zero tuning; the custom models remain for the third-person / world weapon). Jammer → **custom** (no stock equivalent); offset/scale tuned to `(5,-5,9)` / `1.4`. Remaining jammer polish: it renders dark (custom-model material — investigate) and wants a forward rotation. This is set in `FirstPersonViewmodel.Items.cs` (per-weapon `RenderMode`).
5. **Later, if going custom:** move sound/effect timing off C# timers onto **animation events** (#7) and rig moving parts (#9: slide/mag/bolt).

## AI-generated asset caveat

If weapons come from AI generation, the bottleneck is almost always **rigging and animation
quality, not the mesh**. A decent model can be fixed; a bad skeleton or bad animations usually
means rebuilding the whole setup. This is exactly why the current system leans on Facepunch
skeletons/animgraphs and only swaps in the custom *mesh* — it sidesteps the riskiest part.

## Appendix — verified Facepunch `v_m4a1` viewmodel bones (2026-06-14)

Enumerated live from the spawned stock driver (`CreateBoneObjects = true`). The same skeleton
backs the other `v_*` stock weapons, so these names are the ones to target.

- **Weapon** (under `weapon_root` → `weapon_root_children`): `weapon_root`, `muzzle`,
  `weapon_IK_hand_R`, `weapon_IK_hand_L`, `stock` (`stock_lever`, `stock_pin`), `trigger`,
  `magazine`, `magazine_release`, `bolt_catch`, `mode_selector`, `bolt_flap`, `bolt`,
  `charging_handle`.
- **Arms** (under `root` → `clavicle_R/L` → `arm_upper_*` → `arm_lower_*` → `hand_R/L`): full
  finger chains `finger_{index,middle,ring,pinky,thumb}_{meta,0,1,2}_{R,L}`, plus `*_twist*`
  control bones and a `camera` bone.

The custom weapon mesh attaches rigidly to `weapon_root`. The weapon carries real moving-part
bones (`trigger`, `magazine`, `bolt`, `charging_handle`) that only a fully custom rig (#9) would
drive — the current static mesh does not.
