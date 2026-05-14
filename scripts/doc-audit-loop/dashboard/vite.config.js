import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..', '..');
const latestRunDir = path.join(
  projectRoot,
  'scripts',
  'doc-audit-loop',
  'runs',
  'latest',
);

async function safeReadText(filePath) {
  try {
    return await fs.readFile(filePath, 'utf8');
  } catch {
    return null;
  }
}

async function safeStat(filePath) {
  try {
    return await fs.stat(filePath);
  } catch {
    return null;
  }
}

async function safeExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function safeReaddir(dirPath) {
  try {
    return await fs.readdir(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function parseIntSafe(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? '').trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseAuditFindings(auditText) {
  if (!auditText) {
    return 0;
  }
  const matches = auditText.match(/^## FINDING\s+/gm);
  return matches ? matches.length : 0;
}

function parseValidatedCounts(validatedText) {
  if (!validatedText) {
    return { confirmed: 0, dropped: 0 };
  }

  const summaryMatch = validatedText.match(
    /^## SUMMARY\s+confirmed=(\d+)\s+dropped=(\d+)\s*$/im,
  );
  if (summaryMatch) {
    return {
      confirmed: parseIntSafe(summaryMatch[1]),
      dropped: parseIntSafe(summaryMatch[2]),
    };
  }

  const confirmed = (validatedText.match(/^## CONFIRMED\s+F\d+/gm) || []).length;
  const dropped = (validatedText.match(/^## DROPPED\s+F\d+/gm) || []).length;
  return { confirmed, dropped };
}

function parseFixCounts(fixReportText) {
  if (!fixReportText) {
    return { edits: 0 };
  }
  const summaryMatch = fixReportText.match(
    /^## SUMMARY\s+iter\s+\d+\s+edits=(\d+)\s+issues_appended=(\d+)\s+skips=(\d+)\s*$/im,
  );
  if (!summaryMatch) {
    return { edits: 0 };
  }
  return { edits: parseIntSafe(summaryMatch[1]) };
}

function parseReviewCounts(reviewText) {
  if (!reviewText) {
    return { pass: 0, fixedInline: 0, unfixable: 0 };
  }
  const summaryMatch = reviewText.match(
    /^## SUMMARY\s+iter\s+\d+\s+pass=(\d+)\s+fixed_inline=(\d+)\s+unfixable=(\d+)\s*$/im,
  );
  if (!summaryMatch) {
    return { pass: 0, fixedInline: 0, unfixable: 0 };
  }
  return {
    pass: parseIntSafe(summaryMatch[1]),
    fixedInline: parseIntSafe(summaryMatch[2]),
    unfixable: parseIntSafe(summaryMatch[3]),
  };
}

function parseOrchestratorVerifierStatuses(orchestratorLogText) {
  const byIter = new Map();
  if (!orchestratorLogText) {
    return byIter;
  }

  const lines = orchestratorLogText.split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(/iter\s+(\d+):\s+verifier\s+(GREEN|RED)\b/i);
    if (!match) {
      continue;
    }
    byIter.set(parseIntSafe(match[1]), match[2].toUpperCase());
  }

  return byIter;
}

function parseStartedAtFromFirstLine(firstLine, fallbackDate) {
  if (!firstLine) {
    return null;
  }

  const isoLike = firstLine.match(
    /(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)/,
  );
  if (isoLike) {
    const parsed = new Date(isoLike[1].replace(' ', 'T'));
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toISOString();
    }
  }

  const hms = firstLine.match(/\[(\d{2}):(\d{2}):(\d{2})\]/);
  if (hms && fallbackDate instanceof Date && !Number.isNaN(fallbackDate.getTime())) {
    const composed = new Date(fallbackDate);
    composed.setHours(parseIntSafe(hms[1]), parseIntSafe(hms[2]), parseIntSafe(hms[3]), 0);
    return composed.toISOString();
  }

  return null;
}

async function computeStartedAtIso(orchestratorLogPath) {
  const stat = await safeStat(orchestratorLogPath);
  if (!stat) {
    return null;
  }

  const logText = await safeReadText(orchestratorLogPath);
  const firstLine = logText ? logText.split(/\r?\n/, 1)[0] : '';
  const parsedFromLine = parseStartedAtFromFirstLine(firstLine, stat.birthtime);
  if (parsedFromLine) {
    return parsedFromLine;
  }

  if (stat.birthtime instanceof Date && !Number.isNaN(stat.birthtime.getTime())) {
    return stat.birthtime.toISOString();
  }

  if (stat.mtime instanceof Date && !Number.isNaN(stat.mtime.getTime())) {
    return stat.mtime.toISOString();
  }

  return null;
}

function deriveIterStatus({
  iterNumber,
  orchestratorStatus,
  verifierText,
  auditText,
  validatedText,
  fixReportText,
  reviewText,
}) {
  if (orchestratorStatus === 'GREEN' || orchestratorStatus === 'RED') {
    return orchestratorStatus;
  }

  if (verifierText) {
    if (/verifier\s+GREEN/i.test(verifierText)) {
      return 'GREEN';
    }
    if (/verifier\s+RED/i.test(verifierText)) {
      return 'RED';
    }
    if (/\bError\s+1\b/i.test(verifierText)) {
      return 'RED';
    }
    if (/\bexit(?:\s+code)?\s*[:=]?\s*[1-9]\d*\b/i.test(verifierText)) {
      return 'RED';
    }
  }

  if (auditText && (!validatedText || !fixReportText || !reviewText)) {
    return 'RUNNING';
  }

  if (iterNumber <= 0) {
    return 'UNKNOWN';
  }

  return 'UNKNOWN';
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

async function buildIterSummaries() {
  const itersRoot = path.join(latestRunDir, 'iters');
  const entries = await safeReaddir(itersRoot);
  const iterDirs = entries.filter((entry) => entry.isDirectory() && /^iter-\d+$/.test(entry.name));

  const orchestratorLogPath = path.join(latestRunDir, 'orchestrator.log');
  const orchestratorLogText = await safeReadText(orchestratorLogPath);
  const statusByIter = parseOrchestratorVerifierStatuses(orchestratorLogText);

  const summaries = await Promise.all(
    iterDirs.map(async (entry) => {
      const id = entry.name;
      const number = parseIntSafe(id.replace('iter-', ''), 0);
      const iterDir = path.join(itersRoot, id);

      const [auditText, validatedText, fixReportText, reviewText, verifierText] = await Promise.all([
        safeReadText(path.join(iterDir, 'audit.md')),
        safeReadText(path.join(iterDir, 'validated.md')),
        safeReadText(path.join(iterDir, 'fix-report.md')),
        safeReadText(path.join(iterDir, 'review.md')),
        safeReadText(path.join(iterDir, 'verifier.log')),
      ]);

      const { confirmed, dropped } = parseValidatedCounts(validatedText);
      const { edits } = parseFixCounts(fixReportText);
      const { pass, fixedInline, unfixable } = parseReviewCounts(reviewText);

      return {
        id,
        number,
        status: deriveIterStatus({
          iterNumber: number,
          orchestratorStatus: statusByIter.get(number),
          verifierText,
          auditText,
          validatedText,
          fixReportText,
          reviewText,
        }),
        findings: parseAuditFindings(auditText),
        confirmed,
        dropped,
        edits,
        pass,
        fixedInline,
        unfixable,
      };
    }),
  );

  summaries.sort((a, b) => b.number - a.number);
  return summaries;
}

function docAuditApi() {
  return {
    name: 'doc-audit-api',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        try {
          const method = req.method || 'GET';
          const url = new URL(req.url || '/', 'http://localhost');
          const pathname = url.pathname;

          if (!pathname.startsWith('/api/')) {
            next();
            return;
          }

          if (method !== 'GET') {
            sendJson(res, { error: 'method not allowed' }, 405);
            return;
          }

          if (pathname === '/api/status') {
            const iterText = await safeReadText(
              path.join(latestRunDir, 'state', 'iteration.txt'),
            );
            const iteration = parseIntSafe(iterText, 0);
            const converged = await safeExists(path.join(latestRunDir, 'CONVERGED'));
            const verifierFailed = await safeExists(
              path.join(latestRunDir, 'VERIFIER_FAILURES.md'),
            );
            const startedAt = await computeStartedAtIso(
              path.join(latestRunDir, 'orchestrator.log'),
            );

            let runDir = latestRunDir;
            try {
              runDir = await fs.realpath(latestRunDir);
            } catch {
              // Keep symlink path fallback when latest does not exist yet.
            }

            sendJson(res, {
              iteration,
              converged,
              startedAt,
              runDir,
              verifierFailed,
            });
            return;
          }

          if (pathname === '/api/log') {
            const tailRaw = url.searchParams.get('tail');
            let tail = parseIntSafe(tailRaw, 200);
            if (tail <= 0) {
              tail = 200;
            }
            tail = Math.min(tail, 2000);

            const logText =
              (await safeReadText(path.join(latestRunDir, 'orchestrator.log'))) || '';
            const lines = logText.split(/\r?\n/);
            if (lines.length > 0 && lines[lines.length - 1] === '') {
              lines.pop();
            }
            const payload = lines.slice(-tail).join('\n');
            sendText(res, payload);
            return;
          }

          if (pathname === '/api/iters') {
            const summaries = await buildIterSummaries();
            sendJson(res, summaries);
            return;
          }

          const iterMatch = pathname.match(/^\/api\/iter\/([^/]+)$/);
          if (iterMatch) {
            const id = decodeURIComponent(iterMatch[1]);
            if (!/^iter-\d+$/.test(id)) {
              sendJson(res, { error: 'invalid iter id' }, 400);
              return;
            }

            const iterDir = path.join(latestRunDir, 'iters', id);
            const [audit, validated, fixReport, review, verifier] = await Promise.all([
              safeReadText(path.join(iterDir, 'audit.md')),
              safeReadText(path.join(iterDir, 'validated.md')),
              safeReadText(path.join(iterDir, 'fix-report.md')),
              safeReadText(path.join(iterDir, 'review.md')),
              safeReadText(path.join(iterDir, 'verifier.log')),
            ]);

            sendJson(res, { id, audit, validated, fixReport, review, verifier });
            return;
          }

          sendJson(res, { error: 'not found' }, 404);
        } catch {
          // API endpoints are best-effort and should never crash the dev server.
          if (!res.headersSent) {
            sendJson(res, {});
          }
        }
      });
    },
  };
}

export default defineConfig({
  server: {
    port: 4322,
  },
  plugins: [docAuditApi()],
});
