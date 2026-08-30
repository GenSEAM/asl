// AgentScript runtime for the TypeScript backend.
//
// Int32 and Int64 both lower to `bigint`, never to `number`: a JavaScript number
// is a double, so it stops being exact at 2^53 — the divergence EXPERIMENT.md
// already records between Python and JavaScript. `bigint` is exact over the
// whole Int64 range and traps outside it, which is what lets this backend be
// compared against Rust and Swift at all.
//
// Strings are measured, sliced and indexed in Unicode scalars. JavaScript
// indexes a string in UTF-16 code units, where Rust's `chars()`, Swift's
// `unicodeScalars` and Python's `len()` all count scalars, so every length,
// slice, index and ordering here goes through `[...s]`, which iterates code
// points.
//
// Node's standard library is imported at the bottom of this file and only
// there. The pure core above it needs nothing beyond the language.

/// `Option` and `Result` are hand-rolled discriminated unions rather than
/// `T | null` and the stdlib's `Result`-alikes: `T | null` cannot express a
/// nested `(Option (Option T))`, and a tag the compiler can narrow on is what
/// makes the transpiler's `match` lowering type-check without a cast.
export type ASOption<T> =
  | { readonly tag: "some"; readonly value: T }
  | { readonly tag: "none" };

/// Both arms name their payload `value` so the `match` lowering reads one field
/// whichever arm it narrowed to.
export type ASResult<T, E> =
  | { readonly tag: "ok"; readonly value: T }
  | { readonly tag: "err"; readonly value: E };

export const NONE: ASOption<never> = { tag: "none" };

export function some<T>(v: T): ASOption<T> {
  return { tag: "some", value: v };
}

/// The arm not being built is `never`, not a second type parameter to infer.
/// `ok(x)` appears inside an immediately-applied closure wherever the transpiler
/// lowers a `match`, and a call's contextual type does not reach into one — so
/// an inferable `E` would land on `unknown` and stop assigning to the function's
/// declared `Result`. `never` widens to whatever the declaration says instead.
export function ok<T>(v: T): ASResult<T, never> {
  return { tag: "ok", value: v };
}

export function err<E>(e: E): ASResult<never, E> {
  return { tag: "err", value: e };
}

/// A class, not a two-element tuple: `(.-first p)` has to lower to a field read,
/// and `pair` is also a map key and a sort subject, which the structural `eq`
/// and `cmp` below recognise by constructor.
export class ASPair<A, B> {
  constructor(
    readonly first: A,
    readonly second: B,
  ) {}
}

/// Carries an AgentScript `err` out of a `try`. A `defun` containing a `try`
/// catches exactly this and returns the value as its own `err`, so the
/// propagation never escapes the function that declared the `Result`.
export class ASThrown<E> extends Error {
  constructor(readonly value: E) {
    super("as: unhandled err");
  }
}

/// A Map keyed by a canonical rendering of the AgentScript key, not by the key
/// itself: JavaScript's `Map` compares object keys by reference, so a `Pair` or
/// a record key would miss every lookup where Rust's `BTreeMap` and Swift's
/// `Dictionary` hit. The original key is kept beside the value so iteration can
/// hand it back.
export interface ASMap<K, V> {
  readonly entries: ReadonlyMap<string, readonly [K, V]>;
}

export const MAP_EMPTY: ASMap<never, never> = { entries: new Map() };

type Fields = Record<string, unknown>;

function isFields(v: unknown): v is Fields {
  return typeof v === "object" && v !== null;
}

function keyOf(v: unknown): string {
  if (typeof v === "bigint") return `i${v}`;
  // Tagged so an Int64 1 and a Float64 1.0 are different keys, as they are
  // different values in a language with no implicit conversion.
  if (typeof v === "number") return `f${fmtF64(v)}`;
  if (typeof v === "string") return `s${JSON.stringify(v)}`;
  if (typeof v === "boolean") return `b${v ? 1 : 0}`;
  if (Array.isArray(v)) return `[${v.map(keyOf).join(",")}]`;
  if (!isFields(v)) return "u";
  const ks = Object.keys(v).sort();
  return `{${ks.map((k) => `${k}:${keyOf(v[k])}`).join(",")}}`;
}

// ---------- equality and ordering ----------

