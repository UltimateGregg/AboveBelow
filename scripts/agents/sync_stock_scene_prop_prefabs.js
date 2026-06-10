#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/environment/stock/beech_shrub_wide_small.prefab",
    rootName: "BeechShrubWideSmall",
    model: "models/sbox_props/shrubs/beech/beech_shrub_wide_small.vmdl",
    kind: "visual",
  },
  {
    path: "Assets/prefabs/environment/stock/pine_shrub_tall_b.prefab",
    rootName: "PineShrubTallB",
    model: "models/sbox_props/shrubs/pine/pine_shrub_tall_b.vmdl",
    kind: "visual",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_medium_wall.prefab",
    rootName: "BeechBushMediumWall",
    model: "models/sbox_props/shrubs/beech/beech_bush_medium_wall.vmdl",
    kind: "visual",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_regular_medium_b.prefab",
    rootName: "BeechBushRegularMediumB",
    model: "models/sbox_props/shrubs/beech/beech_bush_regular_medium_b.vmdl",
    kind: "visual",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_hedge_96x128_corner.prefab",
    rootName: "BeechHedge96x128Corner",
    model: "models/sbox_props/shrubs/beech/beech_hedge_96x128_corner.vmdl",
    kind: "prop",
    health: 0,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/beech_hedge_40x128.prefab",
    rootName: "BeechHedge40x128",
    model: "models/sbox_props/shrubs/beech/beech_hedge_40x128.vmdl",
    kind: "prop",
    health: 0,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large.prefab",
    rootName: "FencePanelLarge",
    model: "models/props/temporary_fencing/fence_panel_large.vmdl",
    kind: "prop",
    health: 100,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large_bent.prefab",
    rootName: "FencePanelLargeBent",
    model: "models/props/temporary_fencing/fence_panel_large_bent.vmdl",
    kind: "prop",
    health: 0,
    mass: 10,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/bench_table_01.prefab",
    rootName: "BenchTable01",
    model: "models/props/trim_sheets/bench/bench_table/bench_table_01.vmdl",
    kind: "prop",
    health: 0,
    mass: 95,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/old_bench.prefab",
    rootName: "OldBench",
    model: "models/sbox_props/benches/old_bench.vmdl",
    kind: "prop",
    health: 100,
    mass: 90,
    impactDamage: 100,
    minImpactDamageSpeed: 1100,
  },
  {
    path: "Assets/prefabs/environment/stock/iron_fence_128.prefab",
    rootName: "IronFence128",
    model: "models/sbox_props/iron_fence/iron_fence_128.vmdl",
    kind: "prop",
    health: 100,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/tree_oak_big_a.prefab",
    rootName: "TreeOakBigA",
    model: "models/sbox_props/trees/oak/tree_oak_big_a.vmdl",
    kind: "prop",
    health: 0,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
  {
    path: "Assets/prefabs/environment/stock/street_bin_rubbish.prefab",
    rootName: "StreetBinRubbish",
    model: "models/sbox_props/bin/street_bin_rubbish.vmdl",
    kind: "prop",
    health: 0,
    mass: 0,
    impactDamage: 0,
    minImpactDamageSpeed: 500,
  },
];

const args = process.argv.slice(2);
let root = process.cwd();
let check = false;

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === "--root") {
    root = path.resolve(args[++i]);
  } else if (arg === "--check") {
    check = true;
  }
}

