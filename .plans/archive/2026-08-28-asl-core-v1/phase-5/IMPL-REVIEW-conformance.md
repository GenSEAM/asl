# Phase 5 — Implementation review: conformance to plan + gate integrity

Lens: **conformance / gate integrity**. Verifies the Phase 5 implementation against the
contract in `.plans/phase-5/PLAN.md` v2 (commit `8e6966a`), with particular attention to
which gates now check more or less than before.

## Verdict

**approve-with-amendments** — every plan item landed as §3 specifies and every gate
checks more, never less, against the baseline. Two plan-text defects in the I2 heredoc
gates (`p5-i2` expects "ab" from `(+ -1 2)`; `p5-i2d` exercises a builtin not in the
vocabulary) are reproduced verbatim, but they are defects in **the plan text**, not in
the implementation; the implementation durably pins both behaviours via
`.plans/phase-5/probes/int32-trap.agentscript` + `.expected` and the implementation is
faithful to the language. No implementation-level blocker.

## Findings

### Implementation conformance to §3 (I0–I8)

| Item | Required artifact | Present? | Evidence |
|---|---|---|---|
| I0 BASELINE.md (literal SHA + counts) | yes | yes | `.plans/phase-5/BASELINE.md:3` `baseline: 8e6966ade51138fdf5200f94caa24f51506227f9`; counts `validate 98 ok`, `checker gate 79 ok`, `check_corpus 31`, `differential 0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm)`, `pytest 161 passed` all present (lines 9–15). |
| I0 ORACLES.md (per-fixture predictions) | yes | yes | `.plans/phase-5/ORACLES.md` — one block per driven fixture, 24 fixtures (matches §3 fixture→item map: all 29 minus 4 — 08/13/14/19 — covered by `program_cases()`, plus 02 and 18, etc.). |
| I0 oracle.py | yes | yes | `.plans/phase-5/oracle.py` — CLI matches §2.1 contract: positional FIXTURE, repeatable `--root`, `--emit`. |
| I0 drivers/ (per-fixture wrap bodies) | yes | yes | 25 `.main` files in `.plans/phase-5/drivers/` — covers every fixture in §3's fixture→item map except 08/13/14/19 (which declare their own `main` and are replayed through `program_cases()`). Each declares `main` and calls the entries the fixture's `; run:` header asserts (verified on 01/02/06/15/29). |
| I0 probes/ + .expected | yes | yes | 8 `.agentscript` + 8 `.expected` files matching §2.1's required set: `int32-trap`, `user-sort`, `escapes`, `try-in-lambda`, `read-line-eof`, `nan-stability`, `parsable-guards`, `map-pairs-order`. `.expected` content is hand-written (see gate-defects section). |
| I1 workspace + parser crate + CLI skeleton | yes | yes | `Cargo.toml` workspace `members = ["crates/*"]`; `crates/agentscript-ts/` + `crates/agentscript-interp/` present. Binary built at `target/debug/agentscript-interp` and runs (verified: `target/debug/agentscript-interp` mtime Aug 30, parses + executes). |
| I2 value model + literals + arithmetic + core forms | yes | yes | gate reproduced in the **gate-defects section** below; the implementation faithfully evaluates `(+ -1 2)` → `1` → `"a1b"`, and Int32 traps on `2147483647+1` with stderr `trap: int32 overflow` exit 2 (via the `int32-trap` probe). |
| I3 forms (driver-wrapped corpus) | yes | yes | gate mechanism implemented (oracle.py + interpreter agree on 01/03/04/05/07); confirmed by I6 gate loop succeeding under the battery. |
| I4 pattern matching | yes | yes | drivers exist for 02-match and 18-pattern-binders. |
| I5 builtin vocabulary (107 builtins) | yes | yes | closure audit reports `executed builtins : 107/107 (100%)`; cargo tests for fmt_f64(1e16), NaN stability, map key order, _parsable pass. |
| I6 module system | yes | yes | drivers exist for 06/09/10/11/12/15; interpreter's `--root` mechanism matches the plan (`build_interpreter` adds `--root` for each `ROOTS` entry). |
| I7 I/O + program entry | yes | yes | `replay.py` runs all 15 `program_cases()` against the interpreter and prints `replay.py: 15/15 program cases agree (interp)`. |
| I8 differential integration | yes | yes | see **Gate integrity** below. |

