# Phase 2 implementation review — oracles and repairs

Lens: are the checked-in expected values right, and are the repairs correct.
Method: every value below was derived from `AGENT_SPEC_CORE.md` §6 and `prelude/prelude.json`'s
declared semantics, re-implemented in a standalone oracle that imports nothing from
`backend/`, then compared to the checked-in expectation. Runtime behaviour was probed by
compiling `backend/rust/rt.rs` directly and by transpiling probe fixtures through the real
`to_rust.py` / `to_python.py`.

## Verdict

**accept-with-fixes** — all 78 checked-in function expectations and all 7 new program
expectations are correct, and the three disputed values were adjudicated in the implementer's
favour; but two of the ten repaired lowerings (`list-sort`, `checked-div`/`checked-mod`) leave a
live cross-backend divergence that no executed case can see.

## Independently derived values

Oracle: `scratchpad/oracle.py` (spec-derived; no import of `backend/runtime.py`). Run over every
case in `backend/cases/*.json`:

```
78 cases, 0 disagreements
```

Spot table — the fifteen weighted toward a plausible wrong answer, plus the program mode:

| case | checked-in expectation | my derivation | agree? |
|---|---|---|---|
| `fnum(-7,2)` (mod, negative dividend) | `-5.0\|-3.5\|-1.0\|-14.0\|-9.0\|7.0\|7.0\|-7.0\|2.0\|some -3.5\|some -1.0` | same (`fmod(-7,2) = -1.0`) | yes |
| `fnum(9007199254740993,2)` (2^53+1, exponent) | `…\|1.8014398509481984e+16\|…` | same (`repr(1.8014398509481984e16)`) | yes |
| `fnum(7,3)` (non-terminating quotient) | `2.3333333333333335` | same | yes |
| `fnum(5,0)` (zero divisor at Float64) | `none\|none` | same | yes |
| `num(-7,2)` (trunc, not floor) | `-5\|-3\|-1\|-14\|-9\|7\|7\|-7\|2\|some -3\|some -1` | same | yes |
| `num(9007199254740993,2)` (Int64 exact) | `…\|4503599627370496\|1\|18014398509481986\|…` | same | yes |
| `minmax("nan","1.0")` | `nan\|nan\|none` | same (first arg stands; `f_to_i(NaN)=none`) | yes |
| `minmax("1.0","nan")` | `1.0\|1.0\|some 1` | same | yes |
| `minmax("-3.9","1.5")` (trunc toward zero) | `-3.9\|1.5\|some -3` | same | yes |
| `narrow(9007199254740993)` | `none\|9007199254740992.0\|some 9007199254740992` | same | yes |
| `agg-empty()` (empty `(List Float64)`) | `T\|0\|0.0\|none\|none\|[]` | same (`repr(float(0))`) | yes |
| `agg("0.1,0.2")` | `F\|2\|0.30000000000000004\|0.1\|0.2\|[0.1,0.2]` | same | yes |
| `agg("-2,-9,4")` (negatives) | `F\|3\|-7.0\|-9.0\|4.0\|[-9.0,-2.0,4.0]` | same | yes |
| `lookup("3,1,3,2",9)` (`list-index-of` absent) | `F\|none\|4\|9\|[3,3,2,1]` | same | yes |
| `lookup("3,1,3,2",3)` (first occurrence) | `T\|some 0\|4\|9\|[3,3,2,1]` | same | yes |
| `query("héllo","l")` (non-ASCII index) | `5\|some 2\|T\|F\|F\|F\|5` | same — see §disputed | yes |
| `cut("héllo",1,3)` | `["some","él"]` | same | yes |
| `cut("banana",0,7)` / `(…,3,1)` (slice bounds) | `["none"]` / `["none"]` | same (`0<=a<=b<=n`) | yes |
| `transform("42")` (whole float renders `42.0`) | `42\|42\|24\|42\|42\|n=2\|some 42\|42.0` | same | yes |
| `transform("")` (empty line) | `\|\|\|\|\|n=0\|none\|0.0` | same (`"".split(" ") == [""]`) | yes |
| `band(3,3,7)` … `band(3,5,7)` (5 cases) | `TTFTFFTF` `TTTFTTFF` `FTFTTTFT` `TFTFTFTT` `TTTTTTFF` | identical, all five | yes |
| `lifecycle("c b a","b")` (sorted keys) | `3\|T\|2\|a,c` | same | yes |
| 19-io-errors program cases 1–7 | as declared in `differential.py:program_cases` | hand-derived; all seven agree (append-then-read-back, `absent`, `ENOENT`→`not-found`, `EACCES`→`permission-denied`, EOF `read-line` → `none`, six-label spelling, `read-all`) | yes |

