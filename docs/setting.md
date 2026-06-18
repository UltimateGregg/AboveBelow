# Setting & Art Direction — Bouneurmaum National Park

> **This is the canonical setting for ABOVE / BELOW.** Every model, material, light, and
> effect should read as one place: a rural national park in daytime. When in doubt about how
> something should look, it should look like it belongs in this park. Treat this doc as the
> source of truth for art direction; link new asset briefs back to it.

## The place

The entire level is set in **Bouneurmaum National Park** — a rural, backcountry national park.
Think pine forest broken by grassland clearings, dirt and gravel service roads, low rolling
hills, and a handful of weathered rural structures connected by trails and park signage. It is
*not* a city, not a military base, not an industrial site. It is a quiet public park that an
incident has spilled into.

The park name is already canon in-project — see the welcome sign
([`docs/assets/briefs/bouneurmaum_park_sign.md`](assets/briefs/bouneurmaum_park_sign.md):
"Welcome to Bouneurmaum National Park").

## Why there's a fight here (light framing)

Keep the fiction light — the art direction matters more than the plot. The framing that ties
the props together: a contested **incident staged in the park**. One side runs drones from a
hasty staging area (the **command tent** is that motif — an incident-response tent dropped into
a clearing), the other moves through the park on the ground. This is what lets deployed
equipment (tents, launch pads, a jammer gun, grenades) read as *plausibly brought into a
civilian park* rather than set-dressing for a generic warzone. Don't escalate it into a
full military installation.

## Time of day, mood, readability

- **Daytime, clear-to-lightly-hazy, warm sun.** This is a competitive shooter first — readability
  beats mood. High-contrast outdoor daylight so soldiers read against terrain from drone height,
  and the drone reads against sky from the ground.
- **Atmospheric depth, not gloom.** A little distance haze over the pines sells the scale and the
  vertical above/below relationship. Avoid dusk/night/fog that would hurt target acquisition.
- Gameplay-readability lights (operator signal lights, launch-pad glow) are allowed to be
  saturated and "gamey" — they are wayfinding, not mood lighting. Keep them visually distinct
  from natural light.

## Palette

- **Naturals dominate:** pine green, grass green, bark and dirt browns, weathered timber, grey
  rock, gravel tan.
- **Park-service accents:** the dark-brown-and-cream of national-park signage (matching the park
  sign), faded ranger greens.
- **Reserve bright/accent colors for gameplay** — team/role signal colors, launch pads, hazard
  markers. Don't spend vivid color on background dressing; the eye should go to players and
  objectives.

## What belongs here

Use this as the shopping list for new environment assets:

- **Terrain & flora:** pines (windswept + broad), grass clumps, shrubs/hedges, oak trees, mossy
  rocks, fallen logs, dirt/gravel roads, worn foot paths, berms.
- **Park infrastructure:** trail signage and the welcome sign, split-rail and iron fences,
  benches, picnic tables, fire rings / camp stoves, trash bins, a water tower, restroom/ranger
  outbuildings, a small visitor structure.
- **Rural structures:** log cabins and weathered rural houses (the existing house assets), barns
  or sheds, a parking pull-off.
- **Incident dressing (sparse):** the staged command tent, drone launch pads, sandbag cover,
  a damaged/abandoned vehicle (the burnt car wreck), crates.

## What to avoid (theme creep)

- Dense urban cityscapes, skyscrapers, storefronts, neon.
- Sci-fi / futuristic surfaces, holograms, clean sci-fi military bases.
- Office/industrial interiors, factories, warehouses.
- Night/horror/post-apocalyptic moods. Wear and weathering are fine; ruin is not the theme.

If an asset would look out of place in a real national park photo, it probably doesn't belong —
or it needs to be reframed as park or incident-response equipment.

## Existing assets that already fit

These shipped before the setting was written down, but they're on-theme — reuse and extend them
rather than inventing parallel props:

`bouneurmaum_park_sign`, `terrain_pine` (windswept/broad), `grass_clump`, `terrain_rock`,
stock foliage (oak, beech bushes/hedges, pine shrubs), `iron_fence`/`fence_panel`,
`old_bench`/`bench_table`, `street_bin_rubbish`, `WaterTower`, `logcabin`,
`House_Large`/`House_Small`/`house_rural`, `large_command_tent`, `burnt_car_wreck`,
`CampStove`, the road/curb/shoulder set.

## How this drives the other work

- **Lighting / post (Track 2):** target a national-park daytime look — warm directional sun, sky
  ambient/fill, light distance haze over the pines. The pass is about *selling the setting*, not
  just adding bloom.
- **VFX (Track 2):** effects should read against foliage and soil — dirt/dust impact puffs on
  ground, wood splinters on cabins/fences, grey smoke for explosions, muzzle flash that pops
  against green. Avoid stylized sci-fi tracers/effects.
- **New models:** every new asset brief should state how the asset fits Bouneurmaum National Park
  and link back to this doc.

## Naming

Keep **ABOVE / BELOW** as the project title and the above/below vertical framing. "Bouneurmaum
National Park" is the *place* the title's conflict happens in — use it for the map/level identity
and signage, not as a rename of the game.