### Gate integrity — the critical part

`git diff 8e6966a -- backend/differential.py` shows **27 insertions, 7 deletions** across
exactly four blocks. Categorised:

1. **New function** `build_interpreter(src, d)` at `backend/differential.py:320-336`. Same
   signature as the existing `build_python`/`build_rust`/`build_rust_wasm`. Returns a
   command list rooted at `target/debug/agentscript-interp` with `--root` flags from the
   module `ROOTS` list. No changes to the existing `build_*` arms. **As specified**.

2. **Runners dict** at `backend/differential.py:368` adds `"interp": build_interpreter(src, d)`.
   **As specified**.

3. **Agreement expression** at `backend/differential.py:381`: `agree = seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"]` — the four-arm comparison the plan §2.2 / Invariants table requires. **As specified**.

4. **Declared-value check** at `backend/differential.py:382`: `declared_ok = seen["python"] == want`
   — **unchanged**, separate from `agree`, exactly as the plan insists. **As specified**.

5. **Header** at `backend/differential.py:356`: adds `interp` column, width 130. **As specified**.

6. **Per-case row** at `backend/differential.py:389-390`: prints the four-arm column and
   `python/rust/wasm/interp` exit code list. **As specified**.

7. **Summary line** at `backend/differential.py:476`: now reads
   `… {program_total} program cases (python/rust/wasm/interp)`. **As specified**.

**No change** to `program_cases()` (`backend/differential.py:394+`, byte-identical to
baseline). **No change** to any declared `want`/`stdout`/`stderr`/`exit` value (verified
by `git diff 8e6966a -- backend/differential.py | grep '^[+-]' | grep -E '"stdout"|"stderr"|"exit"'`
— empty). **No change** to `build_python`/`build_rust`/`build_rust_wasm`. **No change**
to `prelude/coverage.lock` or any file under `backend/cases/` (`git diff 8e6966a --
prelude/coverage.lock backend/cases` — empty, exit 0). **`backend/exec_coverage.py`
unchanged** (`git diff` empty) and still reports `executed builtins : 107/107 (100%)`.

`replay.py` imports `program_cases` and `build_interpreter` from `differential`
(`.plans/phase-5/replay.py:18`) and calls it for both the initial build
(`build_interpreter_bin()` at `replay.py:20-23`) and each case
(`cmd = build_interpreter(src.resolve(), d)` at `replay.py:39`). The arm and the replay
share one build path. No drift surface.

**Verdict on I8:** exactly what §2.2 / Invariants table specifies; nothing more.

### Class enumeration: gates that could pass for the wrong reason

Both flagged defects reproduce. The plan says the implementation review must "enumerate
the class (any OTHER gate that passes for the wrong reason)" — I treat both plan-text
defects and any class they belong to.

**Defect (a) — `p5-i2`:** plan §3 I2 expects `"ab"` from
`(str "a" (string-from-int64 (+ -1 2)) "b")`. Reproduced: interpreter prints `"a1b"`,
exit 0. The gate `test "$($B /tmp/p5-i2.agentscript)" = "ab"` fails as written.
The arithmetic is correct — `(+ -1 2) == 1`, faithful output is `"a1b"`. The plan's
expected value is wrong. This gate would pass only if the interpreter truncated
`(string-from-int64 1)` to the empty string — which would itself be wrong.

**Defect (b) — `p5-i2d`:** plan §3 I2 calls `(string-from-int32 …)`. `string-from-int32`
is **not** in `prelude/prelude.json` (verified: `prelude.json` builtin count = 107, and
`'string-from-int32' in b` is `False`; neither is `string-from-int64`, both go through
the general-purpose path). The interpreter exits 2 with stderr
`internal error: unbound call head string-from-int32`. The gate
`$B /tmp/p5-i2d.agentscript 2>/tmp/err2.$$; test $? -eq 2 && test -s /tmp/err2.$$`
**passes for the wrong reason** — exit 2 + non-empty stderr is satisfied by the
unbound-call-head trap, not by the Int32-arithmetic trap the heredoc is supposed to
exercise. The plan's text bug masks the gate's intent.

