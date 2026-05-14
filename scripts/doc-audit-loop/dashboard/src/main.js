const state = {
  status: {
    iteration: 0,
    converged: false,
    startedAt: null,
    runDir: '',
    verifierFailed: false,
  },
  iters: [],
  selectedIterId: null,
  selectedIterDetails: null,
  activeTab: 'audit',
  paused: false,
};

const tabNames = {
  audit: 'audit.md',
  validated: 'validated.md',
  fixReport: 'fix-report.md',
  review: 'review.md',
};

const currentIterEl = document.querySelector('#current-iter');
const runMetaEl = document.querySelector('#run-meta');
const statusBadgeEl = document.querySelector('#status-badge');
const itersBodyEl = document.querySelector('#iters-body');
const detailsTitleEl = document.querySelector('#details-title');
const detailsTabsEl = document.querySelector('#details-tabs');
const detailsContentEl = document.querySelector('#details-content');
const logContentEl = document.querySelector('#log-content');
const pauseLogEl = document.querySelector('#pause-log');

function toNumber(value) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

async function fetchJson(url, fallback) {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      return fallback;
    }
    return await response.json();
  } catch {
    return fallback;
  }
}

async function fetchText(url, fallback = '') {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      return fallback;
    }
    return await response.text();
  } catch {
    return fallback;
  }
}

function getBadge() {
  if (state.status.converged) {
    return { text: 'CONVERGED', className: 'green' };
  }
  if (state.status.verifierFailed) {
    return { text: 'RED', className: 'red' };
  }

  const newestStatus = state.iters[0]?.status;
  if (newestStatus === 'GREEN') {
    return { text: 'GREEN', className: 'green' };
  }
  if (newestStatus === 'RED') {
    return { text: 'RED', className: 'red' };
  }
  if (newestStatus === 'RUNNING') {
    return { text: 'RUNNING', className: 'gray' };
  }
  return { text: 'UNKNOWN', className: 'gray' };
}

function renderHeader() {
  if (!currentIterEl || !runMetaEl || !statusBadgeEl) {
    return;
  }

  currentIterEl.textContent = String(toNumber(state.status.iteration));

  const startedAtText = state.status.startedAt
    ? new Date(state.status.startedAt).toLocaleString()
    : 'unknown start';
  const runDirText = state.status.runDir || 'unknown run dir';
  runMetaEl.textContent = `Run: ${runDirText} | Started: ${startedAtText}`;

  const badge = getBadge();
  statusBadgeEl.textContent = badge.text;
  statusBadgeEl.className = `badge ${badge.className}`;
}

function renderIters() {
  if (!itersBodyEl) {
    return;
  }

  if (!Array.isArray(state.iters) || state.iters.length === 0) {
    itersBodyEl.innerHTML = '<tr><td colspan="9" class="empty">No iterations yet.</td></tr>';
    return;
  }

  const rows = state.iters
    .map((iter) => {
      const selectedClass = iter.id === state.selectedIterId ? ' selected' : '';
      const statusClass =
        iter.status === 'GREEN'
          ? 'status-green'
          : iter.status === 'RED'
            ? 'status-red'
            : 'status-gray';

      return `<tr data-id="${iter.id}" class="iter-row${selectedClass}">
        <td>${iter.id}</td>
        <td><span class="status-chip ${statusClass}">${iter.status || 'UNKNOWN'}</span></td>
        <td>${toNumber(iter.findings)}</td>
        <td>${toNumber(iter.confirmed)}</td>
        <td>${toNumber(iter.dropped)}</td>
        <td>${toNumber(iter.edits)}</td>
        <td>${toNumber(iter.pass)}</td>
        <td>${toNumber(iter.fixedInline)}</td>
        <td>${toNumber(iter.unfixable)}</td>
      </tr>`;
    })
    .join('');

  itersBodyEl.innerHTML = rows;
}

function renderDetails() {
  if (!detailsTitleEl || !detailsContentEl || !detailsTabsEl) {
    return;
  }

  const selected = state.selectedIterId;
  detailsTitleEl.textContent = selected ? `Iteration ${selected}` : 'Iteration details';

  const buttons = detailsTabsEl.querySelectorAll('.tab');
  buttons.forEach((button) => {
    const tab = button.getAttribute('data-tab');
    button.classList.toggle('active', tab === state.activeTab);
  });

  if (!state.selectedIterDetails) {
    detailsContentEl.textContent = 'Select an iteration to view details.';
    return;
  }

  const content = state.selectedIterDetails[state.activeTab];
  detailsContentEl.textContent = content || '';
}

function renderLog(logText) {
  if (!logContentEl) {
    return;
  }

  logContentEl.textContent = logText || '';
  if (!state.paused) {
    logContentEl.scrollTop = logContentEl.scrollHeight;
  }
}

// Pipeline order: a later stage's file landing implies it's the freshest.
const TAB_PIPELINE = ['audit', 'validated', 'fixReport', 'review'];

