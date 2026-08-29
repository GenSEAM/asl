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
