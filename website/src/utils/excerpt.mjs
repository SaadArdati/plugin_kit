// Extracts a `// #docregion <name>` ... `// #enddocregion <name>` slice from
// a Dart source string. Mirrors the Dart team's code_excerpter convention.
//
// Throws if the region is missing or malformed; the build should fail loud
// rather than render an empty block.

/**
 * @param {string} source
 * @param {string} name
 * @returns {string}
 */
export function extractRegion(source, name) {
  const start = `// #docregion ${name}`;
  const end = `// #enddocregion ${name}`;

  const lines = source.split('\n');
  const startIdx = lines.findIndex((l) => l.trim() === start);
  if (startIdx === -1) {
    throw new Error(`extractRegion: missing '${start}'`);
  }
  const endIdx = lines.findIndex(
    (l, i) => i > startIdx && l.trim() === end,
  );
  if (endIdx === -1) {
    throw new Error(`extractRegion: missing '${end}' after line ${startIdx + 1}`);
  }

  const body = lines.slice(startIdx + 1, endIdx);
  return dedent(body).join('\n');
}

/**
 * @param {string[]} lines
 * @returns {string[]}
 */
function dedent(lines) {
  const indents = lines
    .filter((l) => l.trim().length > 0)
    .map((l) => l.match(/^[ \t]*/)[0].length);
  if (indents.length === 0) return lines;
  const min = Math.min(...indents);
  return lines.map((l) => l.slice(min));
}