/// Structural equality. `=`, `list-contains?` and `list-index-of` compare by
/// value in every other backend, and JavaScript's `===` compares objects by
/// reference, so there is nothing to delegate to.
export function eq(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  }
  if (a instanceof Map && b instanceof Map) {
    if (a.size !== b.size) return false;
    for (const [k, v] of a) {
      if (!b.has(k) || !eq(v, b.get(k))) return false;
    }
    return true;
  }
  // Identity is not equality for a container: a list holding a NaN equals
  // itself on a host that compares by reference, and the language's equality
  // never does. Only non-container values fall through to `===`.
  if (!isFields(a) || !isFields(b)) return a === b;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => k in b && eq(a[k], b[k]));
}

/// Code-point order, not UTF-16 order. `<` on two JavaScript strings compares
/// code units, which sorts an astral character below U+E000..U+FFFF; Rust orders
/// UTF-8 bytes and Python orders code points, and both agree with this.
function cmpStr(a: string, b: string): number {
  const ua = [...a];
  const ub = [...b];
  const n = Math.min(ua.length, ub.length);
  for (let i = 0; i < n; i++) {
    const x = ua[i].codePointAt(0) ?? 0;
    const y = ub[i].codePointAt(0) ?? 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return ua.length === ub.length ? 0 : ua.length < ub.length ? -1 : 1;
}

/// Total order over the values the other backends can order. A tagged value —
/// an `Option`, a `Result`, an enum case — is refused rather than ordered by its
/// tag string: Rust orders those by declaration position and an alphabetical
/// tag would silently disagree. Rust and Swift refuse the same programs at
/// compile time; this backend has no type to refuse them from, so it says so
/// here instead of guessing.
export function cmp(a: unknown, b: unknown): number {
  if (typeof a === "bigint" && typeof b === "bigint") {
    return a < b ? -1 : a > b ? 1 : 0;
  }
  if (typeof a === "number" && typeof b === "number") {
    // NaN is the greater value, as it is on the other hosts: a NaN-holding
    // element sorts last and ties with another NaN, which is what keeps a
    // stable sort's input order among them.
    const an = Number.isNaN(a);
    const bn = Number.isNaN(b);
    if (an && bn) return 0;
    if (an) return 1;
    if (bn) return -1;
    return a < b ? -1 : a > b ? 1 : 0;
  }
  if (typeof a === "string" && typeof b === "string") return cmpStr(a, b);
  if (typeof a === "boolean" && typeof b === "boolean") {
    return (a ? 1 : 0) - (b ? 1 : 0);
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) {
      const c = cmp(a[i], b[i]);
      if (c !== 0) return c;
    }
    return a.length === b.length ? 0 : a.length < b.length ? -1 : 1;
  }
  if (a instanceof ASPair && b instanceof ASPair) {
    const c = cmp(a.first, b.first);
    return c !== 0 ? c : cmp(a.second, b.second);
  }
  if (isFields(a) && isFields(b) && !("tag" in a) && !("tag" in b)) {
    // A record: field order is declaration order, which is the order Rust's
    // derived `Ord` and Swift's synthesized `<` both compare in.
    for (const k of Object.keys(a)) {
      const c = cmp(a[k], b[k]);
      if (c !== 0) return c;
    }
    return 0;
  }
  throw new Error("no ordering for this value");
}

// ---------- arithmetic ----------

type ASNum = bigint | number;

// §3: for Int32/Int64 "wrapping is an error not a behavior". A bigint has no
// width, so the Int64 bound is enforced here or not at all. As in the Python
// runtime, an Int32 overflow inside the range is caught only by the typed
// backends — this runtime cannot tell the two widths apart at the operation.
const I64_MIN = -(2n ** 63n);
const I64_MAX = 2n ** 63n - 1n;

function checked(n: bigint): bigint {
  if (n < I64_MIN || n > I64_MAX) throw new Error("integer overflow");
  return n;
}

export function add<T extends ASNum>(a: T, b: T): T {
  if (typeof a === "bigint") return checked(a + (b as bigint)) as T;
  return ((a as number) + (b as number)) as T;
}

export function sub<T extends ASNum>(a: T, b: T): T {
  if (typeof a === "bigint") return checked(a - (b as bigint)) as T;
  return ((a as number) - (b as number)) as T;
}

