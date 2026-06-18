/* ABOVE / BELOW ops dashboard frontend.
   Vanilla JS, no dependencies. Talks only to the local dashboard server;
   MCP editor calls are proxied server-side. */

"use strict";

const S = {
  catalog: null,
  pipelines: null,
  reports: [],
  jobs: { current: null, queued: [], recent: [] },
  history: [],
  editor: { editorOnline: false },
  activeJobId: null,
  es: null,
  nextLine: 0,
  runOpts: { showInfo: false, failOnWarning: false },
  autoscroll: true,
  suiteFilter: "",
  reportFilter: "",
  activeReport: null,
  expandedHistory: null,
  logDomLines: 0,
};

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------------
// API helper + toast
// ---------------------------------------------------------------------------

async function api(path, options = {}) {
  const opts = { method: options.method || "GET", headers: {} };
  if (options.body !== undefined) {
    opts.method = options.method || "POST";
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(options.body);
  }
  const response = await fetch(path, opts);
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || `${response.status} ${response.statusText}`);
  }
  return data;
}

let toastTimer = null;
function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.classList.remove("hidden");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add("hidden"), 4000);
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

function fmtDuration(sec) {
  if (sec == null) return "";
  if (sec < 60) return `${sec.toFixed(0)}s`;
  return `${Math.floor(sec / 60)}m ${Math.round(sec % 60)}s`;
}