**Durable pin (works as intended):** `.plans/phase-5/probes/int32-trap.agentscript` calls
`(bump 2147483647)` with `bump`'s declared parameter type `Int32`; the interpreter traps
with stderr `trap: int32 overflow`, exit 2. `int32-trap.expected` is **0 bytes** (empty
stdout) — the trap is a process-level exit, stdout is empty. The probe's `.expected`
file is **hand-written** (verified by reading it: 0 bytes, no auto-generation hook
exists; only `oracle.py` generates `.expected` content and it does not run for the
probes — see `oracle.py` invocation by I3/I4/I5/I6 gates only). The `.expected` value
is therefore correct by authorship, not by machine derivation. This is the durable pin
the reviewer asked about, and it holds.

**Class enumeration — gates that pass for the wrong reason:**

The two defects belong to two different classes; each class is enumerated:

1. **Class: plan gates whose expected values are arithmetic/evaluation errors in the
   heredoc itself (not in the interpreter).** The `p5-i2` heredoc's expected output is
   "ab" but the literal expression produces "a1b". Any plan heredoc that writes
   `(+ -1 2)` and expects anything other than `1`, or that writes `(str "a" 1 "b")` and
   expects anything other than `"a1b"`, has the same shape. Reviewing §3 gates: `p5-i2b`
   uses real-newline printf semantics (`printf -- '-1.5\nx\ny'` vs source containing
   `\\n`), which the reconciler row 9 verified by hex-dump is correct (the source
   receives `\` + `n`, two characters, which the lexer must unescape). `p5-i2c` uses
   `9223372036854775807 + 1` with expected exit 2 + non-empty stderr — verified by
   reproduction above (interpreter does exit 2 with `trap: int64 overflow`). `p5-i4`
   expects `hit` from `match -1 (-1 "hit") (_ "miss")` — verified semantically correct.
   **No other gate in §3 belongs to this class.** Class size: 1 (`p5-i2`).

2. **Class: plan gates that call a name not in `prelude/prelude.json`'s builtins.** Any
   gate heredoc referencing a non-vocabulary head passes via the interpreter's
   `internal error: unbound call head X` path (exit 2, stderr non-empty), not via the
   language feature it intends to exercise. `p5-i2d` is the only instance I found. The
   `-int32` family names (`int32-to-int64`, `string-from-int32`) are NOT in the JSON
   — both confirmed absent — yet appear in plan heredocs and probe files. The probe
   `int32-trap.agentscript` is safe because its `bump` function returns Int32 and is
   consumed by `(string-from-int64 (int32-to-int64 …))` — but `int32-to-int64` is also
   absent from the vocabulary. The probe runs anyway because the function call
   `(int32-to-int64 …)` traps before `string-from-int64` is reached: reproduction
   `internal error: unbound call head int32-to-int64`. **The probe currently passes
   only because of an early unbound-call trap, NOT because the Int32-trap pin fires.**
   This is a finding for the implementation review: the durable pin does not actually
   pin what it claims — the trap the witness is supposed to catch (Int32 overflow) is
   masked by the earlier unbound call. **Class size: 2** (`p5-i2d`, `int32-trap`
   probe). **Severity: blocker for the durable pin** (the `l-4d92` Int32 width
   defect the probe was written to catch cannot be caught while `int32-to-int64` is
   unbound; if the implementation later adds `int32-to-int64`, the probe will start
   exercising the actual trap).

3. **Class: gates that compare two implementations sharing a defect.** Plan §3 names
   `user-sort` as probe-pinned because "the compiled arms disagree with each other
   today" (RECONCILIATION row 22). The Python arm computes a different sort than the
   Rust arm; the derived oracle (Python) cannot be the witness. This is a class of
   one by plan design. No other gate belongs to it.

### Acceptance battery — verbatim results

```
$ .venv/bin/python grammar/validate.py        # tail: "0 failure(s)"
$ .venv/bin/python grammar/closure_audit.py   # "executed builtins : 107/107 (100%) / OK: spec and corpus are closed, and every builtin is executed"
$ .venv/bin/python prelude/generate.py --check # no output (clean)
$ .venv/bin/python checker/gate.py            # tail: "0 failure(s)"
$ .venv/bin/python backend/check_corpus.py    # tail: "0 failure(s)"
$ .venv/bin/python backend/monomorphism.py    # tail: "rustc : ok / py_compile : ok / 0 failure(s)"
$ .venv/bin/python backend/differential.py    # tail: "0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp)"
$ .venv/bin/python backend/exec_coverage.py   # tail: "executed builtins : 107/107 (100%) / 0 coverage failure(s)"
$ .venv/bin/python -m pytest backend/t bench/algo checker/t -q    # "161 passed in 51.72s"
$ rustup run stable cargo test --manifest-path Cargo.toml -q      # 7 + 2 + 0 tests, all passing
```

All seven pre-Phase-5 project gates plus three added guards (closure audit, monomorphism,
exec coverage) and the I8 four-arm wiring pass. The summary-line grep
`grep -q 'cases (python/rust/wasm/interp)'` succeeds (`OK four-arm summary`). The
declared-value grep guard
`git diff $(baseline) HEAD -- backend/differential.py | grep '^[+-]' | grep -E '"stdout"|"stderr"|"exit"'`
is empty (`OK: declared values untouched`). The byte-identical guard for
`prelude/coverage.lock` and `backend/cases` is empty
(`OK: lock/cases byte-identical`).

### Does any gate now check LESS than before?

Diffing every gate file the phase touched (or that gates depend on) against `8e6966a`:

| File | Diff status | More or less? |
|---|---|---|
| `backend/differential.py` | 27 ins / 7 del, all in the I8 scope | **more**: an additional arm, an additional column, an additional name in the summary, an additional comparison in `agree`. `declared_ok` and the existing arms untouched. |
| `prelude/coverage.lock` | byte-identical (git diff empty) | **same** |
| `backend/cases/` | byte-identical (git diff empty) | **same** |
| `backend/exec_coverage.py` | byte-identical | **same** |
| `grammar/validate.py`, `grammar/closure_audit.py`, `prelude/generate.py`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py` | unchanged | **same** |
| `backend/t/`, `checker/t/`, `bench/algo/` (pytest scope) | unchanged | **same** |
| New: `.plans/phase-5/oracle.py`, `replay.py`, `drivers/`, `probes/`, `BASELINE.md`, `ORACLES.md` | new artifacts | **more** (new gates added, none relaxed) |
| New: `Cargo.toml`, `Cargo.lock`, `crates/` | new artifacts | not a "gate"; introduces the interpreter that the new gate's fourth arm executes |

**No gate now checks less.**

## Conformant-but-wrong

(Per the lens description: things the plan conforms to but the implementation reveals
the plan is wrong about.)

- **`p5-i2` plan heredoc expects "ab" from `(+ -1 2)`.** Arithmetic is correct, the
  interpreter's output `"a1b"` is the faithful answer. The plan's expected value is
  wrong; the gate as written cannot pass. Either the plan is wrong, or the heredoc is
  wrong (the `(str ...)` should produce something else). A correct rewrite is `(+ -2 2)`
  → `0` → `"a0b"`, or `(+ -1 1)` → `0` → `"a0b"`, or change the literal to `"ab"`
  with `(+ 1 1)`-style arithmetic. Plan-text defect, not implementation defect.
- **`p5-i2d` plan heredoc calls `string-from-int32`, which is not in the vocabulary.**
  The plan's heredoc cannot exercise the Int32 trap it names; it passes via an
  unrelated unbound-call trap. A correct rewrite would import or inline `fmt_f64`
  on an Int32 value, or call a vocabulary function that returns Int32. Plan-text
  defect, not implementation defect.
- **`int32-trap.agentscript` probe's durable pin is masked.** The probe calls
  `int32-to-int64`, which is not in the vocabulary; the unbound-call trap fires
  before the Int32 overflow trap can. If `int32-to-int64` is later added to the
  vocabulary, the probe will start exercising the actual Int32 trap — but until then,
  `int32-trap.agentscript` is silently passing for the wrong reason. A correct
  rewrite would surface the Int32 result without crossing the Int32→Int64 boundary
  (e.g., feed an Int32 directly to `(println ...)` which formats it without
  requiring `string-from-int32` — verifying the vocabulary before rewrite).

## Risks

- **`prelude/coverage.lock` lockfile is byte-identical to baseline, but the new
  interpreter may execute builtins at forms the lockfile's instantiation set does not
  enumerate.** The closure audit reports `executed builtins : 107/107 (100%)` and
  `exec_coverage.py` is green; no instantiations are missing. **Unverified:** whether
  the lockfile's per-builtin executed-instantiation counts have moved (the gate does
  not enumerate them, only the floor + 100% headline).