// Window during which manual tab clicks suppress auto-switch (ms). Lets the
// user read a tab without being yanked to a newer one mid-read.
const MANUAL_TAB_GRACE_MS = 10000;

async function loadIterDetails(iterId) {
  if (!iterId) {
    return;
  }

  const details = await fetchJson(`/api/iter/${iterId}`, null);
  state.selectedIterDetails = details;
  renderDetails();
}

// Poll the currently-selected iter's details, detect which tabs changed
// since last poll, render the new content, and auto-switch to the freshest
// changed tab unless the user manually picked a tab within the grace window.
async function pollSelectedIter() {
  if (!state.selectedIterId) {
    return;
  }
  const fresh = await fetchJson(`/api/iter/${state.selectedIterId}`, null);
  if (!fresh) {
    return;
  }

  const prev = state.selectedIterDetails || {};
  const changedTabs = TAB_PIPELINE.filter(
    (tab) => (fresh[tab] || '') !== (prev[tab] || ''),
  );

  if (changedTabs.length === 0) {
    return;
  }

  state.selectedIterDetails = fresh;

  // Pipeline order means later-listed = freshest. If review just landed in
  // the same poll where validated also changed, jump to review.
  const freshestChanged = changedTabs[changedTabs.length - 1];
  const withinGrace =
    Date.now() - (state.manualTabPickAt || 0) < MANUAL_TAB_GRACE_MS;
  if (!withinGrace && freshestChanged !== state.activeTab) {
    state.activeTab = freshestChanged;
  }

  renderDetails();
}

async function pollStatusAndIters() {
  const [statusData, iterData] = await Promise.all([
    fetchJson('/api/status', state.status),
    fetchJson('/api/iters', []),
  ]);

  state.status = {
    iteration: toNumber(statusData?.iteration),
    converged: Boolean(statusData?.converged),
    startedAt: statusData?.startedAt || null,
    runDir: statusData?.runDir || '',
    verifierFailed: Boolean(statusData?.verifierFailed),
  };

  const previousNewestId = state.previousNewestId || null;
  state.iters = Array.isArray(iterData) ? iterData : [];
  const newestId = state.iters[0]?.id || null;

  const selectedStillExists = state.iters.some((iter) => iter.id === state.selectedIterId);

  let shouldLoadDetails = false;
  if (!selectedStillExists) {
    // First load or the selected iter was pruned: jump to the newest.
    state.selectedIterId = newestId;
    state.selectedIterDetails = null;
    state.manualTabPickAt = 0;
    shouldLoadDetails = Boolean(newestId);
  } else if (
    newestId &&
    previousNewestId &&
    newestId !== previousNewestId &&
    state.selectedIterId === previousNewestId
  ) {
    // A fresh iter row just appeared AND the user was tracking the previous
    // newest, so auto-advance to follow the live progress. If the user is
    // inspecting an older iter, leave them alone.
    state.selectedIterId = newestId;
    state.selectedIterDetails = null;
    state.manualTabPickAt = 0;
    shouldLoadDetails = true;
  }

  state.previousNewestId = newestId;

  renderHeader();
  renderIters();
  renderDetails();

  if (shouldLoadDetails) {
    await loadIterDetails(state.selectedIterId);
  }
}

async function pollLog() {
  if (state.paused) {
    return;
  }
  const logText = await fetchText('/api/log?tail=400', '');
  renderLog(logText);
}

itersBodyEl?.addEventListener('click', async (event) => {
  const row = event.target.closest('tr[data-id]');
  if (!row) {
    return;
  }
  const iterId = row.getAttribute('data-id');
  if (!iterId || iterId === state.selectedIterId) {
    return;
  }

  state.selectedIterId = iterId;
  state.selectedIterDetails = null;
  // Clear the manual-tab-grace marker so auto-switch on the new iter's
  // freshly arriving files works immediately.
  state.manualTabPickAt = 0;
  renderIters();
  renderDetails();
  await loadIterDetails(iterId);
});

detailsTabsEl?.addEventListener('click', (event) => {
  const button = event.target.closest('button[data-tab]');
  if (!button) {
    return;
  }
  const tab = button.getAttribute('data-tab');
  if (!tabNames[tab]) {
    return;
  }

  // Record the manual pick so auto-switch holds off for the grace window.
  state.manualTabPickAt = Date.now();
  state.activeTab = tab;
  renderDetails();
});

pauseLogEl?.addEventListener('change', async (event) => {
  state.paused = Boolean(event.target.checked);
  if (!state.paused) {
    await pollLog();
  }
});

renderHeader();
renderIters();
renderDetails();
renderLog('');

void pollStatusAndIters();
void pollLog();
void pollSelectedIter();

setInterval(() => {
  void pollStatusAndIters();
}, 2000);

setInterval(() => {
  void pollLog();
}, 1500);

// Refresh the selected iter's markdown panels so the right column tracks
// the orchestrator's live writes. Auto-switches to the freshest tab on
// change (unless the user manually picked a tab in the last few seconds).
setInterval(() => {
  void pollSelectedIter();
}, 2500);
