#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const heldItemTemplates = [
  {
    label: "Assault rifle held item",
    path: "Assets/prefabs/items/assault_rifle_m4_held.prefab",
    source: "Assets/prefabs/soldier_assault.prefab",
    sourcePath: ["Body", "Weapon"],
    rootName: "Weapon",
    component: "DroneVsPlayers.HitscanWeapon",
    requiredChildren: ["WeaponVisual", "MuzzleSocket", "LeftHandIk", "RightHandIk"],
    model: "models/weapons/assault_rifle_m4.vmdl"
  },
  {
    label: "Pilot SMG held item",
    path: "Assets/prefabs/items/smg_mp7_held.prefab",
    source: "Assets/prefabs/pilot_ground.prefab",
    sourcePath: ["Body", "Weapon"],
    rootName: "Weapon",
    component: "DroneVsPlayers.HitscanWeapon",
    requiredChildren: ["WeaponVisual", "MuzzleSocket", "LeftHandIk", "RightHandIk"],
    model: "models/weapons/smg_mp7.vmdl"
  },
  {
    label: "Shotgun held item",
    path: "Assets/prefabs/items/shotgun_held.prefab",
    source: "Assets/prefabs/soldier_heavy.prefab",
    sourcePath: ["Body", "Weapon"],
    rootName: "Weapon",
    component: "DroneVsPlayers.ShotgunWeapon",
    requiredChildren: ["WeaponVisual", "MuzzleSocket", "LeftHandIk", "RightHandIk"],
    model: "models/shotgun.vmdl"
  },
  {
    label: "Drone jammer held item",
    path: "Assets/prefabs/items/drone_jammer_held.prefab",
    source: "Assets/prefabs/soldier_counter_uav.prefab",
    sourcePath: ["Body", "Weapon"],
    rootName: "Weapon",
    component: "DroneVsPlayers.DroneJammerGun",
    requiredChildren: ["WeaponVisual", "MuzzleSocket", "LeftHandIk", "RightHandIk"],
    model: "models/jammer_gun.vmdl"
  },
  {
    label: "Chaff grenade held item",
    path: "Assets/prefabs/items/chaff_grenade_held.prefab",
    source: "Assets/prefabs/soldier_assault.prefab",
    sourcePath: ["Body", "Grenade"],
    rootName: "Grenade",
    component: "DroneVsPlayers.ChaffGrenade",
    requiredChildren: ["LeftHandIk", "RightHandIk"],
    model: "models/chaff_grenade.vmdl"
  },
  {
    label: "Frag grenade held item",
    path: "Assets/prefabs/items/frag_grenade_held.prefab",
    source: "Assets/prefabs/soldier_counter_uav.prefab",
    sourcePath: ["Body", "Grenade"],
    rootName: "Grenade",
    component: "DroneVsPlayers.FragGrenade",
    requiredChildren: ["LeftHandIk", "RightHandIk"],
    model: "models/frag_grenade.vmdl"
  },
  {
    label: "EMP grenade held item",
    path: "Assets/prefabs/items/emp_grenade_held.prefab",
    source: "Assets/prefabs/soldier_heavy.prefab",
    sourcePath: ["Body", "Grenade"],
    rootName: "Grenade",
    component: "DroneVsPlayers.EmpGrenade",
    requiredChildren: ["LeftHandIk", "RightHandIk"],
    model: "models/emp_grenade.vmdl"
  },
  {
    label: "Pilot drone deployer held item",
    path: "Assets/prefabs/items/pilot_drone_deployer_held.prefab",
    source: "Assets/prefabs/pilot_ground.prefab",
    sourcePath: ["Body", "DroneDeployer"],
    rootName: "DroneDeployer",
    component: "DroneVsPlayers.DroneDeployer",
    requiredChildren: ["LeftHand", "RightHand", "LeftHandIk", "RightHandIk"],
    models: ["models/weapons/rc_transmitter.vmdl", "models/drone_fpv.vmdl", "models/drone_fpv_prop.vmdl"]
  }
];