export function mul<T extends ASNum>(a: T, b: T): T {
  if (typeof a === "bigint") return checked(a * (b as bigint)) as T;
  return ((a as number) * (b as number)) as T;
}

export function neg<T extends ASNum>(a: T): T {
  if (typeof a === "bigint") return checked(-a) as T;
  return -(a as number) as T;
}

export function absv<T extends ASNum>(a: T): T {
  if (typeof a === "bigint") return checked(a < 0n ? -a : a) as T;
  return Math.abs(a as number) as T;
}

/// The specification says `/` "traps on a zero divisor" without qualifying it to
/// integers, so the float case traps too. IEEE-754 would hand back an infinity
/// and this backend would disagree with the other three on the language's most
/// basic operator.
export function div<T extends ASNum>(a: T, b: T): T {
  if (typeof a === "bigint") {
    if ((b as bigint) === 0n) throw new Error("division by zero");
    return checked(a / (b as bigint)) as T;
  }
  if ((b as number) === 0) throw new Error("division by zero");
  return ((a as number) / (b as number)) as T;
}

export function rem<T extends ASNum>(a: T, b: T): T {
  if (typeof a === "bigint") {
    if ((b as bigint) === 0n) throw new Error("modulo by zero");
    return (a % (b as bigint)) as T;
  }
  if ((b as number) === 0) throw new Error("modulo by zero");
  return ((a as number) % (b as number)) as T;
}

export function checkedDiv<T extends ASNum>(a: T, b: T): ASOption<T> {
  if (typeof a === "bigint") {
    if ((b as bigint) === 0n) return NONE;
    const q: bigint = (a as bigint) / (b as bigint);
    // The quotient can leave Int64 (e.g. I64_MIN / -1 = 2^63); that is `none`,
    // not a trap, exactly as the Python and Rust checked operations report it.
    return q < I64_MIN || q > I64_MAX ? NONE : some(q as T);
  }
  return (b as number) === 0 ? NONE : some(((a as number) / (b as number)) as T);
}

export function checkedRem<T extends ASNum>(a: T, b: T): ASOption<T> {
  if (typeof a === "bigint") {
    return (b as bigint) === 0n ? NONE : some((a % (b as bigint)) as T);
  }
  return (b as number) === 0 ? NONE : some(((a as number) % (b as number)) as T);
}

/// `min` keeps the left operand on a tie and `max` the right, matching Rust's
/// `Ord::min`/`Ord::max` and Swift's free functions.
export function min<T>(a: T, b: T): T {
  return cmp(a, b) <= 0 ? a : b;
}

export function max<T>(a: T, b: T): T {
  return cmp(b, a) >= 0 ? b : a;
}

// ---------- strings ----------

export function strLen(s: string): bigint {
  return BigInt([...s].length);
}

export function concat(parts: readonly string[]): string {
  return parts.join("");
}

export function chars(s: string): string[] {
  return [...s];
}

export function strRev(s: string): string {
  return [...s].reverse().join("");
}

/// An empty separator yields a leading and a trailing empty field, as Rust's
/// `str::split("")` does. JavaScript's own `split("")` would instead cut the
/// string into UTF-16 code units, splitting a surrogate pair in half.
export function split(s: string, sep: string): string[] {
  const u = [...s];
  const p = [...sep];
  if (p.length === 0) return ["", ...u, ""];
  const out: string[] = [];
  let start = 0;
  let i = 0;
  while (i + p.length <= u.length) {
    if (u.slice(i, i + p.length).join("") === sep) {
      out.push(u.slice(start, i).join(""));
      i += p.length;
      start = i;
    } else {
      i += 1;
    }
  }
  out.push(u.slice(start).join(""));
  return out;
}

export function replace(s: string, from: string, to: string): string {
  return from.length === 0 ? s : split(s, from).join(to);
}

export function strSlice(s: string, a: bigint, b: bigint): ASOption<string> {
  const u = [...s];
  if (a < 0n || b < a || b > BigInt(u.length)) return NONE;
  return some(u.slice(Number(a), Number(b)).join(""));
}

export function strIndexOf(s: string, sub: string): ASOption<bigint> {
  const i = scalarIndex(s, sub);
  return i === null ? NONE : some(BigInt(i));
}

