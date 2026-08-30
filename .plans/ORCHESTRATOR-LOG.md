# Orchestrator log

## Baseline (2026-08-29, before Phase 1)
All seven gates green, 47 tests pass, tree dirty (owner declined a baseline commit).
`HANDBOOK.md` 12,078 chars ≈ 3,020 tokens.
Pre-phase snapshot of the tree kept in the session scratchpad for diffing.

## Cross-phase links found during planning — do not lose these

* **`defenum` Rust codegen is one defect with two discoverers.** Phase 1 reproduced `rustc`
  rejecting the `06-module` lowering (`E0412`, `{ }` binders dropped, no indirection for the
  recursive case). Phase 2 independently found 8 builtins blocked by the same lowering missing
  `Ord`/`Eq` derives. Both are `defenum` codegen. **Phase 1 owns the whole fix**, derives included,
  because it is already opening that code — Phase 2 must not plan around it separately.
* **`06-module` sits on both skip lists** in `backend/check_corpus.py`. The backend gate is green
  partly by exclusion. Un-skipping it is a Phase 1 prerequisite; the phase is not done while any
  fixture stays skipped without a recorded reason.
* **`grammar/closure_audit.py` never scans `bench/`.** Phase 2 found `bench/algo/variants/tight.agents`
  already exercising 7 builtins the coverage figure calls unexercised. The reported 33% is therefore
  wrong in the safe direction, but the gate's denominator and scan root both need stating explicitly
  before a coverage floor is set on top of them.
* **`differential.py` function mode is hardcoded to one task shape** (histogram, `Map<String,Int64>`).
  Any phase that adds a differential case in function mode inherits generalising it. Phase 2 flagged
  this as design-only; whichever phase implements it first owns the code.

## Phase status
| Phase | Plan | Plan review | Implementation | Impl review | Gates | Commit |
|---|---|---|---|---|---|---|
| 1 — module-boundary types | v2 reconciled | 2 lenses, 4 blockers, all folded | done | 2 lenses + /code-review, 2 fix passes | 7/7 green, 79 tests | `a635ab4` |
| 2 — vocabulary coverage | v3 amending | v1 rejected, v2 approve-with-amendments | done | 2 lenses, 3 blockers + 5 majors fixed | 7/7 green, 161 tests | `b6b43ff` |
| 3 — rename AgentS → AgentScript | v1 architect | 2 lenses (returned empty; self-reviewed) | done | 2 lenses (returned empty; self-reviewed) | 7/7 green, 161 tests | `4a7677b` |
| 4 — WebAssembly target v1 | feasibility measured | — (direct) | done | — (direct) | 7/7 green, 161 tests | — |
| 5 — reference interpreter | — | — | — | — | — | — |
| 6 — agent-facing tooling | — | — | — | — | — | — |
| 7 — TypeScript backend | — | — | — | — | — | — |
| 8 — Go backend | — | — | — | — | — | — |
| 9 — harness whole-program mode | — | — | — | — | — | — |

## 2026-08-29 — orchestrator-verified defect, independent of any agent report

Phase 2's reviewer claimed the numeric builtins are `i64`-only against a declared `N N -> N`.
I checked it myself rather than take the report:

```
backend/rust/rt.rs:10  pub fn div(a: i64, b: i64) -> i64
backend/rust/rt.rs:14  pub fn rem(a: i64, b: i64) -> i64
backend/rust/rt.rs:18  pub fn checked_div(a: i64, b: i64) -> Option<i64>
backend/rust/rt.rs:19  pub fn checked_rem(a: i64, b: i64) -> Option<i64>
backend/rust/rt.rs:82  pub fn sum(xs: Vec<i64>) -> i64
```
and `min`/`max` lower to `std::cmp::min`/`max`, which do not compile on `f64` at all:
`error[E0277]: the trait bound `f64: Ord` is not satisfied`.

`N` in the vocabulary covers `Int32`, `Int64` and `Float64`. So on the Rust backend **`/`, `mod`,
`checked-div`, `checked-mod`, `min`, `max` and `list-sum` are broken for `Float64` and for `Int32`
today** — and `/` and `mod` are inside the 36 builtins the coverage figure calls *exercised*.

Two consequences:
* The premise "exercised ⇒ the lowering works" is false. Coverage counts the builtin, not the
  types it was exercised at. Phase 2's coverage floor must be defined over (builtin × numeric type)
  or it measures the wrong thing.
