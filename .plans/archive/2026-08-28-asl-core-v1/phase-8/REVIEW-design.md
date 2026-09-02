# Phase 8 REVIEW — design and feasibility lens

Reviewer: steps-architect-pro (critic, design lens). Scope: D1–D7 design soundness,
constitution check, gate feasibility. Every claim below cites a path:line the reviewer read
this session; probes were run in `/tmp` only.

## Verdict

**approve-with-amendments** — two blocker findings, both with cheap, well-specified fixes.
The architecture (single-package emission, panic/recover `try`, raw-errno mapping, TS-precedent
scope) is sound and several of its riskiest claims were re-verified by probe. The plan cannot be
implemented as written because (B1) the checked-in runtime does not compile and W2's item text
forbids the fix, and (B2) an entire runtime component the differential pins — NaN-aware deep
equality and ordering — is absent from the plan's inventory.

## Constitution check

No `.factory/CONSTITUTION.md` or `CONSTITUTION.md` exists anywhere in the tree
(Glob over `**/CONSTITUTION.md`, zero matches). Nothing to enforce; no violation possible.

## Verified-true claims (the plan got these right)

- `go vet` exits 0 on a `package main` without `func main`, outside any module; `go build`
  rejects it with `function main is undeclared in the main package` — reproduced this session
  in `/tmp/p8-verify.*`. The corpus column can vet, `build_go` can build. D1 holds.
- `sed 's/^package rt$/package main/'` matches `backend/golang/rt/rt.go:8` exactly; the
  copy-time rewrite shape is robust (single anchored line, no other `package` lines in the file).
- `errors.As(err, &syscall.Errno)` surfaces the errno for real file failures on darwin: probed
  ENOENT=2 (open missing), EACCES=13 (chmod 0 then open), EEXIST=17 (O_CREATE|O_EXCL),
  ENOTDIR=20 (write through a file path) — all surfaced through `*os.PathError`/`*os.LinkError`
  unwrapping. D5's route is feasible; the Python table (`backend/runtime.py:269-273`) matches.
- Go silently wraps `MinInt64 / -1` (language spec: two's-complement wrap, no panic; the spec's
  own example), so D3's added trap is genuinely needed — the checked-in `Div`
  (`backend/golang/rt/rt.go:40`) has no MinInt64 check.
- A type assertion to a **type parameter** compiles and works on the tagged-struct shape
  (`xs.Args[0].(T)` probed OK in `/tmp/p8-alt3`), so D2's `Args[i].(<declared type>)` is legal
  Go even where the declared type is a generic parameter.
- The type-safer D2 alternative (per-case structs behind a generic interface + type switch)
  compiles and discriminates, but **type inference fails on zero-arity constructors**
  (`cannot infer T`, probed twice in `/tmp/p8-alts`, `/tmp/p8-alt2`) and forces per-case type
  bookkeeping plus a rewritten serializer. The plan's tagged-struct call is the lazier correct
  option. D2 stands as the right trade — see M2 for the amendment it needs.
- `try`-in-lambda is unreachable by construction: the checker rejects it
  (`checker/types_.py:577-581`, rule-5) and the semantic fixture
  `grammar/corpus/semantic/try-in-lambda.agentscript:10` pins the rejection. The TS arm's
  explicit reject (`backend/to_typescript.py:440-443`) is belt-and-braces only.
- No function-mode differential source declares a `main` defun (grep over all 25 case `src`
  files), so the synthesized driver cannot collide with an emitted host entry on today's case
  set. `01-basics` declares no `main`, so W3's stub-main gate shape is correct.
- D4's re-panic rule is airtight as designed: `recover` converts only `Thrown` (panic values
  carry a Go type tag, so the `_, ok := r.(Thrown)` test cannot mistake an overflow-trap string
  for a Result error); overflow/`Div` traps re-panic and propagate; a `try`-guarded defun can
  never swallow another defun's `Thrown` because the inner guard converts it to a *return value*
  before it crosses the boundary. Panics in `!` defuns reach the goroutine top unless a guard
  converts them — and guards exist only in `Result`-returning defuns, exactly the other arms'
  invariant.
