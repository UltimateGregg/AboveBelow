"""Job queue for the ops dashboard.

A single daemon worker thread executes jobs strictly one at a time (audit
suites compile the project and may launch headless Blender; concurrent runs
would contend). Each job keeps a ring buffer of output lines guarded by a
Condition; SSE handler threads wait on it directly.
"""

from __future__ import annotations

import collections
import datetime
import json
import subprocess
import sys
import threading
import traceback
from pathlib import Path

LINE_CAP = 20_000
LINE_DROP = 1_000
TAIL_KEEP = 200
HISTORY_FILE_CAP = 200
HISTORY_INDEX_LIMIT = 50
CREATE_NO_WINDOW = 0x08000000

ACTIVE_STATES = ("queued", "running")


def _now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


class Job:
    _seq = 0
    _seq_lock = threading.Lock()

    def __init__(self, kind: str, title: str, args: dict, command: list[str]):
        with Job._seq_lock:
            Job._seq += 1
            seq = Job._seq
        epoch_ms = int(datetime.datetime.now().timestamp() * 1000)
        self.id = f"j{epoch_ms}-{seq}"
        self.kind = kind
        self.title = title
        self.args = args
        self.command = command
        self.state = "queued"
        self.exit_code: int | None = None
        self.created_at = _now_iso()
        self.started_at: str | None = None
        self.ended_at: str | None = None
        self.started_mono: float | None = None
        self.duration_sec: float | None = None
        self.lines: list[str] = []
        self.base_index = 0  # absolute index of lines[0]
        self.line_count = 0  # absolute count of lines ever appended
        self.proc: subprocess.Popen | None = None
        self.cancel_requested = False
        self.cond = threading.Condition()

    def append_line(self, line: str) -> None:
        with self.cond:
            self.lines.append(line)
            self.line_count += 1
            if len(self.lines) > LINE_CAP:
                del self.lines[:LINE_DROP]
                self.base_index += LINE_DROP
            self.cond.notify_all()

    def set_state(self, state: str, exit_code: int | None = None) -> None:
        with self.cond:
            self.state = state
            if exit_code is not None:
                self.exit_code = exit_code
            self.cond.notify_all()

    def finished(self) -> bool:
        return self.state not in ACTIVE_STATES

    def summary(self, queue_position: int | None = None) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "title": self.title,
            "args": self.args,
            "state": self.state,
            "exitCode": self.exit_code,
            "startedAt": self.started_at,
            "endedAt": self.ended_at,
            "durationSec": self.duration_sec,
            "lineCount": self.line_count,
            "queuePosition": queue_position,
        }

    def log_slice(self, start: int, limit: int = 2_000) -> dict:
        with self.cond:
            start = max(start, self.base_index)
            offset = start - self.base_index
            lines = self.lines[offset : offset + limit]
            return {
                "from": start,
                "lines": lines,
                "next": start + len(lines),
                "truncatedBefore": self.base_index,
                "done": self.finished() and start + len(lines) >= self.line_count,
            }


