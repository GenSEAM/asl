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
| 1 — module-boundary types | v2 reconciled | 2 lenses, 4 blockers, all folded | in progress | — | — | — |
| 2 — vocabulary coverage | v1 REJECTED, v2 in progress | 4 blockers | — | — | — | — |
| 3 — Wasm target v1 | feasibility done | — | — | — | — | — |
| 4 — JS/TS backend | — | — | — | — | — | — |
| 5 — Go backend | — | — | — | — | — | — |
| 6 — reference interpreter | — | — | — | — | — | — |
| 7 — harness whole-program mode | — | — | — | — | — | — |

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
