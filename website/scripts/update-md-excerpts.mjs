#!/usr/bin/env node
// Updates code excerpts in plain Markdown files.
//
// Walks every .md file passed as argument (or every README.md / CHANGELOG.md
// under packages/* if no args), finds anchors of the shape
//
//   <!-- code-excerpt "path/from/repo/root.dart (region-name)" -->
//   ```dart
//   ...will be rewritten...
//   ```
//
// and replaces the code block body with the named docregion from the source
// file. Run with --check to fail on any pending change instead of writing.

import { readFile, writeFile } from 'node:fs/promises';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractRegion } from '../src/utils/excerpt.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const ANCHOR = /<!--\s*code-excerpt\s+"([^"\s]+)\s*\(([^)]+)\)"\s*-->\s*\n```(\w+)?\n([\s\S]*?)\n```/g;

async function processFile(path, check) {
  const original = await readFile(path, 'utf8');
  let changed = false;
  const next = original.replace(
    ANCHOR,
    (match, file, region, lang, _body) => {
      const sourcePath = resolve(REPO_ROOT, file);
      // synchronous read inside replace: load all sources up front in the
      // outer pass to keep it pure-string.
      const source = sources.get(sourcePath);
      if (!source) {
        throw new Error(
          `${path}: anchor references missing source ${file}`,
        );
      }
      const slice = extractRegion(source, region);
      const rebuilt = `<!-- code-excerpt "${file} (${region})" -->\n\`\`\`${lang ?? ''}\n${slice}\n\`\`\``;
      if (rebuilt !== match) changed = true;
      return rebuilt;
    },
  );

  if (!changed) return false;
  if (check) {
    console.error(`stale: ${relative(REPO_ROOT, path)}`);
    return true;
  }
  await writeFile(path, next, 'utf8');
  console.log(`updated: ${relative(REPO_ROOT, path)}`);
  return true;
}

// Two-pass to keep replace() purely synchronous: gather every source path
// referenced by any anchor in any input file, load them, then run the
// rewrite.
const sources = new Map();

async function loadSourcesForFiles(files) {
  for (const f of files) {
    const original = await readFile(f, 'utf8');
    for (const m of original.matchAll(/<!--\s*code-excerpt\s+"([^"\s]+)\s*\(/g)) {
      const sourcePath = resolve(REPO_ROOT, m[1]);
      if (!sources.has(sourcePath)) {
        sources.set(sourcePath, await readFile(sourcePath, 'utf8'));
      }
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const check = args.includes('--check');
  const files = args.filter((a) => !a.startsWith('--'));
  if (files.length === 0) {
    console.error('usage: update-md-excerpts.mjs [--check] <file.md> ...');
    process.exit(2);
  }

  await loadSourcesForFiles(files);

  let stale = 0;
  for (const f of files) {
    if (await processFile(f, check)) stale++;
  }

  if (check && stale > 0) {
    console.error(`\n${stale} file(s) need re-running without --check`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