function stableGuid(seed) {
  const hex = crypto.createHash("sha1").update(seed).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function baseObject(template) {
  return {
    __guid: stableGuid(`${template.path}:root`),
    __version: 2,
    Flags: 0,
    Name: template.rootName,
    Position: "0,0,0",
    Rotation: "0,0,0,1",
    Scale: "1,1,1",
    Tags: "",
    Enabled: true,
    NetworkMode: 2,
    NetworkFlags: 0,
    NetworkOrphaned: 0,
    NetworkTransmit: true,
    OwnerTransfer: 1,
    Components: [],
    Children: [],
  };
}

function modelRenderer(template) {
  return {
    __type: "Sandbox.ModelRenderer",
    __guid: stableGuid(`${template.path}:renderer`),
    __enabled: true,
    Flags: 0,
    BodyGroups: 18446744073709552000,
    CreateAttachments: false,
    LodOverride: null,
    MaterialGroup: null,
    MaterialOverride: null,
    Materials: null,
    Model: template.model,
    OnComponentDestroy: null,
    OnComponentDisabled: null,
    OnComponentEnabled: null,
    OnComponentFixedUpdate: null,
    OnComponentStart: null,
    OnComponentUpdate: null,
    RenderOptions: {
      GameLayer: true,
      OverlayLayer: false,
      BloomLayer: false,
      AfterUILayer: false,
    },
    RenderType: "On",
    Tint: "1,1,1,1",
  };
}

function prop(template) {
  return {
    __type: "Sandbox.Prop",
    __guid: stableGuid(`${template.path}:prop`),
    __enabled: true,
    Flags: 0,
    BodyGroups: 18446744073709552000,
    Health: template.health,
    IsStatic: false,
    MaterialGroup: null,
    Model: template.model,
    OnComponentDestroy: null,
    OnComponentDisabled: null,
    OnComponentEnabled: null,
    OnComponentFixedUpdate: null,
    OnComponentStart: null,
    OnComponentUpdate: null,
    OnPropBreak: null,
    OnPropTakeDamage: null,
    StartAsleep: false,
    Tint: "1,1,1,1",
  };
}

function modelCollider(template) {
  return {
    __type: "Sandbox.ModelCollider",
    __guid: stableGuid(`${template.path}:collider`),
    __enabled: true,
    Flags: 0,
    ColliderFlags: 0,
    Elasticity: null,
    Friction: null,
    IsTrigger: false,
    Model: template.model,
    OnComponentDestroy: null,
    OnComponentDisabled: null,
    OnComponentEnabled: null,
    OnComponentFixedUpdate: null,
    OnComponentStart: null,
    OnComponentUpdate: null,
    OnObjectTriggerEnter: null,
    OnObjectTriggerExit: null,
    OnTriggerEnter: null,
    OnTriggerExit: null,
    RollingResistance: null,
    Static: false,
    Surface: null,
    SurfaceVelocity: "0,0,0",
  };
}

function rigidbody(template) {
  return {
    __type: "Sandbox.Rigidbody",
    __guid: stableGuid(`${template.path}:rigidbody`),
    __enabled: true,
    Flags: 0,
    AngularDamping: 0,
    EnableImpactDamage: true,
    EnhancedCcd: false,
    Gravity: true,
    GravityScale: 1,
    ImpactDamage: template.impactDamage,
    LinearDamping: 0,
    Locking: {
      X: false,
      Y: false,
      Z: false,
      Pitch: false,
      Yaw: false,
      Roll: false,
    },
    MassCenterOverride: "0,0,0",
    MassOverride: template.mass,
    MinImpactDamageSpeed: template.minImpactDamageSpeed,
    MotionEnabled: true,
    OnComponentDestroy: null,
    OnComponentDisabled: null,
    OnComponentEnabled: null,
    OnComponentFixedUpdate: null,
    OnComponentStart: null,
    OnComponentUpdate: null,
    OverrideMassCenter: false,
    RigidbodyFlags: 0,
    SleepThreshold: 2,
    StartAsleep: false,
  };
}

function buildPrefab(template) {
  const rootObject = baseObject(template);
  if (template.kind === "prop") {
    rootObject.Components.push(prop(template));
  }

  rootObject.Components.push(modelRenderer(template));

  if (template.kind === "prop") {
    rootObject.Components.push(modelCollider(template));
    rootObject.Components.push(rigidbody(template));
  }

  return {
    RootObject: rootObject,
    ResourceVersion: 3,
  };
}

function serialize(prefab) {
  return `${JSON.stringify(prefab, null, 2)}\n`;
}

const changed = [];
for (const template of templates) {
  const absolutePath = path.join(root, template.path);
  const next = serialize(buildPrefab(template));
  const current = fs.existsSync(absolutePath) ? fs.readFileSync(absolutePath, "utf8") : "";
  if (current !== next) {
    changed.push(template.path);
    if (!check) {
      fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
      fs.writeFileSync(absolutePath, next);
    }
  }
}

if (check) {
  if (changed.length > 0) {
    console.error("Stock scene prop prefab templates are out of sync:");
    for (const file of changed) {
      console.error(` - ${file}`);
    }
    process.exit(1);
  }
  console.log(`Stock scene prop prefab templates are in sync (${templates.length} templates).`);
} else {
  console.log(`Synced ${templates.length} stock scene prop prefab template(s).`);
}
