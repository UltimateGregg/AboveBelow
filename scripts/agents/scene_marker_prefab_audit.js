#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/markers/player_spawn_soldier.prefab",
    instancePath: "prefabs/markers/player_spawn_soldier.prefab",
    rootName: "PlayerSpawn_Soldier",
    componentType: "DroneVsPlayers.PlayerSpawn",
    roleProperty: "Role",
    expectedRole: "Soldier",
    requiredTag: "PlayerSpawn",
  },
  {
    path: "Assets/prefabs/markers/player_spawn_pilot.prefab",
    instancePath: "prefabs/markers/player_spawn_pilot.prefab",
    rootName: "PlayerSpawn_Pilot",
    componentType: "DroneVsPlayers.PlayerSpawn",
    roleProperty: "Role",
    expectedRole: "Pilot",
    requiredTag: "DroneSpawn",
  },
  {
    path: "Assets/prefabs/markers/training_dummy_spawn.prefab",
    instancePath: "prefabs/markers/training_dummy_spawn.prefab",
    rootName: "TrainingDummySpawn",
    componentType: "DroneVsPlayers.TrainingDummySpawn",
    roleProperty: "PreferredRole",
    expectedRole: "Spectator",
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

const issues = [];

function addIssue(severity, area, issuePath, message, recommendation = "") {
  issues.push({ severity, area, path: issuePath, message, recommendation });
}

function normalizeSlashes(value) {
  return value.replace(/\\/g, "/");
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function walkGameObjects(node, callback, insidePrefab = false) {
  const isPrefabInstance = Boolean(node.__Prefab);
  callback(node, insidePrefab, isPrefabInstance);

  const nextInsidePrefab = insidePrefab || isPrefabInstance;
  for (const child of node.Children || []) {
    walkGameObjects(child, callback, nextInsidePrefab);
  }
}

function matchingTemplateForDirectMarker(node) {
  for (const component of node.Components || []) {
    for (const template of templates) {
      if (component.__type !== template.componentType) {
        continue;
      }

      if (component[template.roleProperty] === template.expectedRole) {
        return template;
      }
    }
  }

  return null;
}

function countSceneUsage() {
  const scenePath = "Assets/scenes/main.scene";
  const absoluteScenePath = path.join(root, scenePath);
  const prefabCounts = new Map(templates.map((template) => [template.instancePath, 0]));
  const directCounts = new Map(templates.map((template) => [template.instancePath, 0]));

  if (!fs.existsSync(absoluteScenePath)) {
    addIssue("Error", "Scene Marker Prefab", scenePath, "Main scene is missing.", "Restore main.scene before auditing scene marker prefab usage.");
    return { prefabCounts, directCounts };
  }

  let scene;
  try {
    scene = readJson(scenePath);
  } catch (error) {
    addIssue("Error", "Scene Marker Prefab", scenePath, `Main scene JSON failed to parse: ${error.message}`, "Fix invalid scene JSON before auditing scene marker prefab usage.");
    return { prefabCounts, directCounts };
  }

  for (const gameObject of scene.GameObjects || []) {
    walkGameObjects(gameObject, (node, insidePrefab, isPrefabInstance) => {
      if (isPrefabInstance && prefabCounts.has(node.__Prefab)) {
        prefabCounts.set(node.__Prefab, prefabCounts.get(node.__Prefab) + 1);
      }

      if (insidePrefab || isPrefabInstance) {
        return;
      }

      const template = matchingTemplateForDirectMarker(node);
      if (template) {
        directCounts.set(template.instancePath, directCounts.get(template.instancePath) + 1);
      }
    });
  }

  return { prefabCounts, directCounts };
}

function inspectPrefab(template) {
  const absolutePath = path.join(root, template.path);
  if (!fs.existsSync(absolutePath)) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      "Required marker prefab is missing.",
      "Create reusable marker prefabs for repeated scene-authored gameplay markers.",
    );
    return;
  }

  let prefab;
  try {
    prefab = readJson(template.path);
  } catch (error) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      `Marker prefab JSON failed to parse: ${error.message}`,
      "Fix invalid prefab JSON before relying on the marker template.",
    );
    return;
  }

  const rootObject = prefab.RootObject;
  if (!rootObject) {
    addIssue("Error", "Scene Marker Prefab", template.path, "Marker prefab has no RootObject.", "Regenerate or repair the prefab JSON.");
    return;
  }

  if (rootObject.Name !== template.rootName) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      `Root name expected '${template.rootName}' but found '${rootObject.Name}'.`,
      "Keep marker prefab root names stable so scene authors can identify archetypes quickly.",
    );
  }

  if (template.requiredTag && rootObject.Tags !== template.requiredTag) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      `Marker prefab is missing required tag '${template.requiredTag}'.`,
      "Keep legacy spawn tags on spawn marker templates for GameSetup compatibility.",
    );
  }

  const component = (rootObject.Components || []).find((candidate) => candidate.__type === template.componentType);
  if (!component) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      `Missing required component '${template.componentType}'.`,
      "Keep scene marker templates aligned with the runtime marker components.",
    );
    return;
  }

  if (component[template.roleProperty] !== template.expectedRole) {
    addIssue(
      "Error",
      "Scene Marker Prefab",
      template.path,
      `${template.componentType}.${template.roleProperty} expected '${template.expectedRole}'.`,
      "Create one role-specific marker prefab per common scene-authoring role.",
    );
  }

  addIssue("Info", "Scene Marker Prefab", template.path, "Marker prefab template check completed.");
}

console.log("");
console.log("== Scene Marker Prefab Audit ==");
console.log(`Root: ${normalizeSlashes(root)}`);

for (const template of templates) {
  inspectPrefab(template);
}

const usage = countSceneUsage();
for (const template of templates) {
  const directCount = usage.directCounts.get(template.instancePath) || 0;
  const prefabCount = usage.prefabCounts.get(template.instancePath) || 0;

  if (prefabCount > 0) {
    addIssue(
      "Info",
      "Scene Marker Prefab",
      "Assets/scenes/main.scene",
      `${prefabCount} scene prefab instance(s) use ${template.path}.`,
      "Keep repeated gameplay markers prefab-backed for scene authoring.",
    );
  }

  if (directCount > 0) {
    addIssue(
      requireMigrated ? "Error" : "Info",
      "Scene Marker Prefab",
      "Assets/scenes/main.scene",
      `${directCount} direct scene marker object(s) match ${template.path}.`,
      "Migrate repeated gameplay markers to saved-scene prefab instances.",
    );
  }
}

const visibleIssues = issues.filter((issue) => showInfo || issue.severity !== "Info");
if (visibleIssues.length === 0) {
  console.log("No blocking issues found.");
} else {
  for (const issue of visibleIssues) {
    const location = issue.path ? ` [${issue.path}]` : "";
    console.log(`[${issue.severity}] ${issue.area}${location} - ${issue.message}`);
    if (issue.recommendation) {
      console.log(`  Recommendation: ${issue.recommendation}`);
    }
  }
}

if (issues.some((issue) => issue.severity === "Error")) {
  process.exit(1);
}

if (failOnWarning && issues.some((issue) => issue.severity === "Warning")) {
  process.exit(1);
}