function parseArgs(argv) {
  const args = { root: "", showInfo: false, failOnWarning: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-Root" && i + 1 < argv.length) {
      args.root = argv[++i];
    } else if (arg === "-ShowInfo") {
      args.showInfo = true;
    } else if (arg === "-FailOnWarning") {
      args.failOnWarning = true;
    }
  }
  return args;
}

function findProjectRoot(start) {
  let current = path.resolve(start || process.cwd());
  if (fs.existsSync(current) && !fs.statSync(current).isDirectory()) {
    current = path.dirname(current);
  }

  while (true) {
    if (fs.existsSync(path.join(current, "dronevsplayers.sbproj"))) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`Could not find S&Box project root from '${start || process.cwd()}'.`);
    }
    current = parent;
  }
}

function readJson(root, relativePath) {
  const fullPath = path.join(root, relativePath);
  return JSON.parse(fs.readFileSync(fullPath, "utf8"));
}

function walk(node, visitor) {
  if (!node) return;
  visitor(node);
  for (const child of node.Children || []) {
    walk(child, visitor);
  }
}

function findChild(node, name) {
  return (node.Children || []).find((child) => child.Name === name) || null;
}

function findDescendantPath(rootObject, parts) {
  let current = rootObject;
  for (const part of parts) {
    current = findChild(current, part);
    if (!current) return null;
  }
  return current;
}

function componentTypes(node) {
  return (node.Components || [])
    .map((component) => component.__type)
    .filter((type) => typeof type === "string" && type.length > 0);
}

function hasComponent(node, type) {
  return componentTypes(node).includes(type);
}

function hasModel(node, model) {
  let found = false;
  walk(node, (child) => {
    for (const component of child.Components || []) {
      if (component.Model === model) {
        found = true;
      }
    }
  });
  return found;
}

function collectModels(node) {
  const models = new Set();
  walk(node, (child) => {
    for (const component of child.Components || []) {
      if (typeof component.Model === "string" && component.Model.length > 0) {
        models.add(component.Model);
      }
    }
  });
  return models;
}

function childNames(node) {
  return new Set((node.Children || []).map((child) => child.Name));
}

function normalizedSnapshot(node) {
  const clone = JSON.parse(JSON.stringify(node));
  const guidReplacements = new Map();
  let nextGuid = 1;

  delete clone.NetworkMode;
  delete clone.__variables;
  delete clone.__properties;

  walk(clone, (child) => {
    if (child.__guid) {
      guidReplacements.set(child.__guid, `GUID_${nextGuid++}`);
      child.__guid = guidReplacements.get(child.__guid);
    }
    for (const component of child.Components || []) {
      if (component.__guid) {
        guidReplacements.set(component.__guid, `GUID_${nextGuid++}`);
        component.__guid = guidReplacements.get(component.__guid);
      }
    }
  });

  function normalize(value) {
    if (Array.isArray(value)) {
      value.forEach(normalize);
      return;
    }
    if (!value || typeof value !== "object") return;

    for (const [key, current] of Object.entries(value)) {
      if ((key === "__guid" || key === "go" || key === "component_id") && guidReplacements.has(current)) {
        value[key] = guidReplacements.get(current);
      } else {
        normalize(current);
      }
    }
  }

  normalize(clone);
  return JSON.stringify(clone);
}

function addIssue(issues, severity, area, issuePath, message, recommendation = "") {
  issues.push({ severity, area, path: issuePath, message, recommendation });
}

