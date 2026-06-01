#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const prefabProperties = {
  FixedUpdateFrequency: 50,
  MaxFixedUpdates: 5,
  NetworkFrequency: 30,
  NetworkInterpolation: true,
  PhysicsSubSteps: 1,
  ThreadedAnimation: true,
  TimeScale: 1,
  UseFixedUpdate: true,
  Metadata: {},
};

const templates = [
  {
    path: "Assets/prefabs/environment/house_large_playable.prefab",
    rootName: "HouseLargePlayable",
    sourceName: "House_Large_01",
    matchNames: ["House_Large_01", "House_Large_02"],
    menuPath: "Drone vs Players/Environment/HouseLargePlayable",
    menuIcon: "home",
  },
  {
    path: "Assets/prefabs/environment/house_small_playable.prefab",
    rootName: "HouseSmallPlayable",
    sourceName: "House_Small_02",
    matchNames: ["House_Small_02", "House_Small_03"],
    menuPath: "Drone vs Players/Environment/HouseSmallPlayable",
    menuIcon: "home",
  },
  {
    path: "Assets/prefabs/environment/house_small_collision_playable.prefab",
    rootName: "HouseSmallCollisionPlayable",
    sourceName: "House_Small_01",
    matchNames: ["House_Small_01", "House_Small_04"],
    menuPath: "Drone vs Players/Environment/HouseSmallCollisionPlayable",
    menuIcon: "home",
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

function prefabInstancePath(template) {
  return template.path.replace(/^Assets\//, "");
}

function cloneForPrefab(source, template, scenePath) {
  function cloneObject(node, objectPath) {
    const clone = {};
    for (const [key, value] of Object.entries(node)) {
      if (key === "__Prefab" || key === "__PrefabInstancePatch" || key === "__PrefabIdToInstanceId") {
        continue;
      }

      clone[key] = JSON.parse(JSON.stringify(value));
    }

    clone.__guid = stableGuid(`${template.path}:object:${objectPath}`);
    clone.__version = clone.__version || 2;
    clone.Children = (node.Children || []).map((child) => cloneObject(child, `${objectPath}/${child.Name || "Child"}`));
    clone.Components = (node.Components || []).map((component, index) => {
      const componentClone = JSON.parse(JSON.stringify(component));
      componentClone.__guid = stableGuid(`${template.path}:component:${objectPath}:${index}:${componentType(component)}`);
      return componentClone;
    });
    return clone;
  }

  const rootObject = cloneObject(source, scenePath);
  rootObject.Name = template.rootName;
  rootObject.Position = "0,0,0";
  rootObject.Rotation = "0,0,0,1";
  rootObject.Scale = "1,1,1";

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

  const sourceChildren = sourceObject?.Children || [];
  for (let i = 0; i < (prefabObject.Children || []).length; i += 1) {
    collectPrefabIds(prefabObject.Children[i], sourceChildren[i], mapping, `${seed}:child:${i}`);
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

function addRecursiveOverrides(overrides, source, prefabObject) {
  addObjectOverrides(overrides, source, prefabObject);
  addComponentOverrides(overrides, source, prefabObject);

  for (let i = 0; i < (prefabObject.Children || []).length; i += 1) {
    addRecursiveOverrides(overrides, source.Children[i], prefabObject.Children[i]);
  }
}

function shapeProblems(source, prefabObject, scenePath) {
  const problems = [];
  const sourceChildren = source.Children || [];
  const prefabChildren = prefabObject.Children || [];
  if (sourceChildren.length !== prefabChildren.length) {
    problems.push(`${scenePath} child count ${sourceChildren.length} does not match prefab child count ${prefabChildren.length}`);
    return problems;
  }

  const sourceTypes = (source.Components || []).map(componentType).sort();
  const prefabTypes = (prefabObject.Components || []).map(componentType).sort();
  if (!deepEqual(sourceTypes, prefabTypes)) {
    problems.push(`${scenePath} component types ${sourceTypes.join(",")} do not match prefab component types ${prefabTypes.join(",")}`);
  }

  for (let i = 0; i < sourceChildren.length; i += 1) {
    if (sourceChildren[i].Name !== prefabChildren[i].Name) {
      problems.push(`${scenePath} child ${i} name ${sourceChildren[i].Name} does not match prefab child ${prefabChildren[i].Name}`);
      continue;
    }

    problems.push(...shapeProblems(sourceChildren[i], prefabChildren[i], `${scenePath}/${sourceChildren[i].Name}`));
  }

  return problems;
}

function toPrefabInstance(source, template, prefab, scenePath) {
  const prefabRoot = prefab.RootObject;
  const problems = shapeProblems(source, prefabRoot, scenePath);
  if (problems.length > 0) {
    return { skipped: problems };
  }

  const mapping = {};
  collectPrefabIds(prefabRoot, source, mapping, source.__guid);

  const overrides = [];
  addRecursiveOverrides(overrides, source, prefabRoot);

  return {
    node: {
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

function migrateArray(objects, prefabByPath, stats, scenePath = "") {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const currentPath = scenePath ? `${scenePath}/${node.Name || "(unnamed)"}` : (node.Name || "(unnamed)");
    const template = templates.find((candidate) => candidate.matchNames.includes(node.Name || ""));
    if (template && !node.__Prefab) {
      const result = toPrefabInstance(node, template, prefabByPath.get(template.path), currentPath);
      if (result.node) {
        objects[i] = result.node;
        stats.migrated += 1;
        stats.byPrefab.set(template.path, (stats.byPrefab.get(template.path) || 0) + 1);
      } else {
        stats.skipped.push(...result.skipped);
      }
      continue;
    }

    migrateArray(node.Children || [], prefabByPath, stats, currentPath);
  }
}

const scenePath = "Assets/scenes/main.scene";
const scene = readJson(scenePath);
const prefabByPath = new Map();
const createdPrefabs = [];

for (const template of templates) {
  if (exists(template.path)) {
    prefabByPath.set(template.path, readJson(template.path));
    continue;
  }

  const source = findDirectObject(scene.GameObjects || [], template.sourceName);
  if (!source) {
    throw new Error(`Cannot create ${template.path}; source object ${template.sourceName} was not found as a direct scene object.`);
  }

  const prefab = cloneForPrefab(source.node, template, source.scenePath);
  prefabByPath.set(template.path, prefab);
  createdPrefabs.push(template.path);
}

const stats = { migrated: 0, byPrefab: new Map(), skipped: [] };
migrateArray(scene.GameObjects || [], prefabByPath, stats);

if (!dryRun) {
  for (const prefabPath of createdPrefabs) {
    writeJson(prefabPath, prefabByPath.get(prefabPath));
  }

  if (stats.migrated > 0) {
    writeJson(scenePath, scene);
  }
}

const action = dryRun ? "Would migrate" : "Migrated";
const createAction = dryRun ? "Would create" : "Created";
console.log(`${createAction} ${createdPrefabs.length} playable building prefab(s).`);
for (const prefabPath of createdPrefabs) {
  console.log(` - ${prefabPath}`);
}

console.log(`${action} ${stats.migrated} building scene placement(s) to prefab instances.`);
for (const [prefabPath, count] of Array.from(stats.byPrefab.entries()).sort((a, b) => a[0].localeCompare(b[0]))) {
  console.log(` - ${count} ${prefabPath}`);
}

if (stats.skipped.length > 0) {
  console.log(`Skipped ${stats.skipped.length} building placement problem(s).`);
  for (const skipped of stats.skipped) {
    console.log(` - ${skipped}`);
  }
  process.exitCode = 1;
}
