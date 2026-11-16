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
// Scrolling only decides which rest he belongs to. He travels by his own tail: it uncurls toward the
// hook on the liana and coils there as he comes up, or uncoils to lower him and then lets go.
// The stylesheet swings him when he lands. Left-hand eggs leave before they reach him.
const lerp = (a, b, k) => a + (b - a) * k, clamp = (x) => Math.min(1, Math.max(0, x)), ease = (x) => x * x * (3 - 2 * x);
const still = matchMedia('(prefers-reduced-motion: reduce)');
const travelMs = 2200, reachPart = 0.22, holdPart = 0.8, headerPx = 56;
let rest = null, move = null, at = { x: 6, y: 60, w: 96 };

function spot(name) {
  const dock = name === 'hero' ? $('#leon-dock-hero') : name === 'foot' ? $('#leon-dock') : null;
  if (!dock) {
    const narrow = innerWidth < 640, margin = $('main .shell')?.getBoundingClientRect().left ?? 0;
    return { x: narrow ? 2 : 6, y: 60, w: narrow ? 56 : Math.min(120, Math.max(88, margin - 12)) };
  }
  const r = dock.getBoundingClientRect(), w = Math.max(0, Math.min(r.width, r.height) - 12);
  return { x: r.left + (r.width - w) / 2, y: r.top + (r.height - w) / 2, w };
}

// The rig: while Leon travels his artwork is redrawn on a canvas, body first, then his own tail as a
// strip mesh bent along its traced centreline. The part of the tail between him and the hook on the
// liana runs straight; the rest stays coiled, so the coil winds at the hook as he comes closer.
const rig = { ready: false, cut: 2 };
function rigLoad() {
  const canvas = $('#leon-rig'), perch = $('#chameleon-perch');
  if (!canvas || !perch || still.matches) return;
  const pts = canvas.dataset.tail.split(';').map((p) => p.split(',').map((n) => Number(n) / 1000));
  const edge = (i) => {
    const a = pts[Math.max(i - 1, 0)], b = pts[Math.min(i + 1, pts.length - 1)], n = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    const nx = -(b[1] - a[1]) / n, ny = (b[0] - a[0]) / n, h = pts[i][2] + 0.005;
    return [pts[i][0] - nx * h, pts[i][1] - ny * h, pts[i][0] + nx * h, pts[i][1] + ny * h, h];
  };
  rig.edges = pts.map((_, i) => edge(i));
  rig.segs = pts.slice(1).map((p, i) => ({ len: Math.hypot(p[0] - pts[i][0], p[1] - pts[i][1]), dir: Math.atan2(p[1] - pts[i][1], p[0] - pts[i][0]) }));
  rig.pts = pts; rig.length = rig.segs.slice(rig.cut).reduce((sum, s) => sum + s.len, 0);
  const load = (src) => new Promise((ok, bad) => { const im = new Image(); im.onload = () => ok(im); im.onerror = bad; im.src = src; });
  Promise.all([load(canvas.dataset.body), load(canvas.dataset.art)]).then(([body, art]) => {
    rig.body = body; rig.art = art; rig.canvas = canvas; rig.ctx = canvas.getContext('2d'); rig.ready = true; perch.dataset.rig = 'on';
  }).catch(() => {});
}
const turn = (a) => Math.atan2(Math.sin(a), Math.cos(a));
function triangle(ctx, img, w, s, d) {
  const den = (s[0] - s[4]) * (s[3] - s[5]) - (s[2] - s[4]) * (s[1] - s[5]);
  if (Math.abs(den) < 1e-9) return;
  const a = ((d[0] - d[4]) * (s[3] - s[5]) - (d[2] - d[4]) * (s[1] - s[5])) / den, c = ((s[0] - s[4]) * (d[2] - d[4]) - (s[2] - s[4]) * (d[0] - d[4])) / den;
  const b = ((d[1] - d[5]) * (s[3] - s[5]) - (d[3] - d[5]) * (s[1] - s[5])) / den, e = ((s[0] - s[4]) * (d[3] - d[5]) - (s[2] - s[4]) * (d[1] - d[5])) / den;
  const mx = (d[0] + d[2] + d[4]) / 3, my = (d[1] + d[3] + d[5]) / 3, out = (x, m) => x + Math.sign(x - m) * 0.7;
  ctx.save(); ctx.beginPath(); ctx.moveTo(out(d[0], mx), out(d[1], my)); ctx.lineTo(out(d[2], mx), out(d[3], my)); ctx.lineTo(out(d[4], mx), out(d[5], my)); ctx.closePath(); ctx.clip();
  ctx.transform(a, b, c, e, d[4] - a * s[4] - c * s[5], d[5] - b * s[4] - e * s[5]); ctx.drawImage(img, 0, 0, w, w); ctx.restore();
}
function rigDraw(w, hookX, hookY, reach) {
  const { ctx, canvas, pts, segs, edges, cut } = rig, dpr = Math.min(2, window.devicePixelRatio || 1), px = Math.round(3 * w * dpr);
  if (canvas.width !== px) { canvas.width = px; canvas.height = px; }
  ctx.setTransform(dpr, 0, 0, dpr, w * dpr, w * dpr); ctx.clearRect(-w, -w, 3 * w, 3 * w); ctx.drawImage(rig.body, 0, 0, w, w);
  const rootX = pts[cut][0] * w, rootY = pts[cut][1] * w, gap = Math.hypot(hookX - rootX, hookY - rootY), total = rig.length * w;
  const straight = reach * Math.min(gap, total * 0.8), soft = total * 0.1, lead = 8, aim = Math.atan2(hookY - rootY, hookX - rootX);
  const curlAt = (run) => { const k = clamp((run - straight) / soft + 0.5); return k * k * (3 - 2 * k); };
  let run = 0, bent = segs[cut].dir;
  for (let i = cut + 1; i < cut + lead; i++) { bent += turn(segs[i].dir - segs[i - 1].dir) * curlAt(run); run += segs[i - 1].len * w; }
  const steer = turn(aim - bent) * clamp(straight / (total * 0.2)) / lead;
  let x = rootX, y = rootY, dir = segs[cut].dir + steer, prev = null; run = 0;
  for (let i = cut; i < segs.length; i++) {
    const h0 = edges[i][4] * w, h1 = edges[i + 1][4] * w, nx = -Math.sin(dir), ny = Math.cos(dir);
    const x1 = x + Math.cos(dir) * segs[i].len * w, y1 = y + Math.sin(dir) * segs[i].len * w;
    const near = prev || [x - nx * h0, y - ny * h0, x + nx * h0, y + ny * h0], far = [x1 - nx * h1, y1 - ny * h1, x1 + nx * h1, y1 + ny * h1];
    const s0 = edges[i], s1 = edges[i + 1];
    triangle(ctx, rig.art, w, [s0[0] * w, s0[1] * w, s0[2] * w, s0[3] * w, s1[2] * w, s1[3] * w], [near[0], near[1], near[2], near[3], far[2], far[3]]);
    triangle(ctx, rig.art, w, [s0[0] * w, s0[1] * w, s1[2] * w, s1[3] * w, s1[0] * w, s1[1] * w], [near[0], near[1], far[2], far[3], far[0], far[1]]);
    run += segs[i].len * w; x = x1; y = y1; prev = far;
    if (i + 1 < segs.length) dir += turn(segs[i + 1].dir - segs[i].dir) * curlAt(run) + (i + 1 < cut + lead ? steer : 0);
  }
}

