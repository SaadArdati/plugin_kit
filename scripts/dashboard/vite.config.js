import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

import { parseIntSafe, parseStartedAtFromFirstLine } from './src/loops/_helpers.js';
import bugHuntDriver from './src/loops/bug-hunt.js';
import coverageDriver from './src/loops/coverage.js';
import decompDriver from './src/loops/decomp.js';
import docAuditDriver from './src/loops/doc-audit.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');

// Loop registry. To add a new loop, write a driver in src/loops/, import it
// here, and add it to this Map. The frontend discovers loops via /api/loops.
const drivers = new Map([
  [docAuditDriver.id, docAuditDriver],
  [bugHuntDriver.id, bugHuntDriver],
  [coverageDriver.id, coverageDriver],
  [decompDriver.id, decompDriver],
]);

async function safeReadText(filePath) {
  try { return await fs.readFile(filePath, 'utf8'); } catch { return null; }
}

async function safeStat(filePath) {
  try { return await fs.stat(filePath); } catch { return null; }
}

async function safeReaddir(dirPath) {
  try { return await fs.readdir(dirPath, { withFileTypes: true }); } catch { return []; }
}

async function computeStartedAtIso(orchestratorLogPath) {
  const stat = await safeStat(orchestratorLogPath);
  if (!stat) return null;
  const text = await safeReadText(orchestratorLogPath);
  const firstLine = text ? text.split(/\r?\n/, 1)[0] : '';
  const parsedFromLine = parseStartedAtFromFirstLine(firstLine, stat.birthtime);
  if (parsedFromLine) return parsedFromLine;
  if (stat.birthtime instanceof Date && !Number.isNaN(stat.birthtime.getTime())) {
    return stat.birthtime.toISOString();
  }
  if (stat.mtime instanceof Date && !Number.isNaN(stat.mtime.getTime())) {
    return stat.mtime.toISOString();
  }
  return null;
}

function setNoStore(res) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
}

function sendJson(res, data, statusCode = 200) {
  res.statusCode = statusCode;
  setNoStore(res);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(data));
}

function sendText(res, data, statusCode = 200) {
  res.statusCode = statusCode;
  setNoStore(res);
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.end(data);
}

function getRunDir(driver) {
  return path.join(projectRoot, driver.runsRelativePath, 'latest');
}

async function readIterFiles(driver, iterDir) {
  const fileEntries = await Promise.all(
    Object.entries(driver.iterFiles).map(async ([key, name]) => {
      const text = await safeReadText(path.join(iterDir, name));
      return [key, text];
    }),
  );
  return Object.fromEntries(fileEntries);
}

async function buildIterSummaries(driver) {
  const runDir = getRunDir(driver);
  // Drivers can override the iter root subdir (e.g., decomp uses `steps/`)
  // and the iter-dir naming regex (e.g., decomp uses `step-NN`).
  const itersSubdir = driver.itersSubdir || 'iters';
  const iterDirRegex = driver.iterDirRegex || /^iter-\d+$/;
  const itersRoot = path.join(runDir, itersSubdir);
  const entries = await safeReaddir(itersRoot);
  const iterDirs = entries.filter(
    (entry) => entry.isDirectory() && iterDirRegex.test(entry.name),
  );

  const [orchestratorLogText, stoplistText] = await Promise.all([
    safeReadText(path.join(runDir, 'orchestrator.log')),
    safeReadText(path.join(runDir, 'state', 'stoplist.md')),
  ]);
  const ctx = driver.buildOrchestratorContext({ orchestratorLogText, stoplistText });

  const summaries = await Promise.all(
    iterDirs.map(async (entry) => {
      const id = entry.name;
      // Strip prefix (`iter-` or `step-`) and parse the trailing number.
      // Suffixes like `0a` -> number=0 (sort by base index), driver column
      // surfaces the human-readable id via files like `step.txt`.
      const numberMatch = id.match(/(\d+)/);
      const number = numberMatch ? parseIntSafe(numberMatch[1], 0) : 0;
      const iterDir = path.join(itersRoot, id);
      const files = await readIterFiles(driver, iterDir);
      const row = driver.computeRow(files, { ...ctx, iterNumber: number });
      return {
        id,
        number,
        status: row.status,
        ...row.columns,
      };
    }),
  );

  summaries.sort((a, b) => b.number - a.number);
  return summaries;
}

