#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
let root = process.cwd();
let showInfo = false;
let failOnWarning = false;

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === "--root") {
    root = path.resolve(args[++i]);
  } else if (arg === "--show-info") {
    showInfo = true;
  } else if (arg === "--fail-on-warning") {
    failOnWarning = true;
  }
}

const scenePath = "Assets/scenes/main.scene";
const allowedDirectObjects = new Map([
  ["Scene Information", ["Sandbox.SceneInformation"]],
  ["BlockoutMap/ArenaFloor", ["Sandbox.Terrain"]],
]);

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function componentTypes(node) {
  return (node.Components || []).map((component) => component.__type || component.Type || "");
}

function sameComponents(actual, expected) {
  return actual.length === expected.length && actual.every((type, index) => type === expected[index]);
}

function walkSceneObject(node, sceneObjectPath, state) {
  const name = node.Name || "(unnamed)";
  const nextPath = sceneObjectPath ? `${sceneObjectPath}/${name}` : name;

  if (node.__Prefab) {
    return;
  }

  const components = componentTypes(node);
  const children = node.Children || [];
  if (components.length > 0) {
    state.directComponentObjects.push({
      path: nextPath,
      components,
    });
  } else if (children.length > 0) {
    state.directContainerCount += 1;
  }

  for (const child of children) {
    walkSceneObject(child, nextPath, state);
  }
}

function logInfo(message) {
  if (showInfo) {
    console.log(`[Info] Scene Prefab Coverage - ${message}`);
  }
}

const errors = [];
const warnings = [];
let scene;

try {
  scene = readJson(scenePath);
} catch (error) {
  errors.push(`Could not parse ${scenePath}: ${error.message}`);
}

if (scene) {
  const state = {
    directComponentObjects: [],
    directContainerCount: 0,
  };

  for (const rootObject of scene.GameObjects || []) {
    walkSceneObject(rootObject, "", state);
  }

  for (const entry of state.directComponentObjects) {
    if (!allowedDirectObjects.has(entry.path)) {
      errors.push(`Direct non-prefab scene object '${entry.path}' owns component(s): ${entry.components.join(",")}. Move reusable component-bearing scene objects into prefabs, or add a narrow documented exception if the object is scene metadata.`);
      continue;
    }

    const expected = allowedDirectObjects.get(entry.path);
    if (!sameComponents(entry.components, expected)) {
      errors.push(`Allowed direct scene object '${entry.path}' has unexpected component set '${entry.components.join(",")}'. Expected '${expected.join(",")}'. Keep direct scene exceptions narrow and update this audit only when the exception is intentional.`);
    }
  }

  logInfo(`Checked ${state.directComponentObjects.length} direct component-bearing object(s) and ${state.directContainerCount} direct container object(s).`);
}

for (const warning of warnings) {
  console.log(`[Warning] Scene Prefab Coverage - ${warning}`);
}

for (const error of errors) {
  console.log(`[Error] Scene Prefab Coverage - ${error}`);
}

if (errors.length > 0 || (failOnWarning && warnings.length > 0)) {
  process.exit(1);
}

logInfo("Scene prefab coverage contract passed.");
