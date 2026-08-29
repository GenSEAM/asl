# Phase 2 plan v2 — verification

Narrow re-check of the four blockers, the coverage definition, the measurement claims, the
narrowing, and the Phase 1 collision. Inventory not re-derived; settled design not re-litigated.

Everything below was run this session. `python` = `.venv/bin/python`; `rustc` =
`rustup run stable rustc --edition 2021`. Probes were built in the session scratchpad against a
snapshot of the working tree; **no source file was changed**. Phase 1 is being implemented
concurrently — where a gate is red, that is called out as mid-edit rather than as a v2 defect.

## Verdict

**approve-with-amendments** — B2, B3 and B4 close on compiled evidence I reproduced verbatim, but
B1 closes only partially (v2's numerator is still a *static scan*, now of a smaller file set, and I
raised it 21 → 32 with a ten-line fixture whose single case executes none of the eleven builtins it
adds), and two of v2's work items collide head-on with code Phase 1 has **already landed** in the
tree (`rule-13` is taken; `corpus/valid/09`–`12` are taken).

## Blocker closure

| # | what v2 does | verdict | reason |
|---|---|---|---|
| **B1** — coverage floor measured mentions, not execution | §2: "Covered = called by a source `differential.py` executes, in a case whose result both backends match against a checked-in expected value." §7: numerator = `run_query(differential.executed_sources())`; gate condition 4 requires every `corpus/valid` fixture to appear in a case or on a reason-carrying `UNEXECUTED` list. | **partially closed** | The *definition* (§2) says "in a case"; the *mechanism* (§7) never checks that half. `run_query` is the same tree-sitter static scan `closure_audit.py:32-50` runs today, just over fewer files. A call head in a branch no case reaches still counts. Demonstrated: adding one fixture to the executed set whose only case takes the `else` arm raised the numerator **21 → 32** (+11 builtins, zero executed). Gate condition 4 is satisfied by *one* case of any kind, so it does not close this. The two fakes the rejection named — markdown, and an un-executed `corpus/valid` file — are genuinely closed. |
| **B2** — numeric lowerings `i64`-only against `N N -> N` | §6 rows 1-6: a `Num` trait (`ZERO`/`quot`/`rest`/`plus`) for `i32`/`i64`/`f64`; `div`/`rem`/`checked_div`/`checked_rem`/`sum` generic over it. W5 turns the (builtin × instantiation) sweep into a permanent gate; §5 fixture `13` runs the `Float64` and `Int32` legs; §2 requires every `N`-typed builtin at `Int64` **and** `Float64`. | **closed** | Defect reproduced (see spot-checks); the repair text compiles and its semantics reproduce; the class is made un-shippable by W5 rather than by an eyeball. One residual: the *Tier B* half of the guarantee (`Int64` and `Float64` both executed) is enforced against `coverage.lock`'s hand-written `instantiations` field, which v2's own risk 5 admits no gate verifies. Tier A's compile-level guarantee is mechanical and does hold. |
| **B3** — `min`/`max` double-evaluation and NaN divergence | §6 row 7: templates become `rt::min({0}, {1})`/`rt::max({0}, {1})`; `pub fn min<T: PartialOrd>(a: T, b: T) -> T { if b < a { b } else { a } }`. §1.4 keeps the double-evaluation finding and *rejects* the rejection's `E0382` sub-claim (every `N` is `Copy`). Row 9 writes `least` as a `reduce`, not `iter().min()`. | **closed** | Each argument appears once in the emitted expression, so the double-evaluation is gone by construction. All four NaN values reproduce against Python exactly (below). The `E0382` correction is right: `min`/`max` are `N N -> N` and every `N` is `Copy`. |
| **B4** — `differential.py` hardcoded to a single `String` input | W6, four separable parts: (a) typed multi-arg inputs, types taken from `parse_signature(task["signature"])` rather than a hand-written `arg_types` that could drift; (b) a recursive `J` trait in a new `backend/rust/harness.rs`; (c) Python-side normalisation of `_as.NONE` and non-finite floats; (d) `(argv, files, expected_stdout, expected_exit)` for program mode. Cases go in `backend/cases/`, not `bench/tasks/`. | **closed** | Hardcoding confirmed verbatim at `differential.py:35`, `:47`, `:51`, `:53-57`, `:66`, and `programs()` comparing python-vs-rust only at `:101`. W6 addresses each, and the recursive encoder is required by §5's three composed shapes. Amendment needed on its *regression baseline*, not its design — see finding 8. |

