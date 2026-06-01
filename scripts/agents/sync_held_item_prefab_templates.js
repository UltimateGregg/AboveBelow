#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const heldItemTemplates = [
  {
    label: "Assault Rifle M4",
    source: "Assets/prefabs/soldier_assault.prefab",
    sourcePath: ["Body", "Weapon"],
    target: "Assets/prefabs/items/assault_rifle_m4_held.prefab",
    menuIcon: "my_location"
  },
  {
    label: "SMG MP7",
    source: "Assets/prefabs/pilot_ground.prefab",
    sourcePath: ["Body", "Weapon"],
    target: "Assets/prefabs/items/smg_mp7_held.prefab",
    menuIcon: "speed"
  },
  {
    label: "Shotgun",
    source: "Assets/prefabs/soldier_heavy.prefab",
    sourcePath: ["Body", "Weapon"],
    target: "Assets/prefabs/items/shotgun_held.prefab",
    menuIcon: "police"
  },
  {
    label: "Drone Jammer",
    source: "Assets/prefabs/soldier_counter_uav.prefab",
    sourcePath: ["Body", "Weapon"],
    target: "Assets/prefabs/items/drone_jammer_held.prefab",
    menuIcon: "wifi_tethering_off"
  },
  {
    label: "Chaff Grenade",
    source: "Assets/prefabs/soldier_assault.prefab",
    sourcePath: ["Body", "Grenade"],
    target: "Assets/prefabs/items/chaff_grenade_held.prefab",
    menuIcon: "blur_on"
  },
  {
    label: "Frag Grenade",
    source: "Assets/prefabs/soldier_counter_uav.prefab",
    sourcePath: ["Body", "Grenade"],
    target: "Assets/prefabs/items/frag_grenade_held.prefab",
    menuIcon: "scatter_plot"
  },
  {
    label: "EMP Grenade",
    source: "Assets/prefabs/soldier_heavy.prefab",
    sourcePath: ["Body", "Grenade"],
    target: "Assets/prefabs/items/emp_grenade_held.prefab",
    menuIcon: "bolt"
  },
  {
    label: "Pilot Drone Deployer",
    source: "Assets/prefabs/pilot_ground.prefab",
    sourcePath: ["Body", "DroneDeployer"],
    target: "Assets/prefabs/items/pilot_drone_deployer_held.prefab",
    menuIcon: "settings_remote"
  }
];

function parseArgs(argv) {
  const args = { root: "", check: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-Root" && i + 1 < argv.length) {
      args.root = argv[++i];
    } else if (arg === "-Check") {
      args.check = true;
    }
  }
  return args;
}

function findProjectRoot(start) {
  let current = path.resolve(start || process.cwd());
  if (fs.existsSync(current) && !fs.statSync(current).isDirectory()) {
    current = path.dirname(current);
  }

  while (true) {
    if (fs.existsSync(path.join(current, "dronevsplayers.sbproj"))) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`Could not find S&Box project root from '${start || process.cwd()}'.`);
    }
    current = parent;
  }
}

function readJson(root, relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function findChild(node, name) {
  return (node.Children || []).find((child) => child.Name === name) || null;
}

function findDescendantPath(rootObject, parts) {
  let current = rootObject;
  for (const part of parts) {
    current = findChild(current, part);
    if (!current) return null;
  }
  return current;
}

function walk(node, visitor) {
  if (!node) return;
  visitor(node);
  for (const child of node.Children || []) {
    walk(child, visitor);
  }
}

function deterministicGuid(seed) {
  const hex = crypto.createHash("md5").update(seed).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function remapGuids(rootObject, targetPath) {
  const map = new Map();

  walk(rootObject, (node) => {
    if (node.__guid && !map.has(node.__guid)) {
      map.set(node.__guid, deterministicGuid(`${targetPath}:${node.__guid}`));
    }
    for (const component of node.Components || []) {
      if (component.__guid && !map.has(component.__guid)) {
        map.set(component.__guid, deterministicGuid(`${targetPath}:${component.__guid}`));
      }
    }
  });

  function remapValue(value) {
    if (Array.isArray(value)) {
      for (const entry of value) remapValue(entry);
      return;
    }
    if (!value || typeof value !== "object") return;

    for (const [key, current] of Object.entries(value)) {
      if ((key === "__guid" || key === "go" || key === "component_id") && map.has(current)) {
        value[key] = map.get(current);
      } else {
        remapValue(current);
      }
    }
  }

  remapValue(rootObject);
}

function ensureStandaloneRoot(rootObject) {
  if (rootObject.NetworkMode === undefined) {
    rootObject.NetworkMode = 0;
  }
  if (rootObject.__variables === undefined) {
    rootObject.__variables = [];
  }
  if (rootObject.__properties === undefined) {
    rootObject.__properties = {
      FixedUpdateFrequency: 50,
      MaxFixedUpdates: 5,
      NetworkFrequency: 30,
      NetworkInterpolation: true,
      PhysicsSubSteps: 1,
      ThreadedAnimation: true,
      TimeScale: 1,
      UseFixedUpdate: true,
      Metadata: {}
    };
  }
}

function buildPrefab(root, spec) {
  const source = readJson(root, spec.source);
  const sourceNode = findDescendantPath(source.RootObject, spec.sourcePath);
  if (!sourceNode) {
    throw new Error(`Could not find ${spec.source}:${spec.sourcePath.join("/")}`);
  }

  const rootObject = JSON.parse(JSON.stringify(sourceNode));
  remapGuids(rootObject, spec.target);
  ensureStandaloneRoot(rootObject);

  return {
    RootObject: rootObject,
    ShowInMenu: true,
    MenuPath: `Drone vs Players/Held Items/${spec.label}`,
    MenuIcon: spec.menuIcon,
    DontBreakAsTemplate: false,
    ResourceVersion: 1,
    __references: [],
    __version: 1
  };
}

function normalizeNewlines(text) {
  return text.replace(/\r\n/g, "\n");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = findProjectRoot(args.root || process.cwd());
  const changed = [];

  for (const spec of heldItemTemplates) {
    const prefab = buildPrefab(root, spec);
    const output = `${JSON.stringify(prefab, null, 2)}\n`;
    const targetFullPath = path.join(root, spec.target);
    const existing = fs.existsSync(targetFullPath)
      ? normalizeNewlines(fs.readFileSync(targetFullPath, "utf8"))
      : null;

    if (existing !== normalizeNewlines(output)) {
      changed.push(spec.target);
      if (!args.check) {
        fs.mkdirSync(path.dirname(targetFullPath), { recursive: true });
        fs.writeFileSync(targetFullPath, output, "utf8");
      }
    }
  }

  if (args.check) {
    if (changed.length > 0) {
      console.log("Held-item prefab templates are out of sync:");
      for (const target of changed) console.log(` - ${target}`);
      process.exit(1);
    }

    console.log(`Held-item prefab templates are in sync (${heldItemTemplates.length} templates).`);
    return;
  }

  if (changed.length === 0) {
    console.log(`Held-item prefab templates already up to date (${heldItemTemplates.length} templates).`);
    return;
  }

  console.log("Wrote held-item prefab templates:");
  for (const target of changed) console.log(` - ${target}`);
}

main();
