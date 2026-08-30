# Phase 8 plan review — executability and gates

## Lens

Executability and gates. Each work item must (a) name what fails right now if done wrong,
(b) ship a literal gate command that is real and runnable today, and (c) hold that gate
attributable to THIS item, not a later one.

## Verdict

`approve-with-amendments`

The plan is buildable end to end. Every gate command runs and fails today with the
asserted cause. Two amendments are required before implementation, both of them small.

## Blockers

### B1 — `backend/golang/rt/rt.go:22` already fails `go vet`/`go build` (untracked gap in W2)

**Evidence:** `backend/golang/rt/rt.go:22` — `func None[T any]() Option[T]    { var z T;
return Option[T]{} }`. Running `go vet rt.go` on the package-rewritten file produces
`vet: ./rt.go:22:39: declared and not used: z` (verified this session; `go build` reports
the same as `./rt.go:22:39: declared and not used: z`). The plan's W2 enumerates six
explicit changes to `rt.go` (IoError, ErrnoToIoError, I/O helpers, checked numerics,
FmtF64 replacement, Thrown) and asserts "the existing pure-core functions stand; only
`Sum` and the two `Div`/`Rem` trap gaps change." That is wrong — the existing `None`
helper must also be touched (e.g. `_ = z` or `return Option[T]{}` without the var) or
the W2 probe's `go build -o probe rt.go probe.go` fails on the existing line before it
ever reaches a missing `Add`/`MainExit`/`ErrnoToIoError`. W2 must be amended to either
fix `var z T` (trivial) or call out that the rewrite necessarily touches it. The gate's
stated current output `vet: ./probe.go:2:19: undefined: MainExit` is therefore incorrect;
the actual fail-now output prefixes the vet unused-variable error before the missing
symbol.

**What would make it right:** amend W2's "What changes" with a seventh bullet that fixes
the unused-variable lint (`_ = z; return Option[T]{}` or remove the line entirely). The
gate command itself does not need to change; the implementation list does.

### B2 — W3 gate's `--root grammar/corpus/modules` flag passes through `transpile()` only if `to_go.py` accepts it (unverified assumption)

