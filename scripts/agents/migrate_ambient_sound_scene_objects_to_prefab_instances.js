#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const template = {
  path: "Assets/prefabs/environment/ambient_sound_point.prefab",
  rootName: "AmbientSoundPoint",
  sourceName: "AmbientLightWind",
  matchNames: [
    "AmbientLightWind",
    "AmbientBirdsChirping",
    "AmbientBirdsCanopyFar",
    "AmbientCrowsDistant",
  ],
  menuPath: "Drone vs Players/Environment/AmbientSoundPoint",
  menuIcon: "volume_up",
};

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

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function stringifyJson(value) {
  return `${JSON.stringify(value, null, 2).replace(/\b18446744073709552000\b/g, "18446744073709551615")}\n`;
}

function writeJson(relativePath, value) {
  fs.mkdirSync(path.dirname(path.join(root, relativePath)), { recursive: true });
  fs.writeFileSync(path.join(root, relativePath), stringifyJson(value));
}

function exists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function componentType(component) {
  return component.__type || component.Type || "";
}

function prefabInstancePath() {
  return template.path.replace(/^Assets\//, "");
}

function objectIdentifier(type, idValue) {
  return { Type: type, IdValue: idValue };
}

function addPropertyOverride(overrides, type, idValue, property, value) {
  overrides.push({
    Target: objectIdentifier(type, idValue),
    Property: property,
    Value: value,
  });
}

function cloneForPrefab(source, scenePath) {
  const rootObject = clone(source);
  rootObject.__guid = stableGuid(`${template.path}:object:${scenePath}`);
  rootObject.__version = rootObject.__version || 2;
  rootObject.Name = template.rootName;
  rootObject.Position = "0,0,0";
  rootObject.Rotation = "0,0,0,1";
  rootObject.Scale = "1,1,1";
  rootObject.Children = [];
  rootObject.Components = (source.Components || []).map((component, index) => {
    const componentClone = clone(component);
    componentClone.__guid = stableGuid(`${template.path}:component:${scenePath}:${index}:${componentType(component)}`);
    return componentClone;
  });

  return {
    RootObject: rootObject,
    ShowInMenu: false,
    MenuPath: template.menuPath,
    MenuIcon: template.menuIcon,
    DontBreakAsTemplate: false,
    ResourceVersion: 1,
    __references: [],
    __version: 1,
  };
}

function componentsByType(components) {
  const byType = new Map();
  for (const component of components || []) {
    const type = componentType(component);
    if (!byType.has(type)) {
      byType.set(type, []);
    }
    byType.get(type).push(component);
  }
  return byType;
}

function collectPrefabIds(prefabObject, sourceObject, mapping, seed) {
  mapping[prefabObject.__guid] = sourceObject?.__guid || stableGuid(`${seed}:object:${prefabObject.__guid}`);

  const sourceComponentsByType = componentsByType(sourceObject?.Components || []);
  for (const component of prefabObject.Components || []) {
    const candidates = sourceComponentsByType.get(componentType(component)) || [];
    const sourceComponent = candidates.shift();
    mapping[component.__guid] = sourceComponent?.__guid || stableGuid(`${seed}:component:${component.__guid}`);
  }
}

function addObjectOverrides(overrides, source, prefabObject) {
  const ignored = new Set(["__guid", "__version", "Components", "Children"]);
  for (const [key, value] of Object.entries(source)) {
    if (ignored.has(key)) {
      continue;
    }

    if (!deepEqual(value, prefabObject[key])) {
      addPropertyOverride(overrides, "GameObject", prefabObject.__guid, key, value);
    }
  }
}

function addComponentOverrides(overrides, source, prefabObject) {
  const sourceComponentsByType = componentsByType(source.Components || []);
  for (const prefabComponent of prefabObject.Components || []) {
    const candidates = sourceComponentsByType.get(componentType(prefabComponent)) || [];
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

function shapeProblems(source, prefabObject, scenePath) {
  const problems = [];
  if ((source.Children || []).length !== (prefabObject.Children || []).length) {
    problems.push(`${scenePath} child count ${(source.Children || []).length} does not match prefab child count ${(prefabObject.Children || []).length}`);
  }

  const sourceTypes = (source.Components || []).map(componentType).sort();
  const prefabTypes = (prefabObject.Components || []).map(componentType).sort();
  if (!deepEqual(sourceTypes, prefabTypes)) {
    problems.push(`${scenePath} component types ${sourceTypes.join(",")} do not match prefab component types ${prefabTypes.join(",")}`);
  }

  return problems;
}

function toPrefabInstance(source, prefab, scenePath) {
  const prefabRoot = prefab.RootObject;
  const problems = shapeProblems(source, prefabRoot, scenePath);
  if (problems.length > 0) {
    return { skipped: problems };
  }

  const mapping = {};
  collectPrefabIds(prefabRoot, source, mapping, source.__guid);

  const overrides = [];
  addObjectOverrides(overrides, source, prefabRoot);
  addComponentOverrides(overrides, source, prefabRoot);

  return {
    node: {
      __guid: source.__guid,
      __version: 2,
      __Prefab: prefabInstancePath(),
      __PrefabInstancePatch: {
        AddedObjects: [],
        RemovedObjects: [],
        PropertyOverrides: overrides,
        MovedObjects: [],
      },
      __PrefabIdToInstanceId: mapping,
    },
  };
}

function findDirectObject(objects, name, scenePath = "") {
  for (const node of objects || []) {
    const currentPath = scenePath ? `${scenePath}/${node.Name || "(unnamed)"}` : (node.Name || "(unnamed)");
    if (!node.__Prefab && node.Name === name) {
      return { node, scenePath: currentPath };
    }

    const found = findDirectObject(node.Children || [], name, currentPath);
    if (found) {
      return found;
    }
  }

  return null;
}

function migrateArray(objects, prefab, stats, scenePath = "") {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const currentPath = scenePath ? `${scenePath}/${node.Name || "(unnamed)"}` : (node.Name || "(unnamed)");
    if (template.matchNames.includes(node.Name || "") && !node.__Prefab) {
      const result = toPrefabInstance(node, prefab, currentPath);
      if (result.node) {
        objects[i] = result.node;
        stats.migrated += 1;
      } else {
        stats.skipped.push(...result.skipped);
      }
      continue;
    }

    migrateArray(node.Children || [], prefab, stats, currentPath);
  }
}

const scenePath = "Assets/scenes/main.scene";
const scene = readJson(scenePath);
let prefab;
let createdPrefab = false;

if (exists(template.path)) {
  prefab = readJson(template.path);
} else {
  const source = findDirectObject(scene.GameObjects || [], template.sourceName);
  if (!source) {
    throw new Error(`Cannot create ${template.path}; source object ${template.sourceName} was not found as a direct scene object.`);
  }

  prefab = cloneForPrefab(source.node, source.scenePath);
  createdPrefab = true;
}

const stats = { migrated: 0, skipped: [] };
migrateArray(scene.GameObjects || [], prefab, stats);

if (!dryRun) {
  if (createdPrefab) {
    writeJson(template.path, prefab);
  }

  if (stats.migrated > 0) {
    writeJson(scenePath, scene);
  }
}

const action = dryRun ? "Would migrate" : "Migrated";
const createAction = dryRun ? "Would create" : "Created";
console.log(`${createAction} ${createdPrefab ? 1 : 0} ambient sound prefab(s).`);
if (createdPrefab) {
  console.log(` - ${template.path}`);
}
console.log(`${action} ${stats.migrated} ambient sound scene placement(s) to prefab instances.`);
if (stats.migrated > 0) {
  console.log(` - ${stats.migrated} ${template.path}`);
}

if (stats.skipped.length > 0) {
  console.log(`Skipped ${stats.skipped.length} ambient sound placement problem(s).`);
  for (const skipped of stats.skipped) {
    console.log(` - ${skipped}`);
  }
  process.exitCode = 1;
}