**Disagreements: 0 of 78 (plus 0 of the 7 new program cases).**

## The three disputed values

### Fixture 22 — the plan's §5 table

* **Plan** (`PLAN.md:714` table): `[3,3,7]`→`TTFFF F T F`, `[3,7,7]`→`TTTFT T T F`,
  `[3,2,7]`→`FTFFT T F T`, `[3,8,7]`→`TFTFT F T T`, `[3,5,7]`→`TTTFT T F F`.
* **Implementer**: hand-derived five new strings.
* **My adjudication: implementer right, plan wrong in four of five rows.**

Column 4 is `(> hi x)` with `hi = 7`; it is false only when `x >= 7`. The plan writes `F` in all
five rows, so `[3,3,7]`, `[3,2,7]` and `[3,5,7]` are wrong. Column 7 is
`(or (= x lo) (> x hi))`; for `[3,7,7]` the plan's own columns force `(= x lo) = F` (col 5 says
`x != lo`) and `(> x hi) = F` (col 2 says `hi >= x`), so col 7 must be `F` — the plan writes `T`.
That is the internal inconsistency the implementer reported, and it is real: one column required
to be both `T` and `F` in the same row. My independent derivation reproduces the implementer's
five strings exactly (row `[3,8,7]` was already correct and is unchanged).

### Fixture 27 — `["héllo","l"]`

* **Plan** (`PLAN.md:880`): `5|some 3|T|F|F|F|5`, with the note "a lowering that returned
  `s.find()` directly gives `4` here".
* **Implementer**: `5|some 2|…`, on the ground that the language specifies character indices.
* **My adjudication: implementer right; the plan is wrong twice over.**

Specification, `AGENT_SPEC_CORE.md:117`: *"`String` | Sequence of Unicode scalar values.
**All indices are in characters, never bytes.**"* — and `:513` restates it for
`string-index-of` ("Character index of the first occurrence"). `"héllo"` is `h é l l o`, so the
character index of the first `l` is **2**. The plan's `3` is the byte offset (`h`=1 byte,
`é`=2 bytes), and the plan's parenthetical "`s.find()` gives 4" is wrong too — the raw byte
offset is 3, not 4.

**Both backends agree, and here is how**, which is the load-bearing part: Python's `str.find`
is code-point indexed, so `_as.str_index_of` is char-native by construction; Rust's `str::find`
returns a **byte** offset, and `rt.rs:71-73` converts it —
`s.find(sub).map(|byte| s[..byte].chars().count() as i64)`. `rt::str_len` (`:59`) counts
`chars()`, and `rt::str_slice` (`:66-70`) skips/takes over `chars()`. So the one place a
portability bug could hide — the byte→char conversion in `str_index_of` — is present and
correct, and the checked-in `some 2` is what pins it. Had the plan's `3` been taken, the gate
would have demanded the *byte* offset from Python, which cannot produce it, and the fixture
would have been rewritten until it agreed on a value the specification forbids.

### Fixture 21 — the dead `fallback`

* **Plan**: third field is `(option-or (result-to-option r) -1)` — a literal, with the declared
  `(fallback Int64)` parameter unused; expectations `…|FB|-1`.
* **Implementer**: uses `fallback`; expectations `…|FB|5` and `…|FB|9`.
* **My adjudication: implementer right.** Both readings are internally consistent, but the
  plan's leaves a declared parameter dead, which the checker's own `unused` discipline aside is
  a case that cannot distinguish "the fallback is plumbed through" from "a constant is
  returned". My derivation of the implemented body gives `ok:43|43|43`, `err:E<bad:x>|FB|5`,
  `err:E<bad:>|FB|9` — matching the checked-in file. Note this is a *deviation that changes what
  the case discriminates* (for the better); it is recorded, so no objection.