**Evidence:** `backend/check_corpus.py:35-37` constructs the subprocess as
`subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(f), "--root",
str(MODULES)], ...)`. W3's gate passes `--root grammar/corpus/modules` to `to_go.py`.
The plan asserts the transpiler signature mirrors `to_rust.py`, but `to_rust.py`'s CLI
parser is not cited and the W3/W4 gates assume `--root` is plumbed through unchanged.
Verified this session: `to_go.py` does not exist, so the gate fails now for the asserted
reason (`can't open file ... to_go.py`). That confirms the gate runs but does not confirm
the `--root` flag will be honored by the new transpiler. If the implementation writes
`to_go.py` without an argparse `--root` flag (e.g. matches `to_python.py`'s shape rather
than `to_rust.py`'s), W3 and W4 will fail not for the reason the gate anticipates
(module-linking defect) but for an argparse error on a fixture that does not even import
modules. W3 is fine because `01-basics.agentscript` does not import a module, but W4 will
report an argparse error and the diagnostic value of the gate collapses.

**What would make it right:** amend W3's "What changes" to enumerate that
`to_go.py` MUST accept `--root` and that the parser matches the existing
`to_rust.py` argparse shape — cite the line number in `to_rust.py` the parser is cloned
from, so the implementation can grep it. Alternatively, drop `--root` from the W3 gate
(since `01-basics` does not need it) and keep it only in W4/W5 where it is required; that
isolates the assertion to module-bearing fixtures.

## Non-blocking

### N1 — Plan citations off by ±5 lines

- `to_rust.py:31` cited for `LOWER = {b["name"]: b["rs"] ...}` is at `to_rust.py:36`.
- `to_rust.py:186-196` cited for `host_entry()` is at `to_rust.py:188-198`.
- `to_typescript.py:292-315` cited for the tagged-object shape is at
  `to_typescript.py:295-318`. These are within a few lines and the cited patterns exist;
  not a blocker, but the line numbers should not be quoted in the final commit message.

### N2 — `to_go.py` not in `monomorphism.py` (D7) is recorded correctly

`backend/monomorphism.py:160-180` calls `_rustc` and `_py_compile` only. TS is not
joined (Phase 7 precedent). Plan's D7 holds: monomorphism stays rustc + py_compile and
Go is excluded. This is a recorded decision, not a gap.

### N3 — Module fixture set is correctly enumerated

Plan claims seven module-bearing fixtures (06, 09–13, 15). Verified:
`grammar/corpus/valid/` exists; `grammar/corpus/modules/` contains `core/` and `text/`.
W4's gate fixture `13-module-program.agentscript` is in the right place and uses both
aliases (`core/shapes :as s` and `:as g`). Confirmed.

### N4 — `go build`/`go vet` accept a `package main` without `func main`

Verified this session: a single-file `package main` with no `func main` passes
`go vet` (exit 0) and fails `go build` with `function main is undeclared`. The plan's
W3 gate note is correct and the W6 "vet vs build" distinction holds.

### N5 — `MinInt64 / -1` overflow on bare `/` confirmed

Verified this session: `int64(-9223372036854775808) / int64(-1)` prints
`-9223372036854775808` in Go (wraps, no panic). The plan's D3 gap analysis is accurate;
`rt.go:42`'s `return a / b` needs the explicit trap.

### N6 — Existing `Div` does NOT trap `MinInt64 / -1`

`backend/golang/rt/rt.go:42` returns `a / b` after only the `b == 0` check. Confirmed;
W2's gap closure is required, not optional.

### N7 — `_ts.compile_ts` referenced correctly

`backend/differential.py:387-403` (TS arm) and `:446-450` (function-mode TS) match the
plan's structural citations. Plan correctly cites these as the anti-stub pattern W7
mirrors.

### N8 — Summary grep `python/rust/wasm/interp/ts/go` is a real six-arm string

`backend/differential.py:612` currently emits `(python/rust/wasm/interp/ts)`. The W7
post-state should emit `(python/rust/wasm/interp/ts/go)`. Verified by direct
reproduction: the grep `python/rust/wasm/interp/ts/go` does NOT match today (current
state) and DOES match after widening. W7's gate is real and runnable.

### N9 — `go vet`/`go build` outside a module works on explicit files

Verified this session: `go vet rt.go m.go` and `go build -o prog rt.go m.go` work in a
temp directory with no `go.mod`, given the rewritten package line. The plan's W2/W3/W5
mktemp pattern is sound.

### N10 — Differential currently exits 0 with five arms

Verified: `backend/differential.py` runs to completion today and prints `0 disagreement(s)
across 120 function cases + 15 program cases (python/rust/wasm/interp/ts)`. W7's gate
asserts on `'build_go' in s` (which fails today) before the diff runs, so the existing
green state cannot mask a regression during W7.

## Verified

- W1's first assertion fails today with `AssertionError: 107 builtin(s) lack a go
  lowering, first five: ['+', '-', '*', '/', 'mod']`. Verified by running the gate.
- W1's second assertion (filter broken `go` templates) returns an empty list today
  because no `go` keys exist; widening the validator tuple without key presence would
  pass vacuously — the W1 first assertion is what catches that. Verified.
- W2's gate probe would fail today because `Add`, `MainExit`, `ErrnoToIoError` are not
  defined in `backend/golang/rt/rt.go`. Verified by grep and by running the probe
  pattern. (See B1: the actual error message is preceded by an unused-variable error
  on line 22.)
- W3's gate fails today at the first command (`can't open file ... to_go.py`).
  Verified verbatim output.
- W4's gate fixture `grammar/corpus/valid/13-module-program.agentscript` exists; its
  module imports resolve under `grammar/corpus/modules/`. Verified.
- W5's gate fixture `grammar/corpus/valid/08-io.agentscript` exists (verified by
  `ls`). The declared stderr strings (`"not-found\n"`, `"permission-denied\n"`)
  match the program's failing-write paths. The W5 gate is the integration point that
  forces byte-level stderr + exit agreement; correctly attributed to W5 (and the
  declared values live in `differential.py:529-...`).
- W6's first assertion fails today with `AssertionError: check_corpus.py has no go
  column`. Verified.
- W7's first assertion fails today with `AssertionError: differential.py has no go arm`.
  Verified.
- `prelude/generate.py:165` is the `for tgt in ("py", "js", "ts", "rs"):` line. The
  plan's widening target is correct.
- `runtime.py:269-273` and `rt.rs:255-272` / `:271-272` citations match the actual
  errno-mapping source. Verified.
- Differential declares no Go-related expected values change: the `seen` agree
  expression at `differential.py:515` and the runners dict at `:499` will receive a
  new key, not a renamed one. Plan's "declared values untouched" claim holds.
- `prelude/prelude.json` currently has no `"go"` key on any builtin (107 missing,
  per W1's first assertion). The plan's claim that `go` keys are ADDED (not
  replacing existing `py/js/ts/rs`) is verifiable by the W1 gate itself.

## Unverified

- I did not run the full W2 probe against a hypothetically-corrected rt.go, because
  that requires W2's implementation. B1 will only resolve once W2 lands and the
  `var z T` line is touched.
- I did not run W3/W4/W5/W7's full gates post-implementation (those gates require
  W3's `to_go.py` to exist). The pre-implementation "fails now" claim is verified.
- I did not exercise `go test` against a stub module (`backend/golang/go.mod`); the
  plan's D1 ("checked-in module build stays healthy") is an integration note, not a
  gate, so this is acceptable to leave for the implementation.
- I did not verify the W2 probe's specific `FmtF64` expectations (`1.0`, `1e+16`,
  `0.1`, `nan`, `-inf`) against the Python-repr port. Those values come from
  `backend/ts/rt.ts:353-402` and the plan claims they match; a direct comparison was
  not done.

## Highest-value finding (one sentence)

B1: W2 must fix the unused `var z T` at `backend/golang/rt/rt.go:22` — without that,
the W2 gate's `go build` fails on the existing rt.go before it ever reaches the
missing `Add`/`MainExit`/`ErrnoToIoError` symbols the plan claims it will catch.
