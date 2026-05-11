#!/usr/bin/env node
// Generates raster PNG variants for each per-package logo SVG in /assets/.
// Run via: npm run build-package-logos
//
// Output for each entry in SOURCES:
//   /assets/<name>-256.png
//   /assets/<name>-512.png
//
// Per-package READMEs (rendered on pub.dev and GitHub) reference the 256
// variant via raw.githubusercontent.com because relative paths inside
// pub-rendered READMEs are not reliably resolved (dart-lang/pub-dev#5068).
// 512 is kept around as a higher-DPI source.
//
// /assets/logo.{svg,256,512.png} is the canonical plugin_kit mark and is
// intentionally not regenerated here; add it to SOURCES only if you also
// want this script to overwrite it.

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const assetsDir = path.join(repoRoot, 'assets');

const SOURCES = [
  { svg: 'flutter_plugin_kit.svg' },
  { svg: 'plugin_kit_dialog.svg' },
];

const SIZES = [256, 512];

async function renderPng(svgBuffer, size, output) {
  await sharp(svgBuffer, { density: 384 })
    .resize(size, size, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png({ compressionLevel: 9 })
    .toFile(output);
  console.log(`  ${path.relative(repoRoot, output)}  (${size}x${size})`);
}

async function main() {
  console.log('build-package-logos: rendering PNG variants from /assets/*.svg');

  for (const { svg } of SOURCES) {
    const stem = svg.replace(/\.svg$/, '');
    const svgBuffer = await readFile(path.join(assetsDir, svg));
    for (const size of SIZES) {
      const output = path.join(assetsDir, `${stem}-${size}.png`);
      await renderPng(svgBuffer, size, output);
    }
  }

  console.log('build-package-logos: done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
