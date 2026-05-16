// Driver for the coverage-completion loop. Surfaces the per-iter proposal,
// GREEN gate exit, validator decision, MUTATION gate exit, and reviewer
// decision so the dashboard can show each iter's regression-armor outcome at a
// glance.

import { parseDashField, parseIntSafe, parseSingleLineUnder } from './_helpers.js';

// Stoplist "kind" tokens written by scripts/coverage-loop/orchestrator.sh.
// Anything not listed falls through to RUNNING via the inference fallback.
const STOPLIST_KIND_TO_STATUS = {
  landed: 'LANDED',
  infeasible: 'DROPPED',
  'no-green': 'DROPPED',
  'validator-dropped': 'DROPPED',
  'mutation-infra': 'DROPPED',
  'mutation-passed': 'DROPPED',
  'reviewer-failed': 'DROPPED',
};

function parseStoplistStatuses(stoplistText) {
  const byIter = new Map();
  if (!stoplistText) return byIter;
  // Lines look like: "- iter 3 landed: <slug>"
  //                  "- iter 5 mutation-passed: <slug>"
  const re = /^-\s*iter\s+(\d+)\s+([A-Za-z][A-Za-z0-9_-]*):/gm;
  let m;
  while ((m = re.exec(stoplistText)) !== null) {
    const iter = parseIntSafe(m[1]);
    const status = STOPLIST_KIND_TO_STATUS[m[2]];
    if (status) byIter.set(iter, status);
  }
  return byIter;
}

function shortStatus(text) {
  const v = parseSingleLineUnder(text, '## STATUS');
  if (!v) return null;
  if (v === 'PROPOSAL_FOUND') return 'OK';
  if (v === 'INFEASIBLE') return 'INF';
  if (v === 'CLEAN') return 'CLN';
  return v;
}

function shortDecision(text) {
  return parseSingleLineUnder(text, '## DECISION') || null;
}

// mutation_check exit-code semantics (orchestrator.sh):
//   0 = test FAILED against mutated source -> load-bearing (PASS)
//   1 = test PASSED against mutated source -> NOT load-bearing (FAIL)
//   2 = infrastructure error
function shortMutation(exitText) {
  const v = (exitText || '').trim();
  if (v === '0') return 'PASS';
  if (v === '1') return 'FAIL';
  if (v === '2') return 'ERR';
  return v || '-';
}

export default {
  id: 'coverage',
  label: 'Coverage',
  runsRelativePath: 'scripts/coverage-loop/runs',

  iterFiles: {
    hunt: 'hunt.md',
    testWriter: 'test-writer.md',
    greenOut: 'green.out',
    greenExit: 'green.exit',
    validated: 'validated.md',
    mutationOut: 'mutation.out',
    mutationExit: 'mutation.exit',
    review: 'review.md',
  },

  tabs: [
    { id: 'hunt', label: 'hunt.md' },
    { id: 'testWriter', label: 'test-writer.md' },
    { id: 'greenOut', label: 'green.out' },
    { id: 'validated', label: 'validated.md' },
    { id: 'mutationOut', label: 'mutation.out' },
    { id: 'review', label: 'review.md' },
  ],

  pipelineOrder: [
    'hunt',
    'testWriter',
    'greenOut',
    'validated',
    'mutationOut',
    'review',
  ],

  columns: [
    { id: 'package', label: 'Pkg', kind: 'text' },
    { id: 'slug', label: 'Slug', kind: 'text' },
    { id: 'category', label: 'Cat', kind: 'text' },
    { id: 'green', label: 'GRN', kind: 'text' },
    { id: 'validated', label: 'Val', kind: 'text' },
    { id: 'mutation', label: 'MUT', kind: 'text' },
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
    const category = parseDashField(files.hunt, 'category') || '-';
    const greenExit = (files.greenExit || '').trim();
    const validated = shortDecision(files.validated);
    const mutation = shortMutation(files.mutationExit);
    const review = shortDecision(files.review) || '-';

    let status = ctx?.statusByIter?.get(ctx.iterNumber);
    if (!status) {
      const huntStatus = shortStatus(files.hunt);
      if (huntStatus === 'CLN') status = 'CLEAN';
      else if (huntStatus === 'INF') status = 'DROPPED';
      else if (review === 'PASS' && mutation === 'PASS') status = 'LANDED';
      else if (review === 'FAIL') status = 'DROPPED';
      else if (mutation === 'FAIL' || mutation === 'ERR') status = 'DROPPED';
      else if (validated === 'FAIL') status = 'DROPPED';
      else if (greenExit && greenExit !== '0') status = 'DROPPED';
      else if (files.hunt) status = 'RUNNING';
      else status = 'UNKNOWN';
    }

    return {
      status,
      columns: {
        package: pkg,
        slug,
        category,
        green: greenExit || '-',
        validated: validated || '-',
        mutation,
        review,
      },
    };
  },

  computeRunStatus({ runDirFiles }) {
    return {
      converged: runDirFiles.has('CONVERGED'),
      verifierFailed: false,
    };
  },
};
