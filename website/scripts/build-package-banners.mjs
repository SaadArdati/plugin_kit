#!/usr/bin/env node
// Renders per-package banners (one logo each) for use as README heros and
// per-package social previews. Uses the same backdrop and typographic
// system as build-social-banner.mjs so the brand reads as one piece, but
// shows only the package's own mark to avoid confusion on pub.dev /
// GitHub where a sister-package banner would be misleading.
//
// Outputs (under /assets/):
//   social-banner-plugin_kit-1500x500.png
//   social-banner-flutter_plugin_kit-1500x500.png
//   social-banner-plugin_kit_dialog-1500x500.png
//
// The three-logo composition stays in build-social-banner.mjs and is
// reserved for the root README, the docs site, and articles.
//
// Run: node website/scripts/build-package-banners.mjs

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const assetsDir = path.join(repoRoot, 'assets');

// haloColor tints the soft radial glow behind the logo so the warm/cool
// energy of the halo lines up with the dominant color of the mark itself.
// The wordmark color stays gold across all packages on purpose; consistent
// wordmarks signal that these are siblings in the same family.
const PACKAGES = [
  {
    name: 'plugin_kit',
    svg: 'logo.svg',
    wordmark: 'plugin_kit',
    tagline: 'A plugin runtime for Dart.',
    haloColor: '#F6C800',
  },
  {
    name: 'flutter_plugin_kit',
    svg: 'flutter_plugin_kit.svg',
    wordmark: 'flutter_plugin_kit',
    tagline: 'Flutter ergonomics for plugin_kit.',
    haloColor: '#16B9FD',
  },
  {
    name: 'plugin_kit_dialog',
    svg: 'plugin_kit_dialog.svg',
    wordmark: 'plugin_kit_dialog',
    tagline: 'A live customization dialog for plugin_kit.',
    haloColor: '#F6C800',
  },
];

const W = 1500;
const H = 500;

async function renderLogo(svgPath, size) {
  const svg = await readFile(svgPath);
  return sharp(svg, { density: 384, limitInputPixels: false })
    .resize(size, size, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();
}

function backplateSvg(w, h, haloColor) {
  return `<svg width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="bg" cx="50%" cy="50%" r="78%">
      <stop offset="0%" stop-color="#2A1F14"/>
      <stop offset="55%" stop-color="#15100A"/>
      <stop offset="100%" stop-color="#080603"/>
    </radialGradient>
    <radialGradient id="halo" cx="50%" cy="50%" r="38%">
      <stop offset="0%" stop-color="${haloColor}" stop-opacity="0.22"/>
      <stop offset="45%" stop-color="${haloColor}" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="${haloColor}" stop-opacity="0"/>
    </radialGradient>
    <pattern id="grid" x="0" y="0" width="48" height="48" patternUnits="userSpaceOnUse">
      <path d="M48 0 L0 0 0 48" fill="none" stroke="#F6C800" stroke-opacity="0.025" stroke-width="1"/>
    </pattern>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <rect width="${w}" height="${h}" fill="url(#grid)"/>
  <rect width="${w}" height="${h}" fill="url(#halo)"/>
</svg>`;
}

function textOverlaySvg(w, h, wordmark, tagline) {
  const monoStack = "'JetBrains Mono','SF Mono','Menlo','Consolas',monospace";
  const sansStack = "'Inter','Helvetica Neue','Arial',sans-serif";

  // Logo occupies the upper portion; text block sits below.
  const cx = w / 2;
  const wordmarkBaseline = Math.round(h * 0.80);
  const wordmarkSize = Math.round(h * 0.072);
  const wordmarkLetterSpacing = Math.round(wordmarkSize * 0.16);

  const taglineBaseline = wordmarkBaseline + Math.round(h * 0.072);
  const taglineSize = Math.round(h * 0.040);
  const taglineLetterSpacing = Math.round(taglineSize * 0.10);

  return `<svg width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg">
  <text x="${cx}" y="${wordmarkBaseline}" text-anchor="middle"
        font-family="${monoStack}" font-size="${wordmarkSize}" font-weight="500"
        letter-spacing="${wordmarkLetterSpacing}" fill="#F6C800" fill-opacity="0.92">${wordmark}</text>
  <text x="${cx}" y="${taglineBaseline}" text-anchor="middle"
        font-family="${sansStack}" font-size="${taglineSize}" font-weight="400"
        letter-spacing="${taglineLetterSpacing}" fill="#E6D8B0" fill-opacity="0.62">${tagline}</text>
</svg>`;
}

async function buildOne(pkg) {
  // Logo sized as ~62% of banner height, vertically biased toward the top
  // so the wordmark+tagline block sits comfortably below.
  const logoSize = Math.round(H * 0.62);
  const logoX = Math.round((W - logoSize) / 2);
  const logoY = Math.round(H * 0.05);

  const [bg, logo] = await Promise.all([
    sharp(Buffer.from(backplateSvg(W, H, pkg.haloColor))).png().toBuffer(),
    renderLogo(path.join(assetsDir, pkg.svg), logoSize),
  ]);

  const overlay = textOverlaySvg(W, H, pkg.wordmark, pkg.tagline);

  const outPath = path.join(assetsDir, `social-banner-${pkg.name}-${W}x${H}.png`);
  await sharp(bg)
    .composite([
      { input: logo, left: logoX, top: logoY },
      { input: Buffer.from(overlay), left: 0, top: 0 },
    ])
    .png({ compressionLevel: 9 })
    .toFile(outPath);
  console.log(`  ${path.relative(repoRoot, outPath)}  (${W}x${H}, ${pkg.name})`);
}

async function main() {
  console.log('build-package-banners: rendering per-package banners');
  for (const pkg of PACKAGES) {
    await buildOne(pkg);
  }
  console.log('build-package-banners: done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
