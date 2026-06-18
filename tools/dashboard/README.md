# ABOVE / BELOW Ops Dashboard

Local browser control panel for this project's workflows: run the
`run_agent_checks.ps1` audit suites with live streamed output, re-run asset
pipeline exports, watch the s&box editor control plane, and read `.tmpbuild`
reports. Python stdlib only — no dependencies.

## Start

```powershell
powershell -ExecutionPolicy Bypass -File tools\dashboard\start_dashboard.ps1
```

…or manually:

```powershell
python tools\dashboard\server.py --port 8723 --open
```

Then browse to <http://127.0.0.1:8723/> (Firefox is the tested target).

## Notes

- Jobs run **one at a time** (audits compile the project / launch Blender);
  extra runs queue up and are cancellable. Cancel kills the whole process tree.
- Run history persists in `.tmpbuild/dashboard/runs/` (gitignored).
- The Editor tab needs the s&box editor open with the MCP Server dock on
  port 29015. `editor_save_scene` is deliberately not exposed.
- Ctrl+C in the server window cancels any running job before exiting.