* `ROADMAP.md` §2 lists the Rust backend as **working**. It is working for `Int64`. That row needs
  correcting when Phase 2 lands, not left as an overclaim — and Phase 3 inherits this, because the
  Wasm route goes through Rust.

Ownership: **Phase 2** repairs the numeric lowerings. Phase 1 keeps the `defenum` codegen fix.

## Phase 2 v2 verification — parked amendments

Verdict approve-with-amendments. B2/B3/B4 closed; **B1 partial**. All three independent spot-checks
reproduced verbatim, including the executed baseline of **21/107**.

Three amendments are held until Phase 1 lands, because two of them depend on what Phase 1 actually
takes:

1. **B1 — the coverage numerator is still fakeable.** §7 counts a static tree-sitter scan, now over
   fewer files. The verifier demonstrated the fake rather than describing it: a ten-line fixture
   with one case taking the `else` arm moved the reported figure **21 → 32 with zero of the eleven
   builtins executed**. Fix on record: trace the generated Python (`sys.settrace` / `sys.monitoring`,
   no new dependency) and fail on unreached lines, so the numerator counts lines that ran.
2. **`rule-13` collides** — Phase 1 has taken it (`checker/resolve.py:238`, the
   private-type-in-exported-signature rule, spec checklist item 13). Phase 2's W4 becomes rule-14,
   confirmed against Phase 1's landed code, not against its plan.
3. **Fixture numbers `09`–`12` collide** with Phase 1's imported-type fixtures. Phase 2's ten
   fixtures renumber to 13–22, again confirmed after Phase 1 lands.

Also recorded, not blocking: `coverage.lock`'s `instantiations` field is the sole enforcement of the
`N`-at-both-types rule and no gate verifies it; Tier A's probe count, domains and exclusions are
written down nowhere; the narrowing costs 0 model-facing tokens because `HANDBOOK.md` is untouched.

Observed mid-flight, not a defect: `check_corpus.py` red with 10 failures (missing module search
root) while Phase 1 was mid-edit; `pytest` at 54, not the baseline 47 — Phase 1 is adding tests.

## Phase 1 — implementation landed, then reviewed

Gates verified by the orchestrator directly, not taken from the implementer's report: all seven
green, 59 tests pass, `rustc` on `06-module` 13 errors → 0. Acceptance criterion holds — `rule-13`
rejects a private type named in an exported signature.

**Conformance lens: 0 blockers.** All 17 items landed. No gate checks less than before — every gate
change verified additive against the pre-phase snapshot, and the new assertions were mutation-tested
to confirm they bite. All 12 new semantic fixtures survive perturbation: each fires the code its
header names, and each checks clean once the violation is removed.

**Correctness lens: 2 blockers, both silently wrong with every gate green.**

1. `cond_clause`/`else_clause` were never converted to `sequence()` in either backend — the same
   defect the phase claims to have fixed, one form over. Rust drops `(try (println "first"))` from a
   `cond` clause entirely, `?` propagation included: Python prints `first\nsecond`, Rust prints
   `second`. The bare-effect variant is dropped by **both** backends, so `differential.py` cannot
   see it — agreeing on the wrong answer is agreement.
2. A binder inside an imported unit sharing a name with one of that unit's own top-level functions
   is emitted as the qualified top-level path; `self.local` is consulted with no lexical scope. In
   higher-order form it is silently wrong on both backends *in agreement*: prints `3 6` instead of
   `101 102`. The root-unit control is correct, so this phase introduced it.

**Finding that is not a bug but changes what the gates are worth:** the implementer's claim that
`sequence()` is byte-identical on pre-existing fixtures is true and vacuous. A parse-tree sweep
finds exactly one multi-expression body in the entire corpus, created by this phase. The changed
path was never reached by anything older. Multi-expression bodies are a coverage hole in their own
right and need fixtures regardless of the two blockers.

**Not a hole after all:** deviation 1 (rule 13 reports local types; a qualified type reports rule-9).
`semantic/import-unexported-type.agents` is exactly that program, carries `; expect-only: rule-9`,
fires it, and checks clean after perturbation. Spec §2.7 already assigns `rule-9` there.

Owed beyond the two blockers: `ROADMAP.md` is stale in four places (§2's table, `:61`, `:141-144`,
`:208-211` still describes `r-ea8c` as open while PCP marks it Resolved) — replacement text drafted
in the conformance report's appendix; imported-call arity is unchecked with no fixture recording it.

## Phase 1 closed — `a635ab4`

