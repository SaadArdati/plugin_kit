// Driver for the decomp-loop. Surfaces per-step pipeline state: spec section,
// codex executor output, gate results (analyze, test, grep, signatures,
// line-count), diff, reviewer decision, status, and commit message. The
// orchestrator writes phase.txt continuously so the dashboard can show what
// phase a running step is in (executor / analyze / test / grep / signatures /
// reviewer / staging / ready / blocked) without waiting for the step to end.

import { parseDashField, parseIntSafe, parseSingleLineUnder } from './_helpers.js';

function readPhase(text) {
  return (text || '').trim() || '-';
}

function readStatus(text) {
  return (text || '').trim();
}

function readExit(text) {
  const v = (text || '').trim();
  if (v === '') return '-';
  if (v === '0') return 'PASS';
  return 'FAIL';
}

function readGrep(text) {
  const v = (text || '').trim();
  if (v === '') return '-';
  if (v === '0') return 'PASS';
  return 'FAIL';
}

function readReview(text) {
  const v = parseSingleLineUnder(text, '## DECISION');
  return v || '-';
}

function readLineCount(text) {
  if (!text) return '-';
  const m = text.match(/runtime\.dart:\s*(\d+)/);
  return m ? `${m[1]}L` : '-';
}

export default {
  id: 'decomp',
  label: 'Decomp',
  runsRelativePath: 'scripts/decomp-loop/runs',
  itersSubdir: 'steps',
  iterDirRegex: /^step-\w+$/,

  iterFiles: {
    step: 'step.txt',
    title: 'title.txt',
    cluster: 'cluster.txt',
    phase: 'phase.txt',
    status: 'status.txt',
    specSection: 'spec-section.md',
    executorPrompt: 'executor.prompt.md',
    codex: 'codex.out',
    codexExit: 'codex.exit',
    analyzeOut: 'analyze.out',
    analyzeExit: 'analyze.exit',
    testOut: 'test.out',
    testExit: 'test.exit',
    grepOut: 'grep-gates.out',
    grepExit: 'grep-gates.exit',
    sigsOut: 'signatures.out',
    sigsExit: 'signatures.exit',
    lineCountOut: 'line-count.out',
    diff: 'diff.patch',
    reviewPrompt: 'review.prompt.md',
    review: 'review.md',
    commitMessage: 'commit-message.txt',
  },

  tabs: [
    { id: 'specSection', label: 'spec' },
    { id: 'executorPrompt', label: 'executor.prompt' },
    { id: 'codex', label: 'codex.out' },
    { id: 'analyzeOut', label: 'analyze' },
    { id: 'testOut', label: 'test' },
    { id: 'grepOut', label: 'grep-gates' },
    { id: 'sigsOut', label: 'signatures' },
    { id: 'lineCountOut', label: 'line-count' },
    { id: 'diff', label: 'diff.patch' },
    { id: 'review', label: 'review.md' },
    { id: 'commitMessage', label: 'commit-msg' },
  ],

  // Order matters for auto-tab-switching. Freshest stage at the end of the
  // list is the tab the dashboard surfaces when a new file lands.
  pipelineOrder: [
    'specSection',
    'executorPrompt',
    'codex',
    'analyzeOut',
    'testOut',
    'grepOut',
    'sigsOut',
    'lineCountOut',
    'diff',
    'review',
    'commitMessage',
  ],

  columns: [
    { id: 'stepId', label: 'Step', kind: 'text' },
    { id: 'cluster', label: 'Cluster', kind: 'text' },
    { id: 'phase', label: 'Phase', kind: 'text' },
    { id: 'analyze', label: 'Anlz', kind: 'text' },
    { id: 'test', label: 'Test', kind: 'text' },
    { id: 'grep', label: 'Grep', kind: 'text' },
    { id: 'sigs', label: 'Sigs', kind: 'text' },
    { id: 'review', label: 'Review', kind: 'text' },
    { id: 'lines', label: 'Lines', kind: 'text' },
  ],

  buildOrchestratorContext({ orchestratorLogText } = {}) {
    // No cross-iter state beyond what each step writes to its own files.
    return {
      logText: orchestratorLogText || '',
    };
  },

  computeRow(files, ctx) {
    const stepId = (files.step || '').trim() || '-';
    const cluster = (files.cluster || '').trim() || '-';
    const phase = readPhase(files.phase);
    const statusText = readStatus(files.status);

    const analyze = readExit(files.analyzeExit);
    const test = readExit(files.testExit);
    const grep = readGrep(files.grepExit);
    const sigs = readExit(files.sigsExit);
    const review = readReview(files.review);
    const lines = readLineCount(files.lineCountOut);

    // Status precedence:
    //   READY_FOR_COMMIT     -> READY (green)
    //   BLOCKED ...          -> BLOCKED (red)
    //   phase set + no terminal status -> RUNNING (gray, with phase shown)
    //   default              -> UNKNOWN (gray)
    let status;
    if (statusText.startsWith('READY_FOR_COMMIT')) {
      status = 'READY';
    } else if (statusText.startsWith('BLOCKED')) {
      status = 'BLOCKED';
    } else if (phase !== '-' && phase !== 'ready') {
      status = `RUNNING:${phase}`;
    } else if (files.step) {
      status = 'RUNNING';
    } else {
      status = 'UNKNOWN';
    }

    return {
      status,
      columns: {
        stepId,
        cluster,
        phase,
        analyze,
        test,
        grep,
        sigs,
        review,
        lines,
      },
    };
  },

  computeRunStatus({ runDirFiles }) {
    return {
      converged: runDirFiles.has('COMPLETE'),
      verifierFailed: false,
    };
  },
};
