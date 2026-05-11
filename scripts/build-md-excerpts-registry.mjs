#!/usr/bin/env node
// One-shot migration: walks the .md files passed as args, parses every
// existing `<!-- code-excerpt "path (region)" -->` anchor, builds the
// central registry at scripts/md-excerpts.json, and strips the anchors
// from the .md files. After this runs, .md files contain no anchor
// artifacts and the registry holds every mapping indexed by dart-fence
// position. Fences without prior anchors get null (= hand-written).

import { readFile, writeFile } from 'node:fs/promises';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REGISTRY = resolve(REPO_ROOT, 'scripts/md-excerpts.json');

const ANCHOR_RE = /^<!--\s*code-excerpt\s+"([^"\s]+)\s*\(([^)]+)\)"\s*-->\s*$/;

function migrateFile(text, mdPath) {
  const lines = text.split('\n');
  const outLines = [];
  const entries = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^```dart\s*$/.test(line)) {
      // Look back for anchor (skip blank lines? no - anchor must be the immediate prev line)
      const prev = outLines.length > 0 ? outLines[outLines.length - 1] : '';
      const m = prev.match(ANCHOR_RE);
      if (m) {
        // Strip the anchor from outLines
        outLines.pop();
        // Also strip a trailing blank line if it exists, to avoid double blanks
        // ... actually no, preserve structure. Just remove the anchor line.
        entries.push({ source: m[1], region: m[2] });
      } else {
        entries.push(null);
      }
      // Emit the fence opener through closer unchanged
      const fenceStart = i;
      outLines.push(line);
      i++;
      let closed = false;
      while (i < lines.length) {
        outLines.push(lines[i]);
        if (/^```\s*$/.test(lines[i])) {
          i++;
          closed = true;
          break;
        }
        i++;
      }
      if (!closed) {
        throw new Error(
          `${mdPath}: unterminated \`\`\`dart fence opened at line ${fenceStart + 1}`,
        );
      }
      continue;
    }
    outLines.push(line);
    i++;
  }
  return { text: outLines.join('\n'), entries };
}

async function main() {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('usage: build-md-excerpts-registry.mjs <file.md> ...');
    process.exit(2);
  }

  const registry = {};
  for (const f of files) {
    const abs = resolve(REPO_ROOT, f);
    const original = await readFile(abs, 'utf8');
    const { text, entries } = migrateFile(original, f);
    registry[f] = entries;
    if (text !== original) {
      await writeFile(abs, text, 'utf8');
      console.log(`stripped anchors: ${f}`);
    }
    const anchored = entries.filter((e) => e !== null).length;
    console.log(`  ${f}: ${entries.length} dart fences (${anchored} anchored, ${entries.length - anchored} hand-written)`);
  }

  await writeFile(REGISTRY, JSON.stringify(registry, null, 2) + '\n', 'utf8');
  console.log(`\nwrote registry: ${relative(REPO_ROOT, REGISTRY)}`);
}

main().catch((e) => {
  console.error(`ERROR: ${e.message}`);
  process.exit(2);
});