function scalarIndex(s: string, sub: string): number | null {
  const u = [...s];
  const p = [...sub];
  if (p.length === 0) return 0;
  for (let i = 0; i + p.length <= u.length; i++) {
    if (u.slice(i, i + p.length).join("") === sub) return i;
  }
  return null;
}

/// Python's `repr`, Rust's `{:?}` and Swift's `String(Double)` all agree on the
/// shortest round-trip digits; they differ from JavaScript's `String` only in
/// when exponent notation is used. Python switches at a decimal exponent of 16
/// (large) and -5 (small); JavaScript waits until 21 and -6, so a value like
/// 2^54 renders `18014398509481984.0` here and `1.8014398509481984e+16` on the
/// other hosts. The digits come from `String(x)` (shortest round-trip, same as
/// the others) and are re-rendered under Python's thresholds.
export function fmtF64(x: number): string {
  if (Number.isNaN(x)) return "nan";
  if (!Number.isFinite(x)) return x > 0 ? "inf" : "-inf";
  if (Object.is(x, -0)) return "-0.0";
  const s = String(x);
  let neg = false;
  let t = s;
  if (t.startsWith("-")) {
    neg = true;
    t = t.slice(1);
  }
  let digits: string;
  let exp10: number;
  const eIdx = t.search(/[eE]/);
  if (eIdx >= 0) {
    const mant = t.slice(0, eIdx);
    const e = parseInt(t.slice(eIdx + 1), 10);
    const [d, frac] = mant.split(".");
    digits = d + (frac ?? "");
    exp10 = d.length - 1 + e;
  } else {
    const [d, frac] = t.split(".");
    digits = d + (frac ?? "");
    exp10 = d.length - 1;
  }
  const first = digits.search(/[1-9]/);
  if (first > 0) {
    digits = digits.slice(first);
    exp10 -= first;
  }
  digits = digits.replace(/0+$/, "");
  const sign = neg ? "-" : "";
  if (exp10 >= 16 || exp10 <= -5) {
    const mant = digits.length === 1 ? digits : digits[0] + "." + digits.slice(1);
    const esign = exp10 < 0 ? "-" : "+";
    const eabs = Math.abs(exp10);
    const epad = eabs < 10 ? "0" + eabs : String(eabs);
    return `${sign}${mant}e${esign}${epad}`;
  }
  if (exp10 >= 0) {
    if (digits.length <= exp10 + 1) {
      return sign + digits + "0".repeat(exp10 + 1 - digits.length) + ".0";
    }
    return sign + digits.slice(0, exp10 + 1) + "." + digits.slice(exp10 + 1);
  }
  return sign + "0." + "0".repeat(-exp10 - 1) + digits;
}

/// `BigInt("")` is `0n` and `BigInt("0x10")` is `16n`, neither of which the
/// other backends parse, so the shape is checked before the conversion. Out of
/// Int64 range is `none`, as it is for Rust's `i64::from_str` and Swift's
/// `Int64.init`.
export function toI64(s: string): ASOption<bigint> {
  const t = s.trim();
  if (!/^[+-]?[0-9]+$/.test(t)) return NONE;
  const n = BigInt(t);
  return n < I64_MIN || n > I64_MAX ? NONE : some(n);
}

export function toF64(s: string): ASOption<number> {
  const t = s.trim();
  if (!/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(t)) {
    // Python's float() accepts the non-finite spellings, and the language's
    // string-to-float64 does too; the regex above is the finite shape only.
    const low = t.toLowerCase();
    if (low === "nan" || low === "+nan" || low === "-nan") return some(NaN);
    if (low === "inf" || low === "+inf" || low === "infinity" || low === "+infinity") {
      return some(Infinity);
    }
    if (low === "-inf" || low === "-infinity") return some(-Infinity);
    return NONE;
  }
  return some(Number(t));
}

export function toI32(n: bigint): ASOption<bigint> {
  return n < -2147483648n || n > 2147483647n ? NONE : some(n);
}

