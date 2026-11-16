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

// Leon is one element with three rests: the hero frame, the corner branch, the footer perch.
// Scrolling only decides which rest he belongs to. A change of rest is a timed jump along an arc,
// the same down the page and back up, and the stylesheet swings him when he lands.
// Left-hand eggs leave before they reach him.
const lerp = (a, b, k) => a + (b - a) * k, clamp = (x) => Math.min(1, Math.max(0, x)), ease = (x) => x * x * (3 - 2 * x);
const still = matchMedia('(prefers-reduced-motion: reduce)');
const jumpMs = 820, headerPx = 56;
let rest = null, jump = null, at = { x: 6, y: 60, w: 96 };

function spot(name) {
  const dock = name === 'hero' ? $('#leon-dock-hero') : name === 'foot' ? $('#leon-dock') : null;
  if (!dock) {
    const narrow = innerWidth < 640, margin = $('main .shell')?.getBoundingClientRect().left ?? 0;
    return { x: narrow ? 2 : 6, y: 60, w: narrow ? 56 : Math.min(120, Math.max(88, margin - 12)) };
  }
  const r = dock.getBoundingClientRect(), w = Math.max(0, Math.min(r.width, r.height) - 12);
  return { x: r.left + (r.width - w) / 2, y: r.top + (r.height - w) / 2, w };
}

function wanted() {
  const hero = $('#leon-dock-hero')?.getBoundingClientRect(), foot = $('#leon-dock')?.getBoundingClientRect();
  if (foot && foot.top < innerHeight - foot.height * 0.6) return 'foot';
  if (hero && hero.bottom > headerPx + hero.height * 0.55) return 'hero';
  return 'branch';
}

function tick(now) {
  const calm = still.matches, next = wanted();
  if (rest === null) rest = next;
  else if (next !== rest) { jump = calm ? null : { from: { ...at }, t0: now }; rest = next; }
  const to = spot(rest);
  let p = 1;
  if (jump) { p = clamp((now - jump.t0) / jumpMs); if (p >= 1) jump = null; }
  const from = jump ? jump.from : to, k = ease(p), arc = jump ? Math.sin(p * Math.PI) : 0;
  const lift = arc * Math.max(70, Math.hypot(to.x - from.x, to.y - from.y) * 0.22), tilt = arc * (to.x < from.x ? -14 : 14), stretch = arc * 0.1;
  at = { x: lerp(from.x, to.x, k), y: lerp(from.y, to.y, k), w: lerp(from.w, to.w, k) };
  const perch = $('#chameleon-perch'), state = jump ? 'air' : rest;
  if (perch) {
    perch.style.transform = `translate3d(${at.x.toFixed(1)}px,${(at.y - lift).toFixed(1)}px,0) rotate(${tilt.toFixed(1)}deg) scale(${(1 - stretch).toFixed(3)},${(1 + stretch).toFixed(3)})`;
    perch.style.width = `${at.w.toFixed(1)}px`;
    if (perch.dataset.rest !== state) perch.dataset.rest = state;
  }
  const leonY = at.y - lift + at.w / 2, sy = window.scrollY || document.documentElement.scrollTop || 0, drift = calm ? 0 : sy * 0.65;
  document.querySelectorAll('[data-egg]').forEach((el) => {
    const ey = Number(el.dataset.y), ex = Number(el.dataset.x), er = Number(el.dataset.r), vy = ((ey - drift) % 3120 + 3120) % 3120 - 160;
    const near = clamp((leonY + 340 - vy) / 340), away = el.dataset.egg === 'L' ? (calm ? Math.round(near) : ease(near)) : 0;
    el.setAttribute('transform', `translate(${(ex - away * 220).toFixed(1)},${vy.toFixed(1)}) rotate(${(er - away * 40).toFixed(1)})`); el.style.opacity = (0.82 * (1 - away * 0.96)).toFixed(2);
  });
  if (jump) frame();
}
let queued = false;
function frame() { if (queued) return; queued = true; requestAnimationFrame((now) => { queued = false; tick(now); }); }
['scroll', 'resize', 'load'].forEach((ev) => window.addEventListener(ev, frame, { passive: true }));
document.addEventListener('scroll', frame, { passive: true, capture: true });
tick(performance.now());

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