## Attacks on the coverage definition

| the fake | does the gate catch it? | what would |
|---|---|---|
| **Dead-branch fixture.** Add `grammar/corpus/valid/NN.agents` with one entry, `(if (string-empty? t) (…60 builtin calls…) "x")`, and one case `[["x"], "x"]`. Both backends return `"x"`, matching the checked-in expected value. | **No.** Measured 21 → **32** with eleven calls in the untaken arm. Tier A compiles it; condition 4 sees a case; the ratchet rises; every gate is green. This is the cheapest single edit and it is the same defect class v1 was rejected for. | Prove *reachability*, not presence. `run_python`'s driver already runs the transpiled module in-process — trace it (`sys.settrace`, or `sys.monitoring` on 3.13; no new dependency, `coverage` is not in the venv) and fail the gate on any line of the generated `cand.py` that no case reaches. That converts §2's "in a case" from prose into the mechanism. |
| **Expected value regenerated from actual output.** Run the harness, paste its output into `backend/cases/*.json` as `expected`. | **No, and it cannot be.** Both backends are generated from the same `prelude.json` declaration, so a wrong *declaration* agrees with itself; §8 names this and offers checked-in expecteds as the mitigation, which regeneration defeats exactly. | Not mechanically catchable inside this repo. Make it a *stated* residual risk beside risk 5: no `--regen` path in the harness; each case in `backend/cases/*.json` carries §5's "rules out" note as a field, so a regenerated value is visibly unaccompanied by a claim; a third independent implementation (Phase 6's reference interpreter) is the only real oracle. |
| **Probe that compiles but is never run** — i.e. shrink Tier A's domain. Drop `Float64` from the `N` domain, or move a builtin into W5's effectful/variadic/higher-order exclusion list. | **No.** `coverage.lock`'s schema (§7) records `floor_pct`, `executed`, `instantiations`, `unproven`, `unexecuted` — **not** the probe count, the domains, or the exclusions. W5's exit code is "number of failing probes", so removing probes removes failures. The exclusions are *printed*, which §8 offers as the audit trail, but no gate reads stdout. I reproduced the domain arithmetic: 56 probed builtins → **440** probes; ten `Map` builtins × `K=Float64` × 4 `V` = 40 removed → **400**. Both numbers are one-line edits away from anything. | Put `tier_a: {probes, domains, excluded}` in `coverage.lock` and give it the same three-way check §7 gives `executed`: below → regression, above → stale lock. Then shrinking the sweep fails the gate instead of shrinking the failure count. |
| **A `coverage.lock` entry no gate cross-checks** (v2's own residual risk 3/§9 risk 5). Write `"list-sum": ["Int64","Float64"]` for a builtin executed only at `Int64`. | **No** — and this is load-bearing, not cosmetic: `instantiations` is the *sole* enforcement point of §2's `N`-at-both-types rule, which is B2's entire Tier-B regression guard. The rule is therefore self-attested. | The checker already infers the concrete type at each call site. Have `checker/resolve.py` emit `(builtin, concrete args)` per call site under a flag, and generate `instantiations` with a `--check` mode, the way `prelude/generate.py` already gates its own output. Serialization of existing inference, not new inference. |
| **Fixture parked on the `UNEXECUTED` list** with an invented reason string. | **No** — condition 4 accepts any reason. | Low impact (it cannot *raise* the count), so: leave it, but require the reason to name a `coverage.lock` key so the two lists cannot silently disagree. |
| Add a `defun` example to `AGENT_SPEC_CORE.md` / widen a scan root / lower the `95` / delete an unexercised builtin | **Yes, all four.** Spec fragments are outside the numerator; there is no scan root to widen; the floor is data and the ratchet is computed against `executed`, not the floor; deleting a builtin makes the lock stale (condition 3) and shrinks Tier A. | — |

## Independent spot-checks

Method for all three: write the probe, `python checker/check.py` (exit code = diagnostic count),
`python backend/to_rust.py`, then `rustc --edition 2021 --crate-type=lib lib.rs` beside a copy of
`backend/rust/rt.rs`. `rt.rs` is untouched by Phase 1 so far (`div`/`rem` still `i64`, `sum` still
`Vec<i64>`, `sort`/`least`/`greatest` still `T: Ord`).

| claim | probe I built | verbatim output | reproduces? |
|---|---|---|---|
| §1.2 — all six `Map` builtins fail at a `Float64` key (`E0277`) | `(defun mg [(m (Map Float64 Int64)) (k Float64)] -> (Option Int64) (map-get m k))` → checker exit **0**; emits `rt::m_get(&m.clone(), &k.clone())` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` … ``note: required by a bound in `m_get` --> rt.rs:86:17`` / ``86 | pub fn m_get<K: Ord, V: Clone>(m: &BTreeMap<K, V>, k: &K) -> Option<V>`` | **yes** |
| §1.2 — `list-sort` fails at `Float64` for a reason unrelated to the `defenum` derives | `(defun srt [(xs (List Float64))] -> (List Float64) (list-sort xs))` → checker exit **0**; emits `rt::sort(xs.clone())` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` … ``note: required by a bound in `sort` --> rt.rs:66:16`` / ``66 | pub fn sort<T: Ord>(mut xs: Vec<T>) -> Vec<T> { xs.sort(); xs }`` | **yes** — and no user type is involved, confirming the attribution correction |
| §1.2 / B2 — `/` at `Float64` and `mod` at `Int32` against a declared `N N -> N` | `(defun q [(a Float64) (b Float64)] -> Float64 (/ a b))` + `(defun m32 [(a Int32) (b Int32)] -> Int32 (mod a b))` → checker exit **0** | ``error[E0308]: arguments to this function are incorrect`` … ``expected `i64`, found `f64` `` / ``note: function defined here --> rt.rs:10:8`` ; ``error[E0308]: mismatched types`` … ``expected `f64`, found `i64` `` ; ``error[E0308]: arguments to this function are incorrect`` … ``expected `i64`, found `i32` `` | **yes** |

**All three reproduce.** The checker rejected nothing in any of them, so §1.2's core claim — the
checker's admissible set is strictly larger than the Rust backend's — holds at the points I probed.

Three further claims, checked because they carry B3 and the executed baseline:

```
EXECUTED TODAY: 21     (run_query over exactly bench/algo/variants/tight.agents
+ = eprintln file-read file-write filter fold list-max map map-empty map-from-pairs
map-get map-pairs map-set map-values not option-or println string-empty? string-split string-trim
REMAINING: 86
```
§1.3's **21/107** reproduces verbatim, builtin list included; `closure_audit.py` still prints
`exercised builtins : 36/107 (33%)`.

```
v1tpl  min(nan,1)=1.0   min(1,nan)=NaN
v2     min(nan,1)=NaN   min(1,nan)=1.0   max(nan,1)=NaN   max(1,nan)=1.0
py     min nan 1.0   max nan 1.0
std sum empty f64=-0.0   fold sum empty=0.0   fold [0.1,0.2]=0.30000000000000004
least([nan,1.0])=Some(NaN)      py min([nan,1.0]) nan
```
§1.4, §1.5, §6 rows 6/7/9 all reproduce verbatim.

Tier A arithmetic: 56 builtins carry a type variable and are neither variadic, higher-order nor
I/O → **440** probes on v2's stated domains; removing `K=Float64` across the ten `Map` builtins
removes 40 → **400**. v2's 400 is right; §6's sentence explaining it ("rule-13 removes those **24**
instantiations … which is why Tier A's denominator is 400") is not — 440 − 24 = 416.

## The narrowing

**Which.** §6 names six as narrowed rather than repaired: `map-get`, `map-set`, `map-has?`,
`map-remove`, `map-pairs`, `map-from-pairs` at a `Float64` key. That is the set that *fails* today
(24 probes). The narrowing itself is a type-level rule, so its real reach is **all ten** `Map`
builtins × `K=Float64` × 4 value types = **40** instantiations, including `map-empty`, `map-size`,
`map-keys`, `map-values`, which compile fine today. v2's own denominator (400) already assumes 40;
only the prose says 24.

**Verdict: legitimate repair, not backend-driven language damage.** The spec is internally
contradictory before any backend is considered — `AGENT_SPEC_CORE.md:123` asks only that `K`
"support equality" while `:545-547` specifies `map-keys` returns keys **sorted** and
`map-values`/`map-pairs` are "ordered by sorted key". Sorting needs a total order. `Float64` has
none, in any target. Narrowing resolves the contradiction toward the behaviour the spec already
specifies and both backends already implement (Python `sorted(...)`, Rust `BTreeMap`). It removes
no capability an ordinary program needs: a float map key is unusable on equality grounds
regardless of representation, and the measured blast radius on the existing corpus, bench and
module fixtures is zero. `min`/`max` are **not** narrowed — §6 row 7 repairs them over `PartialOrd`
across the whole of `N`, so the "integer-only `min`" failure mode does not arise.

**Handbook token delta: zero, and that is the defect.** W4's file list is `checker/resolve.py`,
`AGENT_SPEC_CORE.md:123` + §9, and one semantic fixture. It does **not** touch `prelude/HANDBOOK.md`,
which is generated from `prelude/generate.py`'s hand-written prose blocks (the vocabulary tables
come from `prelude.json`, and no builtin's declared *type* changes). So the artifact resent on
every model call keeps saying, at `HANDBOOK.md:74`:

```
- Constructed: `(List …)`, `(Option …)`, `(Result …)`, `(Pair …)`, `(Map …)`
```

with nothing in `## Types` or `## Rules that have no exceptions` about the key constraint. A model
writes `(Map Float64 Int64)`, the checker rejects it with a rule the handbook never mentioned, and
the phase has made the language narrower without making the normative artifact narrower.
**The plan does not account for this.** Amendment: W4 adds one line to `generate.py`'s Types block
(≈ +60 chars ≈ +15 tokens) and regenerates.

For the record, the deltas that *are* measurable: W1's arity fix is **−98 chars** across the 34
call-form cells (reproduced: 34 mismatches, all 34 old forms present in the file), against the
orchestrator's 12,078-byte baseline. With W4's one line the phase's net handbook cost is ≈ **−38
chars ≈ −10 tokens** — negligible either way, which is precisely why omitting the rule line is not
worth the silence it buys.

## Rebase note for Phase 1

Read from `.plans/phase-1/PLAN.md` W11 (`:702-724`), W12 (`:727-758`), W13 (`:745-758`),
W14 (`:761-775`), W15 (`:777-800`), W16 (`:802-816`), and §2.7 (`:426`). State of the tree now:
`pytest` **54 passed** (not 47); `grammar/corpus/valid/` holds **12** fixtures (not 8);
`check_corpus.py` is **red, 10 failures** (`no module core/shapes on the search path`) — that is
Phase 1 mid-implementation with W11/W13 pending, re-run once and identical, **not** a v2 defect;
`validate.py`, `checker/gate.py`, `generate.py --check`, `closure_audit.py` and `differential.py`
are green.

| v2 work item | what to re-check after Phase 1 lands |
|---|---|
| **W1** (`generate.py`, `HANDBOOK.md`) | Phase 1 **W16 edits the same two prose blocks** (`generate.py:66-69`, `:74-75`) and regenerates `HANDBOOK.md` (+≈85 chars). v2 does not name this collision at all — §3's rebase note covers only `differential.py` and the derives. Rebase W1 onto W16's file, and re-measure the char delta against W16's regenerated baseline, not against 12,078. |
| **W4** (rule-13) | **Blocking collision: `rule-13` is already taken.** `checker/resolve.py:238` reports it for "declared here and not exported"; `grammar/corpus/semantic/private-type-in-exported-signature.agents:1` carries `; expect-only: rule-13`; `AGENT_SPEC_CORE.md:700` is checklist item 13. W4 must claim **rule-14** and checklist item **14**, and its fixture must be `; expect: rule-14`. Also: W4 and Phase 1 W9/W10 edit `checker/resolve.py` in the same region. |
| **W5** (`monomorphism.py`) | Re-run after Phase 1's `defenum`/`defschema` derive fix: the domain gains a `defenum`/`defschema` arm, so 400 is no longer the denominator. Record the new number in `coverage.lock` in the same commit. Also re-check the 51 excluded builtins — W12's qualified-name lowering does not change signatures, so the exclusion set should be unchanged; assert it rather than assume it. |
| **W6** (`differential.py`) | Phase 1 **W11 changes `transpile()`'s signature** (text + `path` + `roots`) and threads a search root through **all four** call sites `:30`, `:46`, `:72`, `:76-84`; **W15 adds a fifth program case** at `:128-132`. Rebase, do not merge. W6's stated regression baseline — "the histogram table … 7 function cases + 4 program cases", "47 passed" — is already stale; capture the baseline **after Phase 1 lands**, from the actual run, and diff against that. W6(a)'s `main()` must keep W11's `roots` threading through the new `backend/cases/` loop. |
| **W7** (`check_corpus.py`) | Phase 1 **W13 rewrites this file**: un-skips `06-module.agents`, deletes `SKIP_RUST`/`SKIP_PY`, and **adds a `run` column** (`runpy` import + entry call). W7's "printed row count is not 8 corpus + 2 bench = 10" is wrong before Phase 2 begins (12 corpus fixtures exist today) and wronger after W8. Restate as "every `corpus/valid` and every `bench/**` source appears with `ok` in `compile`, `run` and `rustc`", with no count. |
| **W8** (fixtures `09`–`18`) | **Blocking collision: `09`, `10`, `11`, `12` already exist** — `09-imported-types.agents`, `10-imported-generic-types.agents`, `11-name-coexistence.agents`, `12-transitive-use.agents`, all landed by Phase 1. Renumber v2's ten fixtures **13–22**. Every §5 fixture must then re-pass `validate.py` under **both** grammars (Phase 1 W5/W6 edit `agents.lark` and `grammar.js`) and `checker/gate.py`. §5's `15`/`16` primitive-only choice should be revisited once the derives land — if enums derive `Ord`, exercise an enum-keyed map and an enum-sorted list rather than recording them `unproven`. |
| **W9** (`closure_audit.py`, `coverage.lock`) | The `unproven` block is written against the pre-Phase-1 derive gap; after Phase 1 those eight entries must move to `instantiations` **with an executed case behind each**, not merely be deleted. Condition 4's fixture list must include Phase 1's four new fixtures — they are in `corpus/valid` and, unless W6 gives them cases, each needs an `UNEXECUTED` entry with a reason. |
| **W10** (`ROADMAP.md` §2) | Phase 1 also corrects ROADMAP rows; check for a textual collision and write the Rust-backend row once, covering both phases' corrections. |
| **W11** (PCP) | §10 entry 10's cross-reference is correct as written; re-check that Phase 1's own PCP entries have not already claimed the same ids. |

## Findings

1. **blocker — v2's numerator is still a static scan; a dead branch inflates it.**
   *Evidence:* §7 computes the numerator as `run_query(differential.executed_sources())`, the same
   tree-sitter query used today. Adding one ten-line fixture to the executed set, with a single
   case `[["x"], "x"]` that takes the `else` arm, moved the numerator **21 → 32** — eleven builtins
   (`list-empty?`, `str`, `string-chars`, `string-from-int64`, `string-join`, `string-length`,
   `string-lower`, `string-replace`, `string-reverse`, `string-slice`, `string-upper`) counted,
   none executed. Tier A compiles it, condition 4 accepts it, the ratchet rises.
   *Amendment (required before W9 can be declared done):* trace the generated Python. `run_python`
   already executes `cand.py` in a subprocess it generates; wrap the driver in `sys.settrace` (or
   `sys.monitoring`, Python 3.13 — `coverage` is not installed and no new dependency is needed) and
   fail the gate on any line of the transpiled fixture that no case reaches. Report per-fixture
   missed lines. This is what makes §2's "in a case" true of the mechanism and not only of the
   prose.

2. **blocker — `rule-13` is already taken by Phase 1.**
   *Evidence:* `checker/resolve.py:238` → `self.report("rule-13", f"{name} in {where} is declared
   here and not exported", token)`; `grammar/corpus/semantic/private-type-in-exported-signature.agents:1`
   → `; expect-only: rule-13`; `AGENT_SPEC_CORE.md:700` is checklist item 13.
   *Amendment:* W4 becomes **rule-14** / checklist item 14 throughout (§4 W4, §6, §9 risk 3, §10
   entry 6), and its fixture is `grammar/corpus/semantic/map-float-key.agents` with
   `; expect: rule-14`.

3. **blocker — §5's fixture numbering collides with four fixtures already in the tree.**
   *Evidence:* `grammar/corpus/valid/` holds `09-imported-types.agents`,
   `10-imported-generic-types.agents`, `11-name-coexistence.agents`, `12-transitive-use.agents`.
   *Amendment:* renumber v2's ten fixtures **13–22**; update §5's headings, §4 W8, and §8's
   "18 valid fixtures" (12 + 10 = 22 before Phase 1 adds any more).

4. **major — `coverage.lock`'s `instantiations` is the only enforcement of the `N`-at-both-types
   rule, and no gate verifies it.**
   *Evidence:* §7's lock schema plus §9 risk 5, which states this honestly but treats it as
   cosmetic. It is not: §2's `Int64`-and-`Float64` requirement *is* B2's Tier-B regression guard,
   and a hand-written field is exactly the kind of second source §4 W6(a) rejects `arg_types` for.
   *Amendment:* emit the concrete type arguments per builtin call site from `checker/resolve.py`
   under a flag — the checker already infers them — and generate `instantiations` with a `--check`
   mode, the same pattern `prelude/generate.py` already uses. If that is judged out of proportion,
   demote §2's `N` rule from "the gate enforces" to "review enforces" and say so in the gate's own
   error message, rather than letting the lock imply enforcement it does not have.

5. **major — Tier A's size, domains and exclusions are recorded nowhere, so the sweep can be shrunk
   silently.**
   *Evidence:* `coverage.lock`'s schema has no probe count. W5's exit code is the *failure* count.
   Removing `Float64` from the `N` domain, or adding a builtin to the effectful/variadic/higher-order
   exclusion list, reduces both probes and failures; §8 offers "it prints the exclusions" as the
   audit trail, and no gate reads stdout. Reproduced the arithmetic: 56 probed builtins → 440
   probes; −40 for `K=Float64` across ten `Map` builtins → 400.
   *Amendment:* `coverage.lock` gains `tier_a: {probes, domains, excluded}` under the same
   below-floor / below-lock / above-lock check §7 gives `executed`.

6. **major — the narrowing never reaches the model-facing artifact.**
   *Evidence:* W4's file list omits `prelude/HANDBOOK.md`; `HANDBOOK.md:71-75` (`## Types`) lists
   `(Map …)` unqualified and `## Rules that have no exceptions` says nothing about key ordering.
   Token delta of the narrowing on the handbook: **0**. The plan does not account for it.
   *Amendment:* W4 adds one line to `prelude/generate.py`'s Types block and regenerates
   (≈ +60 chars ≈ +15 tokens). W1's measured delta is **−98 chars**; net for the phase ≈ −38 chars.

7. **minor — §6's explanation of the 400 denominator is arithmetically wrong.**
   *Evidence:* "rule-13 removes those **24** instantiations from the admissible set, which is why
   Tier A's denominator is 400." 440 − 24 = 416. The rule removes `K=Float64` for **all ten** `Map`
   builtins — 40 instantiations — of which 24 currently fail. Reproduced: 440 → 400.
   *Amendment:* one sentence; the number 400 is correct and stands.

8. **minor — §1.1's "restore this state" baseline is already stale, and one of its gates is red
   mid-Phase-1.**
   *Evidence, this session:* `pytest` → **54 passed** (§1.1 says 47); `corpus/valid` holds 12
   fixtures (§4 W7 says 8); `backend/check_corpus.py` → **10 failure(s)**, all
   `no module core/shapes on the search path` / `no module text/report on the search path` — Phase 1
   mid-implementation, W11/W13 pending; identical on a second run; **not a v2 defect**.
   `validate.py` 0 failures, `checker/gate.py` 0 failures, `generate.py --check` 0,
   `closure_audit.py` `36/107`, `differential.py` `0 disagreement(s) across 7 function cases + 4
   program cases x 2 backends` — the last three all still match §1.1.
   *Amendment:* §1.1 becomes "the state at Phase 1's completion, captured then", and every
   before/after count in W6 and W7 is re-measured at rebase time rather than quoted from §1.1.

9. **minor — an expected value regenerated from output is uncatchable, and should be stated as
   such rather than implied away.**
   *Evidence:* §8's `differential.py` row names the shared-declaration blind spot and offers
   "every case in §5 carries a checked-in **expected** value" as the mitigation. A contributor who
   pastes the harness's own output into `backend/cases/*.json` defeats it, and nothing v2 designs
   sees the difference.
   *Amendment:* add it as a residual risk beside risk 5; no `--regen` path in the harness; carry
   §5's "rules out" note as a field on each case so an unaccompanied expected value is visible in
   review; note that Phase 6's reference interpreter is the only real third oracle.