/// Out of range is `none`, not a saturating cast: the Python runtime's range
/// check decides before the conversion, so a target whose cast saturates would
/// answer INT64_MAX for 1e30 and call that a conversion. NaN and both
/// infinities fall out of the same two comparisons.
export function fToI(x: number): ASOption<bigint> {
  if (!Number.isFinite(x)) return NONE;
  if (x < -9223372036854775808 || x >= 9223372036854775808) return NONE;
  return some(BigInt(Math.trunc(x)));
}

// ---------- lists ----------

export function at<T>(xs: readonly T[], i: bigint): ASOption<T> {
  return i >= 0n && i < BigInt(xs.length) ? some(xs[Number(i)]) : NONE;
}

export function tail<T>(xs: readonly T[]): ASOption<T[]> {
  return xs.length === 0 ? NONE : some(xs.slice(1));
}

export function listSlice<T>(xs: readonly T[], a: bigint, b: bigint): ASOption<T[]> {
  if (a < 0n || b < a || b > BigInt(xs.length)) return NONE;
  return some(xs.slice(Number(a), Number(b)));
}

export function contains<T>(xs: readonly T[], x: T): boolean {
  return xs.some((y) => eq(y, x));
}

export function indexOf<T>(xs: readonly T[], x: T): ASOption<bigint> {
  const i = xs.findIndex((y) => eq(y, x));
  return i < 0 ? NONE : some(BigInt(i));
}

export function sort<T>(xs: readonly T[]): T[] {
  return [...xs].sort(cmp);
}

export function sortBy<T, K>(f: (x: T) => K, xs: readonly T[]): T[] {
  return [...xs].sort((a, b) => cmp(f(a), f(b)));
}

/// Not `Array.prototype.reduce`: its accumulator is inferred from the initial
/// value, which for `(ok (list))` is the narrowest `Result` there is, and the
/// fold then refuses the wider one the callback returns.
export function fold<A, B>(f: (acc: B, x: A) => B, init: B, xs: readonly A[]): B {
  let acc = init;
  for (const x of xs) acc = f(acc, x);
  return acc;
}

export function range(a: bigint, b: bigint): bigint[] {
  const out: bigint[] = [];
  for (let i = a; i < b; i++) out.push(i);
  return out;
}

export function zip<A, B>(a: readonly A[], b: readonly B[]): ASPair<A, B>[] {
  const n = Math.min(a.length, b.length);
  const out: ASPair<A, B>[] = [];
  for (let i = 0; i < n; i++) out.push(new ASPair(a[i], b[i]));
  return out;
}

/// An empty sample has no element to read a width from, so it sums to the
/// numeric zero. Python's `sum([])` is the integer `0` for the same reason, and
/// `string-from-float64` renders it `0.0` — a bigint zero would render as
/// `-inf` through the float formatter, which is a disagreement, not a value.
export function sum<T extends ASNum>(xs: readonly T[]): T {
  if (xs.length === 0) return 0 as unknown as T;
  return xs.reduce((a, b) => add(a, b));
}

export function least<T>(xs: readonly T[]): ASOption<T> {
  if (xs.length === 0) return NONE;
  return some(xs.reduce((m, x) => (cmp(x, m) < 0 ? x : m)));
}

export function greatest<T>(xs: readonly T[]): ASOption<T> {
  if (xs.length === 0) return NONE;
  return some(xs.reduce((m, x) => (cmp(x, m) > 0 ? x : m)));
}

// ---------- maps ----------
//
// Iteration is sorted by key. The specification orders map-keys/values/pairs and
// a JavaScript Map iterates in insertion order, which would make two backends
// disagree on identical input.

export function mGet<K, V>(m: ASMap<K, V>, k: K): ASOption<V> {
  const e = m.entries.get(keyOf(k));
  return e === undefined ? NONE : some(e[1]);
}

export function mSet<K, V>(m: ASMap<K, V>, k: K, v: V): ASMap<K, V> {
  const out = new Map(m.entries);
  out.set(keyOf(k), [k, v]);
  return { entries: out };
}

export function mDel<K, V>(m: ASMap<K, V>, k: K): ASMap<K, V> {
  const out = new Map(m.entries);
  out.delete(keyOf(k));
  return { entries: out };
}

export function mHas<K, V>(m: ASMap<K, V>, k: K): boolean {
  return m.entries.has(keyOf(k));
}