- Line anchors spot-checked: `rt.ts:353` (`fmtF64`), `rt.ts:602` (`unwrap`), `rt.rs:37-41`
  (trap messages), `rt.rs:68` (division trap), `rt.rs:234` (IoError), `to_rust.py:63`
  (`"main"` in the Rust mangle reserved set), `differential.py:499/514-517/612`,
  `generate.py:165` tuple `("py","js","ts","rs")`, `check_corpus.py:99/110` columns.

## Findings

### BLOCKER B1 — the checked-in `rt.go` does not compile; W2's item text forbids the fix

`backend/golang/rt/rt.go:22` is `func None[T any]() Option[T] { var z T; return Option[T]{} }`
— `z` is declared and not used, which Go rejects. Reproduced three ways this session:
`go build ./...` in `backend/golang` fails with `rt/rt.go:22:39: declared and not used: z`;
and the W3/W4/W5 gate shape (`sed` rewrite + explicit-file build) fails with the same error as
the FIRST diagnostic, before any missing symbol. Consequences:

1. The module build the plan claims "must stay healthy" (§2, W2) is broken **today**.
2. Every gate in W2–W7 fails at the rt.go copy step until line 22 changes, for a reason none
   of them name.
3. W2's "What changes" item 6 plus its closer — "The existing pure-core functions stand; only
   `Sum` and the two `Div`/`Rem` trap gaps change" — excludes the one edit that makes anything
   build. Implementing W2 to its written scope leaves every later gate red for a reason the plan
   never budgeted a fix pass for.
4. W2's recorded "current verbatim output" (`undefined: MainExit`) is not what the build prints
   first; the recorded failure mode is wrong, so the gate's before-state is mislabeled.

**Amendment:** W2's scope gains the one-line fix (`None` needs no `var z` at all —
`return Option[T]{}` suffices, or drop the declaration); W2's recorded current output is
re-measured. This is a plan-text fix, not a design change.

### BLOCKER B2 — the Eq/Cmp runtime layer the differential pins is missing from the plan

The plan's W2 inventory lists IoError, errno mapping, I/O helpers, checked numerics, `FmtF64`,
`Thrown`. It omits the equality and ordering layer that live differential cases exercise on the
Go arm:

- `(= a b)` is polymorphic (`T T -> Bool`, prelude.json `=` entry). `backend/cases/25-list-nan-identity.json`
  calls `nan-identity`, which runs `(= xs xs)` over `(List Float64)` holding NaN and expects
  `F` (`grammar/corpus/valid/25-list-aggregation.agentscript:88-91`). Spec: NaN equals nothing,
  "including inside a container" (`AGENT_SPEC_CORE.md:170-171`). Go `==` is unusable twice over:
  it is identity-true for NaN, and composite types are not `==`-able at all.
- `list-contains?`/`list-index-of` lower to `Contains`/`IndexOf`, bounded `[T comparable]`
  (`backend/golang/rt/rt.go:156,164`) — same fixture passes a `(List Float64)` through them
  (`:89`). The checked-in helpers will not compile at the instantiation the case demands;
  they need deep NaN-aware equality. The plan routes `Sum` through checked `Add` but never
  mentions these two.