async function handleStatus(driver, res) {
  const runDir = getRunDir(driver);
  const iterText = await safeReadText(path.join(runDir, 'state', 'iteration.txt'));
  const iteration = parseIntSafe(iterText, 0);

  const runDirEntries = await safeReaddir(runDir);
  const runDirFiles = new Set(
    runDirEntries.filter((e) => e.isFile()).map((e) => e.name),
  );
  const runStatus = driver.computeRunStatus({ runDirFiles });

  const startedAt = await computeStartedAtIso(path.join(runDir, 'orchestrator.log'));

  let resolvedRunDir = runDir;
  try { resolvedRunDir = await fs.realpath(runDir); } catch {
    // Symlink missing: keep unresolved path so UI shows where we expect to look.
  }

  sendJson(res, {
    iteration,
    startedAt,
    runDir: resolvedRunDir,
    ...runStatus,
  });
}

async function handleLog(driver, url, res) {
  const tailRaw = url.searchParams.get('tail');
  let tail = parseIntSafe(tailRaw, 200);
  if (tail <= 0) tail = 200;
  tail = Math.min(tail, 2000);

  const runDir = getRunDir(driver);
  const text = (await safeReadText(path.join(runDir, 'orchestrator.log'))) || '';
  const lines = text.split(/\r?\n/);
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  sendText(res, lines.slice(-tail).join('\n'));
}

async function handleIters(driver, res) {
  const summaries = await buildIterSummaries(driver);
  sendJson(res, summaries);
}

async function handleIterDetail(driver, id, res) {
  const iterDirRegex = driver.iterDirRegex || /^iter-\d+$/;
  if (!iterDirRegex.test(id)) {
    sendJson(res, { error: 'invalid iter id' }, 400);
    return;
  }
  const itersSubdir = driver.itersSubdir || 'iters';
  const iterDir = path.join(getRunDir(driver), itersSubdir, id);
  const files = await readIterFiles(driver, iterDir);
  sendJson(res, { id, ...files });
}

function dashboardApi() {
  return {
    name: 'dashboard-api',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        try {
          const method = req.method || 'GET';
          const url = new URL(req.url || '/', 'http://localhost');
          const pathname = url.pathname;

          if (!pathname.startsWith('/api/')) { next(); return; }
          if (method !== 'GET') { sendJson(res, { error: 'method not allowed' }, 405); return; }

          if (pathname === '/api/loops') {
            sendJson(res, [...drivers.values()].map((d) => ({ id: d.id, label: d.label })));
            return;
          }

          const m = pathname.match(/^\/api\/([^/]+)\/(.+)$/);
          if (!m) { sendJson(res, { error: 'not found' }, 404); return; }
          const [, loopId, action] = m;
          const driver = drivers.get(loopId);
          if (!driver) { sendJson(res, { error: 'unknown loop' }, 404); return; }

          if (action === 'schema') {
            sendJson(res, {
              id: driver.id,
              label: driver.label,
              tabs: driver.tabs,
              pipelineOrder: driver.pipelineOrder,
              columns: driver.columns,
            });
            return;
          }

          if (action === 'status') { await handleStatus(driver, res); return; }
          if (action === 'log') { await handleLog(driver, url, res); return; }
          if (action === 'iters') { await handleIters(driver, res); return; }

          const iterMatch = action.match(/^iter\/([^/]+)$/);
          if (iterMatch) {
            await handleIterDetail(driver, decodeURIComponent(iterMatch[1]), res);
            return;
          }

          sendJson(res, { error: 'not found' }, 404);
        } catch {
          if (!res.headersSent) sendJson(res, {});
        }
      });
    },
  };
}

export default defineConfig({
  server: { port: 4322 },
  plugins: [dashboardApi()],
});