export function mSize<K, V>(m: ASMap<K, V>): bigint {
  return BigInt(m.entries.size);
}

function ordered<K, V>(m: ASMap<K, V>): (readonly [K, V])[] {
  return [...m.entries.values()].sort((a, b) => cmp(a[0], b[0]));
}

export function mKeys<K, V>(m: ASMap<K, V>): K[] {
  return ordered(m).map((e) => e[0]);
}

export function mValues<K, V>(m: ASMap<K, V>): V[] {
  return ordered(m).map((e) => e[1]);
}

export function mPairs<K, V>(m: ASMap<K, V>): ASPair<K, V>[] {
  return ordered(m).map((e) => new ASPair(e[0], e[1]));
}

export function mFrom<K, V>(ps: readonly ASPair<K, V>[]): ASMap<K, V> {
  const out = new Map<string, readonly [K, V]>();
  for (const p of ps) out.set(keyOf(p.first), [p.first, p.second]);
  return { entries: out };
}

// ---------- option and result ----------

export function optOr<T>(o: ASOption<T>, d: T): T {
  return o.tag === "some" ? o.value : d;
}

export function resOr<T, E>(r: ASResult<T, E>, d: T): T {
  return r.tag === "ok" ? r.value : d;
}

export function optMap<A, B>(f: (a: A) => B, o: ASOption<A>): ASOption<B> {
  return o.tag === "some" ? some(f(o.value)) : NONE;
}

export function resMap<A, B, E>(f: (a: A) => B, r: ASResult<A, E>): ASResult<B, E> {
  return r.tag === "ok" ? ok(f(r.value)) : err(r.value);
}

export function resMapErr<T, E, F>(f: (e: E) => F, r: ASResult<T, E>): ASResult<T, F> {
  return r.tag === "ok" ? ok(r.value) : err(f(r.value));
}

export function optToRes<T, E>(o: ASOption<T>, e: E): ASResult<T, E> {
  return o.tag === "some" ? ok(o.value) : err(e);
}

export function resToOpt<T, E>(r: ASResult<T, E>): ASOption<T> {
  return r.tag === "ok" ? some(r.value) : NONE;
}

/// The `try` form: yields the ok value, or throws the err value to the enclosing
/// function's catch.
export function unwrap<T, E>(r: ASResult<T, E>): T {
  if (r.tag === "ok") return r.value;
  throw new ASThrown(r.value);
}

/// Reached only when a `match` covers no arm. The transpiler emits it where the
/// arms leave a gap, so the failure names the language rule rather than
/// surfacing as an undefined return value.
export function nonExhaustive(): never {
  throw new Error("non-exhaustive match");
}

// ---------- I/O ----------
// Node's standard library is imported here and only here. The core above stays
// free of it, so a program that does no I/O depends on nothing but the language.

import * as fs from "node:fs";

/// The closed failure union `main` may terminate on, mirroring the Python and
/// Rust runtimes. Every I/O helper derives a case from the host's `error.code`,
/// the dual of Python's errno table and Rust's `ErrorKind` match; only the
/// differential gate proves the three agree.
export type IoError =
  | { readonly tag: "not-found" }
  | { readonly tag: "permission-denied" }
  | { readonly tag: "already-exists" }
  | { readonly tag: "invalid-path" }
  | { readonly tag: "interrupted" }
  | { readonly tag: "other" };

function isIoError(x: unknown): x is IoError {
  if (typeof x !== "object" || x === null || !("tag" in x)) return false;
  const tag = (x as { tag: unknown }).tag;
  return typeof tag === "string"
    && ["not-found", "permission-denied", "already-exists",
        "invalid-path", "interrupted", "other"].includes(tag);
}

export function notFound(): IoError { return { tag: "not-found" }; }
export function permissionDenied(): IoError { return { tag: "permission-denied" }; }
export function alreadyExists(): IoError { return { tag: "already-exists" }; }
export function invalidPath(): IoError { return { tag: "invalid-path" }; }
export function interrupted(): IoError { return { tag: "interrupted" }; }
export function other(): IoError { return { tag: "other" }; }