function fmtWhen(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  if (isNaN(date)) return iso;
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function fmtBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function fmtMtime(epoch) {
  const date = new Date(epoch * 1000);
  return date.toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function statePill(state) {
  return el("span", `state-pill ${state}`, state);
}

// ---------------------------------------------------------------------------
// Log colorizing
// ---------------------------------------------------------------------------

function classifyLine(line) {
  if (/^\[Error\]/.test(line)) return "sev-error";
  if (/^\[Warning\]/.test(line)) return "sev-warn";
  if (/^\[Info\]/.test(line)) return "sev-info";
  if (/^---- Running /.test(line)) return "sev-section";
  if (/^\s+Recommendation:/.test(line)) return "sev-reco";
  if (/error\s+(CS|MSB)\d/i.test(line)) return "sev-error";
  if (/completed\.\s*$/.test(line)) return "sev-pass";
  if (/failed:?\s*$/.test(line)) return "sev-fail";
  return "";
}

function colorizedFragment(lines) {
  const fragment = document.createDocumentFragment();
  for (const line of lines) {
    const span = el("span", classifyLine(line), line + "\n");
    fragment.appendChild(span);
  }
  return fragment;
}

const LOG_DOM_CAP = 20000;

function appendLogLines(lines) {
  const log = $("console-log");
  log.appendChild(colorizedFragment(lines));
  S.logDomLines += lines.length;
  while (S.logDomLines > LOG_DOM_CAP && log.firstChild) {
    log.removeChild(log.firstChild);
    S.logDomLines--;
  }
  if (S.autoscroll) log.scrollTop = log.scrollHeight;
}

function resetLog() {
  $("console-log").textContent = "";
  S.logDomLines = 0;
  S.nextLine = 0;
}

// ---------------------------------------------------------------------------
// Console drawer + SSE
// ---------------------------------------------------------------------------

function openDrawer() {
  $("console-drawer").classList.remove("collapsed");
}

function watchJob(jobId) {
  if (S.es) {
    S.es.close();
    S.es = null;
  }
  S.activeJobId = jobId;
  resetLog();
  openDrawer();
  renderConsoleHead();

  const es = new EventSource(`/api/stream/${jobId}`);
  S.es = es;

  es.addEventListener("status", (event) => {
    const summary = JSON.parse(event.data);
    if (S.activeJobId !== jobId) return;
    updateJobEverywhere(summary);
    renderConsoleHead();
    renderJobChip();
  });

  es.addEventListener("log", (event) => {
    if (S.activeJobId !== jobId) return;
    const data = JSON.parse(event.data);
    let lines = data.lines;
    if (data.from < S.nextLine) {
      lines = lines.slice(S.nextLine - data.from);
      if (!lines.length) return;
    }
    S.nextLine = Math.max(S.nextLine, data.from + data.lines.length);
    appendLogLines(lines);
  });

  es.addEventListener("end", () => {
    es.close();
    if (S.es === es) S.es = null;
    refreshJobs();
    refreshHistory();
  });

  es.onerror = () => {
    const job = findJob(jobId);
    if (job && !["queued", "running"].includes(job.state)) {
      es.close();
      if (S.es === es) S.es = null;
    }
    // otherwise let EventSource auto-reconnect; Last-Event-ID resumes losslessly
  };
}

function findJob(jobId) {
  if (S.jobs.current && S.jobs.current.id === jobId) return S.jobs.current;
  return (
    S.jobs.queued.find((j) => j.id === jobId) ||
    S.jobs.recent.find((j) => j.id === jobId) ||
    null
  );
}

function updateJobEverywhere(summary) {
  if (S.jobs.current && S.jobs.current.id === summary.id) S.jobs.current = summary;
  S.jobs.queued = S.jobs.queued.map((j) => (j.id === summary.id ? summary : j));
  S.jobs.recent = S.jobs.recent.map((j) => (j.id === summary.id ? summary : j));
  if (summary.state === "running" && (!S.jobs.current || S.jobs.current.id === summary.id)) {
    S.jobs.current = summary;
    S.jobs.queued = S.jobs.queued.filter((j) => j.id !== summary.id);
  }
  renderQueue();
}

function renderConsoleHead() {
  const job = S.activeJobId ? findJob(S.activeJobId) : null;
  $("console-title").textContent = job ? job.title : "";
  const pill = $("console-state");
  if (job) {
    pill.className = `state-pill ${job.state}`;
    pill.textContent = job.state;
    pill.classList.remove("hidden");
  } else {
    pill.classList.add("hidden");
  }
  const cancel = $("console-cancel");
  if (job && ["queued", "running"].includes(job.state)) {
    cancel.classList.remove("hidden");
  } else {
    cancel.classList.add("hidden");
  }
  renderElapsed();
}

function renderElapsed() {
  const job = S.activeJobId ? findJob(S.activeJobId) : null;
  const elapsed = $("console-elapsed");
  if (!job) {
    elapsed.textContent = "";
    return;
  }
  if (job.state === "running" && job.startedAt) {
    const sec = (Date.now() - new Date(job.startedAt).getTime()) / 1000;
    elapsed.textContent = fmtDuration(Math.max(0, sec));
  } else if (job.durationSec != null) {
    elapsed.textContent = fmtDuration(job.durationSec);
  } else {
    elapsed.textContent = "";
  }
}

setInterval(renderElapsed, 1000);

// ---------------------------------------------------------------------------
// Run actions
// ---------------------------------------------------------------------------

async function runSuite(name, button) {
  button.disabled = true;
  setTimeout(() => (button.disabled = false), 1200);
  try {
    const result = await api("/api/run/suite", {
      body: { suite: name, showInfo: S.runOpts.showInfo, failOnWarning: S.runOpts.failOnWarning },
    });
    await refreshJobs();
    watchJob(result.job.id);
  } catch (err) {
    toast(`Run failed: ${err.message}`);
  }
}

async function runPipeline(configName, button) {
  button.disabled = true;
  setTimeout(() => (button.disabled = false), 1200);
  try {
    const result = await api("/api/run/pipeline", { body: { config: configName } });
    await refreshJobs();
    watchJob(result.job.id);
  } catch (err) {
    toast(`Export failed: ${err.message}`);
  }
}

async function cancelJob(jobId) {
  try {
    await api(`/api/jobs/${jobId}/cancel`, { method: "POST" });
    await refreshJobs();
  } catch (err) {
    toast(`Cancel failed: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Suites view
// ---------------------------------------------------------------------------

function renderSuites() {
  if (!S.catalog) return;
  const container = $("suite-groups");
  container.textContent = "";
  const filter = S.suiteFilter.toLowerCase();

  for (const group of S.catalog.groups) {
    const suites = S.catalog.suites.filter(
      (suite) =>
        suite.group === group.id &&
        (!filter ||
          suite.name.toLowerCase().includes(filter) ||
          suite.description.toLowerCase().includes(filter))
    );
    if (!suites.length) continue;

    const section = el("div", "suite-group");
    section.appendChild(el("div", "group-title", group.label));
    for (const suite of suites) {
      const card = el("div", "suite-card");
      card.appendChild(el("span", "suite-name", suite.name));
      const badgeLabel = suite.durationClass === "blender" ? "BLENDER" : suite.durationClass.toUpperCase();
      const badge = el("span", `badge ${suite.durationClass}`, badgeLabel);
      if (suite.durationClass === "blender") badge.title = "Launches headless Blender";
      card.appendChild(badge);
      card.appendChild(el("span", "suite-desc", suite.description));
      const run = el("button", "btn", "RUN");
      run.addEventListener("click", () => runSuite(suite.name, run));
      card.appendChild(run);
      section.appendChild(card);
    }
    container.appendChild(section);
  }
}

// ---------------------------------------------------------------------------
// Queue + history
// ---------------------------------------------------------------------------

function jobRow(job, options = {}) {
  const row = el("div", "queue-row");
  row.appendChild(statePill(job.state));
  row.appendChild(el("span", "row-title", job.title));
  const meta = [];
  if (job.queuePosition != null) meta.push(`#${job.queuePosition}`);
  if (job.durationSec != null) meta.push(fmtDuration(job.durationSec));
  row.appendChild(el("span", "row-meta", meta.join(" ")));
  if (options.cancellable) {
    const cancel = el("button", "btn danger", "✕");
    cancel.title = "Cancel";
    cancel.addEventListener("click", (event) => {
      event.stopPropagation();
      cancelJob(job.id);
    });
    row.appendChild(cancel);
  }
  row.addEventListener("click", () => watchJob(job.id));
  return row;
}

function renderQueue() {
  const panel = $("queue-panel");
  panel.textContent = "";
  let any = false;
  if (S.jobs.current) {
    panel.appendChild(jobRow(S.jobs.current, { cancellable: true }));
    any = true;
  }
  for (const job of S.jobs.queued) {
    panel.appendChild(jobRow(job, { cancellable: true }));
    any = true;
  }
  for (const job of S.jobs.recent.slice(0, 5)) {
    panel.appendChild(jobRow(job));
    any = true;
  }
  if (!any) panel.appendChild(el("div", "empty-note", "Nothing running."));
  renderJobChip();
}

function renderJobChip() {
  const chip = $("job-chip");
  chip.className = "chip";
  if (S.jobs.current) {
    chip.classList.add("running");
    const queueNote = S.jobs.queued.length ? ` +${S.jobs.queued.length}` : "";
    chip.textContent = `RUNNING ${S.jobs.current.title}${queueNote}`;
  } else if (S.jobs.queued.length) {
    chip.textContent = `QUEUED ${S.jobs.queued.length}`;
  } else {
    chip.textContent = "IDLE";
  }
}

function renderHistory() {
  const panel = $("history-panel");
  panel.textContent = "";
  if (!S.history.length) {
    panel.appendChild(el("div", "empty-note", "No runs recorded yet."));
    return;
  }
  for (const run of S.history) {
    const row = el("div", "history-row");
    row.appendChild(statePill(run.state));
    row.appendChild(el("span", "row-title", run.title));
    const meta = [fmtDuration(run.durationSec), fmtWhen(run.endedAt)].filter(Boolean).join(" · ");
    row.appendChild(el("span", "row-meta", meta));
    row.addEventListener("click", () => toggleHistoryTail(run.id, row));
    panel.appendChild(row);
    if (S.expandedHistory && S.expandedHistory.id === run.id) {
      const tail = el("pre", "history-tail");
      tail.appendChild(colorizedFragment(S.expandedHistory.tail || []));
      panel.appendChild(tail);
    }
  }
}

async function toggleHistoryTail(runId) {
  if (S.expandedHistory && S.expandedHistory.id === runId) {
    S.expandedHistory = null;
    renderHistory();
    return;
  }
  try {
    S.expandedHistory = await api(`/api/history/${runId}`);
  } catch (err) {
    toast(`History load failed: ${err.message}`);
    return;
  }
  renderHistory();
}

// ---------------------------------------------------------------------------
// Pipeline view
// ---------------------------------------------------------------------------

function renderPipelines() {
  if (!S.pipelines) return;
  $("blender-warn").classList.toggle("hidden", !!S.pipelines.blenderFound);
  const grid = $("config-grid");
  grid.textContent = "";
  for (const config of S.pipelines.configs) {
    const card = el("div", "panel config-card");
    const head = el("div", "config-head");
    head.appendChild(el("span", "config-name", config.asset));
    card.appendChild(head);

    if (config.error) {
      card.appendChild(el("div", "config-row", `⚠ ${config.error}`));
    } else {
      const blend = el("div", "config-row");
      blend.append("blend: ");
      blend.appendChild(el("b", null, (config.sourceBlend || "?").split(/[\\/]/).pop()));
      card.appendChild(blend);
      const vmdl = el("div", "config-row");
      vmdl.append("vmdl: ");
      vmdl.appendChild(el("b", null, config.targetVmdl || "?"));
      card.appendChild(vmdl);

      const chips = el("div", "config-chips");
      chips.appendChild(el("span", `mini-chip${config.hasCollision ? "" : " off"}`, "COLLISION"));
      chips.appendChild(el("span", `mini-chip${config.hasPrefab ? "" : " off"}`, "PREFAB"));
      chips.appendChild(el("span", "mini-chip", `${config.materialCount} MAT`));
      card.appendChild(chips);
    }

    const run = el("button", "btn", "RUN EXPORT");
    run.disabled = !!config.error;
    run.addEventListener("click", () => runPipeline(config.name, run));
    card.appendChild(run);
    grid.appendChild(card);
  }
}

// ---------------------------------------------------------------------------
// Editor view
// ---------------------------------------------------------------------------

function describeScene(scene) {
  if (scene == null) return "—";
  if (typeof scene === "string") return scene;
  for (const key of ["scene", "sceneName", "name", "activeScene", "path"]) {
    if (typeof scene[key] === "string" && scene[key]) return scene[key];
  }
  return "(see raw status)";
}

function renderEditor() {
  const card = $("editor-card");
  card.textContent = "";
  const editor = S.editor;

  if (!editor.editorOnline) {
    const off = el("div", "editor-offline");
    off.appendChild(el("div", "big", "EDITOR OFFLINE"));
    off.appendChild(
      el(
        "div",
        "hint",
        "Open the s&box editor with the MCP Server dock running (port 29015). Suites, exports, and reports work fine without it."
      )
    );
    card.appendChild(off);
    updateEditorChip(false);
    return;
  }

  const rows = [
    ["Control plane", "REACHABLE", "good"],
    ["Scene", describeScene(editor.scene), ""],
    [
      "Playing",
      editor.isPlaying === true ? "YES" : editor.isPlaying === false ? "NO" : "UNKNOWN",
      editor.isPlaying === true ? "good" : editor.isPlaying === false ? "" : "warn",
    ],
  ];
  for (const [key, value, cls] of rows) {
    const row = el("div", "status-row");
    row.appendChild(el("span", "k", key));
    row.appendChild(el("span", `v ${cls}`.trim(), value));
    card.appendChild(row);
  }

  const actions = el("div", "editor-actions");
  const play = el("button", "btn", "▶ PLAY");
  play.disabled = editor.isPlaying === true;
  play.addEventListener("click", () => editorAction("editor_play", play));
  const stop = el("button", "btn danger", "■ STOP");
  stop.disabled = editor.isPlaying !== true;
  stop.addEventListener("click", () => editorAction("editor_stop", stop));
  actions.appendChild(play);
  actions.appendChild(stop);
  card.appendChild(actions);

  const details = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "Raw status";
  details.appendChild(summary);
  const pre = document.createElement("pre");
  pre.textContent = JSON.stringify({ status: editor.status, scene: editor.scene }, null, 1);
  details.appendChild(pre);
  card.appendChild(details);

  updateEditorChip(true);
}

function updateEditorChip(online) {
  const chip = $("editor-chip");
  chip.textContent = "";
  chip.appendChild(el("span", `dot ${online ? "on" : "off"}`));
  chip.append("EDITOR");
}

async function editorAction(tool, button) {
  button.disabled = true;
  try {
    const result = await api("/api/mcp", { body: { tool } });
    if (!result.ok) toast(`Editor: ${result.error || "action failed"}`);
  } catch (err) {
    toast(`Editor: ${err.message}`);
  }
  await pollEditor(true);
}

let editorPollTimer = null;

async function pollEditor(immediate = false) {
  clearTimeout(editorPollTimer);
  if (!document.hidden || immediate) {
    try {
      S.editor = await api("/api/editor/status");
    } catch (err) {
      S.editor = { editorOnline: false };
    }
    renderEditor();
  }
  editorPollTimer = setTimeout(pollEditor, 5000);
}

// ---------------------------------------------------------------------------
// Reports view
// ---------------------------------------------------------------------------

function renderReports() {
  const list = $("reports-list");
  list.textContent = "";
  const filter = S.reportFilter.toLowerCase();
  const files = S.reports.filter((file) => !filter || file.rel.toLowerCase().includes(filter));
  if (!files.length) {
    list.appendChild(el("div", "empty-note", "No reports yet — run a build or audit."));
    return;
  }
  for (const file of files) {
    const row = el("div", "report-row");
    if (S.activeReport === file.rel) row.classList.add("active");
    row.appendChild(el("div", "rname", file.rel));
    row.appendChild(el("div", "rmeta", `${fmtBytes(file.sizeBytes)} · ${fmtMtime(file.mtime)}`));
    row.addEventListener("click", () => openReport(file));
    list.appendChild(row);
  }
}

async function openReport(file) {
  let report;
  try {
    report = await api(`/api/reports/content?path=${encodeURIComponent(file.rel)}`);
  } catch (err) {
    toast(`Report load failed: ${err.message}`);
    return;
  }
  S.activeReport = file.rel;
  renderReports();

  const head = $("report-head");
  head.textContent = `${report.rel}  (${fmtBytes(report.sizeBytes)})`;
  if (report.truncated) head.appendChild(el("span", "trunc", "TRUNCATED VIEW"));

  const md = $("report-md");
  const pre = $("report-pre");
  if (file.ext === ".md") {
    md.innerHTML = mdLite(report.content);
    md.classList.remove("hidden");
    pre.classList.add("hidden");
  } else {
    pre.textContent = "";
    pre.appendChild(colorizedFragment(report.content.split(/\r?\n/)));
    pre.classList.remove("hidden");
    md.classList.add("hidden");
  }
}

// ---------------------------------------------------------------------------
// markdown-lite (escape-first; headings/bold/italic/code/fences/tables/lists)
// ---------------------------------------------------------------------------

function escapeHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function mdInline(text) {
  let out = escapeHtml(text);
  out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>");
  out = out.replace(
    /\[([^\]]+)\]\((https?:[^)\s]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener">$1</a>'
  );
  return out;
}

function mdTable(rows) {
  const cells = rows.map((row) =>
    row
      .trim()
      .replace(/^\||\|$/g, "")
      .split("|")
      .map((cell) => cell.trim())
  );
  let bodyStart = 0;
  let header = null;
  if (cells.length > 1 && cells[1].every((cell) => /^:?-{2,}:?$/.test(cell))) {
    header = cells[0];
    bodyStart = 2;
  }
  let html = "<table>";
  if (header) {
    html += "<tr>" + header.map((cell) => `<th>${mdInline(cell)}</th>`).join("") + "</tr>";
  }
  for (const row of cells.slice(bodyStart)) {
    html += "<tr>" + row.map((cell) => `<td>${mdInline(cell)}</td>`).join("") + "</tr>";
  }
  return html + "</table>";
}

function mdBlock(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let listOpen = false;
  let tableRows = [];

  const flushTable = () => {
    if (tableRows.length) {
      out.push(mdTable(tableRows));
      tableRows = [];
    }
  };
  const closeList = () => {
    if (listOpen) {
      out.push("</ul>");
      listOpen = false;
    }
  };

  for (const line of lines) {
    if (/^\s*\|.*\|\s*$/.test(line)) {
      closeList();
      tableRows.push(line);
      continue;
    }
    flushTable();

    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      closeList();
      const level = heading[1].length;
      out.push(`<h${level}>${mdInline(heading[2])}</h${level}>`);
      continue;
    }
    const item = line.match(/^\s*[-*]\s+(.*)$/);
    if (item) {
      if (!listOpen) {
        out.push("<ul>");
        listOpen = true;
      }
      out.push(`<li>${mdInline(item[1])}</li>`);
      continue;
    }
    const quote = line.match(/^\s*>\s?(.*)$/);
    if (quote) {
      closeList();
      out.push(`<blockquote>${mdInline(quote[1])}</blockquote>`);
      continue;
    }
    if (!line.trim()) {
      closeList();
      continue;
    }
    closeList();
    out.push(`<p>${mdInline(line)}</p>`);
  }
  closeList();
  flushTable();
  return out.join("\n");
}

function mdLite(source) {
  const parts = source.split("```");
  let html = "";
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 1) {
      const body = parts[i].replace(/^[^\n]*\n/, "");
      html += `<pre class="code"><code>${escapeHtml(body)}</code></pre>`;
    } else {
      html += mdBlock(parts[i]);
    }
  }
  return html;
}

// ---------------------------------------------------------------------------
// Data refresh + polling
// ---------------------------------------------------------------------------

async function refreshJobs() {
  try {
    S.jobs = await api("/api/jobs");
  } catch (err) {
    return;
  }
  renderQueue();
  renderConsoleHead();
}

async function refreshHistory() {
  try {
    const data = await api("/api/history");
    S.history = data.runs;
  } catch (err) {
    return;
  }
  renderHistory();
}

async function refreshReports() {
  try {
    const data = await api("/api/reports");
    S.reports = data.files;
  } catch (err) {
    return;
  }
  renderReports();
}

let jobsPollTimer = null;

async function pollJobs() {
  clearTimeout(jobsPollTimer);
  if (!document.hidden) await refreshJobs();
  jobsPollTimer = setTimeout(pollJobs, 5000);
}

// ---------------------------------------------------------------------------
// Tabs + init
// ---------------------------------------------------------------------------

function switchTab(name) {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.classList.toggle("active", tab.dataset.tab === name);
  }
  for (const view of document.querySelectorAll(".view")) {
    view.classList.toggle("active", view.id === `view-${name}`);
  }
  if (name === "reports") refreshReports();
  if (name === "editor") pollEditor(true);
}

