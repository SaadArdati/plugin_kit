#!/usr/bin/env node
// Updates dart code excerpts in plain Markdown files using a central registry.
//
// The registry lives at scripts/md-excerpts.json and maps each managed .md
// file to an array indexed by dart-fence position:
//
//   {
//     "skills/plugin-kit/testing.md": [
//       null,                                                    // fence 0: hand-written, leave alone
//       {"source": "website/snippets/lib/testing.dart",          // fence 1: rewrite from this region
//        "region": "testing-stub-inject-fake"},
//       null
//     ]
//   }
//
// The script walks each entry, finds the Nth ```dart fence in the file, and
// rewrites its body from the named docregion in the source file. .md files
// stay anchor-free; the only state in the .md is the actual code text. Run
// with --check to fail on drift instead of writing.
//
// Every weird condition is LOUD: missing source file, missing region,
// fence-count mismatch, registry referencing non-existent .md, all errors.

import { readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractRegion } from '../website/src/utils/excerpt.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REGISTRY = resolve(REPO_ROOT, 'scripts/md-excerpts.json');

function findDartFences(text) {
  const fences = [];
  const lines = text.split('\n');
  let openLine = -1;
  for (let i = 0; i < lines.length; i++) {
    if (openLine < 0) {
      if (/^```dart\s*$/.test(lines[i])) openLine = i;
    } else {
      if (/^```\s*$/.test(lines[i])) {
        fences.push({ openLine, closeLine: i });
        openLine = -1;
      }
    }
  }
  if (openLine >= 0) {
    throw new Error(`unterminated \`\`\`dart fence starting at line ${openLine + 1}`);
  }
  return fences;
}

async function processFile(mdPath, entries, sources, check) {
  const absPath = resolve(REPO_ROOT, mdPath);
  if (!existsSync(absPath)) {
    throw new Error(`registry references missing file: ${mdPath}`);
  }
  const text = await readFile(absPath, 'utf8');
  let fences;
  try {
    fences = findDartFences(text);
  } catch (e) {
    throw new Error(`${mdPath}: ${e.message}`);
  }

  if (entries.length !== fences.length) {
    throw new Error(
      `${mdPath}: registry has ${entries.length} entries but file has ${fences.length} \`\`\`dart fences. ` +
      `Update scripts/md-excerpts.json to match (null for hand-written fences).`,
    );
  }

  const lines = text.split('\n');
  const outLines = [];
  let cursor = 0;
  for (let i = 0; i < fences.length; i++) {
    const { openLine, closeLine } = fences[i];
    // Emit everything up to and including the ```dart opener
    for (; cursor <= openLine; cursor++) outLines.push(lines[cursor]);
    const entry = entries[i];
    if (entry === null) {
      // Keep body untouched
      for (; cursor < closeLine; cursor++) outLines.push(lines[cursor]);
    } else {
      if (typeof entry !== 'object' || !entry.source || !entry.region) {
        throw new Error(
          `${mdPath}[${i}]: entry must be null or {source, region}; got ${JSON.stringify(entry)}`,
        );
      }
      const sourceAbs = resolve(REPO_ROOT, entry.source);
      let sourceText = sources.get(sourceAbs);
      if (sourceText === undefined) {
        if (!existsSync(sourceAbs)) {
          throw new Error(`${mdPath}[${i}]: source file does not exist: ${entry.source}`);
        }
        sourceText = await readFile(sourceAbs, 'utf8');
        sources.set(sourceAbs, sourceText);
      }
      let slice;
      try {
        slice = extractRegion(sourceText, entry.region);
      } catch (e) {
        throw new Error(`${mdPath}[${i}]: region "${entry.region}" not found in ${entry.source}: ${e.message}`);
      }
      outLines.push(...slice.split('\n'));
      cursor = closeLine;
    }
    // Emit closing ``` line
    outLines.push(lines[cursor]);
    cursor++;
  }
  // Emit the rest
  for (; cursor < lines.length; cursor++) outLines.push(lines[cursor]);

  const next = outLines.join('\n');
  if (next === text) return false;
  if (check) {
    console.error(`stale: ${mdPath}`);
    return true;
  }
  await writeFile(absPath, next, 'utf8');
  console.log(`updated: ${mdPath}`);
  return true;
}

async function main() {
  const args = process.argv.slice(2);
  const check = args.includes('--check');

  if (!existsSync(REGISTRY)) {
    throw new Error(`registry missing: ${relative(REPO_ROOT, REGISTRY)}`);
  }
  let registry;
  try {
    registry = JSON.parse(await readFile(REGISTRY, 'utf8'));
  } catch (e) {
    throw new Error(`registry JSON parse error: ${e.message}`);
  }
  if (typeof registry !== 'object' || Array.isArray(registry)) {
    throw new Error(`registry must be a JSON object mapping md-path -> array`);
  }

  const sources = new Map();
  let stale = 0;
  for (const [mdPath, entries] of Object.entries(registry)) {
    if (!Array.isArray(entries)) {
      throw new Error(`registry[${mdPath}] must be an array; got ${typeof entries}`);
    }
    if (await processFile(mdPath, entries, sources, check)) stale++;
  }

  if (check && stale > 0) {
    console.error(`\n${stale} file(s) drifted from registry`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(`ERROR: ${e.message}`);
  process.exit(2);
});