/// Node's `error.code` to the closed union, dual-faithful to Python's errno map
/// and Rust's `ErrorKind`. `EINVAL` and `ENAMETOOLONG` fall to `other`, exactly
/// as they do on both duals — a mapping that sent them to `invalid-path` would
/// be the cross-arm divergence this table exists to prevent.
export function codeToIoError(code: string | undefined): IoError {
  switch (code) {
    case "ENOENT": return { tag: "not-found" };
    case "EACCES":
    case "EPERM": return { tag: "permission-denied" };
    case "EEXIST": return { tag: "already-exists" };
    case "ENOTDIR":
    case "EISDIR": return { tag: "invalid-path" };
    case "EINTR": return { tag: "interrupted" };
    default: return { tag: "other" };
  }
}

function errFor(e: unknown): IoError {
  if (typeof e === "object" && e !== null && "code" in e) {
    return codeToIoError((e as { code?: unknown }).code as string | undefined);
  }
  return { tag: "other" };
}

/// Standard input is read once and consumed from a cursor. Node offers no
/// synchronous line reader, and `read-line` followed by `read-all` has to see
/// the remainder of the stream, not the whole of it again. A failing read is an
/// `IoError`, not a silent empty stream — the live hosts map it the same way.
let stdinBuf: string | null = null;
let stdinPos = 0;
let stdinErr: IoError | null = null;

function stdinText(): string {
  if (stdinBuf === null && stdinErr === null) {
    try {
      stdinBuf = fs.readFileSync(0, "utf8");
    } catch (e) {
      stdinErr = errFor(e);
    }
  }
  return stdinBuf ?? "";
}

function attempt<T>(body: () => T): ASResult<T, IoError> {
  try {
    return ok(body());
  } catch (e) {
    return err(errFor(e));
  }
}

export function readLine(): ASResult<ASOption<string>, IoError> {
  if (stdinErr !== null) return err(stdinErr);
  const buf = stdinText();
  if (stdinPos >= buf.length) return ok(NONE);
  const nl = buf.indexOf("\n", stdinPos);
  const line = nl < 0 ? buf.slice(stdinPos) : buf.slice(stdinPos, nl);
  stdinPos = nl < 0 ? buf.length : nl + 1;
  return ok(some(line));
}

export function readAll(): ASResult<string, IoError> {
  if (stdinErr !== null) return err(stdinErr);
  const buf = stdinText();
  const rest = buf.slice(stdinPos);
  stdinPos = buf.length;
  return ok(rest);
}

export function print_(s: string): ASResult<void, IoError> {
  return attempt(() => {
    fs.writeSync(1, s);
  });
}

export function println(s: string): ASResult<void, IoError> {
  return attempt(() => {
    fs.writeSync(1, `${s}\n`);
  });
}

export function eprintln(s: string): ASResult<void, IoError> {
  return attempt(() => {
    fs.writeSync(2, `${s}\n`);
  });
}

export function fileRead(path: string): ASResult<string, IoError> {
  return attempt(() => fs.readFileSync(path, "utf8"));
}

export function fileWrite(path: string, s: string): ASResult<void, IoError> {
  return attempt(() => {
    fs.writeFileSync(path, s, "utf8");
  });
}

export function fileAppend(path: string, s: string): ASResult<void, IoError> {
  return attempt(() => {
    fs.appendFileSync(path, s, "utf8");
  });
}

export function fileExists(path: string): boolean {
  return fs.existsSync(path);
}

export function args(): string[] {
  return process.argv.slice(2);
}

/// Host entry glue: a program's `Result` becomes its exit status, mirroring
/// `main_exit` in the Python and Rust runtimes. `err` prints its case name to
/// stderr and exits 1; a non-Result or non-IoError payload is rejected, because
/// accepting anything else would make this backend disagree with the Rust one
/// about which programs are valid.
export function mainExit(result: ASResult<unknown, IoError>): never {
  if (typeof result !== "object" || result === null || !("tag" in result)
      || (result.tag !== "ok" && result.tag !== "err")) {
    throw new TypeError(`main must return a Result, got ${JSON.stringify(result)}`);
  }
  if (result.tag === "ok") process.exit(0);
  const e = result.value;
  if (!isIoError(e)) {
    throw new TypeError(`main must fail with an IoError, got ${JSON.stringify(e)}`);
  }
  fs.writeSync(2, `${e.tag}\n`);
  process.exit(1);
}
