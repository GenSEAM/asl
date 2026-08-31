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
export const NONE = { tag: "none" };
export function some(v) {
    return { tag: "some", value: v };
}
/// The arm not being built is `never`, not a second type parameter to infer.
/// `ok(x)` appears inside an immediately-applied closure wherever the transpiler
/// lowers a `match`, and a call's contextual type does not reach into one — so
/// an inferable `E` would land on `unknown` and stop assigning to the function's
/// declared `Result`. `never` widens to whatever the declaration says instead.
export function ok(v) {
    return { tag: "ok", value: v };
}
export function err(e) {
    return { tag: "err", value: e };
}
/// A class, not a two-element tuple: `(.-first p)` has to lower to a field read,
/// and `pair` is also a map key and a sort subject, which the structural `eq`
/// and `cmp` below recognise by constructor.
export class ASPair {
    first;
    second;
    constructor(first, second) {
        this.first = first;
        this.second = second;
    }
}
/// Carries an AgentScript `err` out of a `try`. A `defun` containing a `try`
/// catches exactly this and returns the value as its own `err`, so the
/// propagation never escapes the function that declared the `Result`.
export class ASThrown extends Error {
    value;
    constructor(value) {
        super("as: unhandled err");
        this.value = value;
    }
}
export const MAP_EMPTY = { entries: new Map() };
function isFields(v) {
    return typeof v === "object" && v !== null;
}
function keyOf(v) {
    if (typeof v === "bigint")
        return `i${v}`;
    // Tagged so an Int64 1 and a Float64 1.0 are different keys, as they are
    // different values in a language with no implicit conversion.
    if (typeof v === "number")
        return `f${fmtF64(v)}`;
    if (typeof v === "string")
        return `s${JSON.stringify(v)}`;
    if (typeof v === "boolean")
        return `b${v ? 1 : 0}`;
    if (Array.isArray(v))
        return `[${v.map(keyOf).join(",")}]`;
    if (!isFields(v))
        return "u";
    const ks = Object.keys(v).sort();
    return `{${ks.map((k) => `${k}:${keyOf(v[k])}`).join(",")}}`;
}
// ---------- equality and ordering ----------
/// Structural equality. `=`, `list-contains?` and `list-index-of` compare by
/// value in every other backend, and JavaScript's `===` compares objects by
/// reference, so there is nothing to delegate to.
export function eq(a, b) {
    if (Array.isArray(a) && Array.isArray(b)) {
        return a.length === b.length && a.every((x, i) => eq(x, b[i]));
    }
    if (a instanceof Map && b instanceof Map) {
        if (a.size !== b.size)
            return false;
        for (const [k, v] of a) {
            if (!b.has(k) || !eq(v, b.get(k)))
                return false;
        }
        return true;
    }
    // Identity is not equality for a container: a list holding a NaN equals
    // itself on a host that compares by reference, and the language's equality
    // never does. Only non-container values fall through to `===`.
    if (!isFields(a) || !isFields(b))
        return a === b;
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => k in b && eq(a[k], b[k]));
}
/// Code-point order, not UTF-16 order. `<` on two JavaScript strings compares
/// code units, which sorts an astral character below U+E000..U+FFFF; Rust orders
/// UTF-8 bytes and Python orders code points, and both agree with this.
function cmpStr(a, b) {
    const ua = [...a];
    const ub = [...b];
    const n = Math.min(ua.length, ub.length);
    for (let i = 0; i < n; i++) {
        const x = ua[i].codePointAt(0) ?? 0;
        const y = ub[i].codePointAt(0) ?? 0;
        if (x !== y)
            return x < y ? -1 : 1;
    }
    return ua.length === ub.length ? 0 : ua.length < ub.length ? -1 : 1;
}
/// Total order over the values the other backends can order. A tagged value —
/// an `Option`, a `Result`, an enum case — is refused rather than ordered by its
/// tag string: Rust orders those by declaration position and an alphabetical
/// tag would silently disagree. Rust and Swift refuse the same programs at
/// compile time; this backend has no type to refuse them from, so it says so
/// here instead of guessing.
export function cmp(a, b) {
    if (typeof a === "bigint" && typeof b === "bigint") {
        return a < b ? -1 : a > b ? 1 : 0;
    }
    if (typeof a === "number" && typeof b === "number") {
        // NaN is the greater value, as it is on the other hosts: a NaN-holding
        // element sorts last and ties with another NaN, which is what keeps a
        // stable sort's input order among them.
        const an = Number.isNaN(a);
        const bn = Number.isNaN(b);
        if (an && bn)
            return 0;
        if (an)
            return 1;
        if (bn)
            return -1;
        return a < b ? -1 : a > b ? 1 : 0;
    }
    if (typeof a === "string" && typeof b === "string")
        return cmpStr(a, b);
    if (typeof a === "boolean" && typeof b === "boolean") {
        return (a ? 1 : 0) - (b ? 1 : 0);
    }
    if (Array.isArray(a) && Array.isArray(b)) {
        const n = Math.min(a.length, b.length);
        for (let i = 0; i < n; i++) {
            const c = cmp(a[i], b[i]);
            if (c !== 0)
                return c;
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
            if (c !== 0)
                return c;
        }
        return 0;
    }
    throw new Error("no ordering for this value");
}
// §3: for Int32/Int64 "wrapping is an error not a behavior". A bigint has no
// width, so the Int64 bound is enforced here or not at all. As in the Python
// runtime, an Int32 overflow inside the range is caught only by the typed
// backends — this runtime cannot tell the two widths apart at the operation.
const I64_MIN = -(2n ** 63n);
const I64_MAX = 2n ** 63n - 1n;
function checked(n) {
    if (n < I64_MIN || n > I64_MAX)
        throw new Error("integer overflow");
    return n;
}
export function add(a, b) {
    if (typeof a === "bigint")
        return checked(a + b);
    return (a + b);
}
export function sub(a, b) {
    if (typeof a === "bigint")
        return checked(a - b);
    return (a - b);
}
export function mul(a, b) {
    if (typeof a === "bigint")
        return checked(a * b);
    return (a * b);
}
export function neg(a) {
    if (typeof a === "bigint")
        return checked(-a);
    return -a;
}
export function absv(a) {
    if (typeof a === "bigint")
        return checked(a < 0n ? -a : a);
    return Math.abs(a);
}
/// The specification says `/` "traps on a zero divisor" without qualifying it to
/// integers, so the float case traps too. IEEE-754 would hand back an infinity
/// and this backend would disagree with the other three on the language's most
/// basic operator.
export function div(a, b) {
    if (typeof a === "bigint") {
        if (b === 0n)
            throw new Error("division by zero");
        return checked(a / b);
    }
    if (b === 0)
        throw new Error("division by zero");
    return (a / b);
}
export function rem(a, b) {
    if (typeof a === "bigint") {
        if (b === 0n)
            throw new Error("modulo by zero");
        return (a % b);
    }
    if (b === 0)
        throw new Error("modulo by zero");
    return (a % b);
}
export function checkedDiv(a, b) {
    if (typeof a === "bigint") {
        if (b === 0n)
            return NONE;
        const q = a / b;
        // The quotient can leave Int64 (e.g. I64_MIN / -1 = 2^63); that is `none`,
        // not a trap, exactly as the Python and Rust checked operations report it.
        return q < I64_MIN || q > I64_MAX ? NONE : some(q);
    }
    return b === 0 ? NONE : some((a / b));
}
export function checkedRem(a, b) {
    if (typeof a === "bigint") {
        return b === 0n ? NONE : some((a % b));
    }
    return b === 0 ? NONE : some((a % b));
}
/// `min` keeps the left operand on a tie and `max` the right, matching Rust's
/// `Ord::min`/`Ord::max` and Swift's free functions.
export function min(a, b) {
    return cmp(a, b) <= 0 ? a : b;
}
export function max(a, b) {
    return cmp(b, a) >= 0 ? b : a;
}
// ---------- strings ----------
export function strLen(s) {
    return BigInt([...s].length);
}
export function concat(parts) {
    return parts.join("");
}
export function chars(s) {
    return [...s];
}
export function strRev(s) {
    return [...s].reverse().join("");
}
/// An empty separator yields a leading and a trailing empty field, as Rust's
/// `str::split("")` does. JavaScript's own `split("")` would instead cut the
/// string into UTF-16 code units, splitting a surrogate pair in half.
export function split(s, sep) {
    const u = [...s];
    const p = [...sep];
    if (p.length === 0)
        return ["", ...u, ""];
    const out = [];
    let start = 0;
    let i = 0;
    while (i + p.length <= u.length) {
        if (u.slice(i, i + p.length).join("") === sep) {
            out.push(u.slice(start, i).join(""));
            i += p.length;
            start = i;
        }
        else {
            i += 1;
        }
    }
    out.push(u.slice(start).join(""));
    return out;
}
export function replace(s, from, to) {
    return from.length === 0 ? s : split(s, from).join(to);
}
export function strSlice(s, a, b) {
    const u = [...s];
    if (a < 0n || b < a || b > BigInt(u.length))
        return NONE;
    return some(u.slice(Number(a), Number(b)).join(""));
}
export function strIndexOf(s, sub) {
    const i = scalarIndex(s, sub);
    return i === null ? NONE : some(BigInt(i));
}
function scalarIndex(s, sub) {
    const u = [...s];
    const p = [...sub];
    if (p.length === 0)
        return 0;
    for (let i = 0; i + p.length <= u.length; i++) {
        if (u.slice(i, i + p.length).join("") === sub)
            return i;
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
export function fmtF64(x) {
    if (Number.isNaN(x))
        return "nan";
    if (!Number.isFinite(x))
        return x > 0 ? "inf" : "-inf";
    if (Object.is(x, -0))
        return "-0.0";
    const s = String(x);
    let neg = false;
    let t = s;
    if (t.startsWith("-")) {
        neg = true;
        t = t.slice(1);
    }
    let digits;
    let exp10;
    const eIdx = t.search(/[eE]/);
    if (eIdx >= 0) {
        const mant = t.slice(0, eIdx);
        const e = parseInt(t.slice(eIdx + 1), 10);
        const [d, frac] = mant.split(".");
        digits = d + (frac ?? "");
        exp10 = d.length - 1 + e;
    }
    else {
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
export function toI64(s) {
    const t = s.trim();
    if (!/^[+-]?[0-9]+$/.test(t))
        return NONE;
    const n = BigInt(t);
    return n < I64_MIN || n > I64_MAX ? NONE : some(n);
}
export function toF64(s) {
    const t = s.trim();
    if (!/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(t)) {
        // Python's float() accepts the non-finite spellings, and the language's
        // string-to-float64 does too; the regex above is the finite shape only.
        const low = t.toLowerCase();
        if (low === "nan" || low === "+nan" || low === "-nan")
            return some(NaN);
        if (low === "inf" || low === "+inf" || low === "infinity" || low === "+infinity") {
            return some(Infinity);
        }
        if (low === "-inf" || low === "-infinity")
            return some(-Infinity);
        return NONE;
    }
    return some(Number(t));
}
export function toI32(n) {
    return n < -2147483648n || n > 2147483647n ? NONE : some(n);
}
/// Out of range is `none`, not a saturating cast: the Python runtime's range
/// check decides before the conversion, so a target whose cast saturates would
/// answer INT64_MAX for 1e30 and call that a conversion. NaN and both
/// infinities fall out of the same two comparisons.
export function fToI(x) {
    if (!Number.isFinite(x))
        return NONE;
    if (x < -9223372036854775808 || x >= 9223372036854775808)
        return NONE;
    return some(BigInt(Math.trunc(x)));
}
// ---------- lists ----------
export function at(xs, i) {
    return i >= 0n && i < BigInt(xs.length) ? some(xs[Number(i)]) : NONE;
}
export function tail(xs) {
    return xs.length === 0 ? NONE : some(xs.slice(1));
}
export function listSlice(xs, a, b) {
    if (a < 0n || b < a || b > BigInt(xs.length))
        return NONE;
    return some(xs.slice(Number(a), Number(b)));
}
export function contains(xs, x) {
    return xs.some((y) => eq(y, x));
}
export function indexOf(xs, x) {
    const i = xs.findIndex((y) => eq(y, x));
    return i < 0 ? NONE : some(BigInt(i));
}
export function sort(xs) {
    return [...xs].sort(cmp);
}
export function sortBy(f, xs) {
    return [...xs].sort((a, b) => cmp(f(a), f(b)));
}
/// Not `Array.prototype.reduce`: its accumulator is inferred from the initial
/// value, which for `(ok (list))` is the narrowest `Result` there is, and the
/// fold then refuses the wider one the callback returns.
export function fold(f, init, xs) {
    let acc = init;
    for (const x of xs)
        acc = f(acc, x);
    return acc;
}
export function range(a, b) {
    const out = [];
    for (let i = a; i < b; i++)
        out.push(i);
    return out;
}
export function zip(a, b) {
    const n = Math.min(a.length, b.length);
    const out = [];
    for (let i = 0; i < n; i++)
        out.push(new ASPair(a[i], b[i]));
    return out;
}
/// An empty sample has no element to read a width from, so it sums to the
/// numeric zero. Python's `sum([])` is the integer `0` for the same reason, and
/// `string-from-float64` renders it `0.0` — a bigint zero would render as
/// `-inf` through the float formatter, which is a disagreement, not a value.
export function sum(xs) {
    if (xs.length === 0)
        return 0;
    return xs.reduce((a, b) => add(a, b));
}
export function least(xs) {
    if (xs.length === 0)
        return NONE;
    return some(xs.reduce((m, x) => (cmp(x, m) < 0 ? x : m)));
}
export function greatest(xs) {
    if (xs.length === 0)
        return NONE;
    return some(xs.reduce((m, x) => (cmp(x, m) > 0 ? x : m)));
}
// ---------- maps ----------
//
// Iteration is sorted by key. The specification orders map-keys/values/pairs and
// a JavaScript Map iterates in insertion order, which would make two backends
// disagree on identical input.
export function mGet(m, k) {
    const e = m.entries.get(keyOf(k));
    return e === undefined ? NONE : some(e[1]);
}
export function mSet(m, k, v) {
    const out = new Map(m.entries);
    out.set(keyOf(k), [k, v]);
    return { entries: out };
}
export function mDel(m, k) {
    const out = new Map(m.entries);
    out.delete(keyOf(k));
    return { entries: out };
}
export function mHas(m, k) {
    return m.entries.has(keyOf(k));
}
export function mSize(m) {
    return BigInt(m.entries.size);
}
function ordered(m) {
    return [...m.entries.values()].sort((a, b) => cmp(a[0], b[0]));
}
export function mKeys(m) {
    return ordered(m).map((e) => e[0]);
}
export function mValues(m) {
    return ordered(m).map((e) => e[1]);
}
export function mPairs(m) {
    return ordered(m).map((e) => new ASPair(e[0], e[1]));
}
export function mFrom(ps) {
    const out = new Map();
    for (const p of ps)
        out.set(keyOf(p.first), [p.first, p.second]);
    return { entries: out };
}
// ---------- option and result ----------
export function optOr(o, d) {
    return o.tag === "some" ? o.value : d;
}
export function resOr(r, d) {
    return r.tag === "ok" ? r.value : d;
}
export function optMap(f, o) {
    return o.tag === "some" ? some(f(o.value)) : NONE;
}
export function resMap(f, r) {
    return r.tag === "ok" ? ok(f(r.value)) : err(r.value);
}
export function resMapErr(f, r) {
    return r.tag === "ok" ? ok(r.value) : err(f(r.value));
}
export function optToRes(o, e) {
    return o.tag === "some" ? ok(o.value) : err(e);
}
export function resToOpt(r) {
    return r.tag === "ok" ? some(r.value) : NONE;
}
/// The `try` form: yields the ok value, or throws the err value to the enclosing
/// function's catch.
export function unwrap(r) {
    if (r.tag === "ok")
        return r.value;
    throw new ASThrown(r.value);
}
/// Reached only when a `match` covers no arm. The transpiler emits it where the
/// arms leave a gap, so the failure names the language rule rather than
/// surfacing as an undefined return value.
export function nonExhaustive() {
    throw new Error("non-exhaustive match");
}
// ---------- I/O ----------
// Node's standard library is imported here and only here. The core above stays
// free of it, so a program that does no I/O depends on nothing but the language.
import * as fs from "node:fs";
function isIoError(x) {
    if (typeof x !== "object" || x === null || !("tag" in x))
        return false;
    const tag = x.tag;
    return typeof tag === "string"
        && ["not-found", "permission-denied", "already-exists",
            "invalid-path", "interrupted", "other"].includes(tag);
}
export function notFound() { return { tag: "not-found" }; }
export function permissionDenied() { return { tag: "permission-denied" }; }
export function alreadyExists() { return { tag: "already-exists" }; }
export function invalidPath() { return { tag: "invalid-path" }; }
export function interrupted() { return { tag: "interrupted" }; }
export function other() { return { tag: "other" }; }
/// Node's `error.code` to the closed union, dual-faithful to Python's errno map
/// and Rust's `ErrorKind`. `EINVAL` and `ENAMETOOLONG` fall to `other`, exactly
/// as they do on both duals — a mapping that sent them to `invalid-path` would
/// be the cross-arm divergence this table exists to prevent.
export function codeToIoError(code) {
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
function errFor(e) {
    if (typeof e === "object" && e !== null && "code" in e) {
        return codeToIoError(e.code);
    }
    return { tag: "other" };
}
/// Standard input is read once and consumed from a cursor. Node offers no
/// synchronous line reader, and `read-line` followed by `read-all` has to see
/// the remainder of the stream, not the whole of it again. A failing read is an
/// `IoError`, not a silent empty stream — the live hosts map it the same way.
let stdinBuf = null;
let stdinPos = 0;
let stdinErr = null;
function stdinText() {
    if (stdinBuf === null && stdinErr === null) {
        try {
            stdinBuf = fs.readFileSync(0, "utf8");
        }
        catch (e) {
            stdinErr = errFor(e);
        }
    }
    return stdinBuf ?? "";
}
function attempt(body) {
    try {
        return ok(body());
    }
    catch (e) {
        return err(errFor(e));
    }
}
export function readLine() {
    if (stdinErr !== null)
        return err(stdinErr);
    const buf = stdinText();
    if (stdinPos >= buf.length)
        return ok(NONE);
    const nl = buf.indexOf("\n", stdinPos);
    const line = nl < 0 ? buf.slice(stdinPos) : buf.slice(stdinPos, nl);
    stdinPos = nl < 0 ? buf.length : nl + 1;
    return ok(some(line));
}
export function readAll() {
    if (stdinErr !== null)
        return err(stdinErr);
    const buf = stdinText();
    const rest = buf.slice(stdinPos);
    stdinPos = buf.length;
    return ok(rest);
}
export function print_(s) {
    return attempt(() => {
        fs.writeSync(1, s);
    });
}
export function println(s) {
    return attempt(() => {
        fs.writeSync(1, `${s}\n`);
    });
}
export function eprintln(s) {
    return attempt(() => {
        fs.writeSync(2, `${s}\n`);
    });
}
export function fileRead(path) {
    return attempt(() => fs.readFileSync(path, "utf8"));
}
export function fileWrite(path, s) {
    return attempt(() => {
        fs.writeFileSync(path, s, "utf8");
    });
}
export function fileAppend(path, s) {
    return attempt(() => {
        fs.appendFileSync(path, s, "utf8");
    });
}
export function fileExists(path) {
    return fs.existsSync(path);
}
export function args() {
    return process.argv.slice(2);
}
/// Host entry glue: a program's `Result` becomes its exit status, mirroring
/// `main_exit` in the Python and Rust runtimes. `err` prints its case name to
/// stderr and exits 1; a non-Result or non-IoError payload is rejected, because
/// accepting anything else would make this backend disagree with the Rust one
/// about which programs are valid.
export function mainExit(result) {
    if (typeof result !== "object" || result === null || !("tag" in result)
        || (result.tag !== "ok" && result.tag !== "err")) {
        throw new TypeError(`main must return a Result, got ${JSON.stringify(result)}`);
    }
    if (result.tag === "ok")
        process.exit(0);
    const e = result.value;
    if (!isIoError(e)) {
        throw new TypeError(`main must fail with an IoError, got ${JSON.stringify(e)}`);
    }
    fs.writeSync(2, `${e.tag}\n`);
    process.exit(1);
}
//# sourceMappingURL=rt.js.map