- NaN-last ordering: `backend/cases/25-list-nan.json` pins sorted output `[..., nan]` and
  min/max behavior; `23-numeric-minmax.json` pins `min`/`max` with NaN in both operand
  positions. The checked-in `Sort`/`Least`/`Greatest` use bare `<` on an `Ordered` constraint
  (`rt.go:173-177,235,247`) — NaN sorts nowhere deterministic and `Sort`'s comparator is not
  transitive (Go's `sort.SliceStable` may silently mis-sort; it does not detect like Rust does).
  The language's order is `rt.rs:95-110`'s nan_last; the Go twin does not exist and is not in
  the plan.
- `min`/`max` builtins (`N N -> N`, prelude.json) must follow the sort order, NaN greater
  (spec table rows at `AGENT_SPEC_CORE.md:542-543`); `SortBy` keys can be NaN
  (`rank` in the same fixture, `:77-79`).
- `histogram` (the only bench task, `bench/tasks/histogram.json`) compares pair seconds with `=`
  (`bench/algo/variants/tight.agentscript:16`) and returns a Map — it needs equality AND the
  serializer (M3).

The differential compares against declared values (`backend/differential.py:514-517`), so these
cases fail the Go arm loudly — nothing ships silently wrong. But W2 as scoped cannot produce a
runtime that passes W7, and the plan never allocates the work. **Amendment:** W2 gains an item
7 — Go `Eq` (deep, NaN-aware, structural over lists/pairs/records/options/results/enums) and
`Cmp`/nan-last ordering (port of `rt.ts:105-186`'s `eq`/`cmp`, which is itself the pinned
reference), `Contains`/`IndexOf` retargeted at it, `Sort`/`SortBy`/`Least`/`Greatest` switched
to nan-last comparators. `Sort`'s key type also stops being the `Ordered` constraint — a type
switch on `any` like D3's is the established shape.

### MAJOR M1 — the `main` identifier collision is not on Go's mangle list

Fixture `08-io`, `13-module-program`, `19-io-errors` all declare `(defun ! main …)`
(`08-io.agentscript:22`, `13-module-program.agentscript:19`). The Rust backend reserves `main`
in `mangle` precisely for this (`backend/to_rust.py:62-63` comment: "the host entry this
backend emits would collide"). W3's mangle list names Go keywords and predeclared identifiers
but not `main` — which is neither. Emitting the user defun as `func main(args []string)` beside
`func main()` fails vet/build: probed in `/tmp/p8-main`, `go vet` reports
`func main must have no arguments and no return values`. Fail-loud at W6/W7, but it is the
first thing that breaks and the fix is one list entry. **Amendment:** W3's mangle set includes
`main` (and the host entry calls the mangled name), mirroring `to_rust.py:62-63`.

### MAJOR M2 — D2 needs two emission rules the plan does not state

1. **Zero-arity generic cases need an explicit instantiation.** `Leaf()` with an unconstrained
   type parameter cannot infer T (probed: `cannot infer T`). Constructors must emit
   `Leaf[T]()` / be called with explicit type arguments wherever a case is nullary and the enum
   is generic — `core/trees.agentscript`'s `(defenum {T} Tree …)` is exactly this shape and is
   imported by fixture 10.
2. **Assertion targets at type-parameter positions.** A `match` arm on `(t/Tree Int64)` binds
   payload positions whose declared type is `T` — the emitter must assert `Args[i].(T)` where
   `T` is the enclosing defun's type parameter (verified legal in `/tmp/p8-alt3`), and where the
   declared type is itself a generic user type it must emit the instantiated form
   (`Tree[int64]`), not the bare name. W3's bullet "positional type assertions … the transpiler
   knows each case's declared parameter types" is true but hides both rules; state them or the
   first generic-module fixture burns the fix-pass budget on a shape the design already settled.

The design itself holds: wrong assertions compile clean but the differential exercises enum
`match` bodies in program mode (fixture 13 prints through `describe`, 08-io's
`(err (not-found))` pattern), and D7's recorded residual covers the unexercised remainder —
same posture as the TS arm's `any`. The transpiler does not throw away information it has;
it uses the static type to write the assertion and accepts the runtime check as the cost of
Go's lack of sum types.

### MAJOR M3 — function-mode serializer: Map determinism unspecified

`backend/cases/26-map-counts.json` returns raw Maps (`{'a': 2, 'b': 1, 'c': 1}`) — the case's
own comment says "key order in the encoding does not follow insertion order". The TS serializer
sorts entries and renders float/bool/string keys through dedicated paths
(`backend/differential.py:411-447`, `_SER`'s `keySer`). W7's "embedded Go serializer" mentions
`["pair",…]`, `["tag",…]`, "maps sorted" in one clause but gives no key-rendering rule; Go
range order is randomized, so an unsorted or wrong-key-format map is a disagreement the gate
will catch — after the fact. **Amendment:** W7 names the Go serializer's map rule explicitly:
keys rendered through the same canonical spelling as values (floats via `FmtF64`-derived rule,
ints bare, strings JSON-quoted), entries emitted in `Cmp` order — the `_SER` twin, line for
line.

### MINOR m1 — try-in-lambda: no explicit Go-side guard

TS rejects it in the transpiler (`to_typescript.py:440-443`); the plan says nothing for Go.
Unreachable after the checker (`checker/types_.py:577-581`), so not a blocker, but parity with
the explicit TS reject costs one `NotImplementedError` and keeps the two new arms' failure
surface identical. Recommended.

### MINOR m2 — W2 gate probe asserts less than its prose

The gate prose promises `FmtF64` checks on `{1.0, 1e16, 1e15, 0.1, -0.0, nan, inf}` and errno
probes on five constants; the literal probe in the gate block checks `1.0/1e16/0.1/nan/-inf`
and `ENOENT` plus one non-error value only. The 1e15 threshold (Python switches at decimal
exponent 16, per `rt.ts:353-360`'s comment), `-0.0`, and `EACCES/EEXIST/ENOTDIR/EINTR` are
asserted nowhere. Align the probe to the prose or cut the prose.

### MINOR m3 — `FToI`'s approximate bound survives, unmentioned

`rt.go:120-126` guards with `x > 1.7e308` rather than the 2^63 boundary the other arms use
(`rt.rs:163-171`, `rt.ts:434-439`). `from-float`'s cases (`1e30`, `9223372036854775808`,
`-9223372036854775808`) happen to pass through the approximation, so the differential pins it
green — but "the existing pure-core functions stand" blesses a rule that disagrees with the
language at values no case reaches today. Cheap to fix in W2 while the file is open; record it
if deferred.

### MINOR m4 — citation drift in two item references

`backend/check_corpus.py` rustc column is `:99-109` and tsc column `:110-122`, not `:104-108`
and `:119-120` as D1/W6 cite; `backend/to_rust.py`'s boxing rule `boxed()` is at `:195-201`,
not `:193-199`. Cosmetic, but the plan's evidence standard is path:line — fix or drop.

## Risks (unverified, recorded as uncertainty)

1. **MinInt64/-1 wrap under `go build` on this toolchain** is taken from the language spec and
   the plan's probe, not from a trap I executed myself — the W2 probe is the enforcement and is
   the right place for it.
2. **stdin errno shape** — `errors.As` was proven for file paths; a failing stdin read
   (`--slurp` case, `differential.py`'s 19-io-errors group) may surface a different error type.
   Plan records this; correct posture, fix stays inside `ErrnoToIoError`.
3. **EPERM (errno 1) mapping asymmetry** — Go's raw-errno table inherits Python's 13-only
   permission mapping, while Rust's `ErrorKind::PermissionDenied` folds EACCES and EPERM alike
   (`rt.rs:256-272`). Identical to the existing Python/Rust asymmetry and unreachable on the
   seeded 0o000 case (EACCES on darwin), but it is a cross-arm divergence waiting for a host
   that returns EPERM. Recorded, not actionable in this phase.
4. **Case-name collisions across modules** in the flattened single package rely on the checker's
   global case-name uniqueness; I did not verify the checker enforces it. If it does not, a
   duplicate constructor is a compile error named at W6 — fail-loud, contained.
5. **`go vet` analyzer false positives on generated code** — the plan's W6 decision point
   (fix emission; a move off vet is an orchestrator-recorded scope change) is the correct
   handling; no evidence yet that any analyzer will fire.
6. **Trap-path stderr bytes are pinned by nothing** (plan §5 says so itself); a future phase
   wanting cross-arm trap agreement needs new case design. Accepted as stated.

## What the gates get right (design-level)

The anti-stub battery holds: per-fixture independent vet (measure 1), six-arm summary grep
(measure 2), raise-never-skip builders mirroring `build_typescript:387-403` (measure 3), and
byte-level declared stderr (measure 4). W4's gate asserts the prefix mangling is *present in the
emitted source* before vetting, so a `link()` that silently drops imports fails even when its
truncated output would vet — exactly the "declared expected result" a comparison-only gate
cannot supply. D7's monomorphism deferral is honest: the residual is stated, precedent-cited,
and flagged for a future joint close with `ts`/`js`.

## Amendment summary (what must change before implementation starts)

1. **B1:** W2 scope += the `rt.go:22` unused-var fix; re-measure W2's recorded failing output.
2. **B2:** W2 scope += item 7 — `Eq`/`Cmp`/nan-last runtime layer, `Contains`/`IndexOf`/
   `Sort`/`SortBy`/`Least`/`Greatest` retargeted at it.
3. **M1:** W3's mangle set += `main`, host entry calls the mangled name.
4. **M2:** D2/W3 state the two emission rules (explicit instantiation for nullary generic
   cases; type-parameter/instantiated assertion targets).
5. **M3:** W7 names the Go serializer's map-key rendering and ordering rule explicitly.
6. Minors m1–m4 at the orchestrator's discretion; m1 (explicit try-in-fn reject) recommended.