function printIssues(issues, showInfo) {
  const visible = issues.filter((issue) => showInfo || issue.severity !== "Info");
  if (visible.length === 0) {
    console.log("No blocking issues found.");
    return;
  }

  for (const issue of visible) {
    const location = issue.path ? ` [${issue.path}]` : "";
    console.log(`[${issue.severity}] ${issue.area}${location} - ${issue.message}`);
    if (issue.recommendation) {
      console.log(`  Recommendation: ${issue.recommendation}`);
    }
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = findProjectRoot(args.root || process.cwd());
  const issues = [];

  console.log("");
  console.log("== Held Item Prefab Template Audit ==");
  console.log(`Root: ${root}`);

  for (const spec of heldItemTemplates) {
    const targetFullPath = path.join(root, spec.path);
    if (!fs.existsSync(targetFullPath)) {
      addIssue(
        issues,
        "Error",
        "Held Item Template",
        spec.path,
        `${spec.label} template prefab is missing.`,
        "Run scripts/agents/sync_held_item_prefab_templates.ps1 to scaffold the reusable held-item prefab from the active loadout source."
      );
      continue;
    }

    let template;
    let source;
    try {
      template = readJson(root, spec.path);
      source = readJson(root, spec.source);
    } catch (error) {
      addIssue(issues, "Error", "Held Item Template", spec.path, error.message, "Fix invalid JSON before relying on this prefab template.");
      continue;
    }

    const rootObject = template.RootObject;
    if (!rootObject) {
      addIssue(issues, "Error", "Held Item Template", spec.path, "Template has no RootObject.", "Regenerate the held-item template prefab.");
      continue;
    }

    if (rootObject.Name !== spec.rootName) {
      addIssue(issues, "Error", "Held Item Template", spec.path, `RootObject should be '${spec.rootName}', found '${rootObject.Name}'.`, "Keep template roots directly compatible with the active loadout child name.");
    }

    if (!hasComponent(rootObject, spec.component)) {
      addIssue(issues, "Error", "Held Item Template", spec.path, `Template root is missing component '${spec.component}'.`, "Keep the reusable item prefab as a complete held-item graph, not only a visual mesh.");
    }

    const names = childNames(rootObject);
    for (const requiredChild of spec.requiredChildren) {
      if (!names.has(requiredChild)) {
        addIssue(issues, "Error", "Held Item Template", spec.path, `Template is missing child '${requiredChild}'.`, "Keep child sockets and IK targets in the reusable template so AutoWire and first-person viewmodels have stable anchors.");
      }
    }

    if (spec.model && !hasModel(rootObject, spec.model)) {
      addIssue(issues, "Error", "Held Item Template", spec.path, `Template does not render expected model '${spec.model}'.`, "Copy the current active loadout visual into the reusable template or update the contract intentionally.");
    }

    if (spec.models) {
      const models = collectModels(rootObject);
      for (const model of spec.models) {
        if (!models.has(model)) {
          addIssue(issues, "Error", "Held Item Template", spec.path, `Template does not render expected model '${model}'.`, "Copy all pilot deployer visual pieces into the reusable template.");
        }
      }
    }

    const sourceNode = findDescendantPath(source.RootObject, spec.sourcePath);
    if (!sourceNode) {
      addIssue(issues, "Error", "Held Item Source", spec.source, `Could not find source path '${spec.sourcePath.join("/")}'.`, "Restore the active loadout child or update the template source map.");
      continue;
    }

    if (normalizedSnapshot(sourceNode) !== normalizedSnapshot(rootObject)) {
      addIssue(
        issues,
        "Error",
        "Held Item Template",
        spec.path,
        `Template has drifted from active source '${spec.source}:${spec.sourcePath.join("/")}'.`,
        "Regenerate templates after intentional loadout prefab edits so reusable item prefabs stay integration-ready."
      );
    } else {
      addIssue(issues, "Info", "Held Item Template", spec.path, `${spec.label} template matches the active loadout source.`);
    }
  }

  printIssues(issues, args.showInfo);

  if (issues.some((issue) => issue.severity === "Error")) {
    process.exit(1);
  }
  if (args.failOnWarning && issues.some((issue) => issue.severity === "Warning")) {
    process.exit(1);
  }
}

main();
