// DOM bridge for aslang.dev. Every decision on the page is ASL compiled into /site.wasm:
// this file loads the module, forwards clicks on [data-msg] to its update export and applies
// the operations it prints, one ASN form per line: (:attr sel name value) (:text sel s)
// (:swap sel html) (:copy s) (:store key value) (:after ms msg).
const dec = new TextDecoder();
let wasm, out = '', model = 0n;
class Exit { constructor(code) { this.code = code; } }

const cString = (ptr) => {
  const bytes = new Uint8Array(wasm.memory.buffer, ptr);
  return dec.decode(bytes.subarray(0, bytes.indexOf(0)));
};

const imports = { asl: {
  write: (fd, ptr, len) => {
    const s = dec.decode(new Uint8Array(wasm.memory.buffer, ptr, Number(len)));
    if (fd === 1) out += s; else console.error(s);
    return len;
  },
  exit: (code) => { throw new Exit(code); },
  nowNs: () => BigInt(Math.round(performance.now() * 1e6)),
  trap: (code, msg, len) => {
    throw new Error(`${cString(code)}: ${dec.decode(new Uint8Array(wasm.memory.buffer, msg, len))}`);
  },
}};

const $ = (sel) => document.querySelector(sel);
const ops = {
  attr: (sel, name, value) => $(sel)?.setAttribute(name, value),
  text: (sel, s) => { const el = $(sel); if (el) el.textContent = s; },
  swap: (sel, html) => { const el = $(sel); if (el) el.innerHTML = html; },
  copy: (s) => navigator.clipboard?.writeText(s),
  store: (key, value) => { try { localStorage.setItem(`asl.${key}`, value); } catch {} },
  after: (ms, msg) => setTimeout(() => send(msg), ms),
};

const field = /"((?:[^"\\]|\\.)*)"|(-?\d+)|:([a-z]+)/g;
const unquote = (s) => s.replace(/\\(.)/g, (_, c) => (c === 'n' ? '\n' : c));

function apply(text) {
  for (const line of text.split('\n')) {
    const [op, ...args] = [...line.matchAll(field)].map((m) =>
      m[1] !== undefined ? unquote(m[1]) : m[2] !== undefined ? Number(m[2]) : m[3]);
    if (op) ops[op]?.(...args);
  }
}

function run(f) {
  out = ''; let result;
  try { result = f(); } catch (e) { if (!(e instanceof Exit)) throw e; }
  apply(out); return result;
}
function send(code) { model = run(() => wasm.update(BigInt(code), model)); }

function environment() {
  let stored = null;
  try { stored = localStorage.getItem('asl.theme'); } catch {}
  const light = stored ? stored === 'light' : matchMedia('(prefers-color-scheme: light)').matches;
  return BigInt((light ? 1 : 0) + (stored ? 2 : 0));
}

// Leon is one element with three rests: the hero frame, the corner branch, the footer frame.
// Scroll moves him between them and curls his tail; left-hand eggs leave before they reach him.
const lerp = (a, b, k) => a + (b - a) * k, clamp = (x) => Math.min(1, Math.max(0, x)), ease = (x) => x * x * (3 - 2 * x);
const still = matchMedia('(prefers-reduced-motion: reduce)');
const numbers = (s) => s.match(/-?\d+(\.\d+)?/g).map(Number);
const tailPath = (open, curled, k) => {
  const n = open.map((v, i) => lerp(v, curled[i], k).toFixed(1));
  let d = `M${n[0]} ${n[1]}`;
  for (let i = 2; i < n.length; i += 6) d += `C${n.slice(i, i + 6).join(' ')}`;
  return d;
};

