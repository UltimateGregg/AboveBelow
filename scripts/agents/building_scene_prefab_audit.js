#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const templates = [
  {
    prefab: "Assets/prefabs/environment/house_large_playable.prefab",
    scenePrefab: "prefabs/environment/house_large_playable.prefab",
    rootName: "HouseLargePlayable",
    sceneNames: ["House_Large_01", "House_Large_02"],
    model: "models/house_large.vmdl",
    childCount: 55,
    minColliderCount: 54,
    minZoneCount: 6,
  },
  {
    prefab: "Assets/prefabs/environment/house_small_playable.prefab",
    scenePrefab: "prefabs/environment/house_small_playable.prefab",
    rootName: "HouseSmallPlayable",
    sceneNames: ["House_Small_02", "House_Small_03"],
    model: "models/house_small.vmdl",
    childCount: 40,
    minColliderCount: 39,
    minZoneCount: 5,
  },
  {
    prefab: "Assets/prefabs/environment/house_small_collision_playable.prefab",
    scenePrefab: "prefabs/environment/house_small_collision_playable.prefab",
    rootName: "HouseSmallCollisionPlayable",
    sceneNames: ["House_Small_01", "House_Small_04"],
    model: "",
    childCount: 39,
    minColliderCount: 39,
    minZoneCount: 5,
  },
];

const args = process.argv.slice(2);
let root = process.cwd();
let showInfo = false;
let failOnWarning = false;
let requireMigrated = false;

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === "--root") {
    root = path.resolve(args[++i]);
  } else if (arg === "--show-info") {
    showInfo = true;
  } else if (arg === "--fail-on-warning") {
    failOnWarning = true;
  } else if (arg === "--require-migrated") {
    requireMigrated = true;
  }
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function exists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

function componentType(component) {
  return component.__type || component.Type || "";
}

function walkObject(node, visit, underPrefab = false, scenePath = "") {
  const name = node.Name || patchedName(node) || "(unnamed)";
  const nextPath = scenePath ? `${scenePath}/${name}` : name;
  const isPrefab = underPrefab || Boolean(node.__Prefab);
  visit(node, isPrefab, nextPath);
  for (const child of node.Children || []) {
    walkObject(child, visit, isPrefab, nextPath);
  }
}

function countComponents(rootObject, predicate) {
  let count = 0;
  walkObject(rootObject, (node) => {
    for (const component of node.Components || []) {
      if (predicate(component)) {
        count += 1;
      }
    }
  });
  return count;
}

function findChild(rootObject, name) {
  let found = null;
  walkObject(rootObject, (node) => {
    if (!found && node.Name === name) {
      found = node;
    }
  });
  return found;
}

function patchedName(node) {
  const patch = node.__PrefabInstancePatch;
  if (!patch) {
    return node.Name || null;
  }

  const override = (patch.PropertyOverrides || []).find(
    (item) => item.Target?.Type === "GameObject" && item.Property === "Name",
  );
  return override?.Value || node.Name || null;
}

function sceneInstances(scene, template) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (node.__Prefab !== template.scenePrefab) {
        return;
      }

      const name = patchedName(node);
      if (template.sceneNames.includes(name)) {
        matches.push({ node, scenePath, name });
      }
    });
  }
  return matches;
}

function directSceneHouses(scene, template) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (underPrefab || node.__Prefab) {
        return;
      }

      const renderer = (node.Components || []).find(
        (component) => componentType(component) === "Sandbox.ModelRenderer" && component.Model === template.model,
      );
      if (renderer) {
        matches.push(scenePath);
      }
    });
  }
  return matches;
}

function logInfo(message) {
  if (showInfo) {
    console.log(`[Info] Building Prefabs - ${message}`);
  }
}

const errors = [];
const warnings = [];
const scene = readJson("Assets/scenes/main.scene");

for (const template of templates) {
  if (!exists(template.prefab)) {
    errors.push(`Missing prefab ${template.prefab}.`);
    continue;
  }

  const prefab = readJson(template.prefab);
  const rootObject = prefab.RootObject;
  if (!rootObject) {
    errors.push(`${template.prefab} has no RootObject.`);
    continue;
  }

  if (rootObject.Name !== template.rootName) {
    errors.push(`${template.prefab} root should be named ${template.rootName}, found ${rootObject.Name}.`);
  }

  const childCount = (rootObject.Children || []).length;
  if (childCount !== template.childCount) {
    errors.push(`${template.prefab} should have ${template.childCount} child object(s), found ${childCount}.`);
  }

  const modelVisual = findChild(rootObject, "Model_Visual");
  const renderer = (modelVisual?.Components || []).find((component) => componentType(component) === "Sandbox.ModelRenderer");
  if (template.model) {
    if (!renderer || renderer.Model !== template.model) {
      errors.push(`${template.prefab} Model_Visual should render ${template.model}.`);
    }
  } else if (modelVisual || renderer) {
    errors.push(`${template.prefab} should be collision-only and must not carry a Model_Visual child.`);
  }

  const colliderCount = countComponents(rootObject, (component) => componentType(component).endsWith("Collider"));
  if (colliderCount < template.minColliderCount) {
    errors.push(`${template.prefab} should keep at least ${template.minColliderCount} collider component(s), found ${colliderCount}.`);
  }

  const zoneCount = (rootObject.Children || []).filter((child) => /^Zone_/.test(child.Name || "")).length;
  if (zoneCount < template.minZoneCount) {
    errors.push(`${template.prefab} should keep at least ${template.minZoneCount} Zone_* helper object(s), found ${zoneCount}.`);
  }

  const instances = sceneInstances(scene, template);
  if (instances.length !== template.sceneNames.length) {
    const message = `${template.prefab} should have ${template.sceneNames.length} saved scene instance(s), found ${instances.length}.`;
    if (requireMigrated) {
      errors.push(message);
    } else {
      warnings.push(message);
    }
  }

  const directHouses = directSceneHouses(scene, template);
  if (directHouses.length > 0) {
    const message = `${template.model} still appears in direct scene object(s): ${directHouses.join(", ")}.`;
    if (requireMigrated) {
      errors.push(message);
    } else {
      warnings.push(message);
    }
  }

  logInfo(`${template.prefab} has ${childCount} child object(s), ${colliderCount} collider(s), ${zoneCount} zone helper(s), and ${instances.length} scene instance(s).`);
}

for (const warning of warnings) {
  console.log(`[Warning] Building Prefabs - ${warning}`);
}

for (const error of errors) {
  console.log(`[Error] Building Prefabs - ${error}`);
}

if (errors.length > 0 || (failOnWarning && warnings.length > 0)) {
  process.exit(1);
}

logInfo("Playable house prefab contracts passed.");
