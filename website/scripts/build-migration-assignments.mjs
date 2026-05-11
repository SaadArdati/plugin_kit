#!/usr/bin/env node
// Builds .codex-out/migration-assignments.tsv from the inventory plus the
// per-target plans:
//
//   inventory.tsv         (every dart code block in scope)
//   docregion-plan.tsv    (markers in existing source files)
//   snippet-plan.tsv      (planned regions in website/snippets/lib/)
//
// Output columns:
//   doc_file start_line end_line loc region_name source_path action notes
//
// `action` is one of:
//   migrate  - block has a region defined; replace fenced block with extract
//   skip     - block is pure-fragment, pseudocode, or orphan; leave fenced

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

function readTsv(path) {
  if (!existsSync(path)) return null;
  const lines = readFileSync(path, 'utf8').split('\n').filter((l) => l.length);
  if (lines.length < 1) return [];
  const header = lines[0].split('\t');
  return lines.slice(1).map((row) => {
    const cells = row.split('\t');
    return Object.fromEntries(header.map((h, i) => [h, cells[i] ?? '']));
  });
}

function key(doc, start, end) {
  return `${doc}|${start}|${end}`;
}

const inventory = readTsv(`${REPO_ROOT}/.codex-out/inventory.tsv`);
const docregion = readTsv(`${REPO_ROOT}/.codex-out/docregion-plan.tsv`) ?? [];
const snippet = readTsv(`${REPO_ROOT}/.codex-out/snippet-plan.tsv`) ?? [];

if (!inventory) {
  console.error('inventory.tsv not found');
  process.exit(1);
}

// Build a lookup: doc-block-key → { region_name, source_path }
const assignments = new Map();

for (const r of docregion) {
  if (!r.region_name || r.region_name === '(orphan)' || r.region_name === '(mismatch)') continue;
  if (r.notes && (r.notes.includes('orphan') || r.notes.includes('mismatch'))) continue;
  assignments.set(key(r.doc_file, r.start_line, r.end_line), {
    region_name: r.region_name,
    source_path: r.candidate_source,
  });
}

for (const r of snippet) {
  if (!r.target_file || r.target_file === '(skip)') continue;
  if (r.target_file.startsWith('(')) continue;
  assignments.set(key(r.doc_file, r.start_line, r.end_line), {
    region_name: r.region_name,
    source_path: r.target_file,
  });
}

// Compose output rows in inventory order.
const rows = [
  ['doc_file', 'start_line', 'end_line', 'loc', 'region_name', 'source_path', 'action', 'notes'].join('\t'),
];

let migrate = 0, skip = 0;
for (const inv of inventory) {
  const k = key(inv.doc_file, inv.start_line, inv.end_line);
  const a = assignments.get(k);
  if (a) {
    rows.push([
      inv.doc_file, inv.start_line, inv.end_line, inv.loc,
      a.region_name, a.source_path, 'migrate', inv.classification,
    ].join('\t'));
    migrate++;
  } else {
    rows.push([
      inv.doc_file, inv.start_line, inv.end_line, inv.loc,
      '', '', 'skip', inv.classification,
    ].join('\t'));
    skip++;
  }
}

writeFileSync(`${REPO_ROOT}/.codex-out/migration-assignments.tsv`, rows.join('\n') + '\n', 'utf8');
console.log(`migrate: ${migrate}, skip: ${skip}, total: ${migrate + skip}`);
