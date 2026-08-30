# Phase 8 — Go backend

## §1 Scope and acceptance

Build the Go backend out of the partial runtime that already exists. `.plans/PHASES.md:79-80`:
*"`backend/golang/rt/rt.go` exists; no transpiler. A GC'd native target and a fourth differential
arm."* The wording predates Phase 7; measured today, `backend/differential.py` has five arms in
program mode (python/rust/wasm/interp/ts, runners dict `backend/differential.py:499`) and four in
function mode (`run_python:215` / `run_rust:234` / `run_interp:260` / `run_typescript:446`). Go
becomes a **sixth arm in both modes**, fully participating — no skip mechanism, no forwarded
column, no partial output.

Acceptance, each ending in a command:

1. **Every builtin has a `go` lowering in `prelude/prelude.json`**, the widened
   `validate_templates()` (`prelude/generate.py:165`) reports no broken `go` template, and
   `prelude/generate.py --check` stays green with `"go"` in the validation tuple.
2. **`go vet` accepts the emitted output** for every fixture `check_corpus.py` gates (corpus
   valid + bench, `backend/check_corpus.py:20-23`), via a new `go vet` column; a fixture whose
   Go transpile fails or emits nothing is a recorded gate failure, not a skipped column. `go
   build` acceptance is proven separately by `differential.py`'s `build_go` and W5's gate.
3. **The differential gate agrees on six arms** in program mode and five in function mode,
   against the unchanged declared `stdout`/`stderr`/`exit`/`want` values, exits 0, its summary
   names all six arms, **and its summary reports a per-arm case-run count in which the `go`
   count equals the `python` count and is nonzero** — a forwarding or stub arm cannot fill a
   counter that only `run_go`/`build_go` increment.

Toolchain verified this session: `go version go1.26.4 darwin/arm64` at `/opt/homebrew/bin/go`.
No new dependency is installed — the Go toolchain is assumed present, as `rustup` and `tsc` are.

### Decisions (recorded, each the laziest correct option)

**D1 — Single-package layout: emit `rt.go` + `main.go` into one temp dir, both `package main`,
no `go.mod`, no import.** Verified this session: `go build -o prog rt.go main.go` and
`go vet rt.go main.go` both work with explicit file arguments **outside any module**, and `go
vet` accepts a `package main` with no `func main` (exit 0) while `go build` rejects it
(`runtime.main_main·f: function main is undeclared in the main package`) — which is why the
corpus column vets and the differential builds. The checked-in `backend/golang/rt/rt.go` keeps
its `package rt` declaration for its module home (`backend/golang/go.mod`, `module agentscript`);
the build step rewrites that one line to `package main` at copy time. Consequence: prelude `go`
templates reference runtime helpers by **bare CamelCase name** (`Add(a, b)`, not `rt.Add(a, b)`)
— Go has no package self-alias, and a module-import shape (`import "agentscript/rt"` + a
`replace` directive in a temp `go.mod`) buys nothing but scaffolding. The single-package shape
also matches the one-artifact linking model every backend uses (`to_rust.py` header: imports are
linked into one output file; per-module emission would need a build driver before a single
fixture could be gated).

**D2 — Sum types: `defenum` lowers to a tagged struct; `defschema` to a plain Go struct.**

- `defenum` → `type <Name>[T, …] struct { Tag string; Args []any }` plus one exported
  constructor function per case. `Args []any` gives variable arity, and the interface/slice
  indirection makes recursive enums legal without a boxing step — the direct analog of the TS
  backend's tagged objects with positional `_{i}` fields (`backend/to_typescript.py:295-318`),
  which is the only sum-type shape the differential's canonical JSON already agrees on
  (`["tag", args…]`).
- `match` lowers to `switch <subj>.Tag` with positional type assertions
  `Args[i].(<declared type>)` on the bound names — the transpiler knows each case's declared
  parameter types, so no runtime reflection is needed. Two emission rules the transpiler MUST
  implement, stated so no generic fixture burns a fix pass rediscovering them:
  1. **Nullary generic constructors carry an explicit instantiation.** `Leaf()` with an
     unconstrained type parameter cannot infer `T` (`cannot infer T`) — constructors emit
     `Leaf[T]()` (explicit type arguments) wherever a case is nullary and the enum is generic.
     `core/trees.agentscript`'s `(defenum {T} Tree …)`, imported by fixture 10, is exactly this
     shape.
  2. **Assertion targets at type-parameter positions.** Where a match arm's declared payload
     type is the enum's own type parameter, the assertion names the enclosing defun's type
     parameter (`Args[i].(T)`, legal Go); where the declared type is itself an instantiated
     user generic, the assertion uses the instantiated form (`Tree[int64]`), never the bare
     name.
