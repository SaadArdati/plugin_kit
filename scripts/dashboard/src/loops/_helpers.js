// Shared parsing primitives used by multiple loop drivers. Pure functions over
// strings; no I/O. Add a parser here when two drivers need it; keep loop-
// specific parsers local to the driver file.

export function parseIntSafe(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? '').trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function matchCount(text, regex) {
  if (!text) return 0;
  return (text.match(regex) || []).length;
}

export function parseValidatedCounts(text) {
  if (!text) return { confirmed: 0, dropped: 0 };
  const summary = text.match(/^## SUMMARY\s+confirmed=(\d+)\s+dropped=(\d+)\s*$/im);
  if (summary) {
    return {
      confirmed: parseIntSafe(summary[1]),
      dropped: parseIntSafe(summary[2]),
    };
  }
  const confirmed = matchCount(text, /^## CONFIRMED\s+F\d+/gm);
  const dropped = matchCount(text, /^## DROPPED\s+F\d+/gm);
  return { confirmed, dropped };
}

export function parseFixSummary(text) {
  if (!text) return { edits: 0 };
  const m = text.match(
    /^## SUMMARY\s+iter\s+\d+\s+edits=(\d+)\s+issues_appended=(\d+)\s+skips=(\d+)\s*$/im,
  );
  if (!m) return { edits: 0 };
  return { edits: parseIntSafe(m[1]) };
}

export function parseReviewSummary(text) {
  if (!text) return { pass: 0, fixedInline: 0, unfixable: 0 };
  const m = text.match(
    /^## SUMMARY\s+iter\s+\d+\s+pass=(\d+)\s+fixed_inline=(\d+)\s+unfixable=(\d+)\s*$/im,
  );
  if (!m) return { pass: 0, fixedInline: 0, unfixable: 0 };
  return {
    pass: parseIntSafe(m[1]),
    fixedInline: parseIntSafe(m[2]),
    unfixable: parseIntSafe(m[3]),
  };
}

export function parseOrchestratorVerifierStatuses(text) {
  const map = new Map();
  if (!text) return map;
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/iter\s+(\d+):\s+verifier\s+(GREEN|RED)\b/i);
    if (m) map.set(parseIntSafe(m[1]), m[2].toUpperCase());
  }
  return map;
}

// Parse "- key: value" or '- key: "value"' from the first matching line.
export function parseDashField(text, field) {
  if (!text) return null;
  const re = new RegExp(`^- ${field}:\\s*(.*?)\\s*$`, 'm');
  const m = text.match(re);
  if (!m) return null;
  return m[1].replace(/^"(.*)"$/, '$1');
}

// Returns the first non-blank line under "## HEADER", stopping at the next
// "## " header. Used for blocks like "## STATUS\nFIX_APPLIED".
export function parseSingleLineUnder(text, header) {
  if (!text) return null;
  const lines = text.split(/\r?\n/);
  let inside = false;
  for (const line of lines) {
    if (!inside) {
      if (line.trim() === header) inside = true;
      continue;
    }
    if (line.startsWith('## ')) break;
    if (line.trim()) return line.trim();
  }
  return null;
}

export function parseStartedAtFromFirstLine(firstLine, fallbackDate) {
  if (!firstLine) return null;
  const isoLike = firstLine.match(
    /(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)/,
  );
  if (isoLike) {
    const parsed = new Date(isoLike[1].replace(' ', 'T'));
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
  }
  const hms = firstLine.match(/\[(\d{2}):(\d{2}):(\d{2})\]/);
  if (hms && fallbackDate instanceof Date && !Number.isNaN(fallbackDate.getTime())) {
    const composed = new Date(fallbackDate);
    composed.setHours(parseIntSafe(hms[1]), parseIntSafe(hms[2]), parseIntSafe(hms[3]), 0);
    return composed.toISOString();
  }
  return null;
}
