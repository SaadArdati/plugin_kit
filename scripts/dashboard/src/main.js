// Schema-driven dashboard. The list of loops, the per-loop schema (column
// definitions, tab definitions, pipeline order), and the per-iter values all
// come from the server (/api/loops, /api/{loopId}/schema, /api/{loopId}/...).
// The frontend has no hardcoded knowledge of either loop's contents.

const state = {
  loops: [],                  // [{id, label}]
  activeLoopId: null,
  schema: null,               // {tabs, pipelineOrder, columns}
  status: {
    iteration: 0,
    converged: false,
    verifierFailed: false,
    startedAt: null,
    runDir: '',
  },
  iters: [],
  selectedIterId: null,
  selectedIterDetails: null,
  activeTab: null,
  manualTabPickAt: 0,
  previousNewestId: null,
  paused: false,
};

const MANUAL_TAB_GRACE_MS = 10000;

const els = {
  loopTitle: document.querySelector('#loop-title'),
  loopSelector: document.querySelector('#loop-selector'),
  currentIter: document.querySelector('#current-iter'),
  runMeta: document.querySelector('#run-meta'),
  statusBadge: document.querySelector('#status-badge'),
  itersHead: document.querySelector('#iters-head'),
  itersBody: document.querySelector('#iters-body'),
  detailsTitle: document.querySelector('#details-title'),
  detailsTabs: document.querySelector('#details-tabs'),
  detailsContent: document.querySelector('#details-content'),
  logContent: document.querySelector('#log-content'),
  pauseLog: document.querySelector('#pause-log'),
};

