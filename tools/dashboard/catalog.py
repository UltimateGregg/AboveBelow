"""Read-only catalog functions for the ops dashboard.

Parses the suite list out of run_agent_checks.ps1's ValidateSet so the
dashboard stays in sync when suites are added, enumerates asset-pipeline
configs, and lists/reads .tmpbuild reports with traversal-safe paths.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

REPORT_EXTENSIONS = {".md", ".log", ".txt"}
REPORT_FILE_CAP = 500
REPORT_BYTES_CAP = 2 * 1024 * 1024
FALLBACK_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
CONFIG_NAME_RE = re.compile(r"^[A-Za-z0-9][\w\-]*_asset_pipeline\.json$")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


# ---------------------------------------------------------------------------
# Suite catalog
# ---------------------------------------------------------------------------

GROUPS = [
    {"id": "comprehensive", "label": "Comprehensive"},
    {"id": "build", "label": "Build & Logs"},
    {"id": "prefab-combat", "label": "Prefabs: Combat & Items"},
    {"id": "prefab-scene", "label": "Prefabs: Scene"},
    {"id": "scene", "label": "Scene & World"},
    {"id": "assets", "label": "Assets & Models"},
    {"id": "audio-net", "label": "Audio & Networking"},
    {"id": "gameplay", "label": "Gameplay & Balance"},
    {"id": "docs", "label": "Docs & Reference"},
    {"id": "workflow", "label": "UI & Workflow"},
    {"id": "other", "label": "Other"},
]

# suite -> (group, description, durationClass: fast|medium|slow|blender)
SUITE_META = {
    "quick": ("comprehensive", "Standard pre-commit sweep: ~50 audits across build, prefabs, scene, assets, docs (5-7 min)", "slow"),
    "full": ("comprehensive", "Everything in quick plus automation self-test, FBX material slots, balance + playtest reports", "slow"),
    "build": ("build", "Build log sentinel + s&box whitelist audit", "fast"),
    "logs": ("build", "Scan the current s&box log for errors and warnings", "fast"),
    "self-test": ("build", "Validates the agent automation layer itself", "medium"),
    "prefab": ("prefab-combat", "Umbrella sweep: 21 prefab wiring and quality audits", "medium"),
    "prefab-graph": ("prefab-combat", "Prefab reference graph integrity", "fast"),
    "held-items": ("prefab-combat", "Held-item prefab template conformance", "fast"),
    "viewmodel-prefab": ("prefab-combat", "First-person viewmodel prefab", "fast"),
    "runtime-prefab-fallbacks": ("prefab-combat", "Runtime prefab fallback coverage", "fast"),
    "ballistic-tracers": ("prefab-combat", "Ballistic tracer prefab audit", "fast"),
    "muzzle-flash-prefab": ("prefab-combat", "Muzzle flash effect prefab audit", "fast"),
    "grenade-effects": ("prefab-combat", "Grenade detonation effect prefabs", "fast"),
    "thrown-grenade-projectile": ("prefab-combat", "Thrown grenade projectile prefab", "fast"),
    "transient-combat": ("prefab-combat", "Transient combat prefabs (impacts, casings)", "fast"),
    "training-dummy-prefab": ("prefab-combat", "Training dummy pawn prefab", "fast"),
    "team-voice-prefabs": ("prefab-combat", "Team voice comms prefabs", "fast"),
    "team-comms-prefab": ("prefab-combat", "Team comms HUD prefab", "fast"),
    "scene-markers": ("prefab-scene", "Scene marker prefab audit (RequireMigrated)", "fast"),
    "buildings": ("prefab-scene", "Building scene prefab audit (RequireMigrated)", "fast"),
    "readability-lights": ("prefab-scene", "Readability light scene prefab audit (RequireMigrated)", "fast"),
    "ambient-sounds": ("prefab-scene", "Ambient sound scene prefab audit (RequireMigrated)", "fast"),
    "scene-singletons": ("prefab-scene", "Scene singleton prefab audit (RequireMigrated)", "fast"),
    "stock-scene-props": ("prefab-scene", "Stock scene prop prefab audit", "fast"),
    "terrain-scene-prefabs": ("prefab-scene", "Terrain scene prefab migration audit", "fast"),
    "scene-prefab-coverage": ("prefab-scene", "Scene-to-prefab migration coverage", "fast"),
    "scene": ("scene", "18-audit world sweep: integrity, blue lines, terrain, roads, layout, collision, nav", "medium"),
    "blue-lines": ("scene", "Blockout blue-line audit", "fast"),
    "terrain": ("scene", "Terrain floor audit", "fast"),
    "collision": ("scene", "Collision authoring chain: authoring, scale, trees, nav, ladders, layout", "blender"),
    "collision-chain": ("scene", "Collision agent chain audit + report", "medium"),
    "nav": ("scene", "Nav / collision QA audit", "fast"),
    "asset": ("assets", "Asset pipeline + drone visuals + FBX material slots", "medium"),
    "asset-production": ("assets", "AAA quality bar: Blender quality, textures, modeldoc, readiness", "blender"),
    "modeldoc": ("assets", "ModelDoc + collision scale + animated intake", "medium"),
    "animated-model": ("assets", "Animated model intake audit", "fast"),
    "blender-live": ("assets", "Blender live toolkit self-test", "blender"),
    "sound": ("audio-net", "Sound assets, ambient noise, playback wiring", "medium"),
    "networking": ("audio-net", "Networking review ([Sync]/RPC patterns)", "fast"),
    "gameplay-regression": ("gameplay", "Gameplay regression guard (20+ behavior checks)", "fast"),
    "balance": ("gameplay", "Balance config + M4 fire rate + tuning report", "medium"),
    "playtest": ("gameplay", "Playtest checklist (all areas)", "fast"),
    "readiness": ("gameplay", "Feature readiness report + large-component risk", "medium"),
    "docs": ("docs", "Roadmap + all s&box reference intake audits", "medium"),
    "api": ("docs", "API reference audit + sample symbol lookup", "fast"),
    "sbox-docs": ("docs", "s&box docs source snapshot audit", "fast"),
    "release-notes": ("docs", "Release notes + engine/API reference", "medium"),
    "code-search": ("docs", "Code search audits + engine reference", "medium"),
    "learn": ("docs", "Learn intake + UI flow + node tool refs", "medium"),
    "ui": ("workflow", "UI copy + flow audits + UI playtest checklist + readiness", "medium"),
    "editor-first": ("workflow", "Editor-first workflow audit", "fast"),
    "editor-node-tool": ("workflow", "Editor node tool audit", "fast"),
    "train": ("workflow", "Post-task training agent (writes report) + quality/reference audits", "medium"),
}

_validate_set_cache: tuple[float, list[str]] | None = None


def runner_script(root: Path) -> Path:
    return root / "scripts" / "agents" / "run_agent_checks.ps1"


def parse_validate_set(root: Path) -> list[str]:
    """Parse suite names from run_agent_checks.ps1, cached by mtime."""
    global _validate_set_cache
    path = runner_script(root)
    mtime = path.stat().st_mtime
    if _validate_set_cache and _validate_set_cache[0] == mtime:
        return _validate_set_cache[1]

    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\[ValidateSet\(([^)]*)\)\]", text, re.DOTALL)
    if not match:
        raise RuntimeError(f"No ValidateSet found in {path}")
    names = re.findall(r'"([^"]+)"', match.group(1))
    if len(names) < 10:
        raise RuntimeError(
            f"ValidateSet parse looks wrong: only {len(names)} suites found in {path}"
        )
    _validate_set_cache = (mtime, names)
    return names


def blender_exe(root: Path) -> str:
    """DEFAULT_BLENDER from asset_pipeline.py, with a hardcoded fallback."""
    try:
        text = (root / "scripts" / "asset_pipeline.py").read_text(
            encoding="utf-8", errors="replace"
        )
        match = re.search(r'DEFAULT_BLENDER\s*=\s*r?"([^"]+)"', text)
        if match:
            return match.group(1)
    except OSError:
        pass
    return FALLBACK_BLENDER


def suite_catalog(root: Path) -> dict:
    names = parse_validate_set(root)
    suites = []
    for name in names:
        group, description, duration = SUITE_META.get(name, ("other", "", "fast"))
        suites.append(
            {
                "name": name,
                "group": group,
                "description": description,
                "durationClass": duration,
            }
        )
    return {
        "root": str(root),
        "blenderFound": Path(blender_exe(root)).exists(),
        "groups": GROUPS,
        "suites": suites,
    }


# ---------------------------------------------------------------------------
# Asset pipeline configs
# ---------------------------------------------------------------------------

def valid_config_name(name: str) -> bool:
    return bool(CONFIG_NAME_RE.match(name))


def resolve_config(root: Path, name: str) -> Path | None:
    """Validated absolute path of a pipeline config, or None if rejected."""
    if not valid_config_name(name):
        return None
    path = safe_resolve(root / "scripts", name)
    if path is None or not path.is_file():
        return None
    return path


def list_pipeline_configs(root: Path) -> list[dict]:
    configs = []
    for path in sorted((root / "scripts").glob("*_asset_pipeline.json")):
        if not valid_config_name(path.name):
            continue
        entry: dict = {
            "name": path.name,
            "asset": path.name[: -len("_asset_pipeline.json")],
            "mtime": path.stat().st_mtime,
        }
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            entry.update(
                {
                    "sourceBlend": data.get("source_blend"),
                    "targetFbx": data.get("target_fbx"),
                    "targetVmdl": data.get("target_vmdl"),
                    "hasCollision": bool(data.get("collision")),
                    "hasPrefab": bool(data.get("prefab")),
                    "materialCount": len(data.get("material_remap") or {}),
                }
            )
        except (json.JSONDecodeError, OSError):
            entry["error"] = "unparseable"
        configs.append(entry)
    return configs


# ---------------------------------------------------------------------------
# Reports (.tmpbuild)
# ---------------------------------------------------------------------------

def safe_resolve(base: Path, rel: str) -> Path | None:
    """Resolve rel under base; None on traversal/absolute/drive-qualified input."""
    if not rel or rel.startswith(("/", "\\")) or ":" in rel:
        return None
    resolved_base = base.resolve()
    candidate = (resolved_base / rel).resolve()
    try:
        ok = candidate.is_relative_to(resolved_base)
    except AttributeError:  # Python < 3.9
        try:
            ok = os.path.commonpath([str(candidate), str(resolved_base)]) == str(resolved_base)
        except ValueError:
            ok = False
    return candidate if ok else None


def reports_dir(root: Path) -> Path:
    return root / ".tmpbuild"


def list_reports(root: Path) -> list[dict]:
    base = reports_dir(root)
    if not base.is_dir():
        return []
    files = []
    for dirpath, _dirnames, filenames in os.walk(base):
        for filename in filenames:
            if Path(filename).suffix.lower() not in REPORT_EXTENSIONS:
                continue
            full = Path(dirpath) / filename
            try:
                stat = full.stat()
            except OSError:
                continue
            rel = full.relative_to(base).as_posix()
            files.append(
                {
                    "rel": rel,
                    "name": filename,
                    "dir": str(Path(rel).parent.as_posix()) if "/" in rel else "",
                    "sizeBytes": stat.st_size,
                    "mtime": stat.st_mtime,
                    "ext": full.suffix.lower(),
                }
            )
    files.sort(key=lambda f: f["mtime"], reverse=True)
    return files[:REPORT_FILE_CAP]


def read_report(root: Path, rel: str) -> dict | None:
    base = reports_dir(root)
    path = safe_resolve(base, rel)
    if path is None:
        return None
    if not path.is_file() or path.suffix.lower() not in REPORT_EXTENSIONS:
        return {"missing": True}
    stat = path.stat()
    truncated = stat.st_size > REPORT_BYTES_CAP
    with path.open("rb") as fh:
        if truncated and path.suffix.lower() == ".log":
            fh.seek(stat.st_size - REPORT_BYTES_CAP)
            raw = fh.read()
            # Drop the first partial line after seeking mid-file.
            newline = raw.find(b"\n")
            if newline != -1:
                raw = raw[newline + 1 :]
        else:
            raw = fh.read(REPORT_BYTES_CAP)
    return {
        "rel": rel,
        "sizeBytes": stat.st_size,
        "mtime": stat.st_mtime,
        "truncated": truncated,
        "content": raw.decode("utf-8", errors="replace"),
    }


if __name__ == "__main__":
    root = repo_root()
    names = parse_validate_set(root)
    unknown = [n for n in names if n not in SUITE_META]
    print(f"root: {root}")
    print(f"suites: {len(names)} ({len(unknown)} unmapped: {unknown})")
    print(f"blender: {blender_exe(root)} (found={Path(blender_exe(root)).exists()})")
    configs = list_pipeline_configs(root)
    print(f"pipeline configs: {len(configs)}")
    reports = list_reports(root)
    print(f"reports: {len(reports)}")
    for report in reports[:5]:
        print(f"  {report['rel']} ({report['sizeBytes']} bytes)")
