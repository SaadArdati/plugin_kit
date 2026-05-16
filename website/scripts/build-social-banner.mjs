#!/usr/bin/env node
// Renders the shared plugin_kit social banner used for:
//   - Medium article hero (uploads at 1500x750; Medium scales down to 700px
//     content width while preserving aspect, and center-crops a 112x112
//     thumbnail for listings)
//   - Open Graph / Twitter card (1200x630, served from website/public/og.png)
//   - Docs site SEO preview (same og.png file)
//
// Composition keeps the canonical all-yellow plugin_kit mark dead center
// and larger, flanked by the cyan flutter_plugin_kit mark and the mixed
// plugin_kit_dialog mark. Backdrop is warm charcoal with a soft amber
// halo and a barely-visible 48px grid. Center-anchoring means the 112px
// square thumbnail Medium generates shows the canonical mark cleanly.
//
// Outputs:
//   /assets/social-banner-1500x750-{logos,wordmark,tagline}.png
//   /assets/social-banner-1200x630-{logos,wordmark,tagline}.png
//   /website/public/og.png         (copy of 1200x630-tagline)
//
// Run: node website/scripts/build-social-banner.mjs

import { readFile, copyFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const assetsDir = path.join(repoRoot, 'assets');
const websitePublic = path.join(repoRoot, 'website', 'public');

const LOGO_PATHS = {
  flutter: path.join(assetsDir, 'flutter_plugin_kit.svg'),
  main: path.join(assetsDir, 'logo.svg'),
  dialog: path.join(assetsDir, 'plugin_kit_dialog.svg'),
};

const SIZES = [
  { w: 1500, h: 750 },
  { w: 1200, h: 630 },
];

const VARIANTS = ['logos', 'wordmark', 'tagline'];

// The variant whose 1200x630 render is copied to website/public/og.png.
const OG_VARIANT = 'tagline';

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

function backplateSvg(W, H) {
  return `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="bg" cx="50%" cy="50%" r="78%">
      <stop offset="0%" stop-color="#2A1F14"/>
      <stop offset="55%" stop-color="#15100A"/>
      <stop offset="100%" stop-color="#080603"/>
    </radialGradient>
    <radialGradient id="halo" cx="50%" cy="50%" r="38%">
      <stop offset="0%" stop-color="#F6C800" stop-opacity="0.22"/>
      <stop offset="45%" stop-color="#F6C800" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="#F6C800" stop-opacity="0"/>
    </radialGradient>
    <pattern id="grid" x="0" y="0" width="48" height="48" patternUnits="userSpaceOnUse">
      <path d="M48 0 L0 0 0 48" fill="none" stroke="#F6C800" stroke-opacity="0.025" stroke-width="1"/>
    </pattern>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <rect width="${W}" height="${H}" fill="url(#grid)"/>
  <rect width="${W}" height="${H}" fill="url(#halo)"/>
</svg>`;
}

function textOverlaySvg(W, H, variant) {
  if (variant === 'logos') return null;

  const monoStack = "'JetBrains Mono','SF Mono','Menlo','Consolas',monospace";
  const sansStack = "'Inter','Helvetica Neue','Arial',sans-serif";

  // Position text below the center logo. Center logo occupies ~60% of H,
  // vertically centered; its bottom edge is at H/2 + 0.30*H. Place the
  // wordmark baseline a touch under that.
  const cx = W / 2;
  const baseline = Math.round(H / 2 + H * 0.30 + H * 0.075);

  const wordmarkSize = Math.round(H * 0.052);
  const wordmarkLetterSpacing = Math.round(wordmarkSize * 0.18);
  const wordmark = `<text x="${cx}" y="${baseline}" text-anchor="middle"
    font-family="${monoStack}" font-size="${wordmarkSize}" font-weight="500"
    letter-spacing="${wordmarkLetterSpacing}" fill="#F6C800" fill-opacity="0.92">plugin_kit</text>`;

  if (variant === 'wordmark') {
    return `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${wordmark}</svg>`;
  }

  const taglineY = baseline + Math.round(H * 0.052);
  const taglineSize = Math.round(H * 0.028);
  const taglineLetterSpacing = Math.round(taglineSize * 0.12);
  const tagline = `<text x="${cx}" y="${taglineY}" text-anchor="middle"
    font-family="${sansStack}" font-size="${taglineSize}" font-weight="400"
    letter-spacing="${taglineLetterSpacing}" fill="#E6D8B0" fill-opacity="0.62">A plugin runtime for Dart.</text>`;

  return `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${wordmark}${tagline}</svg>`;
}

async function buildOne({ w, h, variant }) {
  const centerSize = Math.round(h * 0.60);
  const sideSize = Math.round(h * 0.38);

  const cx = w / 2;
  const sidePad = Math.round(w * 0.035);
  const sideOffset = Math.round(centerSize / 2 + sideSize / 2 + sidePad);

  const centerY = Math.round((h - centerSize) / 2);
  const sideY = Math.round((h - sideSize) / 2);

  const centerX = Math.round(cx - centerSize / 2);
  const leftX = Math.round(cx - sideOffset - sideSize / 2);
  const rightX = Math.round(cx + sideOffset - sideSize / 2);

  const [bg, leftLogo, centerLogo, rightLogo] = await Promise.all([
    sharp(Buffer.from(backplateSvg(w, h))).png().toBuffer(),
    renderLogo(LOGO_PATHS.flutter, sideSize),
    renderLogo(LOGO_PATHS.main, centerSize),
    renderLogo(LOGO_PATHS.dialog, sideSize),
  ]);

  const composites = [
    { input: leftLogo, left: leftX, top: sideY },
    { input: rightLogo, left: rightX, top: sideY },
    { input: centerLogo, left: centerX, top: centerY },
  ];

  const overlay = textOverlaySvg(w, h, variant);
  if (overlay) {
    composites.push({
      input: Buffer.from(overlay),
      left: 0,
      top: 0,
    });
  }

  const outPath = path.join(assetsDir, `social-banner-${w}x${h}-${variant}.png`);
  await sharp(bg)
    .composite(composites)
    .png({ compressionLevel: 9 })
    .toFile(outPath);
  console.log(`  ${path.relative(repoRoot, outPath)}  (${w}x${h}, ${variant})`);
  return outPath;
}

async function main() {
  console.log('build-social-banner: rendering plugin_kit social banners');
  const byKey = new Map();
  for (const { w, h } of SIZES) {
    for (const variant of VARIANTS) {
      const out = await buildOne({ w, h, variant });
      byKey.set(`${w}x${h}-${variant}`, out);
    }
  }

  const ogSource = byKey.get(`1200x630-${OG_VARIANT}`);
  const ogDest = path.join(websitePublic, 'og.png');
  await copyFile(ogSource, ogDest);
  console.log(`  ${path.relative(repoRoot, ogDest)}  (copied from 1200x630-${OG_VARIANT})`);

  console.log('build-social-banner: done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
