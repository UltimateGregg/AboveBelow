#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/markers/player_spawn_soldier.prefab",
    componentType: "DroneVsPlayers.PlayerSpawn",
    roleProperty: "Role",
    expectedRole: "Soldier",
  },
  {
    path: "Assets/prefabs/markers/player_spawn_pilot.prefab",
    componentType: "DroneVsPlayers.PlayerSpawn",
    roleProperty: "Role",
    expectedRole: "Pilot",
  },
  {
    path: "Assets/prefabs/markers/training_dummy_spawn.prefab",
    componentType: "DroneVsPlayers.TrainingDummySpawn",
    roleProperty: "PreferredRole",
    expectedRole: "Spectator",
  },
];

const args = process.argv.slice(2);
let root = process.cwd();
let dryRun = false;

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === "--root") {
    root = path.resolve(args[++i]);
  } else if (arg === "--dry-run") {
    dryRun = true;
  }
}

function stableGuid(seed) {
  const hex = crypto.createHash("sha1").update(seed).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function prefabInstancePath(template) {
  return template.path.replace(/^Assets\//, "");
}

function objectIdentifier(type, idValue) {
  return { Type: type, IdValue: idValue };
}

function collectPrefabIds(prefabObject, sourceObject, mapping, seed) {
  mapping[prefabObject.__guid] = sourceObject?.__guid || stableGuid(`${seed}:object:${prefabObject.__guid}`);

  const sourceComponentsByType = new Map();
  for (const component of sourceObject?.Components || []) {
    const type = component.__type || "";
    if (!sourceComponentsByType.has(type)) {
      sourceComponentsByType.set(type, []);
    }
    sourceComponentsByType.get(type).push(component);
  }

  for (const component of prefabObject.Components || []) {
    const candidates = sourceComponentsByType.get(component.__type || "") || [];
    const sourceComponent = candidates.shift();
    mapping[component.__guid] = sourceComponent?.__guid || stableGuid(`${seed}:component:${component.__guid}`);
  }

  const sourceChildren = sourceObject?.Children || [];
  for (let i = 0; i < (prefabObject.Children || []).length; i += 1) {
    collectPrefabIds(prefabObject.Children[i], sourceChildren[i], mapping, `${seed}:child:${i}`);
  }
}

function addPropertyOverride(overrides, type, idValue, property, value) {
  overrides.push({
    Target: objectIdentifier(type, idValue),
    Property: property,
    Value: value,
  });
}

function addRootOverrides(overrides, source, prefabRoot) {
  const ignored = new Set(["__guid", "__version", "Components", "Children"]);
  for (const [key, value] of Object.entries(source)) {
    if (ignored.has(key)) {
      continue;
    }

    if (!deepEqual(value, prefabRoot[key])) {
      addPropertyOverride(overrides, "GameObject", prefabRoot.__guid, key, value);
    }
  }
}

function addComponentOverrides(overrides, source, prefabRoot) {
  const sourceComponentsByType = new Map();
  for (const component of source.Components || []) {
    const type = component.__type || "";
    if (!sourceComponentsByType.has(type)) {
      sourceComponentsByType.set(type, []);
    }
    sourceComponentsByType.get(type).push(component);
  }

  for (const prefabComponent of prefabRoot.Components || []) {
    const candidates = sourceComponentsByType.get(prefabComponent.__type || "") || [];
    const sourceComponent = candidates.shift();
    if (!sourceComponent) {
      continue;
    }

    for (const [key, value] of Object.entries(sourceComponent)) {
      if (key === "__guid" || key === "__type") {
        continue;
      }

      if (!deepEqual(value, prefabComponent[key])) {
        addPropertyOverride(overrides, "Component", prefabComponent.__guid, key, value);
      }
    }
  }
}

function findTemplateForObject(node) {
  if (node.__Prefab) {
    return null;
  }

  for (const component of node.Components || []) {
    for (const template of templates) {
      if (component.__type === template.componentType && component[template.roleProperty] === template.expectedRole) {
        return template;
      }
    }
  }

  return null;
}

function toPrefabInstance(source, template, prefab) {
  if ((source.Children || []).length > 0) {
    throw new Error(`${source.Name} has child objects; refusing to collapse it into a marker prefab instance.`);
  }

  const prefabRoot = prefab.RootObject;
  const mapping = {};
  collectPrefabIds(prefabRoot, source, mapping, source.__guid);

  const overrides = [];
  addRootOverrides(overrides, source, prefabRoot);
  addComponentOverrides(overrides, source, prefabRoot);

  return {
    __guid: source.__guid,
    __version: 2,
    __Prefab: prefabInstancePath(template),
    __PrefabInstancePatch: {
      AddedObjects: [],
      RemovedObjects: [],
      PropertyOverrides: overrides,
      MovedObjects: [],
    },
    __PrefabIdToInstanceId: mapping,
  };
}

function migrateArray(objects, prefabByPath, stats) {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const template = findTemplateForObject(node);
    if (template) {
      objects[i] = toPrefabInstance(node, template, prefabByPath.get(template.path));
      stats.migrated += 1;
      stats.byPrefab.set(template.path, (stats.byPrefab.get(template.path) || 0) + 1);
      continue;
    }

    migrateArray(node.Children || [], prefabByPath, stats);
  }
}

const scenePath = path.join(root, "Assets/scenes/main.scene");
const scene = JSON.parse(fs.readFileSync(scenePath, "utf8"));
const prefabByPath = new Map();

for (const template of templates) {
  prefabByPath.set(template.path, readJson(template.path));
}

const stats = { migrated: 0, byPrefab: new Map() };
migrateArray(scene.GameObjects || [], prefabByPath, stats);

if (!dryRun && stats.migrated > 0) {
  fs.writeFileSync(scenePath, `${JSON.stringify(scene, null, 2)}\n`);
}

const action = dryRun ? "Would migrate" : "Migrated";
console.log(`${action} ${stats.migrated} scene marker placement(s) to prefab instances.`);
for (const [prefabPath, count] of Array.from(stats.byPrefab.entries()).sort((a, b) => a[0].localeCompare(b[0]))) {
  console.log(` - ${count} ${prefabPath}`);
}
