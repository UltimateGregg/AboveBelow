#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const template = {
  prefab: "Assets/prefabs/environment/ambient_sound_point.prefab",
  scenePrefab: "prefabs/environment/ambient_sound_point.prefab",
  rootName: "AmbientSoundPoint",
  sceneNames: [
    "AmbientLightWind",
    "AmbientBirdsChirping",
    "AmbientBirdsCanopyFar",
    "AmbientCrowsDistant",
  ],
};

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

function walkObject(node, visit, underPrefab = false, scenePath = "") {
  const name = node.Name || patchedName(node) || "(unnamed)";
  const nextPath = scenePath ? `${scenePath}/${name}` : name;
  const isPrefab = underPrefab || Boolean(node.__Prefab);
  visit(node, isPrefab, nextPath);
  for (const child of node.Children || []) {
    walkObject(child, visit, isPrefab, nextPath);
  }
}

function hasAmbientSound(node) {
  return (node.Components || []).some((component) => componentType(component) === "DroneVsPlayers.AmbientSound");
}

function sceneInstances(scene) {
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

function directSceneAmbientSounds(scene) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (underPrefab || node.__Prefab) {
        return;
      }

      if (template.sceneNames.includes(node.Name || "") && hasAmbientSound(node)) {
        matches.push(scenePath);
      }
    });
  }
  return matches;
}

function logInfo(message) {
  if (showInfo) {
    console.log(`[Info] Ambient Sound Prefab - ${message}`);
  }
}

const errors = [];
const warnings = [];
const scene = readJson("Assets/scenes/main.scene");

if (!exists(template.prefab)) {
  errors.push(`Missing prefab ${template.prefab}.`);
} else {
  const prefab = readJson(template.prefab);
  const rootObject = prefab.RootObject;
  if (!rootObject) {
    errors.push(`${template.prefab} has no RootObject.`);
  } else {
    if (rootObject.Name !== template.rootName) {
      errors.push(`${template.prefab} root should be named ${template.rootName}, found ${rootObject.Name}.`);
    }
    if (!hasAmbientSound(rootObject)) {
      errors.push(`${template.prefab} root should carry one DroneVsPlayers.AmbientSound component.`);
    }
    if ((rootObject.Children || []).length !== 0) {
      errors.push(`${template.prefab} should be a sound-only prefab without child objects.`);
    }
  }
}

const instances = sceneInstances(scene);
if (instances.length !== template.sceneNames.length) {
  const message = `${template.prefab} should have ${template.sceneNames.length} saved scene instance(s), found ${instances.length}.`;
  if (requireMigrated) {
    errors.push(message);
  } else {
    warnings.push(message);
  }
}

const directAmbientSounds = directSceneAmbientSounds(scene);
if (directAmbientSounds.length > 0) {
  const message = `${template.prefab} still has direct scene ambient sound object(s): ${directAmbientSounds.join(", ")}.`;
  if (requireMigrated) {
    errors.push(message);
  } else {
    warnings.push(message);
  }
}

logInfo(`${template.prefab} has ${instances.length} scene instance(s).`);

for (const warning of warnings) {
  console.log(`[Warning] Ambient Sound Prefab - ${warning}`);
}

for (const error of errors) {
  console.log(`[Error] Ambient Sound Prefab - ${error}`);
}

if (errors.length > 0 || (failOnWarning && warnings.length > 0)) {
  process.exit(1);
}

logInfo("Ambient sound prefab contract passed.");
