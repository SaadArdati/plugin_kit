# Loop dashboard

Generalized live monitor for any codex-driven loop in this repo. Currently registers two loops:

- `doc-audit` (reads `scripts/doc-audit-loop/runs/latest/`)
- `bug-hunt` (reads `scripts/bug-hunt-loop/runs/latest/`)

## Run

```bash
make dashboard                    # canonical
make doc-audit-dashboard          # alias: opens with doc-audit selected
make bug-hunt-dashboard           # alias: opens with bug-hunt selected
```

Or directly:

```bash
cd scripts/dashboard && npm install && npm run dev
```

Open `http://localhost:4322`. Switch loops with the top-bar toggle or the URL hash (`#loop=bug-hunt`).

## Layout

- Top bar: loop selector, current iteration, run-level status badge, run dir + start time.
- Main panel: per-iteration table with columns derived from the active loop's schema. Click a row to inspect.
- Right panel: tabs for the active loop's per-iter files. Auto-switches to the freshest tab when a new file lands (10 s grace after a manual click).
- Bottom panel: live tail of `orchestrator.log` with pause toggle. Auto-follows newest iter (cursor stays on the latest row unless you've manually picked an older one).

All polling uses no-store cache headers and rotates on 1.5-2.5 s intervals.

## Architecture

The dashboard knows nothing loop-specific. Each loop registers a **driver** under `src/loops/`. The server exposes namespaced routes:

```
GET /api/loops                 # [{id, label}] from the driver registry
GET /api/{loopId}/schema       # tabs, pipelineOrder, columns
GET /api/{loopId}/status       # run-level: iteration, converged, runDir, startedAt
GET /api/{loopId}/iters        # array of per-iter rows (id, status, ...columns)
GET /api/{loopId}/iter/:id     # full per-iter file contents (one key per file)
GET /api/{loopId}/log          # tail of orchestrator.log
```

The frontend pulls `/api/loops`, picks one (URL hash > first registered), pulls its schema, and renders columns and tabs from that schema. No frontend code mentions any specific loop.

## Adding a new loop

1. Create `src/loops/<id>.js` exporting a driver:

   ```js
   export default {
     id: 'my-loop',
     label: 'My loop',
     runsRelativePath: 'scripts/my-loop/runs',
     iterFiles: { foo: 'foo.md', bar: 'bar.txt' },
     tabs: [{ id: 'foo', label: 'foo.md' }, { id: 'bar', label: 'bar.txt' }],
     pipelineOrder: ['foo', 'bar'],
     columns: [
       { id: 'count', label: 'Count', kind: 'number' },
     ],
     buildOrchestratorContext(orchestratorLogText) { return {}; },
     computeRow(files, ctx) {
       return { status: 'GREEN', columns: { count: 0 } };
     },
     computeRunStatus({ runDirFiles }) {
       return { converged: false, verifierFailed: false };
     },
   };
   ```

2. Import and register it in `vite.config.js`:

   ```js
   import myLoop from './src/loops/my-loop.js';
   const drivers = new Map([
     [docAuditDriver.id, docAuditDriver],
     [bugHuntDriver.id, bugHuntDriver],
     [myLoop.id, myLoop],
   ]);
   ```

3. The frontend picks it up automatically via `/api/loops`.

Shared parsing helpers live in `src/loops/_helpers.js`. Add a new helper there when two drivers need it; keep loop-specific parsers local to the driver file.

## Driver contract

| Field | Purpose |
|---|---|
| `id` | URL-safe loop identifier (also the URL-hash value) |
| `label` | Display name in the loop selector |
| `runsRelativePath` | Path from repo root to the loop's `runs/` dir; the dashboard reads `<runsRelativePath>/latest/` |
| `iterFiles` | Map of `{ shortKey: 'filename' }`; each file appears as a tab and is fetched per iter |
| `tabs` | `[{ id, label }]`; ordering controls the right-panel tab order |
| `pipelineOrder` | `[id, ...]` in stage order, freshest LAST. Drives auto-tab-switch on file change. |
| `columns` | `[{ id, label, kind }]`; defines the iters table (after the fixed ID + Status columns) |
| `buildOrchestratorContext(logText)` | Returns context object passed to every `computeRow`. Use this if multiple iters need a shared parse of the orchestrator log. |
| `computeRow(files, ctx)` | Returns `{ status, columns: { id -> value } }` for one iter. `files` keys come from `iterFiles`. |
| `computeRunStatus({ runDirFiles })` | Returns `{ converged, verifierFailed }`. `runDirFiles` is a `Set` of marker filenames present in the run dir. |

The `computeRow` status string controls the row's chip color: `GREEN`/`PASS`/`CONVERGED` -> green, `RED`/`FAIL`/`FILED` -> red, anything else -> gray. Add new statuses by adding cases in `classifyStatus` in `src/main.js`.
