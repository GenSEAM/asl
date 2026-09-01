import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// The palette lives in one file; this asserts every pairing the components can produce from it.
const here = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(join(here, '..', 'src', 'index.css'), 'utf8');

const block = (sel) => {
  const m = css.match(new RegExp(`${sel}\\s*\\{([\\s\\S]*?)\\n\\s*\\}`));
  if (!m) throw new Error(`index.css has no \`${sel}\` block — the theme selector was renamed.`);
  const out = {};
  for (const [, k, v] of m[1].matchAll(/--([a-z0-9-]+):\s*([\d\s]+);/g)) out[k] = v.trim().split(/\s+/).map(Number);
  return out;
};
const lum = (c) => {
  const [r, g, b] = c.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

// Every foreground/background pairing the components actually produce.
const pairs = [
  ['ink', 'ground', 4.5], ['ink', 'surface', 4.5], ['ink', 'sunken', 4.5], ['ink', 'inset', 4.5],
  ['ink-2', 'ground', 4.5], ['ink-2', 'surface', 4.5], ['ink-2', 'sunken', 4.5], ['ink-2', 'inset', 4.5],
  ['ink-3', 'ground', 4.5], ['ink-3', 'surface', 4.5], ['ink-3', 'sunken', 4.5], ['ink-3', 'inset', 4.5],
  ['signal', 'ground', 4.5], ['signal', 'surface', 4.5], ['signal', 'sunken', 4.5], ['signal', 'inset', 4.5],
  ['line-strong', 'ground', 3], ['line', 'surface', 1.2],
  // The two filled call-to-action pills invert the palette: ground-coloured text on a solid fill.
  ['ground', 'ink', 4.5], ['ground', 'signal', 4.5],
];
// Layer separation: how far a surface sits above its ground.
const layers = [['surface', 'ground'], ['inset', 'surface'], ['ground', 'sunken']];

let bad = 0;
for (const [name, sel] of [['light', ':root'], ['dark', '\\.dark']]) {
  const t = block(sel);
  console.log(`\n== ${name} ==`);
  for (const [fg, bg, need] of pairs) {
    for (const k of [fg, bg]) if (!t[k]) throw new Error(`\`${sel}\` defines no --${k}`);
    const r = ratio(t[fg], t[bg]);
    const ok = r >= need;
    if (!ok) bad++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${fg.padEnd(12)} on ${bg.padEnd(8)} ${r.toFixed(2)} (need ${need})`);
  }
  const lstar = (c) => { const y = lum(c); return y > 0.008856 ? 116 * Math.cbrt(y) - 16 : 903.3 * y; };
  for (const [a, b] of layers) {
    const d = lstar(t[a]) - lstar(t[b]);
    console.log(`     ΔL* ${a} over ${b}: ${d.toFixed(1)}  (contrast ${ratio(t[a], t[b]).toFixed(2)}:1)`);
  }
}
console.log(`\n${bad} failing pairings`);
process.exit(bad === 0 ? 0 : 1);