function onScroll() {
  const calm = still.matches, step = (x) => (calm ? Math.round(x) : ease(x)), sway = calm ? 0 : 1;
  const vh = innerHeight, sy = window.scrollY || 0, narrow = innerWidth < 640;
  const hero = $('#leon-dock-hero')?.getBoundingClientRect(), foot = $('#leon-dock')?.getBoundingClientRect(), fifth = $('#rules')?.getBoundingClientRect();
  const margin = $('main .shell')?.getBoundingClientRect().left ?? 0;
  const bw = narrow ? 64 : Math.min(150, Math.max(104, margin - 8)), bx = narrow ? 2 : 6, by = 60;
  const t1 = hero ? clamp(sy / 320) : 1, e1 = step(t1);
  const aw = hero ? Math.max(0, Math.min(300, hero.width - 24)) : bw, ax = hero ? hero.left + (hero.width - aw) / 2 : bx, ay = hero ? hero.top + (hero.height - aw) / 2 : by;
  let t2 = 0, cw = bw, cx = bx, cy = by;
  if (foot) {
    cw = Math.min(170, foot.width - 16); cx = foot.left + (foot.width - cw) / 2; cy = foot.top + (foot.height - cw) / 2;
    const gone = fifth ? vh * 0.5 - fifth.top : vh * 1.5 - foot.top, left = Math.max(0, foot.bottom + 16 - vh);
    t2 = gone > 0 ? gone / (gone + left) : 0;
  }
  const e2 = step(t2), across = step(clamp((t2 - 0.7) / 0.3)), x = lerp(lerp(ax, bx, e1), cx, across), y = lerp(lerp(ay, by, e1), cy, e2) - Math.sin(t1 * Math.PI) * 24 * sway, w = lerp(lerp(aw, bw, e1), cw, e2);
  const curl = e1 * (1 - 0.55 * Math.sin(t2 * Math.PI) * sway), tilt = (Math.sin(t1 * Math.PI) * -6 + Math.sin(t2 * Math.PI) * 8) * sway;
  const perch = $('#chameleon-perch');
  if (perch) { perch.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,0) rotate(${tilt.toFixed(1)}deg)`; perch.style.width = `${w.toFixed(1)}px`; }
  document.querySelectorAll('.leon-tail path').forEach((el) => {
    el.open ??= numbers(el.dataset.open); el.curled ??= numbers(el.dataset.curl);
    el.setAttribute('d', tailPath(el.open, el.curled, curl));
  });
  const leonY = y + w / 2, drift = sy * 0.65 * sway;
  document.querySelectorAll('[data-egg]').forEach((el) => {
    const ey = Number(el.dataset.y), ex = Number(el.dataset.x), er = Number(el.dataset.r), vy = ((ey - drift) % 3120 + 3120) % 3120 - 160;
    const away = el.dataset.egg === 'L' ? step(clamp((leonY + 340 - vy) / 340)) : 0;
    el.setAttribute('transform', `translate(${(ex - away * 220).toFixed(1)},${vy.toFixed(1)}) rotate(${(er - away * 40).toFixed(1)})`); el.style.opacity = (0.82 * (1 - away * 0.96)).toFixed(2);
  });
}
let queued = false;
const frame = () => { if (queued) return; queued = true; requestAnimationFrame(() => { queued = false; onScroll(); }); };
['scroll', 'resize'].forEach((ev) => window.addEventListener(ev, frame, { passive: true })); onScroll();

const source = fetch('/site.wasm');
const { instance } = await (WebAssembly.instantiateStreaming
  ? WebAssembly.instantiateStreaming(source, imports)
  : source.then((r) => r.arrayBuffer()).then((b) => WebAssembly.instantiate(b, imports)));
wasm = instance.exports;
run(() => wasm._start());
const timed = () => { const t0 = performance.now(), b = wasm.render(); return [BigInt(Math.round((performance.now() - t0) * 1e6)), b]; };
const [cold] = timed(), [warm, bytes] = timed();
run(() => wasm.measured(cold, warm, bytes));
model = environment(); send(1);
document.addEventListener('click', (e) => { const t = e.target.closest('[data-msg]'); if (t) send(Number(t.dataset.msg)); });
