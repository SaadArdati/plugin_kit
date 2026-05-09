#!/usr/bin/env node
// Generates raster favicon variants from public/favicon.svg using sharp.
// Run via: npm run build-favicons
//
// Outputs:
//   public/favicon-32.png        (browser fallback)
//   public/apple-touch-icon.png  (iOS home screen, 180x180, opaque background)
//   public/og.png                (social share preview, 1200x630, opaque background)
//
// favicon.svg itself is the canonical source; modern browsers prefer it.
// PNG variants exist for legacy clients and platforms that demand raster.

import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const websiteRoot = path.resolve(here, '..');
const publicDir = path.join(websiteRoot, 'public');
const svgPath = path.join(publicDir, 'favicon.svg');

// The dark surface used elsewhere in the docs (matches the dialog's chrome)
// so opaque rasters compose visually with the rest of the site.
const DARK_BG = { r: 11, g: 11, b: 12, alpha: 1 };

async function loadSvgBuffer() {
  return readFile(svgPath);
}

async function pngFromSvg({ size, background, output, padding = 0 }) {
  const svg = await loadSvgBuffer();
  const innerSize = size - padding * 2;
  const logo = await sharp(svg)
    .resize(innerSize, innerSize, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const canvas = sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: background ?? { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: logo, gravity: 'center' }])
    .png();

  await canvas.toFile(output);
  console.log(`  ${path.relative(websiteRoot, output)}  (${size}x${size})`);
}

async function ogImage({ width, height, output }) {
  const svg = await loadSvgBuffer();
  // Logo at ~40% of the smaller dimension, centered.
  const logoSize = Math.round(Math.min(width, height) * 0.4);
  const logo = await sharp(svg)
    .resize(logoSize, logoSize, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const canvas = sharp({
    create: {
      width,
      height,
      channels: 4,
      background: DARK_BG,
    },
  })
    .composite([{ input: logo, gravity: 'center' }])
    .png();

  await canvas.toFile(output);
  console.log(`  ${path.relative(websiteRoot, output)}  (${width}x${height})`);
}

async function main() {
  console.log('build-favicons: generating raster variants from favicon.svg');

  await pngFromSvg({
    size: 32,
    background: undefined, // transparent
    output: path.join(publicDir, 'favicon-32.png'),
  });

  await pngFromSvg({
    size: 180,
    background: DARK_BG,
    padding: 18, // ~10% padding so the logo does not bleed to the rounded edges iOS adds
    output: path.join(publicDir, 'apple-touch-icon.png'),
  });

  await ogImage({
    width: 1200,
    height: 630,
    output: path.join(publicDir, 'og.png'),
  });

  console.log('build-favicons: done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
