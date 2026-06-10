#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/environment/stock/beech_shrub_wide_small.prefab",
    model: "models/sbox_props/shrubs/beech/beech_shrub_wide_small.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/pine_shrub_tall_b.prefab",
    model: "models/sbox_props/shrubs/pine/pine_shrub_tall_b.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_medium_wall.prefab",
    model: "models/sbox_props/shrubs/beech/beech_bush_medium_wall.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_regular_medium_b.prefab",
    model: "models/sbox_props/shrubs/beech/beech_bush_regular_medium_b.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_hedge_96x128_corner.prefab",
    model: "models/sbox_props/shrubs/beech/beech_hedge_96x128_corner.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/beech_hedge_40x128.prefab",
    model: "models/sbox_props/shrubs/beech/beech_hedge_40x128.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large.prefab",
    model: "models/props/temporary_fencing/fence_panel_large.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large_bent.prefab",
    model: "models/props/temporary_fencing/fence_panel_large_bent.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/bench_table_01.prefab",
    model: "models/props/trim_sheets/bench/bench_table/bench_table_01.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/old_bench.prefab",
    model: "models/sbox_props/benches/old_bench.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/iron_fence_128.prefab",
    model: "models/sbox_props/iron_fence/iron_fence_128.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/tree_oak_big_a.prefab",
    model: "models/sbox_props/trees/oak/tree_oak_big_a.vmdl",
  },
  {
    path: "Assets/prefabs/environment/stock/street_bin_rubbish.prefab",
    model: "models/sbox_props/bin/street_bin_rubbish.vmdl",
  },
  {
    // Custom-authored prop (not stock, not synced): the scene placement collapses
    // onto the hand-authored static prefab at this path.
    path: "Assets/prefabs/environment/bouneurmaum_park_sign.prefab",
    model: "models/bouneurmaum_park_sign.vmdl",
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

function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function objectIdentifier(type, idValue) {
  return { Type: type, IdValue: idValue };
}

function collectPrefabIds(prefabObject, sourceObject, mapping, seed) {
  mapping[prefabObject.__guid] = sourceObject?.__guid || stableGuid(`${seed}:object:${prefabObject.__guid}`);

  const sourceComponentsByType = new Map();
  for (const component of sourceObject?.Components || []) {
    const type = component.__type || "";
    if (!sourceComponentsByType.has(type)) {
      sourceComponentsByType.set(type, []);
    }
    sourceComponentsByType.get(type).push(component);
  }

  for (const component of prefabObject.Components || []) {
    const candidates = sourceComponentsByType.get(component.__type || "") || [];
    const sourceComponent = candidates.shift();
    mapping[component.__guid] = sourceComponent?.__guid || stableGuid(`${seed}:component:${component.__guid}`);
  }

  const sourceChildren = sourceObject?.Children || [];
  for (let i = 0; i < (prefabObject.Children || []).length; i += 1) {
    collectPrefabIds(prefabObject.Children[i], sourceChildren[i], mapping, `${seed}:child:${i}`);
  }
}

function addPropertyOverride(overrides, type, idValue, property, value) {
  overrides.push({
    Target: objectIdentifier(type, idValue),
    Property: property,
    Value: value,
  });
}

function addRootOverrides(overrides, source, prefabRoot) {
  const ignored = new Set(["__guid", "__version", "Components", "Children"]);
  for (const [key, value] of Object.entries(source)) {
    if (ignored.has(key)) {
      continue;
    }

    if (!deepEqual(value, prefabRoot[key])) {
      addPropertyOverride(overrides, "GameObject", prefabRoot.__guid, key, value);
    }
  }
}

function addComponentOverrides(overrides, source, prefabRoot) {
  const sourceComponentsByType = new Map();
  for (const component of source.Components || []) {
    const type = component.__type || "";
    if (!sourceComponentsByType.has(type)) {
      sourceComponentsByType.set(type, []);
    }
    sourceComponentsByType.get(type).push(component);
  }

  for (const prefabComponent of prefabRoot.Components || []) {
    const candidates = sourceComponentsByType.get(prefabComponent.__type || "") || [];
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

function findTemplateForObject(node, modelToTemplate) {
  if (node.__Prefab) {
    return null;
  }

  const modelPaths = new Set(
    (node.Components || [])
      .map((component) => component.Model)
      .filter((model) => modelToTemplate.has(model)),
  );
  if (modelPaths.size !== 1) {
    return null;
  }

  return modelToTemplate.get(Array.from(modelPaths)[0]);
}

function toPrefabInstance(source, template, prefab) {
  if ((source.Children || []).length > 0) {
    throw new Error(`${source.Name} has child objects; refusing to collapse it into a stock prefab instance.`);
  }

  const prefabRoot = prefab.RootObject;
  const mapping = {};
  collectPrefabIds(prefabRoot, source, mapping, source.__guid);

  const overrides = [];
  addRootOverrides(overrides, source, prefabRoot);
  addComponentOverrides(overrides, source, prefabRoot);

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

function migrateArray(objects, modelToTemplate, prefabByPath, stats) {
  for (let i = 0; i < objects.length; i += 1) {
    const node = objects[i];
    const template = findTemplateForObject(node, modelToTemplate);
    if (template) {
      objects[i] = toPrefabInstance(node, template, prefabByPath.get(template.path));
      stats.migrated += 1;
      stats.byPrefab.set(template.path, (stats.byPrefab.get(template.path) || 0) + 1);
      continue;
    }

    migrateArray(node.Children || [], modelToTemplate, prefabByPath, stats);
  }
}

function serializeScene(scene, originalText) {
  // Preserve the on-disk formatting so the rewrite only touches migrated nodes:
  // keep ulong values JSON.parse mangles, the file's EOL style, and its
  // trailing-newline behaviour.
  let serialized = JSON.stringify(scene, null, 2).replace(/\b18446744073709552000\b/g, "18446744073709551615");
  if (originalText.endsWith("\n")) {
    serialized += "\n";
  }
  if (originalText.includes("\r\n")) {
    serialized = serialized.replace(/\n/g, "\r\n");
  }
  return serialized;
}

const scenePath = path.join(root, "Assets/scenes/main.scene");
const sceneText = fs.readFileSync(scenePath, "utf8");
const scene = JSON.parse(sceneText);
const modelToTemplate = new Map(templates.map((template) => [template.model, template]));
const prefabByPath = new Map();

for (const template of templates) {
  prefabByPath.set(template.path, readJson(template.path));
}

const stats = { migrated: 0, byPrefab: new Map() };
migrateArray(scene.GameObjects || [], modelToTemplate, prefabByPath, stats);

if (!dryRun && stats.migrated > 0) {
  fs.writeFileSync(scenePath, serializeScene(scene, sceneText));
}

const action = dryRun ? "Would migrate" : "Migrated";
console.log(`${action} ${stats.migrated} stock scene prop placement(s) to prefab instances.`);
for (const [prefabPath, count] of Array.from(stats.byPrefab.entries()).sort((a, b) => a[0].localeCompare(b[0]))) {
  console.log(` - ${count} ${prefabPath}`);
}