Owner chose one commit per phase on `main`, applied to every remaining phase without asking again.
This first commit necessarily absorbs the pre-existing uncommitted work as well; that is the
consequence of declining a baseline commit and is recorded rather than hidden.

From here the phase diff is `git diff HEAD`, not an rsync snapshot.

Final state: seven gates green, 79 tests (47 at the phase's start), `rustc` on `06-module` 13 → 0.

Two fix passes landed after review, and each found a defect of the same *class* as the one it was
sent to fix — which is the argument for asking an agent to enumerate the class rather than patch the
instance:
* sent to fix the `cond` traversal hole, the checker pass also found `:default` literals were never
  typed against their field;
* sent to fix `sequence()` in `cond` clauses, the backend pass enumerated all six multi-expression
  body positions and confirmed each routes through it.

`differential.py` now accepts a declared expected stdout per program case. This is the structural
lesson of the phase: two backends agreeing on a wrong answer was being counted as agreement, and it
was demonstrated live, not argued.

**Honest coverage, measured with a tracer rather than a scan: 21/107 executed** against the 35%
`closure_audit.py` reports as mentioned; 33/107 executed overall, 57/107 neither mentioned nor run.
That number is Phase 2's actual starting line.

## Phase 2 — implementation reviewed

Gates verified by the orchestrator: all eight green, 96 tests, coverage **33/107 → 107/107**
executed, 400 monomorphism probes, differential 85 function + 14 program cases.

**The coverage number is real, and it was tested as a number rather than believed.** The coverage
reviewer ran a full 107-builtin mutation test — perturb each Python lowering, delete each effect,
then assert every `; run:` header, differential expectation and program stdout/exit. **101 of 107
mutants died.** The six survivors are named and are the honest limit of the current oracles: the
four `IoError` constructors (compared only against themselves), `map-empty` (its lowering is a
literal `{}`, nothing to mutate), and `file-write`, whose only executed site is a failing path whose
oracle — stdout `""`, exit 1 — cannot be told apart from a crash. Rust-side reachability is 105/107.

**No gate got easier.** Every changed gate checks strictly more; `validate.py` and `checker/gate.py`
are byte-unchanged. `closure_audit`'s deleted `exercised builtins` line was pure print — its exit
code never referenced it.

The oracle reviewer built a spec-derived oracle importing nothing from `backend/` and ran it over
**all 78 function cases plus the 7 new program cases**, not the fifteen it was asked for: zero
disagreements. Where the plan and the implementation disagreed on an expected value, the
implementation was right all three times — the plan's fixture-22 table was wrong in four rows of
five, and its fixture-27 note misstated what Python's `str.find` returns.

### Three blockers, all portability, none reachable by any executed case

1. **`list-sort` at `Float64` with NaN.** Rust's `partial_cmp(..).unwrap_or(Equal)` freezes NaN in
   place; Python's `sorted` does not. Reproduced end to end through the real transpilers:
   `3.0,nan,0.5,1.0,2.0` against `0.5,3.0,nan,1.0,2.0`. The specification demands byte-reproducible
   output.
2. **`MIN / -1`** for `/`, `mod`, `checked-div`, `checked-mod`. Rust panics; Python returns
   `9223372036854775808`, which is outside `Int64`. The language declares fixed widths and trapping
   overflow, so Python is the wrong one here — the fix is to trap, not to widen.
3. **`map-key-order` only narrows *written* annotations.** A `Float64` map key reaching through
   inference — `(List (Pair Float64 Int64))` into `map-from-pairs` — checks clean and then fails at
   `rustc` with `E0277`. So `ROADMAP.md`'s claim that `Float64` is no longer an admissible key is
   false as written, and Tier A's "admissible = what the checker accepts" is a weaker floor than
   advertised.

Ownership: all three are Phase 2's. Blocker 3 also requires the `ROADMAP.md` wording to be retracted
rather than merely footnoted.

## Phase 2 closed — fix wave landed and verified

The three portability blockers and the coverage-integrity findings from both implementation reviews
are fixed. Verified by the orchestrator directly, not taken from any fixer's report (the fixers had
no shell and could not run gates): all seven gates green, **161 tests**, coverage **107/107**
executed, 400 monomorphism probes, differential **120 function + 15 program cases**, 0 disagreements.

Fix wave, by area:

* **Runtime portability** (landed before this session, verified now): the NaN total order
  (`nan_last`/`order_key`), the `MIN / -1` trap-or-none contract, the `f_to_i` range guard, and
  `map-key-order` raised to the inference path in `checker/types_.py`. Pinned by the `backend/cases/`
  boundary cases.