class JobManager:
    def __init__(self, repo_root: Path, runs_dir: Path):
        self.repo_root = repo_root
        self.runs_dir = runs_dir
        self._lock = threading.RLock()
        self._pending: collections.deque[Job] = collections.deque()
        self._current: Job | None = None
        self._recent: collections.deque[Job] = collections.deque(maxlen=50)
        self._jobs: dict[str, Job] = {}
        self._wakeup = threading.Event()
        self._stopping = False
        self._worker = threading.Thread(target=self._run_loop, daemon=True, name="job-worker")
        self._worker.start()

    # -- public API ---------------------------------------------------------

    def submit(self, job: Job) -> dict:
        with self._lock:
            self._jobs[job.id] = job
            self._pending.append(job)
            position = len(self._pending)
        self._wakeup.set()
        return job.summary(queue_position=position)

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            return self._jobs.get(job_id)

    def snapshot(self) -> dict:
        with self._lock:
            current = self._current.summary() if self._current else None
            queued = [job.summary(queue_position=i + 1) for i, job in enumerate(self._pending)]
            recent = [job.summary() for job in reversed(self._recent)]
        return {"current": current, "queued": queued, "recent": recent}

    def cancel(self, job_id: str) -> dict | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return None
            if job in self._pending:
                self._pending.remove(job)
                job.set_state("cancelled")
                job.ended_at = _now_iso()
                self._recent.append(job)
                return {"ok": True, "state": job.state}
            if job is self._current and job.state == "running":
                job.cancel_requested = True
                proc = job.proc
        if job.state == "running" and job.proc is not None:
            self._kill_tree(job.proc.pid)
            return {"ok": True, "state": "cancelling"}
        return {"ok": True, "state": job.state}

    def cancel_current(self) -> None:
        """Shutdown path: kill whatever is running so no orphan tree survives."""
        with self._lock:
            self._stopping = True
            job = self._current
            self._pending.clear()
        if job is not None and job.state == "running" and job.proc is not None:
            job.cancel_requested = True
            self._kill_tree(job.proc.pid)

    # -- internals ----------------------------------------------------------

    @staticmethod
    def _kill_tree(pid: int) -> None:
        try:
            subprocess.run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                capture_output=True,
                creationflags=CREATE_NO_WINDOW,
            )
        except OSError:
            pass  # taskkill missing would be very strange; nothing to do

    def _run_loop(self) -> None:
        while True:
            self._wakeup.wait()
            with self._lock:
                if self._stopping:
                    return
                if not self._pending:
                    self._wakeup.clear()
                    continue
                job = self._pending.popleft()
                self._current = job
            try:
                self._execute(job)
            except Exception:
                job.append_line("[Error] Dashboard - job runner crashed:")
                for line in traceback.format_exc().splitlines():
                    job.append_line(line)
                job.set_state("error")
            finally:
                job.ended_at = _now_iso()
                if job.started_mono is not None:
                    import time

                    job.duration_sec = round(time.monotonic() - job.started_mono, 1)
                self._persist(job)
                with job.cond:
                    if job.line_count > TAIL_KEEP:
                        keep = job.lines[-TAIL_KEEP:]
                        job.base_index = job.line_count - len(keep)
                        job.lines = keep
                    job.cond.notify_all()
                with self._lock:
                    self._current = None
                    self._recent.append(job)

    def _execute(self, job: Job) -> None:
        import time

        job.started_at = _now_iso()
        job.started_mono = time.monotonic()
        try:
            job.proc = subprocess.Popen(
                job.command,
                cwd=str(self.repo_root),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                creationflags=CREATE_NO_WINDOW,
            )
        except OSError as exc:
            job.append_line(f"[Error] Dashboard - failed to start process: {exc}")
            job.set_state("error")
            return
        job.set_state("running")

        assert job.proc.stdout is not None
        for raw in job.proc.stdout:
            job.append_line(raw.decode("utf-8", errors="replace").rstrip("\r\n"))
        exit_code = job.proc.wait()

        if job.cancel_requested:
            job.set_state("cancelled", exit_code)
        elif exit_code == 0:
            job.set_state("passed", exit_code)
        else:
            job.set_state("failed", exit_code)

    def _persist(self, job: Job) -> None:
        try:
            self.runs_dir.mkdir(parents=True, exist_ok=True)
            with job.cond:
                tail = job.lines[-TAIL_KEEP:]
            record = job.summary()
            record["tail"] = tail
            stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
            path = self.runs_dir / f"{stamp}-{job.id}.json"
            path.write_text(json.dumps(record, indent=1), encoding="utf-8")
            self._prune()
        except OSError:
            pass  # history is best-effort; never let it kill the worker

    def _prune(self) -> None:
        files = sorted(self.runs_dir.glob("*.json"))
        for stale in files[: max(0, len(files) - HISTORY_FILE_CAP)]:
            try:
                stale.unlink()
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Command builders — the only place dashboard commands are constructed.
# List argv only; the '&' in this repo's path makes shell strings a footgun.
# ---------------------------------------------------------------------------

def build_suite_job(repo_root: Path, suite: str, show_info: bool, fail_on_warning: bool) -> Job:
    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(repo_root / "scripts" / "agents" / "run_agent_checks.ps1"),
        "-Suite",
        suite,
        "-Root",
        str(repo_root),
    ]
    args = {"suite": suite, "showInfo": show_info, "failOnWarning": fail_on_warning}
    if show_info:
        command.append("-ShowInfo")
    if fail_on_warning:
        command.append("-FailOnWarning")
    return Job("suite", f"suite {suite}", args, command)


def build_pipeline_job(repo_root: Path, config_path: Path) -> Job:
    command = [
        sys.executable,
        str(repo_root / "scripts" / "asset_pipeline.py"),
        "--config",
        str(config_path),
    ]
    args = {"config": config_path.name}
    return Job("pipeline", f"pipeline {config_path.name[: -len('_asset_pipeline.json')]}", args, command)


# ---------------------------------------------------------------------------
# Persisted history
# ---------------------------------------------------------------------------

def load_history_index(runs_dir: Path, limit: int = HISTORY_INDEX_LIMIT) -> list[dict]:
    if not runs_dir.is_dir():
        return []
    entries = []
    for path in sorted(runs_dir.glob("*.json"), reverse=True)[:limit]:
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        record.pop("tail", None)
        entries.append(record)
    return entries


def load_history_entry(runs_dir: Path, run_id: str) -> dict | None:
    if not runs_dir.is_dir() or "/" in run_id or "\\" in run_id or "." in run_id:
        return None
    for path in runs_dir.glob(f"*-{run_id}.json"):
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return None
    return None


if __name__ == "__main__":
    # Smoke test: run the fast 'terrain' suite and stream its output.
    root = Path(__file__).resolve().parents[2]
    manager = JobManager(root, root / ".tmpbuild" / "dashboard" / "runs")
    job = build_suite_job(root, "terrain", show_info=False, fail_on_warning=False)
    manager.submit(job)
    seen = 0
    while True:
        with job.cond:
            if seen >= job.line_count and not job.finished():
                job.cond.wait(timeout=5)
            chunk = job.log_slice(seen, limit=500)
        for line in chunk["lines"]:
            print(line)
        seen = chunk["next"]
        if job.finished() and seen >= job.line_count:
            break
    print(f"--- state={job.state} exit={job.exit_code} duration={job.duration_sec}s")
