# Phase 2 plan review — reconciliation

One row per finding in `.plans/phase-2/REVIEW.md`. Nothing is dropped: the 12 numbered findings
(finding 3 split into its three independent sub-claims), all 27 rows of the non-discriminating
table, all 10 hidden work items, and all 8 "what would slip through" entries.

Every disposition was settled by opening the file or running the command, not by preference.
Evidence lives in `PLAN.md` §1; section references below point there.

**Totals: 48 accept · 10 accept-modified · 1 reject (59 rows).**

---

## Numbered findings

| # | finding | disposition | how, and on what evidence |
|---|---|---|---|
| 1 | blocker — the coverage floor counts mentions, not executions; a conformant implementation reaches 107/107 executing nothing | **accept** | Reproduced. `closure_audit.py:57` is the whole scan root; `:59-66` appends `AGENT_SPEC_CORE.md` fragments; `list-get` is "exercised" only through markdown. v2 redefines the numerator over exactly the sources `differential.py` runs (§2, §7) and adds gate condition 4 — every `corpus/valid` fixture must appear in a case or on a reason-carrying skip list. Spec fragments stay in the undefined-head check, as the finding asks, and are out of the numerator. **The honest executed baseline is 21/107, not 36** (§1.3) — worse than the finding assumed. |
| 2 | blocker — the repair list is incomplete: `/`, `mod`, `checked-div`, `checked-mod` carry the `list-sum` defect | **accept-modified** | Direction confirmed; scope was still too small. A mechanical sweep of all 440 admissible (builtin × instantiation) probes (§1.2) found **39 failures over 16 builtins**, not 7: the four named, plus `list-sum`, `min`, `max`, plus **`list-sort`/`list-min`/`list-max` at `Float64`** (which both v1 and the review attributed to the `defenum` derives — `f64` is not `Ord` before any user type is involved), plus **the six `Map` builtins at a `Float64` key**, which neither document names. Repair list is §6 (10 builtins) and rule-13 (§4 W4) narrows the remaining 24 instantiations. The sweep itself becomes a permanent gate (W5), which is the finding's own "mechanical check, not a per-builtin eyeball". |
| 3a | blocker — `std::cmp::min` rejects `f64` (`E0277`), so the defect being repaired is real | **accept** | Confirmed by the sweep: `min`/`max` at `Float64` → ``E0277: the trait bound `f64: Ord` is not satisfied``. |
| 3b | …and v1's replacement double-evaluates `{0}`, an `E0382` on a non-`Copy` argument | **reject** (the `E0382` half only) | The **double evaluation is real** and is reproduced (§1.4): `to_rust.py` emits `std::cmp::min(rt::sum(xs.clone()), 2.0)`, so v1's template puts `rt::sum(xs.clone())` in the output twice, and a call counter shows the true branch running it again. But `E0382` **cannot** occur here: `min`/`max` are declared `N N -> N`, and every `N` — `Int32`, `Int64`, `Float64` — is `Copy`, so a duplicated argument never moves. The finding's evidence block moves a `Vec<i64>`, which no `min` call can produce. Recorded as duplicated evaluation of a pure expression, not as a move error. The conclusion is unaffected. |
| 3c | …and NaN parity is inverted against Python; §8's "moot pending a NaN literal" is wrong | **accept** | Confirmed verbatim (§1.4). Measured: Python `min(nan,1.0)=nan`, `min(1.0,nan)=1.0`; v1's template gives `1.0` and `NaN` — inverted both ways. NaN needs no literal: `(string-to-float64 "nan")` reaches it, and fixture `13` entry 2 uses exactly that. The finding's `rt.rs` templates are adopted verbatim (§6 row 7), and the semantics are **decided and recorded**: Python's rule — return the first argument unless the second compares strictly past it (§10 entry 4). |
| 4 | blocker — `differential.py` is hardcoded to a single `String` input, not merely one return shape; shapes compose | **accept** | Confirmed at `:35`, `:47`, `:51`, `:53-57`, `:66`. v2 W6 is a four-part work item with its blast radius named: the histogram task's 7 function cases and the 4 program cases are the only regression guard, so the before/after table must be byte-identical. The finding's `arg_types` field is **modified**: types come from `parse_signature(task["signature"])` rather than a hand-written field, because a second declaration is free to drift from the entry's real signature. Return encoding is a `J` trait in a new `backend/rust/harness.rs`, recursive over the value, which is what `(Option (List T))`, `(List (Pair K V))` and `(Result (Option Int64) IoError)` need — all three are used in §5. Python-side normalisation (`_as.NONE` → `["none"]`, non-finite floats → strings) is W6(c). |
| 5 | major — the fixture matrix does not specify discriminating cases; `11` and `09` cannot discriminate at all | **accept** | Confirmed by reading the described programs. §5 is rewritten: every case carries its literal input, its expected output, and the wrong implementation it rules out. Fixture `11` gains a `match` that prints the mapped error, so `result-map-err` replaced by the identity or by `result-map` now fails. Fixture `09` gains an expected-stdout oracle (W6(d)). Where a case earns its place only as coverage — `map-keys` vs `map-values`, `zip`'s components, `result-or`'s arguments, all type-distinct and caught by `rustc` — §5 says so instead of claiming discrimination. |
| 6 | major — the gate can be made green by a documentation edit and cannot see vocabulary shrinkage; `95` is a bare literal | **accept-modified** | Arithmetic confirmed (`100*102//107 = 95`, `100*101//107 = 94`) and the denominator's operator coverage confirmed (`closure_audit.py:34`), now stated explicitly in §7. All three attack vectors close, two of them for a stronger reason than the finding proposed: once the numerator is the executed set, a markdown edit and a scan-root widening have **no effect at all**, rather than being merely discouraged. Floor **and** ratchet, as the finding insists. **Modified:** the data goes in a new `prelude/coverage.lock`, not in `prelude.json`. Putting a coverage metric inside the vocabulary file makes the shrinkage vector (delete a builtin, ratio rises) a single-file edit — the exact failure mode the finding raises. A third gate condition (`executed > lock`) also fails a *stale* lock, so the number must be recorded deliberately. |
| 7 | major — a generic builtin exercised at one instantiation is not exercised; the 100% claim does not survive | **accept** | This is v2's organising principle, not a caveat. Two tiers (§2): Tier A compiles **every** admissible instantiation (400 probes, gate W5); Tier B requires execution, and for every `N`-typed builtin at `Int64` **and** `Float64`. `coverage.lock` records per-builtin instantiations, and lists the eight `defenum`-blocked builtins under `unproven`, owned by Phase 1 — §5's closing subsection says exactly what their fixtures look like after Phase 1 lands. The finding's verdict that v2 must not re-plan the `defenum` fix is honoured: no work item touches it. |
| 8 | minor — §8's Phase-1 uncertainty is stale; three unverified independence points | **accept** | `.plans/phase-1/PLAN.md` exists; `:431` edits `differential.py`, `:354`/`:520-525` own the `defenum` derives, `:386` un-skips `06-module`. §3 states the collision and the resolution — W6 is **rebased** onto Phase 1's edit, not merged — and §9 risk 2 names it as an orchestrator decision. §5's closing subsection and §4 W5 both state what changes when Phase 1 lands (Tier A's domain grows a `defenum`/`defschema` arm). |
| 9 | minor — item 2 fixes one of two copies of the arity heuristic | **accept** | Both facts reproduced independently: **34** mismatches (not `INVENTORY.md`'s 11), and the heuristic at **`prelude/generate.py:31` and `:158`**. W1 fixes both. Visible today in the shipped spec: `AGENT_SPEC_CORE.md:540` renders 2-argument `map-get` as `(map-get a b c d)`. |
| 10 | minor — widening the scan root to `bench/` adds sources no compile gate covers | **accept-modified** | The invariant is adopted; the mechanism is not needed. Because the numerator is now the executed set, `bench/algo/variants/tight.agents` counts *because `differential.py` runs it*, not because a scan root was widened — so v1's item 1 is deleted rather than amended. The finding's amendment stands on its own merits: W7 adds `bench/**/*.agents` to `check_corpus.py`, so every source any gate counts is also compile-gated. Both bench sources were measured passing on both backends first (§1.9), so the widening costs nothing today. |
| 11 | minor — PCP entry 5 records a Phase-1-owned item as unowned | **accept** | §10 entry 10 is a cross-reference to `.plans/ORCHESTRATOR-LOG.md:10-14` and `.plans/phase-1/PLAN.md:354`, explicitly not a new gap. `defschema`'s mirror-image defect (unconditional `Ord` derive) is attached to the same owner rather than opened separately. |
| 12 | minor — `list-sum` on an empty `Float64` list diverges (`0` vs `-0.0`) | **accept-modified** | Divergence confirmed: Rust's `Sum for f64` folds from `-0.0`. **Two corrections.** (a) It is **invisible to the current comparator** — `differential.py` compares Python objects and `-0.0 == 0` is `True` — so it would not have tripped the gate as the finding predicts; it is a latent divergence, not a first-run failure. (b) v2 removes it at the source: §6 row 6 uses `fold(T::ZERO, Num::plus)` rather than the `T: std::iter::Sum<T>` the finding verified, giving a measured `0.0`. The empty-list case moves to its own entry (`15` entry 1b) because `(string-split "" ",")` yields `[""]` on both backends, not `[]` — the finding's placement inside the csv entry could not have produced an empty list. |

---

## Non-discriminating differential cases (27 rows)

All 27 replacement inputs are adopted. Two rows are modified; the reason is given.

| fixture | case | disposition | where it lands in v2 §5 |
|---|---|---|---|
| `09` | "existing writable path (append succeeds)" | accept | case 1: pre-seed `log.txt` with `"A\n"`, append `"B"` from stdin, `file-read` and print. Swapped `file-append` arguments write a file named `B` and print `A\n`. |
| `09` | the 4 remaining `IoError` cases | **accept-modified** | `chmod 000` adopted (case 4, needs W6(d)'s per-case file mode). The sub-claim "accept that `interrupted`/`other` are unreachable" is **wrong as stated and rejected in that part**: all six are ordinary nullary calls, and a probe executes them identically on both backends (§1.8). Case 6 (`--labels`) executes all six constructors and pins their spelling. What is genuinely unreachable is the *host errno mapping* for `EEXIST`/`ENOTDIR`/`EINTR`/other — `coverage.lock` records constructor-covered and mapping-unproven separately, which is the finding's underlying point. |
| `09` | program mode has no oracle | accept | W6(d): cases become `(argv, files, expected_stdout, expected_exit)`; python, rust and expected must all agree. `differential.py:101` compares only python vs rust today. |
| `10` | `("3","x")` vs `("x","3")` cannot be expressed by a single-`String` harness | accept | W6(a) makes inputs a typed list; the entry takes two `String`s and returns a `pair` whose halves render positionally, so a `pair` swap is visible. |
| `10` | `is-ok?`/`is-err?` never both exercised | accept | every case yields `ok` in one half and `err` in the other, so all four predicates take both polarities within a single case. |
| `11` | the error value is discarded, so `result-map-err` is unobservable | accept | the entry now `match`es the `Result` and prints `err:E<bad:x>`. Identity or `result-map` in its place gives `err:bad:x`. A fourth discriminator was added on top: `option-map`-then-`result-map` order (43 vs 44). |
| `12` | `<=` vs `<` discriminated only at equality | accept | cases `x == lo` (`[3,3,7]`) and `x == hi` (`[3,7,7]`) exactly, plus `x=2`, `x=8`, `x=5`. |
| `12` | `and`↔`or` invisible without a mixed operand pair | accept | the report's `and` column takes `TT`/`FT`/`TF` across cases 3/1/4 and its `or` column takes `FF` at case 5 — all four combinations occur. |
| `12` | `>=` listed as covered by a program that uses `<=` twice | accept | one bound is written `(>= hi x)` explicitly and reported as its own column. |
| `13` | "out-of-`Int32`-range" needs the boundary | accept | `2147483647` → some, `2147483648` → none, `-2147483648` → some, `-2147483649` → none. |
| `13` | `checked-div`/`checked-mod` swap invisible when quotient == remainder | accept | `[7,3]` → `some 2` / `some 1`. |
| `13` | `int64-to-float64` needs 2⁵³+1 | accept | case `[9007199254740993, 2]`, the value `differential.py`'s docstring names. |
| `13` | `neg` coincides with `abs` at `0` and on symmetric input | accept | `[7,2]` reports `abs=7`, `neg=-7`; `[-7,2]` is the case where they coincide, kept deliberately as the contrast. |
| `14` | `list-tail` can coincide with other slicings | accept | `n=4` gives `[0,1,2,3]` — length ≥3, distinct, ascending — and `list-tail` is printed on its own (`some [1,2,3]`). |
| `15` | `list-sort` on already-sorted input is the identity | accept | `"3,1,3,2"` — unsorted, with a duplicate. |
| `15` | `list-min`/`list-max` swapped on a single or all-equal list | accept | ≥3 distinct values, both printed; `["5"]` is kept as the explicit single-element contrast rather than as the only case. |
| `15` | `list-length` off-by-one coincides with the index at `n=1` | accept | roster length 4, and `list-index-of` returns **3** — neither `0` nor `length-1`. |
| `15` | `list-sum` must use `Float64`; add empty and `0.1+0.2` | **accept-modified** | `Float64` kept and load-bearing; `0.1,0.2` → `0.30000000000000004` adopted. The empty case moves to entry 1b — `(string-split "" ",")` is `[""]`, not `[]`, on both backends — and the `0` vs `-0.0` divergence is removed at the source (finding 12) rather than asserted. |
| `16` | `map-remove` of an absent key coincides with a correct removal | accept | one present key and one absent key, with `map-size` printed **before and after** each. |
| `16` | `map-has?` is one-sided | accept | present (`"a"`) and absent (`"z"`) cases. |
| `16` | `map-keys` vs `map-values` are type-distinct — do not claim it as discriminating | accept | §5 says so verbatim, and adds a sorted-order case (`"c b a"`) which *is* discriminating, since the two backends reach sorted keys by different routes. |
| `17` | `string-index-of` haystack/needle swap | accept | `("banana","na")` → asserts `some 2`, not `is-some?`. Swapped gives `none`. A non-ASCII case (`"héllo"`) was added on top, pinning char indices against byte indices. |
| `17` | `string-starts-with?`/`string-ends-with?` swap | accept | `("log:hello","log:")` — start only; `("hello.log",".log")` — end only; `("abc","abc")` — the equality boundary. |
| `17` | `string-replace` `from`/`to` swap | accept | `"aXbXc"` → `"a-b-c"`; swapped leaves it unchanged; replace-first gives `"a-bXc"`. |
| `17` | `string-reverse` identity on a palindrome | accept | `"abc"` → `"cba"`, and `"Hello World"` → `"dlroW olleH"`. |
| `17` | `string-lower` identity on lowercase input | accept | `"Hello World"` has an uppercase run; `string-upper` is reported beside it so a swap shows. |
| `17` | `string-empty?` is one-sided | accept | `[""]` and every non-empty case. |

---

## Hidden work items (10 rows)

| # | item | disposition | where |
|---|---|---|---|
| 1 | generalise `rt::div`/`rem`/`checked_div`/`checked_rem` over `N` | **accept-modified** | §6 rows 2-5, via a `Num` trait (row 1) rather than three overloads. Widened: `list-sum`, `min`, `max`, `list-sort`, `list-min`, `list-max` share the shape — 10 repairs, each with compiled proof. |
| 2 | a mechanical `rt.rs`-vs-declared-signature audit | accept | Built and run this session (§1.2), then made permanent as **W5 / `backend/monomorphism.py`** — 400 probes, one `rustc`, one `py_compile`, ~3.5 s, with a unit test that a re-monomorphised `rt::sum` fails it. |
| 3 | `differential.py` input-shape generalisation and a recursive return serializer | accept | W6(a) and W6(b). The flat six-shape enum is dropped for a `J` trait in `backend/rust/harness.rs`. |
| 4 | Python-side output normalisation | accept | W6(c). Adds non-finite float encoding on top of the finding's `_as.NONE` case: `json.dumps(float('nan'))` emits bare `NaN`, which is not JSON, and Rust's `{:?}` emits `NaN` — both are normalised to strings. |
| 5 | a gate asserting every `corpus/valid` fixture is executed, plus `bench/**` in `check_corpus.py` | **accept-modified** | Both adopted: §7 gate condition 4, and W7. Modified only in that `bench/**` is **not** a numerator source — `tight.agents` counts because `differential.py` executes it, so no scan root is widened and the finding's own precedent-setting concern does not arise. |
| 6 | the floor and the current count checked in as data | **accept-modified** | New `prelude/coverage.lock`, not `prelude.json` — see finding 6. Three conditions, not two: below floor, below lock (ratchet), above lock (stale). |
| 7 | `prelude/generate.py:158`, the second copy | accept | W1. |
| 8 | a rebase plan for `differential.py` against Phase 1 | accept | §3 and §9 risk 2: W6 is rebased onto Phase 1's edit, and the orchestrator decides which phase pays if the order flips. |
| 9 | a per-instantiation coverage record | accept | `coverage.lock`'s `instantiations` and `unproven` fields, plus §2's rule that every `N`-typed builtin must execute at `Int64` and `Float64`. §9 risk 5 states honestly that no gate verifies this field against the fixtures. |
| 10 | a NaN case in fixture `13` | **accept-modified** | Adopted, but it cannot live in `13`'s `Int64`-argument entry — NaN is only reachable through `(string-to-float64 "nan")` or `(/ 0.0 0.0)`, and the latter traps. It becomes fixture `13` **entry 2**, taking two `String`s, with `["nan","1.0"]` and `["1.0","nan"]` pinning both operand positions. |

---

## "What would slip through the gate" (8 rows)

| # | scenario | disposition | closed by |
|---|---|---|---|
| 1 | nine fixtures land, no task files; 107/107 with zero execution | accept | §2's executed-set numerator + §7 gate condition 4. Same as finding 1. |
| 2 | `/`, `mod`, `checked-div`, `checked-mod` stay `i64`-only | accept | §6 rows 2-5 repair them; W5 makes the class un-shippable; fixture `13` executes the float leg. Same as finding 2. |
| 3 | `list-sort-by`'s original bug recommitted — same-typed arguments swapped | accept | every §5 case names the wrong implementation it rules out; the same-typed pairs the finding lists (`string-index-of`, `string-contains?`, `string-starts-with?`, `list-append`, `min`, `max`, `!=`) each have an asymmetric case. |
| 4 | `result-map-err` implemented as the identity | accept | fixture `11` case 2 prints the mapped error. |
| 5 | `<=` implemented as `<` | accept | fixture `12` cases `[3,3,7]` and `[3,7,7]`. |
| 6 | `min`/`max` "repaired" with the inline template | accept | §6 row 7 moves both into `rt.rs`; fixture `13` entry 2 pins NaN in both operand positions. |
| 7 | the floor raised by a documentation edit | accept | spec fragments are not in the numerator (§7). |
| 8 | the floor lowered in a one-character diff | accept | floor is data in `coverage.lock`, and lowering it does not clear the ratchet, which is computed against `executed`. |

---

## The review's own negative claim-checks

Each is already carried by a row above; listed so none is lost.

| review claim-check row | carried by |
|---|---|
| "§5's inline-`if` `min` replacement is correct — **no, defect**" | 3a / 3b / 3c |
| "repair count is 2 mandatory — **no, defect**" | 2 |
| "spec fragments count toward coverage — **defect found**" | 1 |
| "…hardcoded to a single `String` input — **defect found**" | 4 |
| "the heuristic exists once — **no**" | 9 |
| "program mode has an oracle — **no**" | 5, and non-discriminating row `09`/program mode |
| "Phase 1's `PLAN.md` does not exist yet — **no, stale**" | 8 |
| "§5's `rt::sum<T: std::iter::Sum<T>>` compiles — **yes, plan is right**" | closed in the plan's favour, then **superseded**: it compiles, but folds `f64` from `-0.0`. §6 row 6 uses `fold(T::ZERO, Num::plus)` instead. See finding 12. |

---

## Found by v2, not in the review

Not reconciliation rows — new evidence the re-plan turned up. Each is carried in `PLAN.md` §1.

1. **`list-sort`, `list-min`, `list-max` fail at `Float64`** for a reason unrelated to `defenum`:
   `f64` is not `Ord`. Both v1 and the review attributed these three to the Phase-1 derive gap.
   (§1.2 — 3 builtins, 3 instantiations.)
2. **All six `Map` builtins fail at a `Float64` key** — 24 instantiations, `E0277`, named by
   neither document. It is a spec contradiction, not a lowering bug: `AGENT_SPEC_CORE.md:123` asks
   only for equality while `:545-547` specifies sorted keys. Closed by rule-13 (W4). (§1.6.)
3. **The executed baseline is 21/107, not 36 and not 43.** 86 builtins remain, not 71. (§1.3.)
4. **`rt::sum` of an empty `Vec<f64>` is `-0.0`, and the divergence is invisible to the current
   comparator** (`-0.0 == 0` is `True` in Python). (§1.5.)
5. **All six `IoError` constructors are executable and agree on both backends** — the review's
   "unreachable" applies to the host error *mapping*, not the constructors. (§1.8.)
6. **`bench/harness/run.py:174,189` globs `bench/tasks/*.json`** — putting fixture case files there
   would make the measurement harness treat them as measurement tasks. They go in
   `backend/cases/`. (§1.9.)
7. **No `.github/` or CI config exists**, so v1's "an external consumer may parse
   `closure_audit.py`'s exit code" risk is closed rather than carried. (§1.9.)

---

# v2 → v3 dispositions (2026-08-29, after Phase 1 landed)

One row per parked amendment and per claim re-verified against the tree. `holds` / `changed` /
`no longer applies`. Every verdict was settled by running the command or opening the file named in
the evidence column; nothing was carried over on trust, including `ROADMAP.md`'s own figures, which
were re-derived rather than quoted.

## The three parked amendments

| # | amendment as parked | disposition | evidence |
|---|---|---|---|
| **A1** | B1 open: v2's numerator is a static tree-sitter scan; a dead-branch fixture moved it 21 → 32 with nothing executed. Fix on record: trace the generated Python and fail on unreached lines. | **changed** — closed by a *builtin-level* tracer rather than a line tracer, and the baseline it reports is **33/107, not 21/107** | The precedent was found in the session scratchpad (`execcov.py`, `mentioned.py`, `asexhits.py`) and re-run: `programs executed : 18`, `EXECUTED builtins : 33/107 (30%)`; `mentioned : 38 / executed : 33 / mentioned-but-never-executed : 17 / executed-but-not-in-scan-set : 12 / neither : 57`. `ROADMAP.md` §6's three numbers reproduce exactly. The mechanism wraps each `to_python.LOWER` template as `(hit(name) or (tpl))`, which fires exactly when the emitted expression is evaluated — strictly more precise than unreached-line detection for this numerator, and it needs no `sys.settrace`. Folded into v3 §7.1 as `backend/exec_coverage.py`; cost measured `real 0m1.354s` for 18 programs. v2's numerator (`run_query` over `differential.py`'s two sources, 21) is replaced, not adjusted: the scan is wrong in **both** directions — 17 counted builtins never run, 12 running builtins are outside the scan root. |
| **A2** | `rule-13` is taken; use `rule-14`. | **no longer applies** — the parked instruction is superseded by PCP `d-bad1`; the code is **`map-key-order`** | `checker/resolve.py:266` reports `rule-13` for a private type in an exported signature; `AGENT_SPEC_CORE.md:695-700` is checklist item 13. `.pcp/lang/checker.md:70` (`d-bad1`, Active): "A check the conformance checklist does not list is coded by name, never by the next free rule number." Landed instances read from `resolve.py`: `type-arity` (`:312`), `internal` (`:633`), plus `unresolved-import`, `arity`, `ctor`. `AGENT_SPEC_CORE.md:682-706` read in full: items 1-13, none covering the domain of a `Map` key (item 6 is mixing numeric operands). So no §9 entry justifies a number. v3 §4 W4 codes it `map-key-order`; fixture `grammar/corpus/semantic/map-float-key.agents`, `; expect-only: map-key-order` — safe because the same program reports **nothing** today (checker exit 0 on the `map-get`-at-`Float64`-key probe). |
| **A3** | Renumber the ten fixtures (verifier said 13–22). | **changed** — they renumber to **19–28** | `ls grammar/corpus/valid/` → 18 fixtures, `01-basics` … `18-pattern-binders`. The verifier's 13–22 was written when the corpus held 12. |

## Re-verified claims

| claim (v2) | disposition | evidence |
|---|---|---|
| §1.1 "all seven gates green, 47 tests" | **changed** — all seven still green, **79 tests** | `pytest backend/t bench/algo checker/t -q` → `79 passed in 0.55s`. Gate-by-gate: `validate.py` 0 (`0 failure(s)`); `closure_audit.py` 0 (`distinct call heads : 56`, `exercised builtins : 38/107 (35%)`, `OK: spec and corpus are closed`); `generate.py --check` 0; `checker/gate.py` 0; `check_corpus.py` 0 (18 rows, columns `python compile run rust rustc`, 10 with a `run` verdict); `differential.py` 0 (`0 disagreement(s) across 7 function cases + 7 program cases x 2 backends`). |
| §1.1 `closure_audit.py` prints `36/107 (33%)` | **changed** — prints `38/107 (35%)` | the run above; Phase 1's four new fixtures added two mentioned builtins. |
| §1.1 `differential.py` "7 function cases + 4 program cases" | **changed** — 7 + **7** | Phase 1 added `13-module-program`, `14-sequenced-bodies`, `15-shadowed-binders` as program cases (`differential.py:135-160`). |
| §1.2 the monomorphism sweep: 440 probes, 39 failures over 16 builtins | **holds, verbatim** | `audit.py` re-run: `total 440 ok 401 checker_reject 0 bad 39`, 39.7 s. Per-builtin: `/ 2, mod 2, checked-div 2, checked-mod 2, list-sum 2, min 1, max 1, list-sort 1, list-min 1, list-max 1, map-get 4, map-set 4, map-has? 4, map-remove 4, map-pairs 4, map-from-pairs 4`. Domain arithmetic re-derived independently: 107 = 9 effectful + 2 variadic + 7 higher-order + 33 monomorphic + **56 probed** → 440; 10 `Map` builtins × `K=Float64` × 4 `V` = 40 → **400**. |
| §1.3 the executed baseline is 21/107, 86 remain | **changed** — **33/107**, **74** remain | see A1. The 74 partition exactly across §5's ten fixtures (11+5+6+7+13+8+8+4+7+5), and 33+74 = 107, so the fixture matrix stands unchanged in content; only the per-fixture *new-builtin* counts moved, because 12 builtins v2 listed as remaining (`some none ok err list list-cons list-max map-from-pairs map-pairs map-values not option-or string-empty? str string-join string-upper string-from-int64 string-from-float64`, in the relevant subsets) already execute. |
| §6 repair 2 — `/` `i64`-only | **holds** | `rt.rs:10 pub fn div(a: i64, b: i64) -> i64`. `Int32` probe → ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``. `Float64` probe → same error, ``expected `i64`, found `f64` ``. Checker exit 0 both. |
| §6 repair 3 — `mod` | **holds** | `rt.rs:14`. `Int32` → ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``; `Float64` → ``expected `i64`, found `f64` ``. |
| §6 repair 4 — `checked-div` | **holds** | `rt.rs:18`. `Int32` → ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``; `Float64` → ``expected `i64`, found `f64` ``. |
| §6 repair 5 — `checked-mod` | **holds** | `rt.rs:19`. `Int32` → ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``; `Float64` → ``expected `i64`, found `f64` ``. |
| §6 repair 6 — `list-sum` `i64`-only against `(List N) -> N` | **holds** | `rt.rs:82 pub fn sum(xs: Vec<i64>) -> i64`. `Int32` → ``error[E0308]: mismatched types`` / ``expected `Vec<i64>`, found `Vec<i32>` ``; `Float64` → ``expected `Vec<i64>`, found `Vec<f64>` ``. |
| §6 repair 7 — `min`/`max` on `f64` | **holds** | `prelude.json` still declares `"rs": "std::cmp::min({0}, {1})"` / `std::cmp::max`. `min` at `Float64` → ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `std::cmp::min` ``; `max` → the same, ``in `std::cmp::max` ``. |
| §6 repairs 8-10 — `list-sort`/`list-min`/`list-max` at `Float64` | **holds** | `rt.rs:66,83,84` still `T: Ord`. Each → ``error[E0277]: the trait bound `f64: Ord` is not satisfied``, `note: required by a bound in` `sort` / `least` / `greatest` respectively. |
| §6 narrowing — six `Map` builtins fail at a `Float64` key | **holds** | `rt.rs:86-95` still `K: Ord`. `map-get` probe → ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `m_get` ``. Sweep confirms 24 failures across the six. |
| §1.7 the arity heuristic: 34 mismatches, two sites, −98 chars | **holds, line numbers moved** | 34 mismatches recomputed against `prelude.json`. Sites are now `prelude/generate.py:30` and `:162` (v2 said `:31`, `:158`). Char delta recomputed by substituting every old call form: **−98** in `HANDBOOK.md` and **−98** in `AGENT_SPEC_CORE.md`; handbook 12,281 → 12,183 chars. |
| §1.9 `bench/harness/run.py` globs `bench/tasks/*.json` | **holds** | `run.py:174` (`--tasks` default) and `:189` (`glob("*.json")`). |
| §1.9 `check_corpus.py` never reaches `bench/` | **holds** | `check_corpus.py:24` — `CORPUS = sorted((ROOT/"grammar"/"corpus"/"valid").glob("*.agents"))`. W7 still owed. |
| §1.9 `differential.py` hardcoded to a single `String` input and a map-only serializer | **holds, line numbers moved** | one task path `:125`; single-arg Python driver `:39`; `.to_string()` inputs `:51`; map-only Rust serializer `:57-61`; no-op normalisation `:70`. |
| §1.9 / W6(d) `programs()` has no expected-output oracle | **no longer applies** — half landed | `differential.py:92-121`: cases are `(argv, fixture, *declared)`; `:104` `want = declared[0] if declared else None`; `:110` `declared_ok`; `:114` `<-- NOT THE DECLARED OUTPUT`. Two cases already carry one. **Still owed:** the per-case `files` map with modes (the fixture argument is one `sample.txt` body, `:107`) and an expected **exit status**. W6(d) rescoped. |
| v2's fixtures are single-module and independent of Phase 1 | **holds, with two scope corrections** | Three representative fixture bodies written and compiled: `band` (fixture 22) and `classify` (fixture 20, `cond`/`:else`) — checker 0, both backends transpile, `rustc` clean. `agg` (fixture 25, `(List Float64)`) — checker 0, both transpile, `rustc` **2 × E0308**, i.e. the W2 `list-sum` defect and nothing else. Corrections: not independent of Phase 1's fixture **numbering** (A3), and they should adopt Phase 1's `; run:` header so `check_corpus.py` gives a `run` verdict rather than `-`. |
| v2's `cond`-using fixtures survive the now-strict resolve pass | **holds** | `classify` probe above; `semantic/unbound-in-cond.agents` exists and `checker/gate.py` is green. |
| W7 acceptance "8 corpus + 2 bench = 10 rows" | **no longer applies** | `check_corpus.py` was rewritten by Phase 1: 18 rows today, no `SKIP_RUST`/`SKIP_PY`, a `run` column. v3 restates W7 as an invariant over every `corpus/valid` and `bench/**` source, with **no count**. |
| W10 "`ROADMAP.md` §2's Rust-backend row reads as *working*" | **no longer applies** | `ROADMAP.md:44` already reads "**working for `Int64`** … Phase 2 owns the repair", and §6 carries a matching bullet. W10 is rescoped to *retire* those statements plus rewrite §6's coverage bullet and extend the `d-bad1` bullet. |

## The verifier's three unresolved notes

| note | disposition | evidence |
|---|---|---|
| `coverage.lock`'s `instantiations` is the sole enforcement of the `N`-at-both-types rule and no gate verifies it | **holds** — and the amendment is now cheap enough to schedule | `prelude/coverage.lock` does not exist (`ls prelude/` → `HANDBOOK.md generate.py prelude.json vocab.py`), so nothing landed. The checker already computes the substitution: `checker/types_.py:131` `from_json(spec, fresh)` and `:160-165` `declared(..., fresh=…)` — "if `fresh` is given they instead become shared metavariables, which is instantiation". `to_python.Transpiler.call` (`:367-383`) holds the head as a Lark `Token` carrying `.line`/`.column`, so the tracer can key hits by `(path, line, col)` and intersect with the checker's per-site map. v3 adds **W9b** for exactly this, with a named fallback: delete the field and demote the rule in the gate's error message rather than leave it implying enforcement. |
| Tier A's probe count, domains and exclusions are recorded nowhere | **holds** | No `coverage.lock`; `monomorphism.py` does not exist. Arithmetic reconfirmed: 56 probed builtins → 440; the exclusion set is 9 effectful, 2 variadic, 7 higher-order, 33 monomorphic. v3 §7.2 adds `tier_a: {probes, domains, excluded}` under the same three-way check as `executed`, and W5's unit tests require a shrunk domain to *fail* rather than to reduce the failure count. |
| the narrowing costs 0 model-facing tokens | **holds** | `HANDBOOK.md:79` still reads ``- Constructed: `(List …)`, `(Option …)`, `(Result …)`, `(Pair …)`, `(Map …)` `` and `## Rules that have no exceptions` (`:32`) says nothing about key ordering. v3 §4 W4's file list now includes `prelude/generate.py`'s Types block plus a regenerate (≈ +60 chars); net phase delta on the handbook ≈ **−38 chars**. |
