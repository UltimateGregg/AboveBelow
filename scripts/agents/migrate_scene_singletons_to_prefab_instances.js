#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/systems/game_manager.prefab",
    rootName: "GameManager",
    sourceName: "GameManager",
    menuPath: "Drone vs Players/Systems/GameManager",
    menuIcon: "settings",
  },
  {
    path: "Assets/prefabs/ui/hud.prefab",
    rootName: "HUD",
    sourceName: "HUD",
    menuPath: "Drone vs Players/UI/HUD",
    menuIcon: "space_dashboard",
  },
  {
    path: "Assets/prefabs/environment/blinding_sun_glare.prefab",
    rootName: "BlindingSunGlare",
    sourceName: "BlindingSun_WestSky",
    menuPath: "Drone vs Players/Environment/BlindingSunGlare",
    menuIcon: "wb_sunny",
    neutralTransform: true,
  },
  {
    path: "Assets/prefabs/environment/sun_directional.prefab",
    rootName: "Sun",
    sourceName: "Sun",
    menuPath: "Drone vs Players/Environment/Sun",
    menuIcon: "wb_sunny",
  },
  {
    path: "Assets/prefabs/environment/skybox_2d.prefab",
    rootName: "2D Skybox",
    sourceName: "2D Skybox",
    menuPath: "Drone vs Players/Environment/2D Skybox",
    menuIcon: "filter_drama",
  },
  {
    path: "Assets/prefabs/systems/main_camera.prefab",
    rootName: "Camera",
    sourceName: "Camera",
    menuPath: "Drone vs Players/Systems/Main Camera",
    menuIcon: "photo_camera",
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

function prefabInstancePath(template) {
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

function cloneComponentsForPrefab(source, template) {
  return (source.Components || []).map((component, index) => {
    const componentClone = clone(component);
    componentClone.__guid = stableGuid(`${template.path}:component:${index}:${componentType(component)}`);
    return componentClone;
  });
}

function cloneForPrefab(source, template) {
  const rootObject = clone(source);
  rootObject.__guid = stableGuid(`${template.path}:root`);
  rootObject.__version = rootObject.__version || 2;
  rootObject.Name = template.rootName;
  rootObject.Components = cloneComponentsForPrefab(source, template);
  rootObject.Children = [];

  if (template.neutralTransform) {
    rootObject.Position = "0,0,0";
    rootObject.Rotation = "0,0,0,1";
    rootObject.Scale = "1,1,1";
  }

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

  const sourceTypeCounts = new Map();
  for (const type of (source.Components || []).map(componentType)) {
    sourceTypeCounts.set(type, (sourceTypeCounts.get(type) || 0) + 1);
  }

  const prefabTypeCounts = new Map();
  for (const type of (prefabObject.Components || []).map(componentType)) {
    prefabTypeCounts.set(type, (prefabTypeCounts.get(type) || 0) + 1);
  }

  const missingTypes = [];
  for (const [type, count] of sourceTypeCounts.entries()) {
    if ((prefabTypeCounts.get(type) || 0) < count) {
      missingTypes.push(type);
    }
  }

  if (missingTypes.length > 0) {
    const sourceTypes = (source.Components || []).map(componentType).sort();
    const prefabTypes = (prefabObject.Components || []).map(componentType).sort();
    problems.push(`${scenePath} component types ${sourceTypes.join(",")} are not covered by prefab component types ${prefabTypes.join(",")}`);
  }

  return problems;
}

function toPrefabInstance(source, prefab, template, scenePath) {
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

function migrateArray(objects, prefab, template, stats, scenePath = "") {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const currentPath = scenePath ? `${scenePath}/${node.Name || "(unnamed)"}` : (node.Name || "(unnamed)");
    if (node.Name === template.sourceName && !node.__Prefab) {
      const result = toPrefabInstance(node, prefab, template, currentPath);
      if (result.node) {
        objects[i] = result.node;
        stats.migrated += 1;
        stats.paths.push(template.path);
      } else {
        stats.skipped.push(...result.skipped);
      }
      continue;
    }

    migrateArray(node.Children || [], prefab, template, stats, currentPath);
  }
}

const scenePath = "Assets/scenes/main.scene";
const scene = readJson(scenePath);
const stats = {
  created: [],
  migrated: 0,
  paths: [],
  skipped: [],
};

for (const template of templates) {
  let prefab;
  if (exists(template.path)) {
    prefab = readJson(template.path);
  } else {
    const source = findDirectObject(scene.GameObjects || [], template.sourceName);
    if (!source) {
      stats.skipped.push(`Cannot create ${template.path}; source object ${template.sourceName} was not found as a direct scene object.`);
      continue;
    }

    prefab = cloneForPrefab(source.node, template);
    stats.created.push({ path: template.path, prefab });
  }

  migrateArray(scene.GameObjects || [], prefab, template, stats);
}

if (!dryRun) {
  for (const item of stats.created) {
    writeJson(item.path, item.prefab);
  }

  if (stats.migrated > 0) {
    writeJson(scenePath, scene);
  }
}

const action = dryRun ? "Would migrate" : "Migrated";
const createAction = dryRun ? "Would create" : "Created";
console.log(`${createAction} ${stats.created.length} scene singleton prefab(s).`);
for (const item of stats.created) {
  console.log(` - ${item.path}`);
}
console.log(`${action} ${stats.migrated} scene singleton placement(s) to prefab instances.`);
for (const prefabPath of stats.paths) {
  console.log(` - ${prefabPath}`);
}

if (stats.skipped.length > 0) {
  console.log(`Skipped ${stats.skipped.length} scene singleton problem(s).`);
  for (const skipped of stats.skipped) {
    console.log(` - ${skipped}`);
  }
  process.exitCode = 1;
}