* **Coverage-gate integrity** (this session): `unexecuted` reasons must name a PCP id, `--write`
  refuses a lower executed count without `--allow-regression`, the "every builtin is executed" line
  is gated on `not unreached`, `unproven` entries expire on a user-defined-type instantiation, and
  the `N`-domain rule is exact per `N`-position. `tier_a.narrowed` is now the label list.
* **`file-write` success path** (this session): `08-io.agents` writes and reads back in one
  invocation, so a deleted write is told apart from a crash; the differential gate gained a 15th
  program case.

Decisions recorded in PCP: `d-6e1f` (NaN total order), `d-8b3c` (numeric edge contract), plus
updates to `d-2c8f`, `d-7c21` and `d-a70b`; `c-3ef8` marked superseded. The
`d-7a15`/`d-2ba6`/`d-6c04`/`c-3d71`/`c-e820`/`l-4d92`/`l-9e13`/`l-5c47` entries minted in
`DRAFT_LOG.md` during the pre-crash "cleanup" wave remain un-folded into their per-area files; they
are recorded in the draft log and the code already reflects them.

## Phase 3 closed — rename AgentS → AgentScript

Mechanical rename executed directly on `main` (owner directive, no working branch): 88 fixtures
`.agents` → `.agentscript`; grammars/tree-sitter `tree-sitter-agents` → `tree-sitter-agentscript`
(name `agents` → `agentscript`, scope `source.agentscript`, file-types `agentscript`); reserved
prefix `agents-` → `agentscript-`; runtime alias `_as` → `_agentscript`; tracer env vars
`AGENTS_EXEC_COVERAGE`/`AGENTS_EXEC_SOURCE`/`AGENTS_COVERAGE_LOCK` → `AGENTSCRIPT_*`; Go module
`agents` → `agentscript`; npm root name `asex` → `agentscript`.

Verified by the orchestrator directly, not from any subagent report: all seven gates green,
**161 tests**, coverage **107/107**, differential **120 function + 15 program cases**, 0
disagreements. Acceptance scans clean under word-bounded patterns (`\bAgentS\b`,
`tree-sitter-agents\b`). Canaries held: `prelude/coverage.lock` byte-identical, `backend/cases/*.json`
changed only in `"src"`, differential expected stdout/stderr/exit unchanged. Frozen exceptions
intact: `AGENT_SPEC.md`/`SPEC_REVIEW.md` untouched, `.plans/**` history preserved, repo dir `asex`
and `ASEX_GATEWAY_KEY` (in `bench/harness/config.example.json`) unchanged.

Both plan-review subagents returned empty reports, so the orchestrator performed the review slices
inline (baseline counts 98/79/88/161 reproduced verbatim). The plan's acceptance greps for `AgentS`
and `tree-sitter-agents` false-positive on the new names without word boundaries; the corrected
scans are recorded in `d-9c1f`. `.plans/phase-3/FEASIBILITY.md` (a Wasm probe) was relocated to
`.plans/phase-4/FEASIBILITY.md`, the phase it describes; the plan's `node pcp/scripts/pcp.js`
actualize command is a phantom (no `pcp.js` exists; PCP is markdown + `INDEX.md` counts).

## Phase 4 closed — WebAssembly target v1

The Wasm arm attaches to the existing differential gate rather than adding a new one: the same
`ToRust` program is compiled to `wasm32-wasip1` and run under node's `WASI` preview1
(`backend/rust/wasi.mjs`), and `programs()` now compares stdout, stderr and exit status across
python, rust and wasm. Verified by the orchestrator directly: all seven gates green, **161 tests**,
differential **120 function + 15 program cases**, 0 disagreements.

The arm earned its place on the first run: the `noperm.txt` case (mode 000) disagreed — wasm said
`not-found` where both native arms said `permission-denied`. Root cause: `rt.rs::io_err` matched
`raw_os_error()` against Unix errno numbers, but on `wasm32-wasip1` that value is a WASI errno
(2 = `ACCES`, not `ENOENT`). Fixed by mapping from `ErrorKind`, which every target normalizes,
folding `NotADirectory | IsADirectory` into `invalid-path` to keep the errno 20/21 case the Python
side reaches by number. Recorded as `d-3c5f` (arm) and `c-7b9e` (portability caveat).

Not done (recorded in `d-3c5f`): function-mode Wasm interop (`i64` as `BigInt`) and the interface
contract / foreign-failure decision the phase description names; program mode is the acceptance
surface, and artifact size is the Rust std baseline.