## Repair audit

| repair | real divergence? | fix correct? | probe and verbatim output |
|---|---|---|---|
| `_as.mod` float path → `math.fmod` | **yes** — `a - div(a,b)*b` is exactly `0.0` for every float pair, against Rust's `%` | **yes**, over all four axes | Rust `rt::rem` vs Python `math.fmod`, nine pairs, byte-identical: `(-7,2)→-1.0`, `(7,-2)→1.0`, `(-7,-2)→-1.0`, `(7.5,2)→1.5`, `(-7.5,2)→-1.5`, `(-4,2)→-0.0`, `(4,-2)→0.0`, `(-0.0,2)→-0.0`, `(7,2.5)→2.0`. Sign follows the **dividend** in every row, matching `prelude.json`'s doc and `:483`. Zero-result sign agrees (`-0.0` vs `0.0`) on both. Integer leg unchanged: `rem(-7,2)=-1`, `rem(7,-2)=1`, `div(-7,2)=-3`. |
| `rt::fmt_f64` | **yes** — `{:?}` gives `NaN` / `1e16` / `1e-5` where `repr` gives `nan` / `1e+16` / `1e-05` | **yes**, exact over 29 values incl. every threshold | Rust `fmt_f64` vs Python `repr(float(x))`, 29 values, **zero differences**. Thresholds probed on both sides of the switch: `1e15→1000000000000000.0`, `1e16→1e+16`, `1e-4→0.0001`, `1e-5→1e-05`; `9.999999999999999e15→1e+16` on both. `-0.0→-0.0`. Subnormals `5e-324→5e-324`, `1e-323→1e-323`, `2.2250738585072014e-308` identical. Near 2^53: `9007199254740992.0`, `9007199254740994.0`, `4503599627370496.0` identical. `inf`/`-inf`/`nan`; `-NaN` renders `nan` on both. Single-digit exponents get the `{:0>2}` pad, three-digit ones are untouched (`5e-324`). |
| `string-from-float64` → `repr(float(...))` | **yes** — `sum([])` is Python `int` `0`, rendered `"0"` against Rust's `"0.0"` | **yes** for observation; the leak itself is still there | `repr(sum([]))` = `0`; `repr(float(sum([])))` = `0.0`; `rt::sum(Vec::<f64>::new())` = `0.0`. See "the leak" below — it is now unobservable, but for a second reason the implementer did not state. |

### Where else the int/float leak is observable

Nowhere, and the reason is worth recording because it is *not* the repair.
`string-from-float64` is the only builtin that renders a `Float64`, so the repair closes the
only rendering path. In a **return** position the leak is invisible for a different reason: the
differential comparator loads both sides with `json.loads` and compares Python objects, and
`0 == 0.0` is `True` — so a `(List Float64)` or `(Map String Float64)` returning Python `int`s
against Rust `f64`s would compare **equal** and the gate would stay green. I could not construct
an observable case: `_as.div`/`_as.mod` promote on contact with a float, `f_to_i(0)` is `some 0`
either way, and a `Float64` literal must carry a decimal point to type-check, so no integer
literal reaches a `Float64` slot. Conclusion: the implementer's statement is right — this fixes
observation, not the leak — and the leak is currently unreachable, but the comparator, not the
repair, is what would hide a future one.

## Non-discriminating cases

Repairs whose executed cases would not catch a plausible wrong implementation:

| repaired lowering | what no executed case would catch |
|---|---|
| `mod` (repair 3) | a negative **divisor** (`mod(7,-2)`: `fmod` gives `1.0`, floored gives `-1.0`) and the sign of a zero remainder (`-0.0` vs `0.0`). Both backends agree today — verified — but nothing pins either. |
| `checked-div` / `checked-mod` (4, 5) | `Int64::MIN / -1` and `Int32::MIN / -1`. See blocker 2. |
| `list-sort` (8) | **stability** — the only sort-by case (`lookup`) has equal keys on *equal elements* (`3` and `3`), so an unstable sort produces byte-identical output. Nothing in the corpus sorts distinguishable elements under equal keys. Also NaN ordering: see blocker 1. |
| `list-min` / `list-max` (9, 10) | a list containing NaN. Verified to agree by probe (both use the same first-wins reduce: `[3,NaN,1,2] → 1.0/3.0`, `[1,NaN,3] → 1.0/3.0`), but a `fold(INFINITY, f64::min)` implementation, which swallows NaN, passes every executed case. |
| `min` / `max` (7) | nothing significant — NaN in both operand positions, the tie, and both orders are all executed. This repair is well covered. |
| `/` (2), `mod` (3), `checked-*` (4,5), `list-sum` (6), `list-sort` (8), `list-min`/`list-max` (9,10) **at `Int32`** | every one. No fixture performs arithmetic at `Int32`; `int64-to-int32` and `int32-to-int64` execute, the `impl Num for i32` block does not. See finding 5. |
| `list-sort-by` (deviation 4, `Ord`→`PartialOrd`) | its own motivation. The only executed instantiation is `K=Int64`, where `Ord` sufficed; `list-sort-by` is higher-order, and `monomorphism.py:classify` excludes higher-order builtins from Tier A, so `K=Float64` is neither compiled nor executed by any gate. |

## Findings

### 1. `blocker` — `list-sort` at `Float64` makes the two backends disagree, and no case sees it

Repair 8 rebound `rt::sort` to `PartialOrd` with
`a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)`. That treats NaN as equal to everything
and, under a stable sort, freezes it in place. Python's `sorted` uses `<` only and produces a
different permutation. `(List Float64)` is a legal type and `(string-to-float64 "nan")` reaches
NaN with no literal, so this is reachable from ordinary source.

Probe — a real fixture through the real transpilers (`to_rust.py`, `to_python.py`), sorting
`(list 3.0 nan 1.0 2.0 0.5)`:

```
rust:   3.0,nan,0.5,1.0,2.0
python: 0.5,3.0,nan,1.0,2.0
```

`PLAN.md` §6 records "`list-sort` with a NaN present is **unspecified**", and
`AGENT_SPEC_CORE.md:555` says only "Stable ascending sort". But `AGENT_SPEC_CORE.md:653` states
the language's own reason for existing here — *"Deterministic, because output that is not
byte-reproducible cannot be differentially tested"* — and this is a program the language admits
whose output is not byte-reproducible across the two backends it ships. Declaring it unspecified
does not make it portable; it makes the gap invisible.

**Fix (pick one, do not leave it as prose):** (a) specify a total order for `Float64` sorting —
IEEE-754 `totalOrder` or "NaN sorts last" — and implement it on both backends, then add a case
with a NaN in the list; or (b) narrow the language the way `map-key-order` narrowed `Map` keys,
rejecting `list-sort` / `list-min` / `list-max` / `list-sort-by` at `Float64`, which contradicts
the whole point of fixture 25 and so is the worse option; or (c) at minimum, add the divergence
to `coverage.lock` as a named, counted exclusion rather than a sentence in a plan.

### 2. `blocker` — `checked-div` / `checked-mod` / `/` / `mod` panic on one backend at `MIN / -1`

Repairs 2–5 kept `self.checked_div(b).expect("overflow in division")` inside `Num::quot`, and
`%` inside `Num::rest`. Rust therefore **panics**; Python returns a value.

```
rust:   rt::checked_div(i64::MIN, -1i64)
        thread 'main' panicked at rt.rs:28:56: overflow in division
        rt::checked_rem(i32::MIN, -1i32)
        thread 'main' panicked at rt.rs:22:36: attempt to calculate the remainder with overflow
python: _as.checked_div(-2**63, -1)  ->  ('some', 9223372036854775808)
        _as.checked_mod(-2**63, -1)  ->  ('some', 0)
```

Note the Python result is not merely different — `9223372036854775808` is outside `Int64`. The
declared contract (`prelude.json`: "Division, or none on a zero divisor") is silent on overflow,
which is exactly why the two implementations drifted. `23-numeric-int.json` covers the zero
divisor and quotient≠remainder but nothing near the boundary, so the gate is green over a case
that crashes one backend.