- `defschema` → an ordinary Go struct with named fields; a field whose type mentions the
  declaring schema becomes `*Name` (the analog of Rust's `Box`, `to_rust.py:195-201`), and
  field access on such a field dereferences.
- `IoError` in `rt.go`: `type IoError struct { Tag string }` with the six zero-arity case
  constructors (`NotFound()` … `Other()`) and a `caseName()` accessor — the Go twin of
  `rt.rs:255-272` and `rt.ts:640-646`.

**D3 — Numerics: Int32→`int32`, Int64→`int64`, Float64→`float64`; checked ops become generic
runtime functions.** One `Number` constraint (`~int32 | ~int64 | ~float64`) with an internal
type switch on `any(a).(type)` — Go generics cannot switch on a type parameter directly but can
on a converted interface. `Add`/`Sub`/`Mul`/`Neg`/`Abs` trap with `rt.rs`'s exact messages
("overflow in addition", "overflow in subtraction", "overflow in multiplication", "overflow in
negation", "overflow in absolute value", `backend/rust/rt.rs:37-51`); `Div`/`Rem` gain the
`MinInt64 / -1` overflow trap the existing `rt.go` `Div` lacks (`rt.go:33-38` checks only
`b == 0`) — Go's bare `/` **silently wraps** that quotient, where `rt.rs:68` expects "overflow
in division". The existing unchecked `Sum` (`rt.go`, plain `+`) routes through `Add`. `FmtF64`
(`rt.go:100`, `strconv.FormatFloat(x, 'g', …)`) is **replaced** by a port of the Python-repr
formatter at `backend/ts/rt.ts:353-402` — the `'g'` format disagrees on exponent thresholds,
`nan`/`inf` spelling, and `-0.0`, which is exactly the class of cross-arm divergence the
differential exists to catch. Honest limit, recorded: trap-path bytes are **not**
byte-comparable across arms (a Go panic's stderr text and exit 2 differ from Rust's exit 101
and Python's traceback) — no program-mode differential case exercises an arithmetic trap today,
and none is added; the trap messages match `rt.rs` for fidelity, not because the gate pins them.

**D4 — `try` lowering: panic/recover, mirroring the TS arm's shape.** `rt.go` gains
`type Thrown struct { Value any }`. `(try e)` lowers to an unwrap that yields the `Ok` value or
panics with `Thrown{err}` (the Go twin of `unwrap()` throwing `ASThrown`, `rt.ts:602`). A defun
whose body contains `try` (the `has_try` guard, `to_typescript.py:298-315`) is emitted as a
closure with a deferred `recover()` that converts `Thrown` back into the function's own `Err`
return value and re-panics anything else — an arithmetic trap is not a `Result` failure, same
rule as `guarded()`'s `throw e`. A defun is the only legal enclosing scope: the checker refuses
`try` inside a lambda (`checker/types_.py:577-581`, rule-5, pinned by
`grammar/corpus/semantic/try-in-lambda.agentscript`), and the Go transpiler mirrors the TS
arm's explicit reject (`to_typescript.py:440-443`) so the two new arms fail identically if the
checker is ever bypassed. This avoids the type plumbing Rust's `?` needs (the enclosing return
type) and is the same boundary shape every arm already uses.

**D5 — `IoError` mapping: `syscall.Errno` via `errors.As`, table identical to Python's.**
`runtime.py:269-273`: `2→not-found, 13→permission-denied, 17→already-exists, 20/21→invalid-path,
4→interrupted`, else `other`. `EINVAL` and `ENAMETOOLONG` fall to `other`, exactly as on both
duals (Python has no errno-22/63 key; Rust's match arm is `_ => IoError::Other`,
`rt.rs:271-272`). The Go arm is native darwin/linux only — there is no Go wasm arm in this
phase — so the WASI-vs-Unix errno divergence (PCP `c-7b9e`) does not arise, and the raw-errno
route is safe here because Go's `syscall.Errno` numbers on the hosts we run are the same Unix
numbers Python's table shares. The mapping lives in one exported function (`ErrnoToIoError`)
so the unit probe can call it directly. Unit-level, the probe pins **all six** mappings
including `EACCES→permission-denied`; differential-level, only `not-found` and
`permission-denied` have failing-path cases (see §5).

**D6 — Prelude templates: 107 new `"go"` keys alongside the existing `py/js/ts/rs`;
`prelude/generate.py:165` tuple `("py","js","ts","rs")` → `("py","js","ts","rs","go")`.**
Reference the `rs` templates for semantics (they are the closest native-compiled sibling);
write Go syntax fresh. The widening lands in the same item as the templates, before the gate
runs, so the validator actually covers the new target. The gate asserts key presence **and**
the widened validator's empty `go` list — key presence alone is the hole Phase 7's W1
documented (the un-widened validator finds no complaints and passes vacuously).

**D7 — Scope: the Phase 7 precedent holds — Go does NOT join `monomorphism.py`.**
`backend/monomorphism.py` compiles rustc + py_compile only (TS deliberately did not join).
`go build` acceptance is proven by `check_corpus.py`'s `go vet` column over the full corpus +
bench set and by `differential.py`'s `build_go`. Deferring is recorded here as the phase
decision; extending monomorphism to Go would be a separate, unclaimed decision. The residual
this leaves — the specific (builtin × instantiation) classes no gate reaches — is enumerated
in §5, so "the corpus instantiates the rest" is a checkable claim rather than a shrug.

### Anti-stub measures (what stops a wired-but-fake Go arm)

1. **Per-fixture independent acceptance** — the `go vet` column compiles each fixture's own
   emitted Go against its own copy of `rt.go`; a forwarding arm has nothing of its own to vet.
   Two fail-loud rules are gate-level, not conventions: a Go transpile failure appends to
   `check_corpus.py`'s `fails` exactly as the python/rust/ts columns do, and an empty emitted
   source is itself a `FAIL` (`"<name>: go backend emitted no source"`).
2. **Per-arm execution counters** — `differential.py` counts, per arm, how many cases that
   arm's runner actually executed in each mode, and the summary prints them
   (`python=N rust=N wasm=N interp=N ts=N go=N`, summed over both modes). W7's gate asserts
   the `go` count is nonzero and equals the `python` count. A `build_go` that forwards to
   another arm's binary, or a stub that hardcodes expected outputs, cannot fill a counter only
   the Go runner increments; a Go runner that silently short-circuits leaves the count short
   and the gate red.
3. **Six-arm summary string** — the differential summary names all six arms,
   `(python/rust/wasm/interp/ts/go)`; the gate greps for it.
4. **Raise, never skip** — `build_go`/`run_go` raise on transpile failure, empty emission, or
   `go build` failure, exactly as `build_typescript:387-403` does; a lowered-then-broken arm
   cannot degrade into a column of `-`.
5. **Byte-level declared values** — the program-mode `not-found`/`permission-denied` stderr
   lines are derived per arm from the host's own errno surface; the differential's
   byte-for-byte comparison plus W2's direct mapping probe (all six cases, unit level) pin
   that the Go arm runs its own runtime. A stub that hardcodes every fixture's declared bytes
   is still caught by measure 2's counter only if it runs through `run_go` — which is exactly
   the point: the counter counts Go-runner executions, not agreements, and the hardcoded stub
   that also ships a real `run_go` is a working backend, not a stub.

## §2 Inventory

**Recovered:** nothing — unlike Phase 7 there is no stash or fork artifact. The starting point
is the checked-in partial runtime `backend/golang/rt/rt.go` (~230 lines, `package rt`, module
`agentscript`, go 1.21): `Option`/`Some`/`None`, `Result`/`Ok`/`Err`, `Pair`, `Div`/`Rem`/
`CheckedDiv`/`CheckedRem`, string ops over `[]rune`, list/map/sort ops, `MGet`/`MSet`/`MKeys`/
`MValues`/`MPairs`/`MFrom`, `Sum`/`Least`/`Greatest`, `FmtF64`, `ToI64`/`ToF64`/`ToI32`/`FToI`.
**It does not compile today**: `None` declares `var z T` and never uses it
(`rt.go:22`), which Go rejects (`rt/rt.go:22:39: declared and not used: z`) — the first thing
W2 fixes, before any of its additions are measurable.

**New:**
- `backend/to_go.py` — the transpiler; clone of the `to_rust.py` skeleton (module linking via
  the `link()`/`closure()` machinery, `LOWER = {b["name"]: b["go"] …}` at `to_rust.py:36`,
  `host_entry()` at `to_rust.py:339-348` emitting `fn main` only when a `main` defun exists,
  template application, and the CLI shape `to_rust.py:729-731` — `file` plus a repeatable
  `--root`, which `check_corpus.py:35-37` and `differential.py:275`/`:382` both pass).
- 107 `"go"` templates in `prelude/prelude.json`.
- In `rt.go`: the I/O surface (IoError, errno mapping, read-line/read-all/print/file ops,
  `MainExit` — the twin of `rt.rs:226-320`), checked `Add/Sub/Mul/Neg/Abs` + `Div`/`Rem`
  overflow trap, the Python-repr `FmtF64`, `Thrown`, and the `Eq`/`Cmp` equality/ordering
  layer (D2/W2 item 8).
- A Go canonical-JSON serializer embedded as a string constant in `differential.py` (the twin
  of `_SER`, `differential.py:411-447`).
- `go_literal`/`go_type` in `differential.py` (the twins of `rust_literal:109` /
  `rust_type:101`).

**Modified:** `prelude/prelude.json`, `prelude/generate.py:165`, `backend/golang/rt/rt.go`,
`backend/check_corpus.py` (new `go vet` column mirroring the rustc column `:99-109` and the
tsc column `:110-122`), `backend/differential.py` (arm in both modes, tables, headers,
agree expressions, summary `:612`).

**Unchanged, verified:** `backend/monomorphism.py` (D7); `grammar/closure_audit.py` and
`backend/exec_coverage.py` are backend-independent — the coverage recorder instruments the
Python lowering only, so adding `go` templates moves no figure, same as Phase 7;
`checker/gate.py`, `grammar/validate.py` read names, not template keys. No existing gate is
weakened; every declared differential value stands.

## §3 Work items

### W1 — Prelude `"go"` templates and the generator tuple

**What changes:** `prelude/prelude.json` gains `"go"` on all 107 builtins, written fresh
against the `rs` templates' semantics, referencing `rt.go` helpers by bare CamelCase name (D1).
`prelude/generate.py:165`: tuple gains `"go"` (D6). Templates that do not format at their
declared arity are fixed in prelude.json, not weakened out of the validator. Go templates that
need a literal brace must double it — the same trap `validate_templates()` documents.

**Why:** acceptance 1; `to_go.py` reads `LOWER = {b["name"]: b["go"] …}` and cannot start
without them. The vocabulary stays one-source.

**Gate (fails now):**
```
.venv/bin/python -c "
import json
bs=json.load(open('prelude/prelude.json'))['builtins']
missing=[b['name'] for b in bs if 'go' not in b]
assert not missing, f'{len(missing)} builtin(s) lack a go lowering, first five: {missing[:5]}'
" && .venv/bin/python -c "
import sys; sys.path.insert(0, 'prelude')
from generate import validate_templates
bad = [x for x in validate_templates() if '[go]' in x or 'no go' in x]
assert not bad, f'{len(bad)} broken go template(s), first: {bad[:3]}'
" && .venv/bin/python prelude/generate.py --check
```
Current verbatim output of the first assert (measured this session):
```
AssertionError: 107 builtin(s) lack a go lowering, first five: ['+', '-', '*', '/', 'mod']
```

**Order justification:** every later item's transpile raises `KeyError: 'go'` without it;
W2–W7 all depend on this file existing in its new shape.

### W2 — Complete `rt.go`: compile fix, I/O surface, checked numerics, Eq/Cmp, Python-repr `FmtF64`

**What changes:** `backend/golang/rt/rt.go` gains and changes, mirroring `backend/rust/rt.rs`:
1. **the one-line compile fix the file needs to build at all** — `None`'s unused
   `var z T` (`rt.go:22`) is removed (`func None[T any]() Option[T] { return Option[T]{} }`);
   until this lands, every later gate fails on the copy step with
   `rt/rt.go:22:39: declared and not used: z` before any missing symbol;
2. `IoError` struct + six case constructors + `caseName()` (D2);
3. `ErrnoToIoError(err error) IoError` via `errors.As(&syscall.Errno)` with D5's table;
4. the I/O helpers — `ReadLine`, `ReadAll`, `PrintOut`, `Println`, `Eprintln`, `FileRead`,
   `FileWrite`, `FileAppend`, `FileExists`, `MainExit` (prints the case name to stderr, returns
   1; 0 on `Ok`) — the twins of `rt.rs:282-320`;
5. checked generic `Add`/`Sub`/`Mul`/`Neg`/`Abs`/`Div`/`Rem`/`CheckedDiv`/`CheckedRem` over a
   `Number` constraint with the rt.rs trap messages and the `MinInt64/-1` division trap;
   existing `Sum` routed through `Add` (D3);
6. `FmtF64` replaced by the port of `rt.ts:353-402` (D3);
7. `type Thrown struct { Value any }` (D4);
8. **the equality/ordering layer the live differential cases exercise:** `Eq(a, b any) bool`
   — deep, structural over lists/pairs/records/options/results/enums, NaN-aware (a value
   holding NaN equals nothing, including itself inside a container, `AGENT_SPEC_CORE.md:170-171`)
   — and `Cmp(a, b any) int` with the language's nan-last order (port of `rt.ts:105-186`'s
   `eq`/`cmp`, the pinned reference; semantics per `rt.rs:82-110`'s `unordered`/`nan_last`:
   a NaN-holding value sorts after every non-NaN-holding one, NaN-holding values tie, and the
   NaN test comes *first* so the comparator is transitive). Retargeted onto them:
   `Contains`/`IndexOf` lose their `[T comparable]` bound (`rt.go:156,164` — they will not
   compile at the `(List Float64)` instantiation case 25 demands), `Sort`/`SortBy`/
   `Least`/`Greatest` drop the bare-`<` `Ordered` comparators (`rt.go:173-177,235,247`) for
   `Cmp`-based ones (Go's `sort.SliceStable` does not detect a non-transitive comparator the
   way Rust's sort does — it silently mis-sorts), and `min`/`max` follow the sort order (NaN
   greater, `AGENT_SPEC_CORE.md:542-543`), keyed by a type switch on `any` like D3's shape;
9. `FToI`'s approximate bound (`x > 1.7e308`, `rt.go:120-126`) replaced by the 2^63 boundary
   the other arms use (`rt.rs:163-171`, `rt.ts:434-439`) — cheap while the file is open, and
   "the existing pure-core functions stand" must not bless a rule the language disagrees with
   at values no case happens to reach.

**Why:** every differential program case that matters (the failing I/O path, `main_exit`'s
stderr, the read/write round trip) is exactly this surface; cases `25-list-nan`,
`25-list-nan-identity`, `23-numeric-minmax`, `26-map-counts` and bench `histogram` (which
compares pair seconds with `=`) are what item 8 exists for — without it, `Contains`/`IndexOf`
do not compile at `(List Float64)` and `Sort`/`min`/`max` disagree on every NaN case. The
float formatter is what keeps function-mode serialization agreeable. The in-repo module build
must stay healthy so the checked-in runtime remains inspectable on its own.

**Gate (fails now)** — a behavioral probe compiled against the rewritten runtime; the probe
asserts: all six trap messages (`Add`, `Sub`, `Mul`, `Neg`, `Abs`, `Div(MinInt64, -1)`),
`FmtF64` on `{1.0, 1e16, 1e15, 0.1, -0.0, nan, inf, -inf}` matching Python's `repr`-derived
strings, `Eq`'s NaN-identity on a list holding NaN, `Cmp`'s nan-last order, and
`ErrnoToIoError` on `errors.New` (→ `other`) plus all five errno constants
(`ENOENT→not-found, EACCES→permission-denied, EEXIST→already-exists, ENOTDIR→invalid-path,
EINTR→interrupted`) injected through `*syscall.PathError`:
```
d=$(mktemp -d /tmp/p8-rt.XXXX) \
  && sed 's/^package rt$/package main/' backend/golang/rt/rt.go > "$d/rt.go" \
  && printf '%s\n' 'package main' 'import ("fmt"; "math"; "syscall"; "errors")' \
       'func mustPanic(msg string, f func()) { defer func() { if r := recover(); r == nil || fmt.Sprint(r) != msg { panic("bad panic: " + fmt.Sprint(r)) } }(); f() }' \
       'func main() {' \
       '  mustPanic("overflow in addition", func() { _ = Add(int64(1), int64(9223372036854775807)) })' \
       '  mustPanic("overflow in subtraction", func() { _ = Sub(int64(1), int64(-9223372036854775808)) })' \
       '  mustPanic("overflow in multiplication", func() { _ = Mul(int64(9223372036854775807), int64(2)) })' \
       '  mustPanic("overflow in negation", func() { _ = Neg(int64(-9223372036854775808)) })' \
       '  mustPanic("overflow in absolute value", func() { _ = Abs(int64(-9223372036854775808)) })' \
       '  mustPanic("overflow in division", func() { _ = Div(int64(-9223372036854775808), int64(-1)) })' \
       '  if FmtF64(1.0) != "1.0" || FmtF64(1e16) != "1e+16" || FmtF64(1e15) != "1000000000000000.0" || FmtF64(0.1) != "0.1" { panic("fmt") }' \
       '  if FmtF64(math.NaN()) != "nan" || FmtF64(math.Inf(1)) != "inf" || FmtF64(math.Inf(-1)) != "-inf" { panic("fmt2") }' \
       '  if FmtF64(math.Copysign(0, -1)) != "-0.0" { panic("fmt3") }' \
       '  xs := []float64{1, math.NaN()}' \
       '  if Eq(xs, xs) { panic("eq: NaN list equals itself") }' \
       '  if Cmp(math.NaN(), 1.0) <= 0 { panic("cmp: NaN must sort last") }' \
       '  if ErrnoToIoError(errors.New("x")).caseName() != "other" { panic("map") }' \
       '  for _, tc := range []struct{ e error; want string }{' \
       '      {&syscall.PathError{Err: syscall.ENOENT}, "not-found"},' \
       '      {&syscall.PathError{Err: syscall.EACCES}, "permission-denied"},' \
       '      {&syscall.PathError{Err: syscall.EEXIST}, "already-exists"},' \
       '      {&syscall.PathError{Err: syscall.ENOTDIR}, "invalid-path"},' \
       '      {&syscall.PathError{Err: syscall.EINTR}, "interrupted"},' \
       '  } { if got := ErrnoToIoError(tc.e).caseName(); got != tc.want { panic("map: " + got) } }' \
       '  println("RT-PROBE-OK")' \
       '}' > "$d/probe.go" \
  && (cd "$d" && go build -o probe rt.go probe.go && ./probe) | grep -q RT-PROBE-OK
```
Current verbatim output of the build half (measured this session, both reviewers reproducing
independently — note this fires on the pre-existing line 22, not on a missing symbol):
```
./rt.go:22:39: declared and not used: z
```
(the missing `Add`/`FmtF64`/`ErrnoToIoError` symbols surface only after item 1 lands).

**Order justification:** W1's templates name these helpers; W3's transpiled output calls them.
Doing the runtime first means the transpiler item's gate measures lowering, not a half-built
runtime — and not an unbuildable one.

### W3 — `backend/to_go.py`: special forms, types, host entry

**What changes:** `backend/to_go.py`, cloned from the `to_rust.py` skeleton and adapted:
- `LOWER` keyed on `"go"`; `PRIM` → `Bool:bool, Int32:int32, Int64:int64, Int:int64,
  Float64:float64, String:string, Unit:struct{}, IoError:IoError` (bare names, D1);
- CLI: `file` positional plus repeatable `--root`, matching the existing transpilers' parser
  shape (`to_rust.py:729-731`) — `check_corpus.py:35-37` and `differential.py:275`/`:382`
  pass `--root` unconditionally, so a transpiler without it turns W4/W5 into argparse errors
  instead of linking diagnostics;
- `mangle` extended for Go keywords, predeclared identifiers (`func type range map chan go
  defer select len cap make new append copy delete min max clear …`), **and `main`** — which
  is neither a keyword nor predeclared but is the package's entry symbol: five corpus fixtures
  declare `(defun ! main [(args (List String))] …)` (`08-io:22`, `13-module-program:19`,
  `14-sequenced-bodies:52`, `15-shadowed-binders:22`, `19-io-errors:48`), and emitting
  `func main(args []string)` beside the host `func main()` is rejected
  (`func main must have no arguments and no return values`). The user defun is emitted as
  `Main_` and the host entry calls the mangled name — mirroring `to_rust.py:62-63`, which
  reserves `main` for exactly this reason;
- module linking: the `link()`/`closure()` machinery verbatim, with linked modules flattened
  into the single output file under defining-path prefix names (the `rust_mod` mangling,
  `to_rust.py:68-74`) plus the prefix-collision check — Go has no nested `pub mod`, so the
  flat-prefix form is the single-package equivalent;
- `defenum`/`defschema` per D2 **including both emission rules** (explicit instantiation for
  nullary generic constructors; type-parameter and instantiated-form assertion targets);
- `match` as `switch` + positional type assertions with the same scope/pattern machinery
  (cons/list patterns lower to slice patterns on `Args`, which needs the slice-match handling
  `to_rust.py` does with `as_slice()`);
- `try_form`/`guarded` per D4, **with the explicit reject**: `has_try` inside a `fn` (lambda)
  raises `NotImplementedError` with the same rationale as `to_typescript.py:440-443` — the
  checker refuses the form (rule-5, `checker/types_.py:577-581`), the semantic fixture pins
  the refusal, and the transpiler-side guard keeps the two new arms' failure surface identical;
- Go's unused-variable/unused-import compile errors handled at emission: bindings never read
  are discarded (`_ = x`), and no import is emitted unless the unit needs it — a Go transpiler
  that emits `import "os"` for a library fixture fails `go vet`;
- `host_entry()`: `func main() { os.Exit(MainExit(Main_(os.Args[1:]))) }` emitted only when a
  `main` defun exists (the twin of `to_rust.py:339-348`), calling the **mangled** name
  (`Main_`), with `os` imported only then.

**Why:** the smallest unit every later item builds on: one no-import fixture transpiles and
compiles end to end.

**Gate (fails now)** — transpile a no-import fixture, compile with `go vet` (accepts a main
package without `func main`, verified), and for the module-less fixture assert a clean build
via a stub main only when none is emitted:
```
d=$(mktemp -d /tmp/p8-basics.XXXX) \
  && .venv/bin/python backend/to_go.py grammar/corpus/valid/01-basics.agentscript > "$d/main.go" \
  && sed 's/^package rt$/package main/' backend/golang/rt/rt.go > "$d/rt.go" \
  && grep -q 'func main' "$d/main.go" || printf 'package main\nfunc main() {}\n' > "$d/zzmain.go" \
  && (cd "$d" && go vet main.go rt.go $( [ -f zzmain.go ] && echo zzmain.go ))
```
Current verbatim output of the first command (measured this session):
```
/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python: can't open file '/Users/purplelephant/projects/asex/backend/to_go.py': [Errno 2] No such file or directory
```

**Order justification:** needs W1 (templates) and W2 (helpers the emitted code calls); W4–W6
are each a widening of the surface this item proves on the minimal fixture.

### W4 — Module linking end to end, and the enum/match structural pin

**What changes:** exercised by W3's ported `link()`; this item's gate is the first time the
linking machinery meets a real module fixture. Any fix is in `to_go.py`'s prefix/alias
handling — no new files. The gate also pins the `defenum`/`match` lowering structurally:
transpiling `06-module.agentscript` — whose `Shape` has a nullary case (`point`), a one-arg
case (`circle`), and a two-arg case (`rectangle`), with `area` matching all three — and
asserting the emitted source contains all three case labels and the correct positional
assertions catches a swapped argument index, a wrong assertion type, or a dropped binding at
emission time, statically, rather than as a runtime panic on an unexercised path.

**Why:** `check_corpus.py` globs every valid fixture and seven of them use modules (06, 09–13,
15 — same set Phase 7 verified); program-mode differential cases 13/15 need linking. Without
linking, the corpus column is a wall of FAIL with no diagnostic value; without the structural
pin, a wrong `Args[i].(<type>)` compiles clean (`go vet`/`go build` accept any syntactically
valid assertion) and panics only on paths the corpus rarely reaches — `13-module-program`
feeds `area` only `rectangle`, and no differential case matches all three `Shape` cases, so
only the structural assertion closes the class.

**Gate (fails now)** — transpile the module-program fixture, assert the defining-path prefix
mangling is present in the emitted source (so a `link()` that discards imports and emits a
root-only file fails even if `go vet` would accept its output), transpile `06-module` and
assert the three match cases and the positional assertion shape, then vet both:
```
d=$(mktemp -d /tmp/p8-mod.XXXX) \
  && .venv/bin/python backend/to_go.py grammar/corpus/valid/13-module-program.agentscript \
       --root grammar/corpus/modules > "$d/main.go" \
  && .venv/bin/python backend/to_go.py grammar/corpus/valid/06-module.agentscript \
       --root grammar/corpus/modules > "$d/mod06.go" \
  && sed 's/^package rt$/package main/' backend/golang/rt/rt.go > "$d/rt.go" \
  && grep -qE '[a-z0-9]+_[a-z0-9]+_' "$d/main.go" \
  && grep -F 'case "circle"' "$d/mod06.go" && grep -F 'case "rectangle"' "$d/mod06.go" \
  && grep -F 'case "point"' "$d/mod06.go" \
  && grep -F 'Args[0].(float64)' "$d/mod06.go" \
  && printf 'package main\nfunc main() {}\n' > "$d/zzmain.go" \
  && (cd "$d" && go vet main.go mod06.go rt.go zzmain.go)
```
Current output: the transpiler does not exist (W3's gate output); after W3 lands, the gate
fails on the first real linking or lowering defect it finds, if any.

**Order justification:** W3 must exist first; W6's corpus-wide column and W7's program-mode
cases 13/15 both route through this.

### W5 — The failing I/O path end to end

**What changes:** none beyond W2/W3/W4's artifacts — this is the first behavioral gate: the
08-io fixture's failing write must produce exactly the declared bytes on the Go arm.

**Why:** program mode compares `stderr` + `exit` byte-for-byte against declared values
(`differential.py:417-421`, `:435-439`); the declared `not-found`/`permission-denied` stderr
lines are what D5's mapping + `MainExit` produce and nothing else can. Honest scope note, as
in Phase 7: the differential pins only `not-found` and `permission-denied` by failing-path
bytes; `already-exists`/`invalid-path`/`interrupted`/`other` are pinned at unit level by W2's
probe — **all five errno constants, not two** — matching the posture recorded in
`prelude/coverage.lock` for the TS arm.

**Gate (fails now):**
```
d=$(mktemp -d /tmp/p8-io.XXXX) \
  && .venv/bin/python backend/to_go.py grammar/corpus/valid/08-io.agentscript \
       --root grammar/corpus/modules > "$d/main.go" \
  && sed 's/^package rt$/package main/' backend/golang/rt/rt.go > "$d/rt.go" \
  && (cd "$d" && go build -o prog main.go rt.go) \
  && printf 'hello from a file\n' > "$d/sample.txt" \
  && (cd "$d" && ./prog sample.txt nodir/out.txt > out.txt 2> err.txt; test $? -eq 1) \
  && test ! -s "$d/out.txt" && test "$(cat "$d/err.txt")" = "not-found"
```
Current output: fails at the first command, exactly as W3's gate does (no `to_go.py`); after
W3–W4 land it still fails unless the errno mapping and `MainExit` produce the declared bytes.

**Order justification:** needs W2 (I/O surface), W3 (transpiler), W4 (this fixture imports a
module); W7's program-mode agreement is only meaningful after this byte-level check.

### W6 — `check_corpus.py` gains the Go column

**What changes:** `backend/check_corpus.py`: for every fixture in `CORPUS`, a `go` transpile
column (`transpile("to_go.py", f)` alongside `:74`) and, for successful transpiles, a `go vet`
compile step mirroring the rustc step `:99-109` — rewrite `rt.go`'s package line, write the
emitted source, `go vet <files>`; a fixture with no emitted `func main` vets fine as-is
(verified this session: `go vet` exits 0 on a main package without `main`; `go build` would
reject it, which is why the column vets and `build_go` builds). Header widened. Two fail-loud
rules, same as the TS column: a Go transpile failure appends to `fails` exactly as the
python/rust/ts columns do; an empty emitted source is itself a `FAIL`
(`"<name>: go backend emitted no source"`).

**Why:** acceptance 2, and the doctrine this file enforces: parsing proving well-formed is not
the target accepting it. The differential only runs fixtures with declared cases; this runs
all of them, including the bench sources — and it is anti-stub measure 1.

**Gate (fails now):**
```
.venv/bin/python -c "
import pathlib
s = pathlib.Path('backend/check_corpus.py').read_text()
assert 'to_go' in s, 'check_corpus.py has no go column'
" && .venv/bin/python backend/check_corpus.py
```
Current verbatim output of the assert half (measured this session):
```
AssertionError: check_corpus.py has no go column
```

**Order justification:** W3–W5 must land first or the column is a wall of FAIL with no
diagnostic value; running before W7 means the differential arm joins a corpus that already
vets clean, so any disagreement W7 finds is semantics, not syntax. W6 is also the toolchain
decision point: **`go vet` is the primary corpus gate** because it is a superset of
type-checking (it runs the compilers' checks plus the analyzers), while plain `go build`
remains what `build_go` and W5 run. If `go vet`'s analyzers reject a legitimate emitted
construct anywhere in the corpus, the emission is fixed — and if a vet analyzer is genuinely
wrong for generated code, switching the corpus column to plain `go build` + `gofmt -e` is a
recorded gate-scope decision for the orchestrator, shown with the failing construct verbatim,
never an absorbed silent change.

### W7 — Differential: the Go arm in both modes

**What changes:** `backend/differential.py`:
- `go_type`/`go_literal` mirroring `rust_type:101`/`rust_literal:109` (integers as
  `int64(n)`/`int32(n)`, nonfinite as `math.NaN()`/`math.Inf(±1)`, lists as typed `[]T{…}`),
- `run_go(src, task)` (function mode): transpile, copy the package-rewritten `rt.go`, emit a
  driver `main.go` carrying the entry calls plus the embedded Go serializer (`_SER`'s twin,
  `differential.py:411-447`, **including its map rule, stated not implied**: keys rendered
  through the same canonical spelling as values — strings JSON-quoted, ints bare, booleans
  `true`/`false`, floats via the `FmtF64`-derived rule — and entries emitted in `Cmp` order
  over the canonicalized key strings; Go range order is randomized, so an unsorted or
  wrong-format map is a guaranteed disagreement, which is why the rule is explicit), `go build
  -o drv main.go rt.go`, run, `json.loads` — mirroring `run_rust:234-259`;
- `build_go(src, d)` (program mode): transpile, raise on empty emission (the
  `build_typescript:392-393` rule), write `main.go` + rewritten `rt.go`, `go build -o prog`,
  return the binary path — mirroring `build_rust:337-348`;
- **per-arm execution counters**: a dict incremented after each arm's output is captured, in
  both modes; the summary prints `python=N rust=N wasm=N interp=N ts=N go=N` (summed over
  function + program cases) beside the arm list. Only the Go runner increments the `go`
  count, so a forwarded column or an arm that never runs leaves it short;
- `functions()`'s length guard extends to include the go list, the table header gains a
  `go` column, and the per-case agree expression gains it; `programs()`' runner dict `:499`
  gains `"go": build_go(src, d)`, the agree expression `:515` gains `seen["go"]`, its header
  gains a `go` column; the summary `:612` becomes
  `(python/rust/wasm/interp/ts/go)`. Declared case values and existing arms untouched. Exit
  code stays the disagreement count.

**Why:** acceptance 3. This is the gate that has caught cross-target defects nothing else
could (I/O mapping, nested-form lowering); Go joins the property instead of claiming it. The
summary string, the per-arm counters, and the non-empty-emission rule are anti-stub measures
2, 3, and 4.

**Gate (fails now)** — the assert half, then a full run that must exit 0 (zero disagreements),
print a summary naming all six arms, and print per-arm counts in which `go` equals `python`
and is nonzero:
```
.venv/bin/python -c "
import pathlib
s = pathlib.Path('backend/differential.py').read_text()
assert 'build_go' in s, 'differential.py has no go arm'
" \
  && out=$(.venv/bin/python backend/differential.py) || { printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q "python/rust/wasm/interp/ts/go"
.venv/bin/python - "$out" <<'EOF'
import re, sys
counts = dict(re.findall(r"(\w+)=(\d+)", sys.argv[1]))
assert counts.get("go") and counts["go"] == counts["python"] and counts["go"] != "0", \
    f"per-arm run counts wrong: {counts}"
EOF
```
Current verbatim output of the assert half (measured this session):
```
AssertionError: differential.py has no go arm
```

**Order justification:** last — the integration point over everything W1–W6 produce; running
it earlier would measure an incomplete backend and burn the one-fix-pass budget on findings
W2–W5's cheaper gates already catch.

## §4 Acceptance battery (the phase is done when all of these pass, in this order)

1. `.venv/bin/python grammar/validate.py`
2. `.venv/bin/python grammar/closure_audit.py`
3. `.venv/bin/python prelude/generate.py --check`
4. `.venv/bin/python checker/gate.py`
5. `.venv/bin/python backend/check_corpus.py`   ← now includes the `go vet` column
6. `.venv/bin/python backend/monomorphism.py`   ← unchanged (D7: Go does not join)
7. `.venv/bin/python backend/differential.py`   ← six arms in program mode, five in function
   mode; summary names all six arms and reports per-arm case-run counts with `go == python`
8. `.venv/bin/python -m pytest backend/t bench/algo checker/t -q`
9. No new coverage floor: `backend/exec_coverage.py` instruments the Python lowering only, the
   `go` templates never enter `to_python.LOWER`, and the figures are data in
   `prelude/coverage.lock`. They are expected to be unchanged by this phase; if any figure
   moves anyway, it moves in the commit that earns it, per AGENTS.md.

## §5 Risks

- **`mangle` collisions against Go keywords and predeclared identifiers** — the corpus
  identifiers were never screened for Go's (e.g. `len`, `min`, `map` as a binder name). W3's
  extended `mangle` handles the known set; a collision outside it surfaces as a `go vet`
  failure at W6 with the offending fixture named. Contained and local.
- **Unused-variable/unused-import emission** — Go rejects both at compile time where Rust
  warns. W3's emission rules cover the general shapes; a corpus form that binds and never
  reads surfaces at W6. The fix is emission-side, never a gate weakening.
- **`go vet` analyzer false positives on generated code** — vet's default analyzers
  (printf, copies, etc.) may flag idiomatic-but-unusual emitted shapes. The decision point is
  W6 (see its gate note): fix the emission; a switch away from vet is an orchestrator decision
  recorded with the failing construct shown verbatim.
- **Trap paths are pinned by no differential case** — overflow/division-by-zero stderr bytes
  are not byte-comparable across arms (D3); the messages match `rt.rs` by choice and all six
  are unit-pinned by W2's probe. If a future phase wants cross-arm trap agreement, it needs a
  new case design, not an assumption that today's gate covers it.
- **Four IoError cases have no failing-path differential case** — `already-exists`,
  `invalid-path`, `interrupted`, `other` are pinned at the unit level only (W2's probe, which
  covers all five errno constants plus the fallback), the same posture as the TS arm. Nobody
  should mistake the differential's 2/6 stderr pinning for full mapping coverage — D5's "table
  identical to Python's" is proven at the unit layer, not by the differential.
- **`FmtF64` port fidelity, with the pinned values named** — what the corpus pins:
  `1.8014398509481984e+16` (the exp10==16 threshold, `23-numeric-float`), `-0.0`
  (`29-literal-floats`), `0.1` and `42.0` (`28-string-transforms`),
  `2.3333333333333335` (shortest round-trip). What only W2's unit probe pins: the `1e15`
  threshold (Python switches to exponent at decimal exponent 16), `nan`/`inf`/`-inf` spelling,
  and `1.0`. A discrepancy outside both sets would agree with itself across Go/Python only if
  Python's own repr also drifted — the declared values are the backstop.
- **EPERM (errno 1) mapping asymmetry** — the raw-errno table inherits Python's
  13-only permission mapping, while Rust's `ErrorKind::PermissionDenied` folds EACCES and
  EPERM alike (`rt.rs:256-272`). Identical to the existing Python/Rust asymmetry and
  unreachable on the seeded 0o000 case (EACCES on darwin), but it is a cross-arm divergence
  waiting for a host that returns EPERM. Recorded, not actionable in this phase.
- **Case-name collisions across modules** in the flattened single package rely on the
  checker's global case-name uniqueness; if it does not enforce it, a duplicate constructor is
  a compile error named at W6 — fail-loud, contained.
- **Enum/match lowering residual** — the corpus exercises enum `match` bodies in program mode
  (fixture 13 through `describe`, 08-io's `(err (not-found))` pattern), and W4's structural
  pin asserts `06-module`'s three `Shape` cases with correct positional assertion types.
  Payload types no fixture binds positionally (the remaining enum cases: `Blob`, `Tree`'s
  `node`, all six `IoError` cases except `not-found`) are covered by D7's recorded residual,
  same posture as the TS arm's `any` assertions.
- **Monomorphism deferred (D7), with the unenforced classes named** — the residual is not
  one sentence but a list: arithmetic at Int32 for `-`, `*`, `/`, `mod`, `min`, `max`, `abs`,
  `neg`, `checked-div`, `checked-mod` (only `+` is exercised at Int32, via `29-literals`'s
  `step` — but the corpus column compiles that fixture, so the generic constraint is at least
  proven to instantiate at `int32`); `string-to-float64` on non-ASCII digit inputs (Python
  rejects them, Rust accepts them — a Go port must pick a side and no case pins it); and
  every other (builtin × concrete instantiation) in the admissible set that neither the corpus
  nor the differential executes. Closing this later should close it for `ts`/`js` at the same
  time.
- **`errors.As` + `syscall.Errno` on the stdin path** — file errors reliably wrap
  `*syscall.Errno` via `*os.PathError`; whether a failing stdin read surfaces the same errno
  shape is unverified until W5/W7 run the `--slurp`/read cases. If stdin errors present
  differently, the fix is inside `ErrnoToIoError`'s unwrapping, not the table.
- **`permission-denied` observability on macOS** — the differential seeds a `0o000` file
  (`differential.py:436-437`); pre-existing condition, python/rust/wasm/ts pass today, so Go
  should see the same errno. If not, that is a genuine disagreement the gate is designed to
  catch.
- **Go version drift** — gates pin nothing; `go1.26.4` is what this machine has and go 1.21 is
  the module floor in `backend/golang/go.mod`. Generics + `any` type-switch semantics used by
  D2/D3 are stable across both.
