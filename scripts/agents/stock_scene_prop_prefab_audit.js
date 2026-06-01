#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const templates = [
  {
    path: "Assets/prefabs/environment/stock/beech_shrub_wide_small.prefab",
    rootName: "BeechShrubWideSmall",
    model: "models/sbox_props/shrubs/beech/beech_shrub_wide_small.vmdl",
    components: ["Sandbox.ModelRenderer"],
  },
  {
    path: "Assets/prefabs/environment/stock/pine_shrub_tall_b.prefab",
    rootName: "PineShrubTallB",
    model: "models/sbox_props/shrubs/pine/pine_shrub_tall_b.vmdl",
    components: ["Sandbox.ModelRenderer"],
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_medium_wall.prefab",
    rootName: "BeechBushMediumWall",
    model: "models/sbox_props/shrubs/beech/beech_bush_medium_wall.vmdl",
    components: ["Sandbox.ModelRenderer"],
  },
  {
    path: "Assets/prefabs/environment/stock/beech_bush_regular_medium_b.prefab",
    rootName: "BeechBushRegularMediumB",
    model: "models/sbox_props/shrubs/beech/beech_bush_regular_medium_b.vmdl",
    components: ["Sandbox.ModelRenderer"],
  },
  {
    path: "Assets/prefabs/environment/stock/beech_hedge_96x128_corner.prefab",
    rootName: "BeechHedge96x128Corner",
    model: "models/sbox_props/shrubs/beech/beech_hedge_96x128_corner.vmdl",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large.prefab",
    rootName: "FencePanelLarge",
    model: "models/props/temporary_fencing/fence_panel_large.vmdl",
    packageIdent: "facepunch.fence_panel_large",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/fence_panel_large_bent.prefab",
    rootName: "FencePanelLargeBent",
    model: "models/props/temporary_fencing/fence_panel_large_bent.vmdl",
    packageIdent: "facepunch.fence_panel_large_bent",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/bench_table_01.prefab",
    rootName: "BenchTable01",
    model: "models/props/trim_sheets/bench/bench_table/bench_table_01.vmdl",
    packageIdent: "facepunch.bench_table_01",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/old_bench.prefab",
    rootName: "OldBench",
    model: "models/sbox_props/benches/old_bench.vmdl",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/iron_fence_128.prefab",
    rootName: "IronFence128",
    model: "models/sbox_props/iron_fence/iron_fence_128.vmdl",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/tree_oak_big_a.prefab",
    rootName: "TreeOakBigA",
    model: "models/sbox_props/trees/oak/tree_oak_big_a.vmdl",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
  },
  {
    path: "Assets/prefabs/environment/stock/street_bin_rubbish.prefab",
    rootName: "StreetBinRubbish",
    model: "models/sbox_props/bin/street_bin_rubbish.vmdl",
    components: ["Sandbox.Prop", "Sandbox.ModelRenderer", "Sandbox.ModelCollider", "Sandbox.Rigidbody"],
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

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readPackageReferences() {
  const projectPath = path.join(root, "dronevsplayers.sbproj");
  if (!fs.existsSync(projectPath)) {
    return new Set();
  }

  const project = readJson(projectPath);
  return new Set(project.PackageReferences || []);
}

function walkGameObjects(node, callback) {
  callback(node);
  for (const child of node.Children || []) {
    walkGameObjects(child, callback);
  }
}

function countSceneObjectUses(model) {
  const scenePath = path.join(root, "Assets/scenes/main.scene");
  if (!fs.existsSync(scenePath)) {
    return 0;
  }

  const scene = readJson(scenePath);
  let count = 0;
  for (const gameObject of scene.GameObjects || []) {
    walkGameObjects(gameObject, (node) => {
      if ((node.Components || []).some((component) => component.Model === model)) {
        count += 1;
      }
    });
  }
  return count;
}

function countScenePrefabUses(prefabPath) {
  const scenePath = path.join(root, "Assets/scenes/main.scene");
  if (!fs.existsSync(scenePath)) {
    return 0;
  }

  const scene = readJson(scenePath);
  let count = 0;
  for (const gameObject of scene.GameObjects || []) {
    walkGameObjects(gameObject, (node) => {
      if (node.__Prefab === prefabPath) {
        count += 1;
      }
    });
  }
  return count;
}

function inspectPrefab(template) {
  const absolutePath = path.join(root, template.path);
  if (!fs.existsSync(absolutePath)) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      template.path,
      "Required stock scene prop prefab is missing.",
      "Generate reusable prefab templates for direct stock props used by the scene.",
    );
    return;
  }

  let prefab;
  try {
    prefab = readJson(absolutePath);
  } catch (error) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      template.path,
      `Prefab JSON failed to parse: ${error.message}`,
      "Fix invalid prefab JSON before relying on the stock prop template.",
    );
    return;
  }

  const rootObject = prefab.RootObject;
  if (!rootObject) {
    addIssue("Error", "Stock Scene Prop Prefab", template.path, "Prefab has no RootObject.", "Regenerate or repair the prefab JSON.");
    return;
  }

  if (rootObject.Name !== template.rootName) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      template.path,
      `Root name expected '${template.rootName}' but found '${rootObject.Name}'.`,
      "Keep stock prop prefab root names stable for asset browser discovery.",
    );
  }

  const raw = fs.readFileSync(absolutePath, "utf8");
  for (const component of template.components) {
    if (!raw.includes(`"__type": "${component}"`)) {
      addIssue(
        "Error",
        "Stock Scene Prop Prefab",
        template.path,
        `Missing required component '${component}'.`,
        "Keep reusable stock prop templates aligned with the scene-authored prop contract.",
      );
    }
  }

  if (!raw.includes(`"Model": "${template.model}"`)) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      template.path,
      `Missing required model reference '${template.model}'.`,
      "Use the same stock model as the direct scene prop this prefab replaces.",
    );
  }

  if (template.packageIdent && !packageReferences.has(template.packageIdent)) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      "dronevsplayers.sbproj",
      `${template.path} references mounted primary asset '${template.model}', but package '${template.packageIdent}' is not mounted.`,
      "Add the Facepunch model package reference before treating this stock prop prefab as integrated.",
    );
  }

  const sceneUses = countSceneObjectUses(template.model);
  if (sceneUses > 0) {
    addIssue(
      requireMigrated ? "Error" : "Info",
      "Stock Scene Prop Prefab",
      "Assets/scenes/main.scene",
      `${sceneUses} direct scene object(s) use ${template.model}; prefab template is available for a future editor scene migration pass.`,
      requireMigrated ? "Run the stock scene prop prefab instance migration so scene placements reference prefab templates directly." : "",
    );
  }

  const prefabUses = countScenePrefabUses(template.path.replace(/^Assets\//, ""));
  if (prefabUses > 0) {
    addIssue(
      "Info",
      "Stock Scene Prop Prefab",
      "Assets/scenes/main.scene",
      `${prefabUses} scene prefab instance(s) use ${template.path}.`,
    );
  }

  addIssue("Info", "Stock Scene Prop Prefab", template.path, "Stock scene prop prefab template check completed.");
}

function inspectEditorMigrationCommand() {
  const relativePath = "Editor/StockScenePropPrefabEditorCommands.cs";
  const absolutePath = path.join(root, relativePath);
  if (!fs.existsSync(absolutePath)) {
    addIssue(
      "Error",
      "Stock Scene Prop Prefab",
      relativePath,
      "Editor migration command is missing.",
      "Add a debug-only editor command that replaces direct stock scene props with prefab API clones instead of hand-authored JSON patches.",
    );
    return;
  }

  const source = fs.readFileSync(absolutePath, "utf8");
  const requiredPatterns = [
    {
      pattern: /dvp_preview_stock_scene_prop_prefab_migration/,
      message: "Missing dry-run preview command for stock scene prop prefab migration.",
    },
    {
      pattern: /dvp_migrate_stock_scene_props_to_prefabs/,
      message: "Missing migration command for stock scene prop prefab integration.",
    },
    {
      pattern: /GameObject\.Clone\s*\(/,
      message: "Migration command must instantiate prefab sources through the S&Box prefab clone API.",
    },
    {
      pattern: /clone\.PrefabInstanceSource/,
      message: "Migration command must verify prefab source metadata on cloned scene roots.",
    },
    {
      pattern: /IsPrefabInstance/,
      message: "Migration command must skip existing prefab instances.",
    },
    {
      pattern: /EditorChanges\.MarkDirty/,
      message: "Migration command must mark the editor scene dirty after live mutations.",
    },
  ];

  for (const requirement of requiredPatterns) {
    if (!requirement.pattern.test(source)) {
      addIssue(
        "Error",
        "Stock Scene Prop Prefab",
        relativePath,
        requirement.message,
      );
    }
  }

  addIssue("Info", "Stock Scene Prop Prefab", relativePath, "Editor migration command check completed.");
}

console.log("");
console.log("== Stock Scene Prop Prefab Audit ==");
console.log(`Root: ${normalizeSlashes(root)}`);

const packageReferences = readPackageReferences();

for (const template of templates) {
  inspectPrefab(template);
}

inspectEditorMigrationCommand();

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