**Fix:** decide the contract (trap on both, or `none` on both — `none` is the better fit for
`checked-*`, whose whole purpose is totality), implement it in `runtime.py` and `Num::quot` /
`Num::rest`, document it on the `/`, `mod`, `checked-div`, `checked-mod` rows, and add a
`num(-9223372036854775808, -1)` case.

### 3. `major` — `float64-to-int64` violates its documented contract on both backends, differently

`AGENT_SPEC_CORE.md:537`: "Truncate toward zero, or none for NaN, infinity **or out of range**."
Neither backend implements the out-of-range clause, and they disagree:

```
rust:   rt::f_to_i(1e30)                    -> Some(9223372036854775807)     (saturating `as i64`)
        rt::f_to_i(9223372036854775808.0)   -> Some(9223372036854775807)
python: _as.f_to_i(1e30)                    -> ('some', 1000000000000000019884624838656)
        _as.f_to_i(9223372036854775808.0)   -> ('some', 9223372036854775808)
```

This is reachable from the **shipped** `narrow` entry: `narrow(9223372036854775807)` converts to
`9223372036854775808.0` and then back, so a single extra case in `23-numeric-narrow.json` would
have failed the gate. The five cases stop at 2^53+1.

**Fix:** `f_to_i` returns `NONE` when `not (-2**63 <= x < 2**63)` in `runtime.py`, and
`rt::f_to_i` returns `None` unless `x >= -9223372036854775808.0 && x < 9223372036854775808.0`;
add the boundary case.

### 4. `major` — `map-key-order` is syntactic, and inference walks straight past it

`checker/resolve.py:map_key_order` scans `TYPE_NAME` tokens inside a written `(Map K V)`
annotation. A `Float64` key reached by **inference** is not annotated anywhere and is admitted:

```agents
(let [(m (map-from-pairs (list (pair 1.5 "a") (pair 0.5 "b"))))]
  (println (string-join (map (fn [k] (string-from-float64 k)) (map-keys m)) ",")))
```

```
checker diagnostics: []
rustc:               error[E0277]: the trait bound `{float}: Ord` is not satisfied
```

That is precisely the failure mode the check's own docstring says it exists to close — *"the
checker admitted it until now: every lowering reached rustc and failed there, at a bound in
rt."* The narrowing therefore does not hold on the inference path, and Tier A cannot see it
because `monomorphism.py` generates probes from written signatures.

**Fix:** raise `map-key-order` from the syntactic pass to `types_.py`, where the `Map`
constructor's key argument is already a resolved type at each instantiation site
(`self.instantiations` now records exactly this), and report there. Add
`grammar/corpus/semantic/map-float-key-inferred.agents`.

### 5. `major` — `Int32` has no Python representation, so Tier A's `Int32` column can never be executed

`backend/to_python.py` contains no occurrence of `Int32` or `i32`; `backend/runtime.py`'s only
`Int32`-aware line is the `-2**31 <= n < 2**31` range test in `to_i32`. Python integers are
unbounded, so `Int32` arithmetic in the Python backend is `Int64`-or-wider arithmetic wearing
the wrong type name, while Rust's `i32` wraps or panics. `impl Num for i32` (`rt.rs:19-24`) is
proven to compile at every instantiation and is executed by nothing.

Tier A's claim — "every admissible instantiation must compile" — is met; the phase's own Tier B
rule ("for every `N`-typed builtin at least `Int64` **and** `Float64`") deliberately excludes
`Int32`, so this is not a rule violation. It is an unstated limit: one third of the `N` domain
has no differential evidence at all and cannot acquire any until the Python backend models
32-bit wrap. Record it in `coverage.lock` beside the other exclusions rather than leaving Tier
A's 400/400 to imply more than was proven.

### 6. `major` — `list-sort-by` at `K=Float64` is verified by nothing

`monomorphism.py:classify` excludes higher-order builtins from Tier A, and the only executed
`list-sort-by` case (`25-list-lookup`) has `K=Int64`. Deviation 4 (`Ord` → `PartialOrd` on
`rt::sort_by`) is therefore unverified by the gate suite — the implementer's own note says it
rests on a one-off probe.