function readLoopFromHash() {
  const hash = window.location.hash || '';
  const m = hash.match(/loop=([^&]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}

function writeLoopToHash(loopId) {
  const next = `#loop=${encodeURIComponent(loopId)}`;
  if (window.location.hash !== next) {
    history.replaceState(null, '', next);
  }
}

async function fetchJson(url, fallback) {
  try {
    const response = await fetch(url);
    if (!response.ok) return fallback;
    return await response.json();
  } catch {
    return fallback;
  }
}

async function fetchText(url, fallback = '') {
  try {
    const response = await fetch(url);
    if (!response.ok) return fallback;
    return await response.text();
  } catch {
    return fallback;
  }
}

function api(path) {
  return `/api/${state.activeLoopId}/${path}`;
}

function classifyStatus(value) {
  const v = String(value || '').toUpperCase();
  if (v === 'GREEN' || v === 'PASS' || v === 'CONVERGED') return 'green';
  if (v === 'RED' || v === 'FAIL' || v === 'FILED') return 'red';
  if (v === 'RUNNING') return 'gray';
  if (v === 'DROPPED') return 'gray';
  return 'gray';
}

function getRunBadge() {
  if (state.status.converged) return { text: 'CONVERGED', className: 'green' };
  if (state.status.verifierFailed) return { text: 'RED', className: 'red' };
  const newestStatus = state.iters[0]?.status;
  if (newestStatus) {
    const cls = classifyStatus(newestStatus);
    return { text: newestStatus, className: cls };
  }
  return { text: 'UNKNOWN', className: 'gray' };
}

function renderLoopSelector() {
  if (!els.loopSelector) return;
  els.loopSelector.innerHTML = state.loops
    .map((loop) => {
      const active = loop.id === state.activeLoopId ? ' active' : '';
      return `<button data-loop="${loop.id}" class="loop-btn${active}">${loop.label}</button>`;
    })
    .join('');
}

function renderHeader() {
  if (!els.currentIter || !els.runMeta || !els.statusBadge) return;
  const activeLoop = state.loops.find((l) => l.id === state.activeLoopId);
  if (els.loopTitle) els.loopTitle.textContent = activeLoop ? `${activeLoop.label} dashboard` : 'loop dashboard';

  els.currentIter.textContent = String(state.status.iteration ?? 0);

  const startedAtText = state.status.startedAt
    ? new Date(state.status.startedAt).toLocaleString()
    : 'unknown start';
  const runDirText = state.status.runDir || 'unknown run dir';
  els.runMeta.textContent = `Run: ${runDirText} | Started: ${startedAtText}`;

  const badge = getRunBadge();
  els.statusBadge.textContent = badge.text;
  els.statusBadge.className = `badge ${badge.className}`;
}

function renderItersHead() {
  if (!els.itersHead || !state.schema) return;
  const cols = ['ID', 'Status', ...state.schema.columns.map((c) => c.label)];
  els.itersHead.innerHTML = cols.map((label) => `<th>${label}</th>`).join('');
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[ch]);
}

function renderIters() {
  if (!els.itersBody || !state.schema) return;
  const colCount = state.schema.columns.length + 2;
  if (!Array.isArray(state.iters) || state.iters.length === 0) {
    els.itersBody.innerHTML = `<tr><td colspan="${colCount}" class="empty">No iterations yet.</td></tr>`;
    return;
  }

  const rows = state.iters.map((iter) => {
    const selectedClass = iter.id === state.selectedIterId ? ' selected' : '';
    const statusClass = `status-${classifyStatus(iter.status)}`;
    const statusText = iter.status || 'UNKNOWN';
    const cells = state.schema.columns.map((col) => {
      const raw = iter[col.id];
      return `<td>${escapeHtml(raw ?? '-')}</td>`;
    }).join('');
    return `<tr data-id="${iter.id}" class="iter-row${selectedClass}">
      <td>${iter.id}</td>
      <td><span class="status-chip ${statusClass}">${statusText}</span></td>
      ${cells}
    </tr>`;
  }).join('');

  els.itersBody.innerHTML = rows;
}

function renderTabs() {
  if (!els.detailsTabs || !state.schema) return;
  els.detailsTabs.innerHTML = state.schema.tabs.map((tab) => {
    const active = tab.id === state.activeTab ? ' active' : '';
    return `<button data-tab="${tab.id}" class="tab${active}">${tab.label}</button>`;
  }).join('');
}

function renderDetails() {
  if (!els.detailsTitle || !els.detailsContent) return;
  const selected = state.selectedIterId;
  els.detailsTitle.textContent = selected ? `Iteration ${selected}` : 'Iteration details';

  renderTabs();

  if (!state.selectedIterDetails) {
    els.detailsContent.textContent = 'Select an iteration to view details.';
    return;
  }
  const content = state.selectedIterDetails[state.activeTab];
  els.detailsContent.textContent = content || '';
}

function renderLog(text) {
  if (!els.logContent) return;
  els.logContent.textContent = text || '';
  if (!state.paused) {
    els.logContent.scrollTop = els.logContent.scrollHeight;
  }
}

async function loadIterDetails(iterId) {
  if (!iterId || !state.activeLoopId) return;
  const details = await fetchJson(api(`iter/${iterId}`), null);
  state.selectedIterDetails = details;
  renderDetails();
}

async function pollSelectedIter() {
  if (!state.selectedIterId || !state.activeLoopId || !state.schema) return;
  const fresh = await fetchJson(api(`iter/${state.selectedIterId}`), null);
  if (!fresh) return;

  const prev = state.selectedIterDetails || {};
  const pipeline = state.schema.pipelineOrder || [];
  const changedTabs = pipeline.filter(
    (tab) => (fresh[tab] || '') !== (prev[tab] || ''),
  );
  if (changedTabs.length === 0) return;

  state.selectedIterDetails = fresh;
  const freshestChanged = changedTabs[changedTabs.length - 1];
  const withinGrace = Date.now() - (state.manualTabPickAt || 0) < MANUAL_TAB_GRACE_MS;
  if (!withinGrace && freshestChanged !== state.activeTab) {
    state.activeTab = freshestChanged;
  }
  renderDetails();
}

async function pollStatusAndIters() {
  if (!state.activeLoopId) return;

  const [statusData, iterData] = await Promise.all([
    fetchJson(api('status'), state.status),
    fetchJson(api('iters'), []),
  ]);

  state.status = {
    iteration: Number(statusData?.iteration ?? 0),
    converged: Boolean(statusData?.converged),
    verifierFailed: Boolean(statusData?.verifierFailed),
    startedAt: statusData?.startedAt || null,
    runDir: statusData?.runDir || '',
  };

  const previousNewestId = state.previousNewestId || null;
  state.iters = Array.isArray(iterData) ? iterData : [];
  const newestId = state.iters[0]?.id || null;

  const selectedStillExists = state.iters.some((i) => i.id === state.selectedIterId);

  let shouldLoadDetails = false;
  if (!selectedStillExists) {
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
  if (state.paused || !state.activeLoopId) return;
  const text = await fetchText(api('log?tail=400'), '');
  renderLog(text);
}

async function loadSchemaForActiveLoop() {
  if (!state.activeLoopId) return;
  const schema = await fetchJson(`/api/${state.activeLoopId}/schema`, null);
  state.schema = schema;
  // Default tab = first in pipeline (start of the flow).
  const firstTab = schema?.tabs?.[0]?.id || null;
  state.activeTab = firstTab;
  renderItersHead();
  renderTabs();
}

async function switchLoop(loopId) {
  if (!loopId || loopId === state.activeLoopId) return;
  state.activeLoopId = loopId;
  state.iters = [];
  state.selectedIterId = null;
  state.selectedIterDetails = null;
  state.previousNewestId = null;
  state.manualTabPickAt = 0;
  state.status = { iteration: 0, converged: false, verifierFailed: false, startedAt: null, runDir: '' };

  writeLoopToHash(loopId);
  renderLoopSelector();
  renderHeader();
  await loadSchemaForActiveLoop();
  await Promise.all([pollStatusAndIters(), pollLog()]);
}

els.itersBody?.addEventListener('click', async (event) => {
  const row = event.target.closest('tr[data-id]');
  if (!row) return;
  const iterId = row.getAttribute('data-id');
  if (!iterId || iterId === state.selectedIterId) return;

  state.selectedIterId = iterId;
  state.selectedIterDetails = null;
  state.manualTabPickAt = 0;
  renderIters();
  renderDetails();
  await loadIterDetails(iterId);
});

els.detailsTabs?.addEventListener('click', (event) => {
  const button = event.target.closest('button[data-tab]');
  if (!button || !state.schema) return;
  const tab = button.getAttribute('data-tab');
  if (!state.schema.tabs.find((t) => t.id === tab)) return;

  state.manualTabPickAt = Date.now();
  state.activeTab = tab;
  renderDetails();
});

els.loopSelector?.addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-loop]');
  if (!button) return;
  await switchLoop(button.getAttribute('data-loop'));
});

els.pauseLog?.addEventListener('change', async (event) => {
  state.paused = Boolean(event.target.checked);
  if (!state.paused) await pollLog();
});

window.addEventListener('hashchange', async () => {
  const next = readLoopFromHash();
  if (next && next !== state.activeLoopId) await switchLoop(next);
});

(async function init() {
  const loops = await fetchJson('/api/loops', []);
  state.loops = Array.isArray(loops) ? loops : [];
  if (state.loops.length === 0) {
    if (els.runMeta) els.runMeta.textContent = 'No loops registered. Add a driver in src/loops/.';
    return;
  }

  const wantedFromHash = readLoopFromHash();
  const initial = state.loops.find((l) => l.id === wantedFromHash) || state.loops[0];
  state.activeLoopId = initial.id;
  writeLoopToHash(state.activeLoopId);

  renderLoopSelector();
  renderHeader();
  await loadSchemaForActiveLoop();
  renderItersHead();
  renderTabs();
  renderDetails();
  renderLog('');

  await Promise.all([pollStatusAndIters(), pollLog()]);

  setInterval(() => { void pollStatusAndIters(); }, 2000);
  setInterval(() => { void pollLog(); }, 1500);
  setInterval(() => { void pollSelectedIter(); }, 2500);
})();
