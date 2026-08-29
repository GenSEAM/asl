# Phase 2 plan review

## Verdict

**reject** — the plan's success metric (`closure_audit.py`'s call-head count) measures *mention in a
parsed file*, not "transpiled and executed", so a fully plan-conformant implementation can reach
`107/107` with every listed gate green while executing none of the 71 builtins; and the repair list
is provably incomplete (`/`, `mod`, `checked-div`, `checked-mod` carry the exact `list-sum` defect,
two of them inside the "exercised, therefore fine" set the plan never inspected).

## Findings

### 1. blocker — the coverage floor counts mentions, not executions; the phase goal is unmet by a conformant implementation

**Claim under review:** §4/§6 — "Projected coverage … 107/107 (100%)", floor at 95% "cannot regress".

**Evidence.** `grammar/closure_audit.py:57` is the entire scan root:

```
sources = sorted((ROOT / "corpus" / "valid").glob("*.agents"))
```

plus, at `closure_audit.py:59-66`, every ```` ```lisp ```` block in `AGENT_SPEC_CORE.md` containing
`(defun` or `(defschema`, written to a tempdir and appended. Those markdown fragments are never
transpiled, never compiled, never run. Running the audit's own `run_query` per source set:

```
corpus/valid exercised: 35
spec-only exercised   : ['list-get']
```

`list-get` is counted as exercised today **solely** because it appears in a spec markdown block.
The numerator already contains non-executed mentions.

Downstream, nothing turns a corpus fixture into an execution:
- `backend/check_corpus.py:57-59` compiles Rust as `--crate-type=lib` and `py_compile`s Python — it
  never runs either.
- `backend/differential.py` executes exactly two sources: `bench/algo/variants/tight.agents`
  (function mode, `differential.py:110-111`) and `grammar/corpus/valid/08-io.agents` (program mode,
  `differential.py:128-132`). Both are hardcoded.
- No gate asserts that a `corpus/valid` fixture has a differential case.

So an implementer who lands items 1, 5 and 8 (nine fixtures) and silently drops items 6 and 7 (task
files, harness generalisation) gets: `validate.py` green, `closure_audit.py` green at 107/107,
`gate.py` green, `check_corpus.py` green, `differential.py` unchanged and green, `pytest` 47 green.
Phase goal entirely unmet. The plan's §7 acceptance gate cannot distinguish that outcome from the
intended one.

**Amendment (required).**
- The floor's numerator must be computed over the **executed** source set — the sources named by
  `differential.py`'s task list plus its program-mode case list — not over `corpus/valid` ∪ spec.
- Add a gate assertion: every `grammar/corpus/valid/*.agents` appears in at least one
  `differential.py` case, or is on an explicit, reason-carrying skip list (mirroring
  `check_corpus.py:22-23`'s `SKIP_RUST`/`SKIP_PY` convention).
- Keep spec fragments in the *undefined-head* check (that is what closure means) but exclude them
  from the coverage numerator, or the documentation can raise coverage on its own.

### 2. blocker — the repair list is incomplete: `/`, `mod`, `checked-div`, `checked-mod` have the `list-sum` defect

**Claim under review:** §5 "Repair count: **2 mandatory**"; `INVENTORY.md` §3 "61 of the 71 are
**looks fine**"; the whole exercised/unexercised framing.

**Evidence.** `backend/rust/rt.rs:10-19`:

```
pub fn div(a: i64, b: i64) -> i64 { … }
pub fn rem(a: i64, b: i64) -> i64 { … }
pub fn checked_div(a: i64, b: i64) -> Option<i64> { … }
pub fn checked_rem(a: i64, b: i64) -> Option<i64> { … }
```

Declared types are `/` `N N -> N`, `mod` `N N -> N`, `checked-div`/`checked-mod`
`N N -> (Option N)`. `checker/types_.py:28` `NUMERIC = {"Int32", "Int64", "Float64"}`. Probe
(scratchpad, checker clean, `to_rust` exit 0):

```lisp
(defun total [(xs (List Float64))] -> Float64 (list-sum xs))
(defun ratio [(a Float64) (b Float64)] -> (Option Float64) (checked-div a b))
(defun rem32 [(a Int32) (b Int32)] -> Int32 (mod a b))
(defun quot32 [(a Int32) (b Int32)] -> Int32 (/ a b))
```

`checker/resolve.check_file` → `CLEAN`. `rustc` (with §5's generic `rt::sum` already applied):

```
error[E0308]: arguments to this function are incorrect
error[E0308]: mismatched types
error[E0308]: arguments to this function are incorrect
error[E0308]: mismatched types
error[E0308]: arguments to this function are incorrect
error[E0308]: mismatched types
error: aborting due to 6 previous errors
```

Six errors, from `ratio`, `rem32`, `quot32`. `total` compiles clean — the generic-`sum` repair works
(see finding 5). `/` and `mod` are in the **exercised 36**; `checked-div`/`checked-mod` are in the
61 the inventory calls "looks fine". Both classifications are wrong, and the plan inherits both.

This falsifies the plan's organising premise. "Exercised" in this repo means "exercised at one
instantiation" — `Int64`. Every generic-signature/monomorphic-helper pair survives that.

**Amendment (required).** Add to the repair list: generalise `rt::div`, `rt::rem`,
`rt::checked_div`, `rt::checked_rem` over the three `N` instantiations (or `rt::div`/`rt::rem` per
the Python semantics at `backend/runtime.py:33-45`, which already branch on `isinstance(a, int)`).
Then audit *every* `rt.rs` helper against its declared signature's type variables — this is a
mechanical check the plan should contain as a work item, not a per-builtin eyeball.

### 3. blocker — §5's `min`/`max` replacement templates are wrong twice over

**Claim under review:** §5 — `"rs": "(if {0} <= {1} {{ {0} }} else {{ {1} }})"`.

**Evidence (a) — the defect being repaired is real.** `rustup run stable rustc`:

```
error[E0277]: the trait bound `f64: Ord` is not satisfied
    --> cmpmin.rs:3:20
   3 |     println!("{}", std::cmp::min(a, b));
     |                    ^^^^^^^^^^^^^ the trait `Ord` is not implemented for `f64`
```

Confirmed also end-to-end: `(defun smaller [(a Float64) (b Float64)] -> Float64 (min a b))` checks
CLEAN and emits `std::cmp::min(a.clone(), b.clone())`, which `rustc` rejects with the same E0277.

**Evidence (b) — the proposed replacement double-evaluates `{0}`.** The template substitutes `{0}`
twice. `backend/to_rust.py` inserts `.clone()` on *identifier* arguments only; a nested call
argument is emitted bare, so `(min (list-sum xs) 2.0)` becomes an expression evaluating `rt::sum(…)`
twice. With a non-`Copy` argument that is a hard error:

```
error[E0382]: use of moved value: `xs`
 --> mintest.rs:8:39
  |
7 |     let xs: Vec<i64> = vec![1,2,3];
  |         -- move occurs because `xs` has type `Vec<i64>`, which does not implement the `Copy` trait
```

Even where `.clone()` rescues it, the argument expression runs twice — a semantic difference from
Python's `min({0}, {1})`, which evaluates once.

**Evidence (c) — NaN parity is inverted, and §8 dismisses this as "moot".**

```
py min(nan,1.0) = nan | min(1.0,nan) = 1.0
py max(nan,1.0) = nan | max(1.0,nan) = 1.0
planA min(nan,1) = 1.0        <-- §5's template
rtfix min(nan,1) = NaN        <-- if b < a { b } else { a }
```

`if a <= b { a } else { b }` returns the *second* argument when the first is NaN; Python (and
`Math.min`) return the first. §8 waves this off pending "whether the checker allows a NaN literal" —
NaN needs no literal: `(/ 0.0 0.0)` and `(string-to-float64 "nan")` both reach it.

**Amendment (required).** Put the comparison in the runtime, not the template:

```rust
pub fn min<T: PartialOrd>(a: T, b: T) -> T { if b < a { b } else { a } }
pub fn max<T: PartialOrd>(a: T, b: T) -> T { if b > a { b } else { a } }
```

templates `rt::min({0}, {1})` / `rt::max({0}, {1})`. Single evaluation, no literal braces to double,
and the `b`-relative comparison reproduces Python's exact tie/NaN behaviour. `max` stops being
"optional bonus": it is the same defect at an *exercised* builtin, which is precisely finding 2's
lesson.

### 4. blocker — `differential.py` generalisation is scoped to return shape only; input shape and shape composition are unplanned

**Claim under review:** §3 item 6 / §8 last bullet — the generalisation is described as adding a
`"return_shape": "scalar"|"list"|"option"|"result"|"pair"|"map"` field plus a Rust-side dispatch.

**Confirmed hardcoding** (as the plan and `ORCHESTRATOR-LOG.md` state):
- `differential.py:110-111` — single task file, single source.
- `differential.py:47,51` — `inputs = ", ".join(f'{json.dumps(i)}.to_string()' …)`, `let ins:
  Vec<String>`.
- `differential.py:35` — `fn(i) for i,_ in json.loads(...)`.
- `differential.py:53-57` — `let g = {fn}(i); for (k, v) in g.iter() { … }`, the histogram-only
  serializer.
- `differential.py:66` — the no-op `raw.replace("{","{").replace("}","}")` normalisation.

**What the plan missed.** The harness is hardcoded to a **single `String` input**, not only to a
single return shape. §4's own case designs need more:

| fixture | described case | needs |
|---|---|---|
| `10` | `("3","x")` vs `("x","3")` | 2 inputs |
| `12` | "swapping which bound is passed first" | 3 inputs (`lo`, `x`, `hi`) |
| `13` | "a `Float64` pair through `min`" | 2 non-String inputs |
| `14`,`15`,`16` | playlist / roster / word map | `(List T)`, `(Map K V)` inputs |

Return shapes also **compose**: `list-slice` returns `(Option (List T))`, `list-index-of` returns
`(Option Int64)`, `map-pairs` returns `(List (Pair K V))`. A flat six-value enum cannot express any
of them; the serializer must be recursive over the declared return type (which
`prelude/vocab.parse_signature` already produces).

**Amendment (required).** Restate item 6 as: (a) case inputs become a list of typed arguments with a
declared `arg_types`; (b) the Rust serializer is driven recursively by the entry's parsed return
type, not by a flat tag; (c) the Python side is normalised too (`_as.NONE` is the tuple `("none",)`
at `backend/runtime.py:9`, which JSON-encodes as `["none"]` — the Rust side must emit the same).
Blast radius on the existing case: the histogram task gains `arg_types: ["String"]` and its return
type comes from the entry signature already recorded in `bench/tasks/histogram.json`
(`"signature": "(defun histogram [(text String)] -> (Map String Int64))"`), so the byte-for-byte
before/after diff the plan asks for is achievable — but it is one task, and it is the only regression
guard the refactor has.

### 5. major — §4's fixture matrix does not specify discriminating cases; several described programs cannot discriminate at all

The project's own evidence (`ROADMAP.md:204-205`) is that `list-sort-by` shipped **with its
arguments in the wrong order**. Mention does not catch that; compilation does not catch it; only an
executed case whose correct answer differs from the wrong-order answer catches it. §4 states a
discriminating intent for 4 of 9 fixtures (`10`, `12` partially, `13` partially, `14`, `17`
partially) and leaves the rest as prose. Full table below.

The structurally worst one: fixture `11` routes the failure path through
`result-to-option` → `option-or`, which **discards the error value**. `result-map-err` therefore has
no observable effect in that program: replacing it with the identity, or with `result-map`, produces
byte-identical output on all three described cases.

Second-worst: fixture `09` runs in **program mode**, and `programs()` (`differential.py:87-105`)
compares `python` against `rust` only — there is no expected-output oracle at all
(`seen["python"] == seen["rust"]`). A defect present in the shared `prelude.json` declaration rather
than in one target's template is invisible there. Additionally, `permission-denied`,
`already-exists`, `interrupted` and `other` appear only as `match` arms that no described case
reaches: compiled, never executed.

**Amendment.** §4 must carry, per fixture, the literal case inputs and expected outputs, and a
one-line note naming which wrong implementation each case rules out. Add the replacements in the
table below.

### 6. major — the coverage gate as designed can be made green by a documentation edit, and cannot see vocabulary shrinkage

**Where.** §6 puts a hard `95` in `grammar/closure_audit.py` after `return len(undefined)`
(`closure_audit.py:88`), with the exit code becoming
`len(undefined) + (0 if pct >= 95 else 1)`.

**Arithmetic check — correct.** `closure_audit.py:79-80` computes
`100*len(calls & builtins)//max(len(builtins),1)` — integer floor. `100*102//107 = 95`,
`100*101//107 = 94`. The plan's "102 builtins must be exercised, at most 5 unexercised" is right.

**Denominator check — the plan does not state this, but it is already correct.** `107` includes the
10 operator-headed builtins (`+ - * / = != < <= > >=`), and `closure_audit.py:32-37`'s query captures
`(call callee: (operator))` as well as `(ident)` and `(qualified)`. The 26%-vs-operators mistake
`ROADMAP.md:202-203` records is fixed. No action needed; the plan should say so explicitly since a
reader cannot tell from §6.

**How a well-meaning edit makes it green while coverage falls.**
1. **Add a `defun` example to `AGENT_SPEC_CORE.md`.** Spec fragments feed the numerator
   (`closure_audit.py:59-66`, verified: `list-get` is spec-only today). One illustrative snippet
   naming 60 builtins pushes the figure to 100% with zero transpilation and zero execution. This is
   the single most likely benign edit, because `AGENT_SPEC_CORE.md` §6 is *generated from the same
   `prelude.json`* the denominator comes from.
2. **Delete an unexercised builtin from `prelude.json`.** Numerator unchanged, denominator drops,
   ratio rises. The gate measures `exercised/declared`, so vocabulary shrinkage always reads as
   improvement. (Deleting a *fixture* correctly fails the gate — that direction works.)
3. **Widen the scan root again** (item 1's own precedent) to any directory the compile gates do not
   cover.

**Also.** `95` as a bare literal in the gate can be lowered in a one-character diff with no test
failing. Put the floor and the current exercised count in `prelude/prelude.json` (the file that
already owns the vocabulary) or in a checked-in `coverage.lock`, and have the gate fail on *either*
a drop below the floor *or* a silent decrease in the recorded count — a floor plus ratchet, not one
or the other.

**On hard-floor-vs-ratchet.** The plan's reasoning (95% is already committed at
`.plans/PHASES.md:32`, verified verbatim: "Raise coverage to ≥95%") is sound, but a hard floor alone
permits a regression from 100% to 95% unnoticed. Both.

### 7. major — a generic builtin exercised at one instantiation is not exercised; the 100% claim does not survive that distinction

§5 defers the 8 `defenum`-Ord builtins and has fixtures `15`/`16` "sidestep the gap by using only
primitive-typed lists/map-keys (`Int64`/`String`)". §1 makes the parallel argument for the 7
bench-proven builtins ("proven working today, with primitive `Map<String, Int64>` keys").

Finding 2 is the counter-example that settles this: `/` and `mod` are exercised — at `Int64` — and
are broken at `Int32` and `Float64`. `list-sum` is the same shape. Exercising `list-sort` at
`(List Int64)` proves nothing about `(List MyEnum)`; exercising `map-keys` at `String` proves nothing
about an enum key. So:

- The plan's "**107/107 (100%)**" is a true statement about `closure_audit.py`'s metric and a false
  statement about the phase goal as written in the brief.
- The plan should say so in §4 rather than projecting 100%, and should record per-builtin **which
  instantiations** are covered — that is the number that would have caught `list-sum`, `/` and `mod`.

The plan is otherwise **correct** not to re-plan the `defenum` fix: `.plans/ORCHESTRATOR-LOG.md:10-14`
assigns it to Phase 1, and `.plans/phase-1/PLAN.md:354` (`W7 — Rust defenum/defschema generics and
recursion (prerequisite)`) and `:520-525` confirm Phase 1 owns it, derives included. §5 does not
schedule the work. Verdict on that sub-question: **sound**.

### 8. minor — §8's Phase-1 uncertainty is stale, and the independence claim has three unverified points

§8: "Phase 1's own `PLAN.md` does not exist yet at this writing". It exists —
`.plans/phase-1/PLAN.md`, 36 KB. Reading it:

| Phase 1 item | collision with Phase 2 |
|---|---|
| `PLAN.md:386` — "delete `06-module.agents` from `SKIP_RUST` and `SKIP_PY` (`:22-23`)" | `check_corpus.py` grows a fixture; Phase 2's fixtures land in the same glob (`check_corpus.py:18`). No conflict, but the gate's row count changes. |
| `PLAN.md:431` — "**backend/differential.py**" (adds a module program-mode case) | **Direct textual collision** with Phase 2 item 6, which rewrites `run_rust`/`main`, and with fixture `09`, which extends the same `differential.py:128-132` case list. |
| `PLAN.md:354`, `:520-525` — W7 `defenum`/`defschema` derives and generics | Changes `to_rust.py:128`/`:137`, the derive lines Phase 2's §5 reasons about. Phase 2's "sidestep with primitives" may become unnecessary. |
| both grammars, `checker/types_.py`/`resolve.py` | All 9 Phase 2 fixtures must re-pass `grammar/validate.py` and `checker/gate.py:39` after Phase 1. |

**Re-check after Phase 1 lands:** fixture `10` and `13` (as §8 already says, both construct
`Pair`/records); **plus** every fixture, against `differential.py` as Phase 1 leaves it — item 6 must
be rebased, not merged; **plus** §5's primitive-only choice in `15`/`16`, which should be revisited
once W7 lands (if enums derive `Ord`, exercise them).

### 9. minor — item 2 fixes one of the two copies of the arity heuristic

**Claim verified exactly.** Diffing `len(lhs.split())` against `len(parse_signature(t)[0])` over all
107 builtins: **34** mismatches — the plan's number, not the inventory's 11. Sample:
`map-from-pairs` 4→1, `map-set` 5→3, `list-append` 4→2, `list-empty?` 2→1.

The heuristic appears **twice**: `prelude/generate.py:31` (in `signature()`, which item 2 fixes) and
`prelude/generate.py:158` (in `validate_templates()`, which item 2 does not mention). The second is
harmless today only because it formats with `max(n, 4)` dummy args and no template exceeds three
placeholders. Fix both, or the drift the plan is closing stays half-open.

`prelude/generate.py --check` exits 0 today (verified), and `.venv/bin/python -m pytest backend/t
bench/algo checker/t -q` reports `47 passed in 0.16s` — §7's "≥47 pass" baseline is correct.

### 10. minor — widening the scan root to `bench/` adds sources no compile gate covers

Item 1 is correct in direction and its arithmetic is exactly right (verified: bench adds
`list-max`, `map-from-pairs`, `map-pairs`, `map-values`, `not`, `option-or`, `string-empty?` — the
plan's 7; total goes 36 → 43, and 64 remain). But `check_corpus.py:18` globs `corpus/valid` only, so
after item 1 the floor's numerator draws on files that no gate transpiles or compiles.

Today this is harmless — I compiled `bench/algo/histogram.agents` (`to_rust` exit 0, `rustc
--crate-type=lib` 0 errors) and it contributes **no** builtin that `tight.agents` does not already
contribute. But the invariant "everything in the numerator is compiled" is what makes the floor mean
anything. **Amendment:** if `bench/**/*.agents` counts toward coverage, add it to
`check_corpus.py`'s scan in the same change.

### 11. minor — §9's PCP entry 5 records a Phase-1-owned item as unowned

§9 bullet 5 records the `defenum` derive gap as "new, deferred, out of Phase 2's scope".
`.plans/ORCHESTRATOR-LOG.md:10-14` already records it and assigns it to Phase 1. Recording it again
as new creates a second owner for one defect — the exact failure mode the orchestrator log exists to
prevent. Reword as a cross-reference, not a new gap.

### 12. minor — `list-sum` on an empty `Float64` list diverges between backends

Python `sum([])` → `0` (int). Rust `Vec<f64>::into_iter().sum()` → `-0.0`:

```
py sum([]) = 0
rust sum(empty f64) = -0.0
```

JSON-compared by `differential.py`, `0` ≠ `-0.0`. Fixture `15`'s empty-roster case (which §4 wants,
for `list-empty?`) will trip this. Not a reason to drop the case — it is a real portability defect
worth recording — but §7's "all seven commands exit 0" will not hold on the first run.

## Non-discriminating differential cases

| fixture | case as described in §4 | why it does not discriminate | replacement input |
|---|---|---|---|
| `09-io-errors` | "an existing writable path (append succeeds)" | `file-append(path, content)` args swapped still writes *a* file; the program never reads back, so stdout is unchanged | append `"B"` to a file pre-seeded with `"A"`, then `file-read` it and print — swapped args produce `A` not `AB` |
| `09-io-errors` | all 4 remaining `IoError` cases | `permission-denied`, `already-exists`, `interrupted`, `other` are `match` arms no described case reaches — compiled, never executed | add a `chmod 000` path (permission-denied); accept that `interrupted`/`other` are unreachable and record it rather than claiming coverage |
| `09-io-errors` | program mode generally | `programs()` compares python vs rust only (`differential.py:101`) — no oracle; a shared-declaration defect is invisible | add the expected stdout/exit to the case tuples and assert all three agree |
| `10-option-result-ctors` | "`("3","x")` vs `("x","3")`" | correct intent, but the harness takes **one** `String` (`differential.py:35,47,51`); as written the case cannot be expressed | single input `"3,x"` / `"x,3"`, entry splits — and the returned string must render both components positionally (`"some(3)|none"`) or a `pair` swap is invisible |
| `10-option-result-ctors` | `is-ok?`/`is-err?` | if every case parses successfully, `is-err?` never returns `true`; swapping the two is undetectable | require ≥1 case yielding `err` and ≥1 yielding `ok`, both printed |
| `11-option-result-combinators` | "downgrade failure with `result-to-option`, fall back with `option-or`" | **the error value is discarded** — `result-map-err` replaced by identity, or by `result-map`, gives byte-identical output on all 3 cases | add a fourth case that returns the *mapped error text* (e.g. via `match` on the `Result` before the downgrade), so `result-map-err`'s function is observable |
| `12-boolean-algebra` | "`lo <= x`, `x <= hi`" | `<=` vs `<` is discriminated **only** at equality; no described case puts `x` on a bound | cases `x == lo` and `x == hi` exactly (e.g. `lo=3, hi=7, x=3` and `x=7`), plus `x=2`, `x=8` |
| `12-boolean-algebra` | "combined with `and`/`or`" | `and`↔`or` swap is invisible unless some case has exactly one operand true | ensure the four operand combinations TT / TF / FT / FF all occur across cases |
| `12-boolean-algebra` | `>=` listed as covered | the described program uses `<=` twice and no `>=` | write one bound as `(>= hi x)` so the builtin actually appears |
| `13-numeric-conversion` | "an out-of-`Int32`-range `Int64`" | any large value passes; an off-by-one in `i32::try_from` (`rt.rs:39`) needs the boundary | `2147483647` → `some`, `2147483648` → `none`, `-2147483648` → `some`, `-2147483649` → `none` |
| `13-numeric-conversion` | "guard a derived ratio with `checked-div`/`checked-mod`" | swapping the two is invisible whenever quotient == remainder | a case where they differ, e.g. `7 / 2` → `some 3` vs `7 mod 2` → `some 1`, both printed |
| `13-numeric-conversion` | `int32-to-int64`, `int64-to-float64` | widenings; a wrong lowering is silent at small magnitudes | `int64-to-float64` on `9007199254740993` (2⁵³+1) — the exact value `differential.py`'s docstring cites as a known cross-runtime divergence |
| `13-numeric-conversion` | `neg` | `neg 0` and any symmetric input coincide with identity | non-zero, and one negative input so `neg` is not confusable with `abs` |
| `14-list-reshaping` | `list-tail` | if the list is reversed first, `list-tail` of the reversed list can coincide with other slicings | length ≥3, distinct elements, `list-tail` result printed on its own |
| `15-list-aggregation` | "a sorted-order check" | `list-sort` on already-sorted input is the identity | unsorted input with a duplicate, e.g. `[3, 1, 3, 2]` |
| `15-list-aggregation` | `list-min`/`list-max` | swapped if the list is a single element or all equal | ≥3 distinct values, both results printed |
| `15-list-aggregation` | `list-length` | off-by-one coincides with the looked-up index for `n=1` | roster length ≥3, and an index lookup that is neither `0` nor `length-1` |
| `15-list-aggregation` | "`list-sum` MUST use `Float64`" | correct and load-bearing — keep. But add: empty list (finding 12 — expect `0` vs `-0.0` divergence) and a sum whose float result is not an integer (`0.1 + 0.2`) |  |
| `16-map-lifecycle` | "add-then-remove sequence" | `map-remove` on an absent key is a no-op and coincides with a correct removal if the key was never added | remove a key that **is** present, and separately one that is not; print `map-size` after each |
| `16-map-lifecycle` | `map-has?` | one-sided; a constant-`true` implementation passes | one present key and one absent key |
| `16-map-lifecycle` | `map-keys` vs `map-values` | type-distinct here (`String` vs `Int64`) so a swap fails to compile — no execution needed; **but** that means the case proves nothing about the builtins | fine as coverage; do not claim it as a discriminating case |
| `17-string-transforms` | `string-index-of` | **both arguments are `String`** — a haystack/needle swap type-checks and compiles; invisible unless the needle is not a substring of itself-reversed context | `(string-index-of "banana" "na")` → `some 2`; swapped → `none`. Must assert the `some 2`, not just `is-some?` |
| `17-string-transforms` | `string-starts-with?` / `string-ends-with?` | swap invisible when prefix == suffix, or when the needle occurs at both ends | needle at the start only (`"log:"` in `"log:hello"`), and separately at the end only |
| `17-string-transforms` | `string-replace` | §4 covers `replaceAll` vs `replace`; it does **not** cover a `from`/`to` swap | `(string-replace "aXbXc" "X" "-")` → `"a-b-c"`; swapped `from`/`to` → `"aXbXc"` unchanged |
| `17-string-transforms` | `string-reverse` | palindromic or single-char input is the identity | `"abc"` → `"cba"` |
| `17-string-transforms` | `string-lower` | already-lowercase input is the identity | input with an uppercase run |
| `17-string-transforms` | `string-empty?` | one-sided | one empty and one non-empty case |

## Claims checked

| claim | cited location | verified? | note |
|---|---|---|---|
| `rt::sum` monomorphic `Vec<i64>` | `backend/rust/rt.rs:82` | **yes** | verbatim `pub fn sum(xs: Vec<i64>) -> i64 { xs.iter().sum() }` |
| `NUMERIC` admits `Float64` | `checker/types_.py:28` | **yes** | `NUMERIC = {"Int32", "Int64", "Float64"}` |
| `(list-sum (list 1.0 …))` type-checks then fails `rustc` | §1 claim (a) | **yes** | `check_file` → CLEAN; `rustc` → `error[E0308] expected Vec<i64>, found Vec<f64>` |
| §5's `rt::sum<T: std::iter::Sum<T>>` repair compiles | §8 "unverified" | **yes — plan is right** | `rustc --edition 2021` exit 0 for `i64`, `f64`, `i32`; and the `total` probe compiles clean. §8's risk can be closed. |
| `defenum` derives only `Debug, Clone, PartialEq` | `backend/to_rust.py:137` | **yes** | verbatim |
| `defschema` derives full `Ord` | `backend/to_rust.py:128` | **yes** | `#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]` |
| `rt.rs` bounds per row (`sort`:66, `least`:83, `greatest`:84, `m_del`:91, `m_pairs`:92, `m_from`:95) | `INVENTORY.md` §3 | **yes** | all six line numbers and bounds correct |
| `std::cmp::min` rejects `f64` | §5 `min` row | **yes** | `error[E0277]: the trait bound 'f64: Ord' is not satisfied` |
| §5's inline-`if` `min` replacement is correct | §5 `min` row | **no — defect** | double-evaluates `{0}` (`E0382` on a non-`Copy` argument); NaN result inverted vs Python. See finding 3. |
| repair count is 2 mandatory | §5 | **no — defect** | `/`, `mod`, `checked-div`, `checked-mod` share the defect. See finding 2. |
| `closure_audit.py` scans only `corpus/valid` + spec | `grammar/closure_audit.py:57-66` | **yes** | line 57 is the glob; 59-66 appends spec fragments |
| the gate's exit code is only the undefined-head count | `grammar/closure_audit.py:88` | **yes** | `return len(undefined)` |
| coverage printed, never enforced | `grammar/closure_audit.py:79-80` | **yes** | integer floor division |
| 36/107 exercised today | §1, `INVENTORY.md` §5 | **yes** | ran the gate: `exercised builtins : 36/107  (33%)` |
| `bench/algo/variants/tight.agents` adds 7 | §1 new finding | **yes** | exactly `list-max, map-from-pairs, map-pairs, map-values, not, option-or, string-empty?`; 36 → 43, 64 remain |
| the 107 denominator includes operators | not stated by the plan | **yes, already correct** | 10 operator names in `prelude.json`; `closure_audit.py:34` captures `(call callee: (operator))` |
| "spec fragments count toward coverage" | **not stated by the plan** | **defect found** | `list-get` is exercised *only* via `AGENT_SPEC_CORE.md`; verified by per-source-set query |
| `generate.py` arity heuristic wrong for 34/107 | §1 | **yes** | reproduced exactly 34; `INVENTORY.md`'s 11 is the undercount, §1's correction stands |
| the heuristic exists once | §3 item 2 (implicitly) | **no** | second copy at `prelude/generate.py:158` in `validate_templates()` |
| `generate.py --check` exits 0 today | §1 / `INVENTORY.md` §2 | **yes** | exit 0 |
| `validate_templates` cannot catch a silently-consumed brace | §1 | **yes** | `generate.py:148-169`; formats with `max(n,4)` dummies, catches only raised exceptions |
| `differential.py` function mode hardcoded to histogram / `Map<String,Int64>` | §3 item 6 | **yes** | `:110-111` task+source, `:53-57` map-only serializer, `:66` normalisation |
| …and hardcoded to a **single `String` input** | **not stated by the plan** | **defect found** | `:35`, `:47`, `:51`. See finding 4. |
| program mode has an oracle | implied by §4 fixture `09` | **no** | `differential.py:101` compares python vs rust only |
| `check_corpus.py` / `differential.py` use `rustup run stable` | §7 | **yes** | `check_corpus.py:57-58`, `differential.py:59-60`, `:80-81` |
| `check_corpus.py`, `gate.py`, `validate.py` auto-discover by glob | §3 item 8 | **yes** | `check_corpus.py:18`, `gate.py:39`, `validate.py:63` |
| 47 tests pass today | §7 | **yes** | `47 passed in 0.16s` |
| `.plans/PHASES.md:32` already commits to ≥95% | §6 | **yes** | "Raise coverage to ≥95%" |
| `ceil(0.95 × 107) = 102` | §6 | **yes** | `100*102//107 = 95`, `100*101//107 = 94` |
| Phase 1's `PLAN.md` "does not exist yet" | §8 | **no — stale** | exists, 36 KB; W7 at `:354` owns the `defenum` derives, `:431` touches `differential.py` |
| Phase 2 does not re-plan the `defenum` fix | vs `ORCHESTRATOR-LOG.md:10-14` | **yes — compliant** | §5 defers it and schedules no work |
| `map-keys`/`map-values`/`map-pairs` are backend-consistent | not claimed | checked anyway — **fine** | Python templates use `sorted(...)`; `rt.rs:1-6` documents the BTreeMap choice. No ordering divergence to design around. |

## Hidden work items

1. **Generalise `rt::div`, `rt::rem`, `rt::checked_div`, `rt::checked_rem`** over `Int32`/`Int64`/
   `Float64` (finding 2). Without this, fixture `13` cannot exercise `checked-div`/`checked-mod` at
   anything but `Int64`, and `/`/`mod` stay broken at two of three instantiations while reported
   green.
2. **A mechanical `rt.rs`-signature-vs-declared-signature audit.** Every helper whose declared
   AgentS signature contains a type variable must be checked for monomorphism. The plan's per-builtin
   eyeball missed four; a script over `vocab.parse_signature` × `rt.rs` would not.
3. **`differential.py` input-shape generalisation** (multi-argument, non-`String`, `List`/`Map`
   arguments) and a **recursive** return serializer driven by the parsed return type — not the flat
   six-shape enum item 6 describes (finding 4).
4. **Python-side output normalisation** in `run_python`, so Option/Result/Pair encode identically on
   both sides (`backend/runtime.py:9`, `:12`).
5. **A gate asserting every `corpus/valid` fixture is executed** by `differential.py` (or explicitly
   skipped with a reason), plus **`bench/**` added to `check_corpus.py`'s scan** if item 1 lets
   `bench/` feed the numerator (findings 1, 10).
6. **The floor's number and the current count checked in as data**, not a literal in the gate
   (finding 6).
7. **`prelude/generate.py:158`** — the second copy of the arity heuristic (finding 9).
8. **Rebase plan for `differential.py` against Phase 1**, which edits the same file (finding 8).
9. **Per-instantiation coverage record** — which type each generic builtin is exercised at
   (finding 7). This is the artifact that would have caught `list-sum`, `/` and `mod`, and the one
   the phase's headline number replaces with a weaker one.
10. **A NaN case in fixture `13`** now that finding 3 shows NaN is reachable without a literal
    (`(/ 0.0 0.0)`, `(string-to-float64 "nan")`), and the two `min` designs disagree on it.

## What would slip through the gate

A plan-conformant implementation passes all seven §7 commands while being wrong in each of these
ways:

1. **Nine fixtures land, no task files land.** `closure_audit.py` reports 107/107, floor satisfied,
   `differential.py` still runs its two original sources. Zero of the 71 builtins executed. The
   phase's stated goal — "transpiled AND executed" — is entirely unmet and no gate says so. *Caught
   by:* asserting every `corpus/valid` fixture appears in a `differential.py` case, and computing the
   floor over the executed set.
2. **`/`, `mod`, `checked-div`, `checked-mod` stay `i64`-only.** They are exercised at `Int64` by the
   existing corpus and by fixture `13`; every gate is green; the `Float64` and `Int32` paths still
   fail `rustc` exactly as `list-sum` did. *Caught by:* the `rt.rs` monomorphism audit (hidden item
   2), or by fixture `13` declaring its arithmetic at `Float64`.
3. **`list-sort-by`'s original bug, recommitted.** Any builtin whose two arguments share a type
   (`string-index-of`, `string-contains?`, `string-starts-with?`, `list-append`, `min`, `max`, `!=`)
   can have its arguments swapped in one backend without failing `rustc`, `py_compile`, the checker,
   or the closure gate — and without failing `differential.py` if the case input is symmetric. §4
   specifies a discriminating input for only some of them. *Caught by:* the replacement inputs in the
   table above.
4. **`result-map-err` implemented as the identity.** Fixture `11`'s described program discards the
   error value; output is byte-identical. *Caught by:* a case that prints the mapped error.
5. **`<=` implemented as `<`.** Fixture `12` as described never puts a value on a bound. *Caught by:*
   `x == lo` and `x == hi` cases.
6. **`min`/`max` "repaired" with §5's inline template.** Compiles (thanks to `to_rust.py`'s
   `.clone()`), passes every gate, and silently returns the wrong operand for NaN and evaluates its
   first argument twice. *Caught by:* a NaN case, and by putting the comparison in `rt.rs`.
7. **The floor raised by a documentation edit.** Adding `defun` examples to `AGENT_SPEC_CORE.md`
   raises the numerator with no compilation and no execution — and `AGENT_SPEC_CORE.md` §6 is
   *generated from the same `prelude.json`* the denominator comes from, so this is a plausible
   accident, not a contrived one. *Caught by:* excluding spec fragments from the numerator.
8. **The floor lowered in a one-character diff.** `95` is a literal in `closure_audit.py`; nothing
   tests it. *Caught by:* checking the floor and the current count in as data, with a ratchet on the
   count.