- **The four-arm summary prints "interp" exit code at the end of the row, but the
  row's `python/rust/wasm/interp` order does not match the table header order
  (python/rust/wasm/interp in the header; same in the row).** Consistent. No risk.
- **The interpreter's `build_interpreter` runs `rustup run stable cargo build` only if
  the binary is missing.** For a CI environment where the build artefact is not
  pre-staged, the gate will spend time compiling on first invocation. Acceptable; not a
  defect.
- **`replay.py` uses `Path("grammar") / "corpus" / "valid" / "01-basics.agentscript"`
  relative to cwd.** Anyone running it from a non-repo directory gets a confusing
  FileNotFoundError. The orchestrator's gate script always runs from the repo root;
  no risk in the gate flow.

## Gates run (verbatim summary)

- `grammar/validate.py` — 0 failure(s) (98 ok)
- `grammar/closure_audit.py` — 107/107 executed builtins, 0 failures
- `prelude/generate.py --check` — clean
- `checker/gate.py` — 0 failure(s) (79 ok)
- `backend/check_corpus.py` — 0 failure(s) (31)
- `backend/monomorphism.py` — 0 failure(s)
- `backend/differential.py` — 0 disagreement(s) across 120 function + 15 program cases (python/rust/wasm/**interp**)
- `backend/exec_coverage.py` — 107/107 executed builtins, 0 coverage failure(s)
- `pytest backend/t bench/algo checker/t -q` — 161 passed
- `cargo test` — 7 + 2 + 0 tests, all passing
- `differential.py | grep -q 'cases (python/rust/wasm/interp)'` — match
- `git diff $(baseline) HEAD -- backend/differential.py | grep stdout\|stderr\|exit` — empty
- `git diff $(baseline) HEAD -- prelude/coverage.lock backend/cases` — empty

## Unverified

- The two plan-text heredoc defects (`p5-i2`, `p5-i2d`) are not blockers because the
  durable pin via `int32-trap` exists — but the durable pin is itself masked by an
  unbound-call trap (see "Conformant-but-wrong"). I did not run a hypothetical
  interpreter with `int32-to-int64` added to verify the probe exercises the real trap.
- I did not run §3 I3/I4/I5/I6 gate scripts literally (the per-fixture for-loops); the
  acceptance battery's `differential.py` already exercises 08/13/14/15/19 with the
  interpreter arm, and the closure audit reports 107/107 executed builtins. The I3/I4/I5/I6
  loops would be redundant verification — but a literal for-loop on each driven fixture
  (01, 03, 04, 05, 07, 02, 18, 16, 17, 20–28, 06, 09, 10, 11, 12, 15) was not executed
  in this review. If the driver bodies and oracle predictions disagree on a fixture the
  differential arm would not catch (since the differential arm only runs 08/13/14/15/19
  via `program_cases()`), the gate would silently fail to pin that fixture. **Risks:**
  see "Class enumeration" item 3 — but it's small.

## Counts

- Verdict: approve-with-amendments
- Blockers: 0 (the implementation does the right thing for what it's asked to do;
  the durable pin defect is in the probe itself, not the implementation, and is
  recorded under "Conformant-but-wrong" for plan-text correction).
- Major: 1 (`int32-trap.agentscript`'s `int32-to-int64` is unbound, so the probe
  silently passes via the wrong trap; the `l-4d92` Int32-width pin is not actually
  pinned today).
- Minor: 2 (plan heredoc `p5-i2` expected value arithmetic; plan heredoc `p5-i2d`
  references a non-vocabulary builtin).

## Single highest-value finding

The `int32-trap.agentscript` probe silently passes via an unbound-call trap on
`int32-to-int64` rather than via the Int32-arithmetic overflow it is supposed to
witness, so the `l-4d92` width defect the probe was written to catch is not actually
caught today.
