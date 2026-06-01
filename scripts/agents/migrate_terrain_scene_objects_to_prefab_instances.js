#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/environment/terrain_assets.prefab",
    models: ["models/terrain_assets.vmdl"],
  },
  {
    path: "Assets/prefabs/environment/terrain_pine.prefab",
    models: ["models/terrain_pine.vmdl"],
  },
  {
    path: "Assets/prefabs/environment/terrain_pine_broad.prefab",
    models: ["models/terrain_pine_broad.vmdl"],
  },
  {
    path: "Assets/prefabs/environment/terrain_pine_windswept.prefab",
    models: ["models/terrain_pine_windswept.vmdl"],
  },
  {
    path: "Assets/prefabs/environment/terrain_rock.prefab",
    models: ["models/terrain_rock.vmdl"],
  },
  {
    path: "Assets/prefabs/environment/terrain_rock_model_collider.prefab",
    models: [],
    matchRootModel: "models/terrain_rock.vmdl",
    matchRootComponentTypes: ["Sandbox.ModelRenderer", "Sandbox.ModelCollider"],
  },
  {
    path: "Assets/prefabs/environment/Berm.prefab",
    models: [],
    matchRootNamePrefix: "Berm_",
  },
  {
    path: "Assets/prefabs/environment/hill_central_north_box.prefab",
    models: [],
    matchRootName: "Hill_CentralNorth",
  },
  {
    path: "Assets/prefabs/environment/Hill.prefab",
    models: [],
    matchRootNamePrefix: "Hill_",
  },
  {
    path: "Assets/prefabs/environment/plateau_east_north_terrain.prefab",
    models: [],
    matchRootName: "Plateau_EastNorth",
  },
  {
    path: "Assets/prefabs/environment/Plateau.prefab",
    models: [],
    matchRootNamePrefix: "Plateau_",
  },
  {
    path: "Assets/prefabs/environment/TrenchSegment.prefab",
    models: [],
    matchRootNamePrefix: "Trench_",
  },
  {
    path: "Assets/prefabs/environment/blockout_cover_box.prefab",
    models: [],
    matchPathPrefix: "BlockoutMap/LevelDesignPass_AboveBelow/",
    matchRootNames: ["DroneLaunchPad", "NorthLowCover"],
    matchRootModel: "models/dev/box.vmdl",
    matchRootComponentTypes: ["Sandbox.ModelRenderer", "Sandbox.BoxCollider"],
  },
  {
    path: "Assets/prefabs/environment/skyline_model_collider_box.prefab",
    models: [],
    matchRootModel: "models/dev/box.vmdl",
    matchRootComponentTypes: ["Sandbox.ModelRenderer", "Sandbox.ModelCollider"],
  },
  {
    path: "Assets/prefabs/environment/visual_dev_box.prefab",
    models: [],
    matchRootModel: "models/dev/box.vmdl",
    matchRootComponentTypes: ["Sandbox.ModelRenderer"],
  },
  {
    path: "Assets/prefabs/environment/grass_clump_single_card.prefab",
    models: [],
    matchGrassClump: true,
    grassCardSuffixes: ["BladeCard_A_Front"],
    allowChildNameSuffix: true,
  },
  {
    path: "Assets/prefabs/environment/grass_clump_five_card.prefab",
    models: [],
    matchGrassClump: true,
    grassCardSuffixes: [
      "BladeCard_A_Front",
      "BladeCard_A_Back",
      "BladeCard_B_Front",
      "BladeCard_B_Back",
      "BladeCard_C_Front",
      "BladeCard_C_Back",
    ],
    emptyGrassCardSuffixes: ["BladeCard_A_Back"],
    allowChildNameSuffix: true,
  },
  {
    path: "Assets/prefabs/environment/grass_clump.prefab",
    models: [],
    matchGrassClump: true,
    allowChildNameSuffix: true,
  },
  {
    path: "Assets/prefabs/environment/ground_grass_clump_patch.prefab",
    models: [],
    matchRootModel: "models/dev/plane.vmdl",
    matchMaterial: "materials/arena/grass_clump.vmat",
  },
  {
    path: "Assets/prefabs/environment/ground_worn_path_patch.prefab",
    models: [],
    matchRootModel: "models/dev/plane.vmdl",
    matchMaterial: "materials/arena/grass_worn_path.vmat",
  },
  {
    path: "Assets/prefabs/environment/berm_soft_cap.prefab",
    models: [],
    matchRootModel: "models/dev/sphere.vmdl",
    matchMaterial: "materials/arena/grass_ground.vmat",
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

function prefabInstancePath(template) {
  return template.path.replace(/^Assets\//, "");
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function stringifyJson(value) {
  return `${JSON.stringify(value, null, 2).replace(/\b18446744073709552000\b/g, "18446744073709551615")}\n`;
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

function numericParts(value) {
  if (typeof value !== "string" || !value.includes(",")) {
    return null;
  }

  const parts = value.split(",").map((part) => Number(part.trim()));
  if (parts.length < 2 || parts.some((part) => Number.isNaN(part))) {
    return null;
  }

  return parts;
}

function closeNumbers(a, b, tolerance = 0.01) {
  return Math.abs(a - b) <= tolerance;
}

function equivalentValue(sourceValue, prefabValue, propertyName = "") {
  if (JSON.stringify(sourceValue) === JSON.stringify(prefabValue)) {
    return true;
  }

  if (sourceValue === null && prefabValue === undefined) {
    return true;
  }

  const sourceParts = numericParts(sourceValue);
  const prefabParts = numericParts(prefabValue);
  if (sourceParts && prefabParts && sourceParts.length === prefabParts.length) {
    const direct = sourceParts.every((part, index) => closeNumbers(part, prefabParts[index]));
    if (direct) {
      return true;
    }

    if (propertyName === "Rotation" && sourceParts.length === 4) {
      return sourceParts.every((part, index) => closeNumbers(part, -prefabParts[index]));
    }
  }

  return false;
}

function componentTypes(components) {
  return (components || []).map((component) => component.__type || "");
}

function sameShape(sourceObject, prefabObject, template, isRoot = false) {
  const sourceChildren = sourceObject.Children || [];
  const prefabChildren = prefabObject.Children || [];
  if (sourceChildren.length !== prefabChildren.length) {
    return false;
  }

  if (!isRoot && sourceObject.Name !== prefabObject.Name) {
    const hasAllowedSuffix = template.allowChildNameSuffix && sourceObject.Name.endsWith(`_${prefabObject.Name}`);
    if (!hasAllowedSuffix) {
      return false;
    }
  }

  const sourceComponentTypes = componentTypes(sourceObject.Components);
  const prefabComponentTypes = componentTypes(prefabObject.Components);
  if (sourceComponentTypes.length !== prefabComponentTypes.length) {
    return false;
  }

  for (let i = 0; i < sourceComponentTypes.length; i += 1) {
    if (sourceComponentTypes[i] !== prefabComponentTypes[i]) {
      return false;
    }
  }

  for (let i = 0; i < sourceChildren.length; i += 1) {
    if (!sameShape(sourceChildren[i], prefabChildren[i], template, false)) {
      return false;
    }
  }

  return true;
}

function collectPrefabIds(prefabObject, sourceObject, mapping, seed) {
  mapping[prefabObject.__guid] = sourceObject?.__guid || stableGuid(`${seed}:object:${prefabObject.__guid}`);

  const sourceComponents = sourceObject?.Components || [];
  const prefabComponents = prefabObject.Components || [];
  for (let i = 0; i < prefabComponents.length; i += 1) {
    mapping[prefabComponents[i].__guid] = sourceComponents[i]?.__guid || stableGuid(`${seed}:component:${prefabComponents[i].__guid}`);
  }

  const sourceChildren = sourceObject?.Children || [];
  const prefabChildren = prefabObject.Children || [];
  for (let i = 0; i < prefabChildren.length; i += 1) {
    collectPrefabIds(prefabChildren[i], sourceChildren[i], mapping, `${seed}:child:${i}`);
  }
}

function addObjectOverrides(overrides, sourceObject, prefabObject, isRoot = false) {
  const ignored = new Set(["__guid", "__version", "__variables", "__properties", "Components", "Children"]);
  for (const [key, value] of Object.entries(sourceObject)) {
    if (ignored.has(key)) {
      continue;
    }

    if (!equivalentValue(value, prefabObject[key], key)) {
      addPropertyOverride(overrides, "GameObject", prefabObject.__guid, key, value);
    }
  }

  const sourceComponents = sourceObject.Components || [];
  const prefabComponents = prefabObject.Components || [];
  for (let i = 0; i < prefabComponents.length; i += 1) {
    addComponentOverrides(overrides, sourceComponents[i], prefabComponents[i]);
  }

  const sourceChildren = sourceObject.Children || [];
  const prefabChildren = prefabObject.Children || [];
  for (let i = 0; i < prefabChildren.length; i += 1) {
    addObjectOverrides(overrides, sourceChildren[i], prefabChildren[i], false);
  }
}

function addComponentOverrides(overrides, sourceComponent, prefabComponent) {
  if (!sourceComponent || !prefabComponent) {
    return;
  }

  const ignored = new Set(["__guid", "__type"]);
  for (const [key, value] of Object.entries(sourceComponent)) {
    if (ignored.has(key)) {
      continue;
    }

    if (!equivalentValue(value, prefabComponent[key], key)) {
      addPropertyOverride(overrides, "Component", prefabComponent.__guid, key, value);
    }
  }
}

function rootRendererModel(node) {
  for (const component of node.Components || []) {
    if (component.__type === "Sandbox.ModelRenderer" && component.Model) {
      return component.Model;
    }
  }

  return null;
}

function rootRenderer(node) {
  const renderers = (node.Components || []).filter((component) => component.__type === "Sandbox.ModelRenderer");
  if (renderers.length !== 1) {
    return null;
  }

  return renderers[0];
}

const defaultGrassCardSuffixes = [
  "BladeCard_A_Front",
  "BladeCard_A_Back",
  "BladeCard_B_Front",
  "BladeCard_B_Back",
  "BladeCard_C_Front",
  "BladeCard_C_Back",
];

function grassCardSuffix(name) {
  return defaultGrassCardSuffixes.find((suffix) => (name || "").endsWith(suffix)) || null;
}

function isGrassClumpObject(node, template) {
  if (node.__Prefab || (node.Components || []).length > 0) {
    return false;
  }

  const children = node.Children || [];
  const expectedSuffixes = template.grassCardSuffixes || defaultGrassCardSuffixes;
  if (children.length !== expectedSuffixes.length) {
    return false;
  }

  const expected = new Set(expectedSuffixes);
  const empty = new Set(template.emptyGrassCardSuffixes || []);
  const seen = new Set();
  return children.every((child) => {
    const suffix = grassCardSuffix(child.Name);
    if (!suffix || !expected.has(suffix) || seen.has(suffix)) {
      return false;
    }

    seen.add(suffix);
    if (empty.has(suffix)) {
      return (child.Components || []).length === 0;
    }

    const renderer = (child.Components || []).find((component) => component.__type === "Sandbox.ModelRenderer");
    return renderer &&
      renderer.Model === "models/dev/plane.vmdl" &&
      renderer.MaterialOverride === "materials/arena/grass_blade_card.vmat" &&
      /BladeCard_[ABC]_(Front|Back)$/.test(child.Name || "");
  });
}

function pathMatchesTemplate(template, scenePath) {
  if (template.matchRootNames && template.matchRootNames.includes(scenePath.split("/").pop())) {
    return true;
  }

  return !template.matchPathPrefix || scenePath.startsWith(template.matchPathPrefix);
}

function findTemplateForSingleRenderer(node, scenePath) {
  if ((node.Children || []).length > 0) {
    return null;
  }

  const renderer = rootRenderer(node);
  if (!renderer) {
    return null;
  }

  return templates.find((template) =>
    pathMatchesTemplate(template, scenePath) &&
    template.matchRootModel === renderer.Model &&
    template.matchMaterial === renderer.MaterialOverride,
  ) || null;
}

function findTemplateForRootComponents(node, scenePath) {
  if ((node.Children || []).length > 0) {
    return null;
  }

  const model = rootRendererModel(node);
  if (!model) {
    return null;
  }

  const types = componentTypes(node.Components);
  return templates.find((template) =>
    pathMatchesTemplate(template, scenePath) &&
    template.matchRootModel === model &&
    template.matchRootComponentTypes &&
    JSON.stringify(template.matchRootComponentTypes) === JSON.stringify(types),
  ) || null;
}

function findTemplateForRootName(node) {
  if (!node.Name) {
    return null;
  }

  if ((node.Components || []).length === 0 && (node.Children || []).length === 0) {
    return null;
  }

  const exactTemplate = templates.find((template) =>
    template.matchRootName &&
    node.Name === template.matchRootName,
  );
  if (exactTemplate) {
    return exactTemplate;
  }

  return templates.find((template) =>
    template.matchRootNamePrefix &&
    node.Name.startsWith(template.matchRootNamePrefix),
  ) || null;
}

function findTemplateForObject(node, modelToTemplate, scenePath) {
  if (node.__Prefab) {
    return null;
  }

  const rootNameTemplate = findTemplateForRootName(node);
  if (rootNameTemplate) {
    return rootNameTemplate;
  }

  const rootComponentTemplate = findTemplateForRootComponents(node, scenePath);
  if (rootComponentTemplate) {
    return rootComponentTemplate;
  }

  const singleRendererTemplate = findTemplateForSingleRenderer(node, scenePath);
  if (singleRendererTemplate) {
    return singleRendererTemplate;
  }

  for (const grassTemplate of templates.filter((template) => template.matchGrassClump)) {
    if (isGrassClumpObject(node, grassTemplate)) {
      return grassTemplate;
    }
  }

  const model = rootRendererModel(node);
  if (!model || !modelToTemplate.has(model)) {
    return null;
  }

  return modelToTemplate.get(model);
}

function toPrefabInstance(source, template, prefab) {
  const prefabRoot = prefab.RootObject;
  if (!sameShape(source, prefabRoot, template, true)) {
    return null;
  }

  const mapping = {};
  collectPrefabIds(prefabRoot, source, mapping, source.__guid);

  const overrides = [];
  addObjectOverrides(overrides, source, prefabRoot, true);

  return {
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
  };
}

function migrateArray(objects, modelToTemplate, prefabByPath, stats, parentPath = "") {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const nodePath = parentPath ? `${parentPath}/${node.Name || ""}` : (node.Name || "");
    const template = findTemplateForObject(node, modelToTemplate, nodePath);
    if (template) {
      const prefabInstance = toPrefabInstance(node, template, prefabByPath.get(template.path));
      if (prefabInstance) {
        objects[i] = prefabInstance;
        stats.migrated += 1;
        stats.byPrefab.set(template.path, (stats.byPrefab.get(template.path) || 0) + 1);
      } else {
        stats.skipped += 1;
        stats.skippedExamples.push(node.Name || node.__guid);
      }
      continue;
    }

    migrateArray(node.Children || [], modelToTemplate, prefabByPath, stats, nodePath);
  }
}

const scenePath = path.join(root, "Assets/scenes/main.scene");
const scene = JSON.parse(fs.readFileSync(scenePath, "utf8"));
const modelToTemplate = new Map();
const prefabByPath = new Map();

for (const template of templates) {
  prefabByPath.set(template.path, readJson(template.path));
  for (const model of template.models) {
    modelToTemplate.set(model, template);
  }
}

const stats = { migrated: 0, skipped: 0, skippedExamples: [], byPrefab: new Map() };
migrateArray(scene.GameObjects || [], modelToTemplate, prefabByPath, stats);

if (!dryRun && stats.migrated > 0) {
  fs.writeFileSync(scenePath, stringifyJson(scene));
}

const action = dryRun ? "Would migrate" : "Migrated";
console.log(`${action} ${stats.migrated} scene object placement(s) to prefab instances.`);
for (const [prefabPath, count] of Array.from(stats.byPrefab.entries()).sort((a, b) => a[0].localeCompare(b[0]))) {
  console.log(` - ${count} ${prefabPath}`);
}

if (stats.skipped > 0) {
  console.log(`Skipped ${stats.skipped} terrain object(s) whose child/component shape did not match the local prefab template.`);
  for (const name of stats.skippedExamples.slice(0, 12)) {
    console.log(` - ${name}`);
  }
}
