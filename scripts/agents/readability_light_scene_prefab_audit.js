#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const templates = [
  {
    prefab: "Assets/prefabs/environment/operator_signal_light.prefab",
    scenePrefab: "prefabs/environment/operator_signal_light.prefab",
    rootName: "OperatorSignalLight",
    sceneNames: [
      "EastLaunch_SignalLight",
      "MidService_SignalLight",
      "NorthHouse_SignalLight",
    ],
    childCount: 1,
    requiresGlowMarker: true,
  },
  {
    prefab: "Assets/prefabs/environment/launch_pad_glow_light.prefab",
    scenePrefab: "prefabs/environment/launch_pad_glow_light.prefab",
    rootName: "LaunchPadGlowLight",
    sceneNames: ["LaunchPad_Glow_North", "LaunchPad_Glow_South"],
    childCount: 0,
    requiresGlowMarker: false,
  },
  {
    prefab: "Assets/prefabs/environment/perch_marker_light.prefab",
    scenePrefab: "prefabs/environment/perch_marker_light.prefab",
    rootName: "PerchMarkerLight",
    sceneNames: ["WaterTower_PerchMarker"],
    childCount: 1,
    requiresGlowMarker: true,
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

function hasPointLight(node) {
  return (node.Components || []).some((component) => componentType(component) === "Sandbox.PointLight");
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

function directSceneLights(scene, template) {
  const matches = [];
  for (const rootObject of scene.GameObjects || []) {
    walkObject(rootObject, (node, underPrefab, scenePath) => {
      if (underPrefab || node.__Prefab) {
        return;
      }

      if (template.sceneNames.includes(node.Name || "") && hasPointLight(node)) {
        matches.push(scenePath);
      }
    });
  }
  return matches;
}

function logInfo(message) {
  if (showInfo) {
    console.log(`[Info] Readability Light Prefabs - ${message}`);
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

  if (!hasPointLight(rootObject)) {
    errors.push(`${template.prefab} root should carry one Sandbox.PointLight component.`);
  }

  const childCount = (rootObject.Children || []).length;
  if (childCount !== template.childCount) {
    errors.push(`${template.prefab} should have ${template.childCount} child object(s), found ${childCount}.`);
  }

  const glowMarker = (rootObject.Children || [])[0];
  const glowRenderer = (glowMarker?.Components || []).find(
    (component) => componentType(component) === "Sandbox.ModelRenderer",
  );
  if (template.requiresGlowMarker) {
    if (!glowRenderer) {
      errors.push(`${template.prefab} should keep a glow marker child with a Sandbox.ModelRenderer.`);
    } else {
      if (glowRenderer.Model !== "models/dev/box.vmdl") {
        errors.push(`${template.prefab} glow marker should render models/dev/box.vmdl.`);
      }
      if (glowRenderer.MaterialOverride !== "materials/emp_glow.vmat") {
        errors.push(`${template.prefab} glow marker should use materials/emp_glow.vmat.`);
      }
    }
  } else if (glowMarker || glowRenderer) {
    errors.push(`${template.prefab} should be a light-only prefab without glow-marker children.`);
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

  const directLights = directSceneLights(scene, template);
  if (directLights.length > 0) {
    const message = `${template.prefab} still has direct scene light object(s): ${directLights.join(", ")}.`;
    if (requireMigrated) {
      errors.push(message);
    } else {
      warnings.push(message);
    }
  }

  logInfo(`${template.prefab} has ${childCount} child object(s) and ${instances.length} scene instance(s).`);
}

for (const warning of warnings) {
  console.log(`[Warning] Readability Light Prefabs - ${warning}`);
}

for (const error of errors) {
  console.log(`[Error] Readability Light Prefabs - ${error}`);
}

if (errors.length > 0 || (failOnWarning && warnings.length > 0)) {
  process.exit(1);
}

logInfo("Readability light prefab contracts passed.");