function wanted() {
  const hero = $('#leon-dock-hero')?.getBoundingClientRect(), foot = $('#leon-dock')?.getBoundingClientRect();
  if (foot && foot.top < innerHeight - foot.height * 0.6 && foot.bottom > headerPx + foot.height * 0.6) return 'foot';
  if (hero && hero.bottom > headerPx + hero.height * 0.55) return 'hero';
  return 'branch';
}

function tick(now) {
  const calm = still.matches, next = wanted();
  if (rest === null) rest = next;
  else if (next !== rest) { move = calm ? null : { from: { ...at }, t0: now, up: next === 'branch' }; rest = next; }
  const to = spot(rest);
  let k = 1, shown = 0, sway = 0;
  if (move) {
    const p = clamp((now - move.t0) / travelMs);
    const q = move.up ? clamp((p - reachPart) / (1 - reachPart)) : clamp(p / holdPart);
    k = ease(q); sway = Math.sin(q * Math.PI) * (to.x < move.from.x ? -7 : 7);
    shown = move.up ? clamp(p / reachPart) : 1 - clamp((p - holdPart) / (1 - holdPart));
    if (p >= 1) move = null;
  }
  const from = move ? move.from : to;
  at = { x: lerp(from.x, to.x, k), y: lerp(from.y, to.y, k), w: lerp(from.w, to.w, k) };
  const perch = $('#chameleon-perch'), state = move ? 'air' : rest;
  if (perch) {
    perch.style.transform = `translate3d(${at.x.toFixed(1)}px,${at.y.toFixed(1)}px,0) rotate(${sway.toFixed(1)}deg)`;
    perch.style.width = `${at.w.toFixed(1)}px`;
    if (perch.dataset.rest !== state) perch.dataset.rest = state;
  }
  if (rig.ready && move) {
    const hook = spot('branch'), cut = rig.pts[rig.cut];
    rigDraw(at.w, hook.x + cut[0] * hook.w - at.x, hook.y + cut[1] * hook.w - at.y, shown);
  }
  const leonY = at.y + at.w / 2, sy = window.scrollY || document.documentElement.scrollTop || 0, drift = calm ? 0 : sy * 0.65;
  document.querySelectorAll('[data-egg]').forEach((el) => {
    const ey = Number(el.dataset.y), ex = Number(el.dataset.x), er = Number(el.dataset.r), vy = ((ey - drift) % 3120 + 3120) % 3120 - 160;
    const near = clamp((leonY + 340 - vy) / 340), away = el.dataset.egg === 'L' ? (calm ? Math.round(near) : ease(near)) : 0;
    el.setAttribute('transform', `translate(${(ex - away * 220).toFixed(1)},${vy.toFixed(1)}) rotate(${(er - away * 40).toFixed(1)})`); el.style.opacity = (0.82 * (1 - away * 0.96)).toFixed(2);
  });
  if (move) frame();
}
let queued = false;
function frame() { if (queued) return; queued = true; requestAnimationFrame((now) => { queued = false; tick(now); }); }
['scroll', 'resize', 'load'].forEach((ev) => window.addEventListener(ev, frame, { passive: true }));
document.addEventListener('scroll', frame, { passive: true, capture: true });
rigLoad(); tick(performance.now());

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