async function init() {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => switchTab(tab.dataset.tab));
  }

  $("suite-filter").addEventListener("input", (event) => {
    S.suiteFilter = event.target.value;
    renderSuites();
  });
  $("report-filter").addEventListener("input", (event) => {
    S.reportFilter = event.target.value;
    renderReports();
  });

  $("opt-showinfo").addEventListener("click", (event) => {
    S.runOpts.showInfo = !S.runOpts.showInfo;
    event.target.classList.toggle("on", S.runOpts.showInfo);
  });
  $("opt-failwarn").addEventListener("click", (event) => {
    S.runOpts.failOnWarning = !S.runOpts.failOnWarning;
    event.target.classList.toggle("on", S.runOpts.failOnWarning);
  });

  $("drawer-toggle").addEventListener("click", () => {
    $("console-drawer").classList.toggle("collapsed");
  });
  $("console-autoscroll").addEventListener("click", (event) => {
    S.autoscroll = !S.autoscroll;
    event.target.classList.toggle("on", S.autoscroll);
  });
  $("console-cancel").addEventListener("click", () => {
    if (S.activeJobId) cancelJob(S.activeJobId);
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      pollJobs();
      pollEditor(true);
    }
  });

  try {
    S.catalog = await api("/api/catalog");
    renderSuites();
  } catch (err) {
    toast(`Catalog load failed: ${err.message}`);
  }
  try {
    S.pipelines = await api("/api/pipelines");
    renderPipelines();
  } catch (err) {
    toast(`Pipelines load failed: ${err.message}`);
  }
  refreshHistory();
  refreshReports();
  pollJobs();
  pollEditor();

  // If something is already running (page reload mid-run), reattach.
  await refreshJobs();
  if (S.jobs.current) watchJob(S.jobs.current.id);
}

document.addEventListener("DOMContentLoaded", init);
