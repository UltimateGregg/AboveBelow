#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const templates = [
  {
    prefab: "Assets/prefabs/systems/game_manager.prefab",
    scenePrefab: "prefabs/systems/game_manager.prefab",
    rootName: "GameManager",
    sourceName: "GameManager",
    requiredComponents: [
      "DroneVsPlayers.GameRules",
      "DroneVsPlayers.GameStats",
      "DroneVsPlayers.GameSetup",
      "DroneVsPlayers.TeamComms",
      "DroneVsPlayers.RoundManager",
      "DroneVsPlayers.AutoWireHelper",
      "DroneVsPlayers.KillFeedTracker",
      "DroneVsPlayers.CollisionDebugViewer",
    ],
  },
  {
    prefab: "Assets/prefabs/ui/hud.prefab",
    scenePrefab: "prefabs/ui/hud.prefab",
    rootName: "HUD",
    sourceName: "HUD",
    requiredComponents: [
      "Sandbox.ScreenPanel",
      "DroneVsPlayers.HudPanel",
    ],
  },
  {
    prefab: "Assets/prefabs/environment/blinding_sun_glare.prefab",
    scenePrefab: "prefabs/environment/blinding_sun_glare.prefab",
    rootName: "BlindingSunGlare",
    sourceName: "BlindingSun_WestSky",
    requiredComponents: [
      "Sandbox.SpriteRenderer",
      "DroneVsPlayers.SunGlareSource",
    ],
  },
  {
    prefab: "Assets/prefabs/environment/sun_directional.prefab",
    scenePrefab: "prefabs/environment/sun_directional.prefab",
    rootName: "Sun",
    sourceName: "Sun",
    requiredComponents: [
      "Sandbox.DirectionalLight",
    ],
  },
  {
    prefab: "Assets/prefabs/environment/skybox_2d.prefab",
    scenePrefab: "prefabs/environment/skybox_2d.prefab",
    rootName: "2D Skybox",
    sourceName: "2D Skybox",
    requiredComponents: [
      "Sandbox.SkyBox2D",
      "Sandbox.EnvmapProbe",
    ],
  },
  {
    prefab: "Assets/prefabs/systems/main_camera.prefab",
    scenePrefab: "prefabs/systems/main_camera.prefab",
    rootName: "Camera",
    sourceName: "Camera",
    requiredComponents: [
      "Sandbox.CameraComponent",
      "Sandbox.Bloom",
      "Sandbox.Tonemapping",
    ],
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

function componentTypes(node) {
  return (node.Components || []).map(componentType);
}

function hasAllComponents(node, requiredComponents) {
  const types = componentTypes(node);
  return requiredComponents.every((type) => types.includes(type));
}

function walkObject(node, visit, underPrefab = false, scenePath = "") {
  const name = node.Name || "(prefab instance)";
  const nextPath = scenePath ? `${scenePath}/${name}` : name;
  const isPrefab = underPrefab || Boolean(node.__Prefab);
  visit(node, isPrefab, nextPath);
  for (const child of node.Children || []) {
    walkObject(child, visit, isPrefab, nextPath);
  }
}

function sceneInstances(scene, template) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (node.__Prefab === template.scenePrefab) {
        matches.push({ node, scenePath });
      }
    });
  }
  return matches;
}

function directSceneObjects(scene, template) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (underPrefab || node.__Prefab) {
        return;
      }

      if (node.Name === template.sourceName && hasAllComponents(node, template.requiredComponents)) {
        matches.push(scenePath);
      }
    });
  }
  return matches;
}

function logInfo(message) {
  if (showInfo) {
    console.log(`[Info] Scene Singleton Prefab - ${message}`);
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

  for (const required of template.requiredComponents) {
    if (!componentTypes(rootObject).includes(required)) {
      errors.push(`${template.prefab} root is missing ${required}.`);
    }
  }

  if ((rootObject.Children || []).length !== 0) {
    errors.push(`${template.prefab} should keep a childless singleton root.`);
  }

  const instances = sceneInstances(scene, template);
  if (instances.length !== 1) {
    const message = `${template.prefab} should have one saved scene instance, found ${instances.length}.`;
    if (requireMigrated) {
      errors.push(message);
    } else {
      warnings.push(message);
    }
  }

  const directObjects = directSceneObjects(scene, template);
  if (directObjects.length > 0) {
    const message = `${template.prefab} still has direct scene object(s): ${directObjects.join(", ")}.`;
    if (requireMigrated) {
      errors.push(message);
    } else {
      warnings.push(message);
    }
  }

  logInfo(`${template.prefab} has ${instances.length} scene instance(s).`);
}

for (const warning of warnings) {
  console.log(`[Warning] Scene Singleton Prefab - ${warning}`);
}

for (const error of errors) {
  console.log(`[Error] Scene Singleton Prefab - ${error}`);
}

if (errors.length > 0 || (failOnWarning && warnings.length > 0)) {
  process.exit(1);
}

logInfo("Scene singleton prefab contract passed.");
