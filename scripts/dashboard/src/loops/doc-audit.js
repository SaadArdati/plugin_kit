// Driver for the doc-audit loop. Ports the original dashboard's parsing 1:1
// so the doc-audit view behaves exactly as before.

import {
  matchCount,
  parseFixSummary,
  parseIntSafe,
  parseOrchestratorVerifierStatuses,
  parseReviewSummary,
  parseValidatedCounts,
} from './_helpers.js';

export default {
  id: 'doc-audit',
  label: 'Doc audit',
  runsRelativePath: 'scripts/doc-audit-loop/runs',

  iterFiles: {
    audit: 'audit.md',
    validated: 'validated.md',
    fixReport: 'fix-report.md',
    review: 'review.md',
    verifier: 'verifier.log',
  },

  tabs: [
    { id: 'audit', label: 'audit.md' },
    { id: 'validated', label: 'validated.md' },
    { id: 'fixReport', label: 'fix-report.md' },
    { id: 'review', label: 'review.md' },
  ],

  // Stage order; later in the list = freshest. Drives auto-tab-switch.
  pipelineOrder: ['audit', 'validated', 'fixReport', 'review'],

  columns: [
    { id: 'findings', label: 'Findings', kind: 'number' },
    { id: 'confirmed', label: 'Confirmed', kind: 'number' },
    { id: 'dropped', label: 'Dropped', kind: 'number' },
    { id: 'edits', label: 'Edits', kind: 'number' },
    { id: 'pass', label: 'Pass', kind: 'number' },
    { id: 'fixedInline', label: 'Fixed', kind: 'number' },
    { id: 'unfixable', label: 'Unfix', kind: 'number' },
  ],

  buildOrchestratorContext(orchestratorLogText) {
    return {
      orchestratorStatusByIter: parseOrchestratorVerifierStatuses(orchestratorLogText || ''),
    };
  },

  computeRow(files, ctx) {
    const findings = matchCount(files.audit, /^## FINDING\s+/gm);
    const { confirmed, dropped } = parseValidatedCounts(files.validated);
    const { edits } = parseFixSummary(files.fixReport);
    const { pass, fixedInline, unfixable } = parseReviewSummary(files.review);

    let status = ctx.orchestratorStatusByIter.get(ctx.iterNumber) || null;
    if (!status) {
      if (files.verifier) {
        if (/verifier\s+GREEN/i.test(files.verifier)) status = 'GREEN';
        else if (/verifier\s+RED/i.test(files.verifier)) status = 'RED';
      }
      if (!status && files.audit && (!files.validated || !files.fixReport || !files.review)) {
        status = 'RUNNING';
      }
      if (!status) status = 'UNKNOWN';
    }

    return {
      status,
      columns: { findings, confirmed, dropped, edits, pass, fixedInline, unfixable },
    };
  },

  computeRunStatus({ runDirFiles }) {
    return {
      converged: runDirFiles.has('CONVERGED'),
      verifierFailed: runDirFiles.has('VERIFIER_FAILURES.md'),
    };
  },
};
