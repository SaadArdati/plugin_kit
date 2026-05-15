// Driver for the bug-hunt loop. Surfaces the per-iter hypothesis, RED/GREEN
// exit codes, fixer status, and reviewer decision so the dashboard can show
// each iter's TDD outcome at a glance.

import { parseDashField, parseIntSafe, parseSingleLineUnder } from './_helpers.js';

// Map of stoplist-line "kind" tokens to terminal iter statuses.
// Anything else lands on RUNNING via the inference fallback in computeRow.
const STOPLIST_KIND_TO_STATUS = {
  fixed: 'FIXED',
  filed: 'FILED',
  'empty-diff': 'FILED',
  'green-failed': 'FILED',
  'review-failed': 'FILED',
  'reviewer-error': 'FILED',
  'tdd-violation': 'FILED',
  dropped: 'DROPPED',
  'no-red': 'DROPPED',
  INFEASIBLE: 'DROPPED',
};

function parseStoplistStatuses(stoplistText) {
  const byIter = new Map();
  if (!stoplistText) return byIter;
  // Lines look like: "- iter 2 empty-diff: <slug> (ISSUE-...)"
  //                  "- iter 1 dropped: <slug>"
  //                  "- iter 7 fixed: <slug>"
  const re = /^-\s*iter\s+(\d+)\s+([A-Za-z][A-Za-z0-9_-]*):/gm;
  let m;
  while ((m = re.exec(stoplistText)) !== null) {
    const iter = parseIntSafe(m[1]);
    const kind = m[2];
    const status = STOPLIST_KIND_TO_STATUS[kind];
    if (status) byIter.set(iter, status);
  }
  return byIter;
}

function shortStatus(text) {
  const v = parseSingleLineUnder(text, '## STATUS');
  if (!v) return null;
  if (v === 'FIX_APPLIED') return 'FIX';
  if (v === 'FIX_TOO_LARGE') return 'BIG';
  if (v === 'TEST_WRITTEN') return 'OK';
  if (v === 'INFEASIBLE') return 'INF';
  if (v === 'HYPOTHESIS_FOUND') return 'OK';
  if (v === 'CLEAN') return 'CLN';
  if (v === 'DRY_RUN') return 'DRY';
  return v;
}

function shortDecision(text) {
  const v = parseSingleLineUnder(text, '## DECISION');
  if (!v) return null;
  return v;
}

export default {
  id: 'bug-hunt',
  label: 'Bug hunt',
  runsRelativePath: 'scripts/bug-hunt-loop/runs',

  iterFiles: {
    hunt: 'hunt.md',
    testWriter: 'test-writer.md',
    redOut: 'red.out',
    redExit: 'red.exit',
    validated: 'validated.md',
    fixReport: 'fix-report.md',
    libDiff: 'lib.diff',
    greenOut: 'green.out',
    greenExit: 'green.exit',
    review: 'review.md',
  },

  tabs: [
    { id: 'hunt', label: 'hunt.md' },
    { id: 'testWriter', label: 'test-writer.md' },
    { id: 'redOut', label: 'red.out' },
    { id: 'validated', label: 'validated.md' },
    { id: 'fixReport', label: 'fix-report.md' },
    { id: 'libDiff', label: 'lib.diff' },
    { id: 'greenOut', label: 'green.out' },
    { id: 'review', label: 'review.md' },
  ],

  // Pipeline order (freshest last). Drives auto-tab-switch on file change.
  pipelineOrder: [
    'hunt',
    'testWriter',
    'redOut',
    'validated',
    'fixReport',
    'libDiff',
    'greenOut',
    'review',
  ],

  columns: [
    { id: 'package', label: 'Pkg', kind: 'text' },
    { id: 'slug', label: 'Slug', kind: 'text' },
    { id: 'sev', label: 'Sev', kind: 'text' },
    { id: 'red', label: 'RED', kind: 'text' },
    { id: 'green', label: 'GRN', kind: 'text' },
    { id: 'fix', label: 'Fix', kind: 'text' },
    { id: 'review', label: 'Review', kind: 'text' },
  ],

  buildOrchestratorContext({ stoplistText } = {}) {
    return {
      statusByIter: parseStoplistStatuses(stoplistText),
    };
  },

  computeRow(files, ctx) {
    const pkg = parseDashField(files.hunt, 'package') || '-';
    const slug = parseDashField(files.hunt, 'slug') || '-';
    const sev = parseDashField(files.hunt, 'severity') || '-';
    const redExit = (files.redExit || '').trim();
    const greenExit = (files.greenExit || '').trim();
    const fix = shortStatus(files.fixReport) || '-';
    const review = shortDecision(files.review) || '-';
    const validated = shortDecision(files.validated);

    // Authoritative status: stoplist entry written by orchestrator at end of
    // iter. Maps FIXED/FILED/DROPPED. Falls back to inference for iters still
    // in flight (no stoplist line yet).
    let status = ctx?.statusByIter?.get(ctx.iterNumber);
    if (!status) {
      if (review === 'PASS' && greenExit === '0') status = 'FIXED';
      else if (review === 'FAIL') status = 'FILED';
      else if (greenExit && greenExit !== '0') status = 'FILED';
      else if (fix === 'BIG') status = 'FILED';
      else if (validated === 'DROPPED') status = 'DROPPED';
      else if (files.hunt) status = 'RUNNING';
      else status = 'UNKNOWN';
    }

    return {
      status,
      columns: {
        package: pkg,
        slug,
        sev,
        red: redExit || '-',
        green: greenExit || '-',
        fix,
        review,
      },
    };
  },

  computeRunStatus({ runDirFiles }) {
    return {
      converged: runDirFiles.has('CONVERGED'),
      // Bug-hunt has no separate verifier-failures concept; per-iter rollback
      // is the equivalent and is reflected via the FILED status on rows.
      verifierFailed: false,
    };
  },
};
