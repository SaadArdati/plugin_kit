#!/usr/bin/env node
// Syncs `^X.Y.Z` version literals in plain Markdown files against the
// canonical pubspec.yaml inside the monorepo.
//
// Mark a managed version by trailing the line with an HTML comment:
//
//   plugin_kit: ^1.0.0  <!-- pubver:plugin_kit -->
//
// The comment is invisible in the rendered Markdown but tells this script
// to keep that `^1.0.0` in lock-step with `packages/plugin_kit/pubspec.yaml`.
//
// Default mode rewrites the .md files in place. `--check` errors on drift
// without writing. Every weird condition (missing pubspec, marker without
// version, unknown package) is a loud error with the offending file/line.

import { readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// Files this script manages. Hard-coded so adding a new managed file is a
// visible, intentional change instead of accidental discovery.
const MANAGED = [
  'README.md',
];

// `packages/<name>/pubspec.yaml` is the convention; if a package ever lives
// elsewhere, add an explicit override here.
const PACKAGE_PATHS = new Map([
  // ['custom_pkg', 'special/path/pubspec.yaml'],
]);

function pubspecPathFor(pkg) {
  const override = PACKAGE_PATHS.get(pkg);
  if (override) return resolve(REPO_ROOT, override);
  return resolve(REPO_ROOT, 'packages', pkg, 'pubspec.yaml');
}

const VERSION_RE = /^version:\s*([^\s#]+)\s*$/m;

async function loadVersion(pkg, sourceFile, lineNo) {
  const path = pubspecPathFor(pkg);
  if (!existsSync(path)) {
    throw new Error(
      `${sourceFile}:${lineNo}: marker references unknown package "${pkg}". ` +
      `Expected pubspec at ${relative(REPO_ROOT, path)}.`,
    );
  }
  const text = await readFile(path, 'utf8');
  const m = text.match(VERSION_RE);
  if (!m) {
    throw new Error(
      `${sourceFile}:${lineNo}: ${relative(REPO_ROOT, path)} has no \`version:\` line.`,
    );
  }
  return m[1];
}

// A managed line looks like
//   <prefix>^<oldVersion><suffix><!-- pubver:<pkg> --><trailing>
// Version pattern is semver-shaped: MAJOR.MINOR(.PATCH)? with optional
// `-prerelease` AND/OR `+build` suffix (e.g. 1.0.0, 0.1.0, 1.2.3-rc.1+build.2).
const SEMVER = String.raw`[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?`;
const MARKER_RE = new RegExp(
  `^(.*?\\^)(${SEMVER})(\\s*)<!--\\s*pubver:([A-Za-z0-9_]+)\\s*-->(.*)$`,
);

// A marker without a preceding `^<version>` on the same line is a config bug.
const ORPHAN_MARKER_RE = /<!--\s*pubver:([A-Za-z0-9_]+)\s*-->/;

async function planFile(mdPath) {
  const absPath = resolve(REPO_ROOT, mdPath);
  if (!existsSync(absPath)) {
    throw new Error(`managed file does not exist: ${mdPath}`);
  }
  const text = await readFile(absPath, 'utf8');
  const lines = text.split('\n');
  const outLines = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(MARKER_RE);
    if (m) {
      const [, prefix, , spacer, pkg, rest] = m;
      const version = await loadVersion(pkg, mdPath, i + 1);
      outLines.push(`${prefix}${version}${spacer}<!-- pubver:${pkg} -->${rest}`);
      continue;
    }
    // Loud-on-weird: a marker that didn't match MARKER_RE means the line is
    // shaped wrong (no `^<version>` ahead of the comment). Catch it.
    if (ORPHAN_MARKER_RE.test(line)) {
      throw new Error(
        `${mdPath}:${i + 1}: found <!-- pubver:... --> marker without a preceding \`^<version>\` on the same line.`,
      );
    }
    outLines.push(line);
  }
  return { mdPath, absPath, current: text, next: outLines.join('\n') };
}

async function main() {
  const check = process.argv.includes('--check');

  const plans = [];
  for (const f of MANAGED) {
    plans.push(await planFile(f));
  }

  let stale = 0;
  for (const plan of plans) {
    if (plan.current === plan.next) continue;
    stale++;
    if (check) {
      console.error(`stale: ${plan.mdPath}`);
      continue;
    }
    await writeFile(plan.absPath, plan.next, 'utf8');
    console.log(`updated: ${plan.mdPath}`);
  }

  if (check && stale > 0) {
    console.error(`\n${stale} file(s) drifted from pubspec versions`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(`ERROR: ${e.message}`);
  process.exit(2);
});