I rebuilt the probe as a real fixture (`(list-sort-by (fn [x] (int64-to-float64 (neg x))) xs)`),
transpiled it with `to_rust.py` and compiled with `rustup run stable rustc`:

```
rustc: 0 errors (one unrelated unused_must_use warning)
rust:   3,2,1
python: 3,2,1
```

So the rebound is **correct** and this is a coverage gap, not a defect. **Fix:** either extend
Tier A to higher-order builtins by generating a monomorphic closure literal for each `fn`
parameter (the probe above shows the shape is expressible), or add a `list-sort-by` case at a
`Float64` key to `25-list-aggregation`. The second is a two-line change and closes the executed
half.

### 7. `minor` — the `25-list-empty` case rationale is stale

The case note reads "the empty Float64 sum, which folds from `-0.0` in Rust's `Sum` impl and is
invisible to a comparator where `-0.0 == 0`". Repair 6 replaced `Sum` with
`fold(T::ZERO, Num::plus)`, so nothing folds from `-0.0` any more; and the value is now rendered
by `string-from-float64`, where `repr(-0.0)` is `'-0.0'` — so it would be *visible*, not
invisible. The note describes the defect the case was written against, not the case's current
discriminating power. Rewrite it to say what it now pins: the `T::ZERO` identity and the
`repr(float(...))` rendering.

### 8. `minor` — `string-to-int64` / `string-to-float64` accept different languages

Not a phase-2 repair; found while probing the parsers the new fixtures exercise.

```
python: _as.to_int("1_0")     -> ('some', 10)     rust: rt::to_i64("1_0")   -> None
        _as.to_float("1_0.5") -> ('some', 10.5)         rt::to_f64("1_0.5") -> None
```

Python's `int()`/`float()` accept PEP 515 underscores (and `int()` accepts non-ASCII decimal
digits); Rust's `parse` accepts neither. `28-string-transforms` covers the ordinary
accept/reject boundary but not this one. Worth a `coverage.lock` note or a normalising guard in
`runtime.py`.

### 9. `minor` — deviation 3's `match` clone is unconditional

`to_rust.py:563` appends `.clone()` to any scrutinee matching `[a-z_][a-z0-9_]*`, including
`Copy` scalars (`n.clone()`) and whole `Vec`s, and when the match has list arms the result is
`xs.clone().as_slice()` — a temporary `Vec` allocated per match. It is correct (the temporary
lives for the whole match scrutinee) and it mirrors the existing rule in `call`, so no
objection; but it is a real allocation on every list `match`, which is the cost PCP `l-880d`
exists to measure. Worth a line in the measurement rather than silence.

Related and also minor: `rt::sort_by` now calls the projection **twice per comparison**
(O(n log n) calls) where Python's `sorted(key=…)` calls it once per element. Unobservable for
pure `fn` arguments, which is all the language has, but it is a behavioural difference from the
Python lowering it is supposed to mirror.

### 10. `minor` — the `js` templates cannot corroborate anything

The brief asked for the `mod` repair to be checked against the `js` template. It cannot be:
`prelude.json` declares `"js": "_as.mod({0}, {1})"` and there is no JavaScript runtime in the
tree (`backend/` holds `rust/` and `golang/`, no `js/`), so `_as.mod` is undefined on that
target. `PLAN.md` §6 already records this for `min`/`max` ("no gate could check the change, so
editing them would create an unverifiable claim"); the same holds for `mod`, and the check
yields no evidence either way. Noted so the absence is not mistaken for agreement.

### 11. `minor` — the plan's fixture-27 note miscounts the byte offset

`PLAN.md:880` says a lowering returning `s.find()` directly "gives `4` here". `"héllo"` is
`h`(1) + `é`(2), so the byte offset of the first `l` is **3**, which is also the value the plan
put in the expectation column. The plan is wrong about both the expectation and its own
justification. Correct the note when the table is reconciled, so the next reader does not
conclude there are two candidate wrong answers.

---

### Counts

blocker 2 · major 4 · minor 5 · derivations disagreeing with the checked-in expectation: **0 of 78**
