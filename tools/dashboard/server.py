"""ABOVE / BELOW ops dashboard server.

Python-stdlib-only local HTTP server: serves the static dashboard, runs the
project's audit suites and asset-pipeline exports through a serialized job
queue with SSE log streaming, proxies the s&box editor MCP control plane,
and exposes .tmpbuild reports.

Usage:  python tools/dashboard/server.py [--port 8723] [--open]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import catalog
import jobs as jobs_mod
import mcp_proxy

APP_NAME = "sbox-dashboard"
VERSION = 1
DEFAULT_PORT = 8723
REPO_ROOT = Path(__file__).resolve().parents[2]
STATIC_DIR = Path(__file__).resolve().parent / "static"
RUNS_DIR = REPO_ROOT / ".tmpbuild" / "dashboard" / "runs"
MAX_BODY = 1_000_000

JOBS: jobs_mod.JobManager | None = None
HTTPD: ThreadingHTTPServer | None = None

STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/static/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/static/style.css": ("style.css", "text/css; charset=utf-8"),
}

SSE_SOCKET_ERRORS = (BrokenPipeError, ConnectionAbortedError, ConnectionResetError, OSError)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = APP_NAME

    # Route table: (method, regex, handler-method name). Order matters.
    ROUTES = [
        ("GET", re.compile(r"^/api/health$"), "h_health"),
        ("GET", re.compile(r"^/api/catalog$"), "h_catalog"),
        ("POST", re.compile(r"^/api/run/suite$"), "h_run_suite"),
        ("POST", re.compile(r"^/api/run/pipeline$"), "h_run_pipeline"),
        ("GET", re.compile(r"^/api/jobs$"), "h_jobs"),
        ("GET", re.compile(r"^/api/jobs/([\w\-]+)/log$"), "h_job_log"),
        ("POST", re.compile(r"^/api/jobs/([\w\-]+)/cancel$"), "h_job_cancel"),
        ("GET", re.compile(r"^/api/jobs/([\w\-]+)$"), "h_job_get"),
        ("GET", re.compile(r"^/api/stream/([\w\-]+)$"), "h_stream"),
        ("GET", re.compile(r"^/api/history$"), "h_history"),
        ("GET", re.compile(r"^/api/history/([\w\-]+)$"), "h_history_entry"),
        ("POST", re.compile(r"^/api/mcp$"), "h_mcp"),
        ("GET", re.compile(r"^/api/editor/status$"), "h_editor_status"),
        ("GET", re.compile(r"^/api/pipelines$"), "h_pipelines"),
        ("GET", re.compile(r"^/api/reports$"), "h_reports"),
        ("GET", re.compile(r"^/api/reports/content$"), "h_report_content"),
        ("POST", re.compile(r"^/api/shutdown$"), "h_shutdown"),
    ]

    # -- plumbing -----------------------------------------------------------

    def do_GET(self) -> None:
        self._route("GET")

    def do_POST(self) -> None:
        self._route("POST")

    def _route(self, method: str) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        self._query = urllib.parse.parse_qs(parsed.query)

        if method == "GET" and path in STATIC_FILES:
            self._send_static(path)
            return
        if method == "GET" and path == "/favicon.ico":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        for route_method, pattern, name in self.ROUTES:
            if route_method != method:
                continue
            match = pattern.match(path)
            if match:
                try:
                    getattr(self, name)(*match.groups())
                except SSE_SOCKET_ERRORS:
                    pass  # client went away mid-response
                except Exception as exc:  # never let one request kill the thread
                    try:
                        self.send_json(500, {"ok": False, "error": f"{type(exc).__name__}: {exc}"})
                    except SSE_SOCKET_ERRORS:
                        pass
                return
        self.send_json(404, {"ok": False, "error": "not found"})

    def send_json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, path: str) -> None:
        filename, content_type = STATIC_FILES[path]
        full = STATIC_DIR / filename
        if not full.is_file():
            self.send_json(404, {"ok": False, "error": f"missing static file {filename}"})
            return
        body = full.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict | None:
        """Parse the JSON request body; {} for empty, None for invalid."""
        length = int(self.headers.get("Content-Length") or 0)
        if length == 0:
            return {}
        if length > MAX_BODY:
            return None
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8", errors="replace"))
        except json.JSONDecodeError:
            return None
        return data if isinstance(data, dict) else None

    def log_message(self, fmt: str, *args) -> None:
        # 5s polling endpoints would flood the console.
        if self.command == "GET":
            quiet = ("/api/editor/status", "/api/jobs", "/api/stream/", "/favicon.ico")
            if any(self.path.startswith(prefix) for prefix in quiet):
                return
        sys.stderr.write(f"[{self.log_date_time_string()}] {fmt % args}\n")

    # -- API handlers -------------------------------------------------------

    def h_health(self) -> None:
        self.send_json(
            200,
            {"ok": True, "app": APP_NAME, "version": VERSION, "pid": os.getpid(), "root": str(REPO_ROOT)},
        )

    def h_catalog(self) -> None:
        self.send_json(200, catalog.suite_catalog(REPO_ROOT))

    def h_run_suite(self) -> None:
        body = self._read_body()
        if body is None or not isinstance(body.get("suite"), str):
            self.send_json(400, {"ok": False, "error": "expected JSON body with 'suite'"})
            return
        suite = body["suite"]
        if suite not in catalog.parse_validate_set(REPO_ROOT):
            self.send_json(400, {"ok": False, "error": f"unknown suite: {suite}"})
            return
        job = jobs_mod.build_suite_job(
            REPO_ROOT, suite, bool(body.get("showInfo")), bool(body.get("failOnWarning"))
        )
        summary = JOBS.submit(job)
        self.send_json(202, {"ok": True, "job": summary})

    def h_run_pipeline(self) -> None:
        body = self._read_body()
        if body is None or not isinstance(body.get("config"), str):
            self.send_json(400, {"ok": False, "error": "expected JSON body with 'config'"})
            return
        config_path = catalog.resolve_config(REPO_ROOT, body["config"])
        if config_path is None:
            self.send_json(400, {"ok": False, "error": f"invalid pipeline config: {body['config']}"})
            return
        job = jobs_mod.build_pipeline_job(REPO_ROOT, config_path)
        summary = JOBS.submit(job)
        self.send_json(202, {"ok": True, "job": summary})

    def h_jobs(self) -> None:
        self.send_json(200, JOBS.snapshot())

    def h_job_get(self, job_id: str) -> None:
        job = JOBS.get(job_id)
        if job is None:
            self.send_json(404, {"ok": False, "error": "unknown job"})
            return
        self.send_json(200, job.summary())

    def h_job_log(self, job_id: str) -> None:
        job = JOBS.get(job_id)
        if job is None:
            self.send_json(404, {"ok": False, "error": "unknown job"})
            return
        try:
            start = int(self._query.get("from", ["0"])[0])
        except ValueError:
            start = 0
        self.send_json(200, job.log_slice(max(0, start)))

    def h_job_cancel(self, job_id: str) -> None:
        result = JOBS.cancel(job_id)
        if result is None:
            self.send_json(404, {"ok": False, "error": "unknown job"})
            return
        self.send_json(200, result)

    def h_history(self) -> None:
        self.send_json(200, {"runs": jobs_mod.load_history_index(RUNS_DIR)})

    def h_history_entry(self, run_id: str) -> None:
        entry = jobs_mod.load_history_entry(RUNS_DIR, run_id)
        if entry is None:
            self.send_json(404, {"ok": False, "error": "unknown run"})
            return
        self.send_json(200, entry)

    def h_mcp(self) -> None:
        body = self._read_body()
        if body is None or not isinstance(body.get("tool"), str):
            self.send_json(400, {"ok": False, "error": "expected JSON body with 'tool'"})
            return
        tool = body["tool"]
        if tool not in mcp_proxy.ALLOWED_TOOLS:
            self.send_json(400, {"ok": False, "error": f"tool not allowed: {tool}"})
            return
        arguments = body.get("arguments")
        if arguments is not None and not isinstance(arguments, dict):
            self.send_json(400, {"ok": False, "error": "'arguments' must be an object"})
            return
        self.send_json(200, mcp_proxy.call_tool(tool, arguments))

    def h_editor_status(self) -> None:
        self.send_json(200, mcp_proxy.editor_status_aggregate())

    def h_pipelines(self) -> None:
        self.send_json(
            200,
            {
                "blenderFound": Path(catalog.blender_exe(REPO_ROOT)).exists(),
                "configs": catalog.list_pipeline_configs(REPO_ROOT),
            },
        )

    def h_reports(self) -> None:
        self.send_json(200, {"files": catalog.list_reports(REPO_ROOT)})

    def h_report_content(self) -> None:
        rel = self._query.get("path", [""])[0]
        report = catalog.read_report(REPO_ROOT, rel)
        if report is None:
            self.send_json(400, {"ok": False, "error": "invalid report path"})
            return
        if report.get("missing"):
            self.send_json(404, {"ok": False, "error": "report not found"})
            return
        self.send_json(200, report)

    def h_shutdown(self) -> None:
        self.send_json(200, {"ok": True})
        JOBS.cancel_current()
        threading.Thread(target=HTTPD.shutdown, daemon=True).start()

    # -- SSE ----------------------------------------------------------------

    def h_stream(self, job_id: str) -> None:
        job = JOBS.get(job_id)
        if job is None:
            self.send_json(404, {"ok": False, "error": "unknown job"})
            return

        start = 0
        last_event_id = self.headers.get("Last-Event-ID")
        if last_event_id and last_event_id.isdigit():
            start = int(last_event_id) + 1

        self.close_connection = True
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        try:
            self._sse_event("status", job.summary())
            while True:
                with job.cond:
                    if start < job.base_index:
                        dropped = job.base_index - start
                        start = job.base_index
                    else:
                        dropped = 0
                    offset = start - job.base_index
                    chunk = list(job.lines[offset : offset + 500])
                    finished = job.finished()
                    if not chunk and not finished:
                        job.cond.wait(timeout=15.0)
                        # Re-read after the wait so a notify doesn't cost a
                        # spurious ping + extra loop turn per line burst.
                        if start < job.base_index:
                            dropped += job.base_index - start
                            start = job.base_index
                        offset = start - job.base_index
                        chunk = list(job.lines[offset : offset + 500])
                        finished = job.finished()
                if dropped:
                    self._sse_comment(f"{dropped} lines dropped from buffer")
                if chunk:
                    self._sse_event(
                        "log",
                        {"from": start, "lines": chunk},
                        event_id=start + len(chunk) - 1,
                    )
                    start += len(chunk)
                    continue
                if finished:
                    self._sse_event("status", job.summary())
                    self._sse_event("end", {"state": job.state})
                    return
                self._sse_comment("ping")
        except SSE_SOCKET_ERRORS:
            return  # client disconnected; nothing to clean up

    def _sse_event(self, event: str, data: dict, event_id: int | None = None) -> None:
        parts = []
        if event_id is not None:
            parts.append(f"id: {event_id}\n")
        parts.append(f"event: {event}\n")
        parts.append(f"data: {json.dumps(data)}\n\n")
        self.wfile.write("".join(parts).encode("utf-8"))
        self.wfile.flush()

    def _sse_comment(self, text: str) -> None:
        self.wfile.write(f": {text}\n\n".encode("utf-8"))
        self.wfile.flush()


def probe_existing(port: int) -> bool:
    """True if the thing already bound to the port is one of us."""
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=1.5) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
            return payload.get("app") == APP_NAME
    except (urllib.error.URLError, socket.timeout, json.JSONDecodeError, OSError):
        return False


def main() -> None:
    global JOBS, HTTPD

    parser = argparse.ArgumentParser(description="ABOVE / BELOW ops dashboard")
    env_port = os.environ.get("PORT")
    parser.add_argument("--port", type=int, default=int(env_port) if env_port else DEFAULT_PORT)
    parser.add_argument("--open", action="store_true", help="open the dashboard in the default browser")
    args = parser.parse_args()

    suites = catalog.parse_validate_set(REPO_ROOT)  # hard-fail early if unparseable
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    JOBS = jobs_mod.JobManager(REPO_ROOT, RUNS_DIR)

    url = f"http://127.0.0.1:{args.port}/"
    try:
        HTTPD = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError:
        if probe_existing(args.port):
            print(f"Dashboard already running at {url}")
            sys.exit(0)
        print(f"Port {args.port} is in use by another application. Try --port <other>.")
        sys.exit(2)
    HTTPD.daemon_threads = True

    print(f"{APP_NAME}: {len(suites)} suites | root {REPO_ROOT}")
    print(f"Serving on {url}  (Ctrl+C to stop; cancels any running job)")
    if args.open:
        threading.Timer(0.5, webbrowser.open, [url]).start()

    try:
        HTTPD.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        JOBS.cancel_current()
        HTTPD.server_close()


if __name__ == "__main__":
    main()
