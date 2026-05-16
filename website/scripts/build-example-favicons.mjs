#!/usr/bin/env node
// Generates favicon and PWA icon variants for each example/*/web/ folder
// using the canonical plugin_kit mark so installed PWAs and browser tabs
// carry the brand instead of the Flutter default.
//
// Outputs per example/{name}/web/:
//   favicon.png                  (32x32, transparent; browser tab)
//   icons/Icon-192.png           (192x192, opaque; PWA + apple-touch-icon)
//   icons/Icon-512.png           (512x512, opaque; PWA)
//   icons/Icon-maskable-192.png  (192x192, opaque; logo fits the 80% safe zone)
//   icons/Icon-maskable-512.png  (512x512, opaque; logo fits the 80% safe zone)
//
// Background color #15100A matches the docs theme-color and the mid-stop
// of the banner backdrop gradient.
//
// Run: node website/scripts/build-example-favicons.mjs

import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const assetsDir = path.join(repoRoot, 'assets');
const exampleDir = path.join(repoRoot, 'example');
const svgPath = path.join(assetsDir, 'logo.svg');

const EXAMPLES = ['state_garden', 'plugin_kit_dialog_demo', 'code_editor'];

const DARK_BG = { r: 21, g: 16, b: 10, alpha: 1 };

async function renderTransparent(size) {
  const svg = await readFile(svgPath);
  return sharp(svg, { density: 384, limitInputPixels: false })
    .resize(size, size, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();
}

async function renderOpaque({ size, paddingPct, output }) {
  const innerSize = size - Math.round(size * paddingPct) * 2;
  const svg = await readFile(svgPath);
  const logo = await sharp(svg, { density: 384, limitInputPixels: false })
    .resize(innerSize, innerSize, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();

  await sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: DARK_BG,
    },
  })
    .composite([{ input: logo, gravity: 'center' }])
    .png()
    .toFile(output);
}

async function buildOne(name) {
  const webDir = path.join(exampleDir, name, 'web');
  const iconsDir = path.join(webDir, 'icons');
  await mkdir(iconsDir, { recursive: true });

  const favBuf = await renderTransparent(32);
  await sharp(favBuf).toFile(path.join(webDir, 'favicon.png'));

  // Regular PWA icons: logo at ~70% of canvas (15% padding each side).
  await renderOpaque({ size: 192, paddingPct: 0.15, output: path.join(iconsDir, 'Icon-192.png') });
  await renderOpaque({ size: 512, paddingPct: 0.15, output: path.join(iconsDir, 'Icon-512.png') });

  // Maskable icons: logo at ~56% so the square bounding box fits within
  // the 80% diameter safe-zone circle the W3C PWA spec defines. Anything
  // outside may be cropped by rounded-mask launchers.
  await renderOpaque({ size: 192, paddingPct: 0.22, output: path.join(iconsDir, 'Icon-maskable-192.png') });
  await renderOpaque({ size: 512, paddingPct: 0.22, output: path.join(iconsDir, 'Icon-maskable-512.png') });

  console.log(`  example/${name}/web/ updated`);
}

async function main() {
  console.log('build-example-favicons: rendering brand favicons for examples');
  for (const name of EXAMPLES) {
    await buildOne(name);
  }
  console.log('build-example-favicons: done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
