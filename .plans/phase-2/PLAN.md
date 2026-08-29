# Phase 2 — Vocabulary coverage  (v2, re-planned after rejection)

Closes PCP `l-3434` / `ROADMAP.md` §6 / `.plans/PHASES.md:30-33`.
Supersedes v1 in full. `INVENTORY.md` is retained only as a raw table; every number in it that
this plan needed has been re-derived from the tree and is restated in §1. No implementation was
performed writing this plan — every experiment ran in the session scratchpad or in a throwaway
copy of the repo, and the working tree is unchanged.

---

## 0. Why v1 was rejected, and what v2 does differently

v1 had one organising premise: *a builtin named in a parsed file is exercised, and an exercised
builtin's lowering works.* Both halves are false, and the review plus the orchestrator log proved
it from the tree.

| v1 | v2 |
|---|---|
| Coverage = call heads in `corpus/valid` + `AGENT_SPEC_CORE.md` markdown. Nine fixtures and no task files reach 107/107 with zero builtins executed. | Coverage = builtins called by the sources `differential.py` **actually executes**, whose cases agree with a checked-in expected value. Markdown cannot move it; a fixture that is never run cannot move it. |
| "36 exercised" → floor at 95% is a short hop. | The honest executed baseline is **21/107 (19%)** (§1.3). 86 builtins to go, not 71. |
| 2 repairs (`list-sum`, `min`), found by eyeball. | **10** repairs, found by a mechanical (builtin × instantiation) sweep of all 440 admissible probes, every one compiled (§1.2, §6). |
| "exercised at `Int64`" counted as exercised. | Two tiers. Tier A: every admissible instantiation must **compile** on both backends, enforced by a generated probe corpus. Tier B: at least one instantiation must **execute** and agree, and for every `N`-typed builtin at least `Int64` **and** `Float64`. |
| `min`/`max` repaired with an inline `if` template. | Repaired in `rt.rs`. v1's template evaluates its first argument twice and inverts Python's NaN result — both reproduced (§1.4). |
| `differential.py` generalisation described as a `return_shape` enum. | A real work item (W6): typed multi-argument inputs, a **recursive** JSON encoder driven by the parsed return type, Python-side normalisation, and an expected-output oracle for program mode. |
| Fixture cases given as prose intent. | Every case carries its literal input and the wrong implementation it rules out (§5). |
| `(Map Float64 V)` not considered. | It type-checks and cannot lower to `BTreeMap` at all. Closed by narrowing the language (W4), not by leaving 24 broken instantiations undiscussed. |

---

## 1. Verified findings

Everything below was run this session. `python` means `.venv/bin/python` from the repo root;
`rustc` means `rustup run stable rustc --edition 2021` (the cargo shim is broken — `AGENTS.md`).

### 1.1 Baseline — all seven gates green, 47 tests

| gate | exit | note |
|---|---|---|
| `grammar/validate.py` | 0 | |
| `grammar/closure_audit.py` | 0 | prints `exercised builtins : 36/107 (33%)` |
| `prelude/generate.py --check` | 0 | |
| `checker/gate.py` | 0 | |
| `backend/check_corpus.py` | 0 | |
| `backend/differential.py` | 0 | `0 disagreement(s) across 7 function cases + 4 program cases x 2 backends` |
| `pytest backend/t bench/algo checker/t -q` | 0 | `47 passed in 0.18s` |

Confirmed. This is the state v2 must restore at the end.

### 1.2 The monomorphism sweep — 16 builtins broken, not 7

Claim: v1's and the review's repair lists are both incomplete.
**Confirmed, and larger than either.**

Method (scratchpad `audit.py`): for every non-effectful, non-variadic, non-higher-order builtin
whose declared type contains a type variable, substitute each admissible concrete type
(`N` → `Int32`/`Int64`/`Float64`; any other variable → `Int64`/`Float64`/`String`/`Bool`),
emit `(defun probe [(a0 T0) …] -> R (name a0 …))`, run `checker/resolve.check_file`, then
`to_rust.py` + `rustc --crate-type=lib`.

```
total probes 440   checker-clean 440   rustc-ok 401   rustc-FAIL 39
```

39 failures over **16** builtins:

| builtin | failing instantiations | first rustc error |
|---|---|---|
| `/`, `mod`, `checked-div`, `checked-mod` | `Int32`, `Float64` | `error[E0308]: arguments to this function are incorrect` |
| `list-sum` | `Int32`, `Float64` | `error[E0308]: mismatched types` |
| `min`, `max` | `Float64` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` |
| `list-sort`, `list-min`, `list-max` | `Float64` | same `E0277` |
| `map-get`, `map-set`, `map-has?`, `map-remove`, `map-pairs`, `map-from-pairs` | key `Float64` (× all 4 value types) | same `E0277` |

`/` and `mod` are inside the 36 the current figure calls *exercised*. `list-sort`, `list-min`,
`list-max` fail at `Float64` for a reason **unrelated** to the `defenum` derives that v1 and the
review both attributed them to — `f64` is not `Ord` even before any user type is involved. The six
`Map` rows are a defect neither document names.

The checker rejected **nothing**: all 440 probes check clean. So the checker's admissible set is
strictly larger than the Rust backend's, at 39 points.

### 1.3 The executed baseline is 21/107, not 36/107 and not 43/107

`differential.py` executes exactly two sources today (`differential.py:110-111`, `:128-132`):
`bench/algo/variants/tight.agents` and `grammar/corpus/valid/08-io.agents`. Running
`closure_audit.run_query` over exactly those two:

```
EXECUTED TODAY: 21
+ = eprintln file-read file-write filter fold list-max map map-empty map-from-pairs
map-get map-pairs map-set map-values not option-or println string-empty? string-split string-trim
REMAINING: 86
```

The 86 are enumerated in §5; they partition exactly across the ten fixtures.
`list-get` is "exercised" today **only** because it appears in an `AGENT_SPEC_CORE.md` markdown
block (review finding 1, confirmed): it is in the 86.

### 1.4 v1's `min` template is wrong twice; the review's NaN evidence is exact, its `E0382` is not

`to_rust.py` on `(min (list-sum xs) 2.0)` emits:

```rust
std::cmp::min(rt::sum(xs.clone()), 2.0)
```

Substituting v1's template `(if {0} <= {1} {{ {0} }} else {{ {1} }})` puts `rt::sum(xs.clone())`
in the output **twice**. Compiled and run with a call counter: the true branch evaluates it a
second time. Confirmed.

`E0382` (the review's evidence (b)) does **not** reproduce for `min`/`max`: every `N` is
`Int32`/`Int64`/`Float64`, all `Copy`, so a duplicated argument never moves. The defect is
duplicated evaluation of a pure expression, not a move error. The conclusion is unchanged.

NaN, measured on both sides:

```
python  min(nan,1.0)=nan   min(1.0,nan)=1.0   max(nan,1.0)=nan   max(1.0,nan)=1.0
v1 tpl  min(nan,1)=1.0     min(1,nan)=NaN                        <-- inverted, both ways
W2 fix  min(nan,1)=NaN     min(1,nan)=1.0     max(nan,1)=NaN     max(1,nan)=1.0
```

Review finding 3(c) confirmed verbatim. `std::cmp::min` also rejects `f64` outright
(`E0277`), so the defect being repaired is real (evidence (a) confirmed).

### 1.5 The `Sum` identity diverges on an empty `Float64` list

```
rust  rt::sum(Vec<f64>::new()) = -0.0        (std's Sum for f64 folds from -0.0)
py    sum([])                  = 0    (int)
```

Real, and **invisible to the current comparator**: `differential.py` compares Python objects, and
`-0.0 == 0` is `True`. W2 removes it at the source by folding from `T::ZERO`; measured
`sum2_empty_f64=0.0`, `sum2(vec![0.1,0.2])=0.30000000000000004` (identical to Python).

### 1.6 `(Map Float64 V)` is a spec contradiction, not just a lowering gap

`AGENT_SPEC_CORE.md:123` — "``(Map K V)`` Immutable keyed collection; `K` must support equality".
`AGENT_SPEC_CORE.md:545-547` — `map-keys` "Keys, **sorted**"; `map-values`/`map-pairs` "ordered by
sorted key". Sorting needs an order, not equality. The checker enforces neither (§1.2: 24 probes
clean), `rt.rs` picks `BTreeMap` (documented at `rt.rs:3-6`) which needs `Ord`, and `f64` has no
total order. The declaration is wider than any backend can implement.

### 1.7 The arity heuristic — 34 mismatches, in two places

`len(b["type"].split("->")[0].split())` vs `len(parse_signature(b["type"])[0])` over all 107:
**34** mismatches (`string-join` 3→2, `list-empty?` 2→1, `list-append` 4→2, `map-from-pairs` 4→1,
`map-set` 5→3, …). The review's number, not `INVENTORY.md`'s 11. Visible in the shipped spec:
`AGENT_SPEC_CORE.md:540` renders 2-argument `map-get` as `(map-get a b c d)`.

The heuristic exists **twice**: `prelude/generate.py:31` (in `signature()`) and
`prelude/generate.py:158` (in `validate_templates()`). v1 named only the first.

### 1.8 The six `IoError` constructors *are* executable — the review's "unreachable" is wrong

The review proposed accepting `interrupted` and `other` as unreachable. They are unreachable as
*host-raised* errors; they are ordinary nullary calls. Probe, checker CLEAN, both backends:

```
(defun label [(e IoError)] -> String (cond ((= e (not-found)) "not-found") … (:else "other")))
(defun labels [] -> String (string-join (list (label (not-found)) … (label (other))) ","))

rust:   not-found,permission-denied,already-exists,invalid-path,interrupted,other
python: not-found,permission-denied,already-exists,invalid-path,interrupted,other
```

All six constructors execute and agree. Fixture `09` executes all six (§5).

### 1.9 Miscellaneous, all confirmed

| claim | verdict |
|---|---|
| `closure_audit.py:57` is the whole scan root; `:59-66` appends spec markdown | yes |
| `closure_audit.py:88` `return len(undefined)` — coverage printed, never enforced | yes |
| `100*102//107 = 95`, `100*101//107 = 94` — 102 builtins is the 95% floor | yes |
| the 107 denominator already includes the 10 operator heads | yes (`closure_audit.py:34`) |
| `check_corpus.py:18` globs `corpus/valid` only; never compiles anything, only `--crate-type=lib` + `py_compile` | yes |
| `bench/algo/histogram.agents` and `variants/tight.agents` both transpile and compile clean on both backends | yes (measured) |
| `differential.py` hardcoded to a single `String` input (`:35`, `:47`, `:51`) and a map-only serializer (`:53-57`), plus a no-op normalisation at `:66` | yes |
| `programs()` (`:87-105`) compares python vs rust only — no expected-output oracle | yes |
| **`bench/harness/run.py:174,189` globs `bench/tasks/*.json`** | yes — new task files must NOT go in `bench/tasks/`, or the measurement harness picks them up (§4 W6) |
| no `.github/` or any CI config in the repo | yes — v1's "exit code consumer" risk is moot |
| `cond`'s fallback is `:else`, not `else` (`grammar/agents.lark:85`) | yes |
| Phase 1 owns the `defenum` `Ord`/`Eq` derives (`.plans/ORCHESTRATOR-LOG.md:10-14`, `.plans/phase-1/PLAN.md:354`) and also edits `differential.py` (`:431`) | yes |

---

## 2. What "covered" means

The gate enforces two independent properties. Neither can be satisfied by editing prose, and
neither can be satisfied by a fixture that is never run.

**Tier A — compiles at every admissible instantiation.**
An *instantiation* is a builtin paired with one concrete assignment to every type variable in its
declared signature. The admissible set is generated from `prelude.json` by
`prelude/vocab.parse_signature`, not hand-listed. Every admissible instantiation must produce a
probe that the checker accepts, `to_rust.py` lowers, `rustc --crate-type=lib` accepts, and
`py_compile` accepts. **Denominator = 400** after W4 narrows Map keys (440 before). Floor: 100%,
no exceptions, no skip list — a failure is either a lowering bug (fix it) or a signature the
language should not admit (narrow it, as W4 does).

*Why this cannot be faked:* the probe corpus is generated from `prelude.json` and compiled by
`rustc`. Adding a markdown example changes nothing. Deleting a builtin removes it from **both**
sides. Widening a scan root is meaningless — there is no scan.

**Tier B — executes and agrees.**
A builtin is **covered** when a `differential.py` case that the harness actually runs calls it,
and both backends' results match a **checked-in expected value**. The numerator is computed over
exactly the source files `differential.py` names — nothing else, and specifically not
`corpus/valid` (which is only compiled) and not `AGENT_SPEC_CORE.md` (which is only parsed).
Denominator = 107 declared builtins. Floor **95%** (`.plans/PHASES.md:32`) **plus a ratchet** on
the exact count, both stored as data in `prelude/coverage.lock`.

Additionally, for every builtin whose signature mentions `N`, Tier B requires an executed case at
`Int64` **and** at `Float64`. That is the rule that would have caught `/`, `mod` and `list-sum`,
and it is recorded per builtin in `coverage.lock`.

**In two lines, for the gate's error message:**

> Covered = called by a source `differential.py` executes, in a case whose result both backends
> match against a checked-in expected value. Mentions in `corpus/valid` or in the spec's markdown
> do not count, and every `N`-typed builtin must be executed at `Int64` and at `Float64`.

---

## 3. Strategy and sequencing

**Repair, then narrow, then prove mechanically, then generalise the harness, then execute.**

1. The two isolated cleanups (`generate.py` arity) go first: they touch nothing else, and they fix
   the agent-facing artifact that goal 4 cares about.
2. The repairs (W2, W3) come before the fixtures. Every one is already proven broken by §1.2 with a
   compiled counter-example — writing a fixture first would only reproduce a known failure. They
   are also proven *fixed*: §6's replacement text was compiled against all 440 probes and against
   the full gate set in a throwaway copy of the repo.
3. W4 narrows the language where no backend can follow it. Doing this before W5 is what lets
   Tier A's floor be 100% rather than "100% minus a skip list".
4. W5 makes the whole thing mechanical and permanent. It is the artifact that would have caught
   this class of defect the first three times (`filter`, `list-sort-by`, `list-sum`), and it is
   cheap: measured **400 probes, checker 0.94 s, one `rustc` 1.57 s, one `py_compile` 1.03 s**.
5. W6 must land before W8, because a fixture without an executed case contributes nothing to
   Tier B. This is the ordering constraint v1 got wrong — it let fixtures land first and called
   the phase done.
6. W8's ten fixtures then execute the 86.

**Rebase against Phase 1.** Phase 1 edits `differential.py` (`.plans/phase-1/PLAN.md:431`) and the
`defenum` derives (`:354`). W6 rewrites `run_rust`/`main`/`programs` — treat Phase 1's change as
the base and **rebase W6 onto it**, do not merge. After Phase 1 lands, re-run W5's gate: the
`defenum` derives will admit new instantiations (enum-keyed maps, sorted enum lists) that Tier A
did not previously generate. Phase 2 does **not** plan that fix; §5 notes what those eight
builtins' fixtures look like afterwards.

---

## 4. Work items

Eleven. Each states the files it touches, what changes, what it depends on, and **how it can fail
before the next item starts** — a check that is run and observed, not assumed.

### W1 — `prelude/generate.py`: one arity source, both copies

*Files:* `prelude/generate.py`, `prelude/HANDBOOK.md`, `AGENT_SPEC_CORE.md` (§6 tables, generated).
*Change:* replace the word-count heuristic at `:31` **and** at `:158` with
`len(parse_signature(b["type"])[0])` (`from vocab import parse_signature`; `generate.py` already
lives in `prelude/`). Regenerate both artifacts.
*Depends on:* nothing.
*Fails before W2 if:* `generate.py --check` is non-zero after regeneration; or `git diff` shows any
line moving other than the 34 call-form cells (`string-join` 3→2, `list-empty?` 2→1,
`list-append` 4→2, `map-from-pairs` 4→1, `map-set` 5→3, and the other 29); or
`closure_audit.py` changes its numbers (it must not — call forms in a table are not `lisp` blocks).
*Measure:* record the `HANDBOOK.md` character delta against the orchestrator's 12,078-char baseline.

### W2 — `rt.rs`: the numeric family over the whole of `N`

*Files:* `backend/rust/rt.rs`, `prelude/prelude.json` (`min`, `max` `rs` templates).
*Change:* §6 rows 1-7. A `Num` trait with `ZERO`/`quot`/`rest`/`plus` implemented for `i32`,
`i64`, `f64`; `div`/`rem`/`checked_div`/`checked_rem`/`sum` generic over it; `min`/`max` as
`PartialOrd` helpers in the runtime, with the templates changed to `rt::min({0}, {1})` /
`rt::max({0}, {1})`.
*Depends on:* nothing.
*Fails before W3 if:* the scratchpad probe rerun still reports any `E0308`/`E0277` for
`/ mod checked-div checked-mod list-sum min max`; or the NaN probe does not print
`min(nan,1)=NaN min(1,nan)=1.0 max(nan,1)=NaN max(1,nan)=1.0`; or `rt::sum` of an empty `Vec<f64>`
is not `0.0`; or `generate.py --check` is non-zero (the templates feed the spec tables).

### W3 — `rt.rs`: ordering helpers off `Ord`

*Files:* `backend/rust/rt.rs`.
*Change:* §6 rows 8-10. `sort`, `least`, `greatest` bounded by `PartialOrd` instead of `Ord`.
`least`/`greatest` are written as a `reduce` with the *Python* tie/NaN rule, not `iter().min()`.
*Depends on:* nothing (independent of W2, but sequence after it so one probe rerun covers both).
*Fails before W4 if:* the probe rerun still reports `E0277` for `list-sort`/`list-min`/`list-max`;
or `rt::least(&[nan, 1.0])` is not `Some(NaN)` (Python's `min([nan,1.0])` is `nan`).

### W4 — rule-13: a `Map` key must be orderable

*Files:* `checker/resolve.py` (new check + `rule-13`), `AGENT_SPEC_CORE.md:123` and §9 checklist,
`grammar/corpus/semantic/map-float-key.agents` (new, with a `; expect: rule-13` header).
*Change:* reject any type where `Float64` occurs anywhere inside a `Map`'s **first** argument,
recursively (`(Map Float64 V)`, `(Map (Pair Float64 T) V)`, `(Map (List Float64) V)`). Spec line
123 becomes "`K` must support ordering — `map-keys` is specified to return keys sorted, which
`Float64` cannot provide"; §9 gains checklist item 13.
*Depends on:* nothing.
*Fails before W5 if:* `checker/gate.py` is non-zero; or the new semantic fixture is not rejected
with `rule-13` specifically (`gate.py` asserts the code, not merely that something was reported);
or any existing `corpus/valid` or `corpus/modules` file starts failing.
*Deliberately out of scope, cross-referenced not re-owned:* `defschema` derives `Ord`
unconditionally (`to_rust.py:128`), so a record with a `Float64` field is an equally illegal Map
key and an equally illegal `list-sort` element. That is the same `defenum`/`defschema` derive
defect **Phase 1 owns** (`.plans/ORCHESTRATOR-LOG.md:10-14`). rule-13 as written covers the
primitive case; extending it through user types belongs with the derive fix.

### W5 — `backend/monomorphism.py`: the Tier-A gate

*Files:* new `backend/monomorphism.py`, new `backend/t/test_monomorphism.py`.
*Change:* generate the admissible instantiation set from `prelude.json` via `parse_signature`
(skip effectful, variadic and higher-order builtins — recorded, with the reason, in the gate's own
output so the exclusion is visible rather than silent). Emit **one** `.agents` source containing
every probe, check it once, transpile it once per backend, and run **one** `rustc --crate-type=lib`
and **one** `py_compile`. Exit code = number of failing probes. On failure, re-emit the failing
probes individually to name the builtin and instantiation.
*Depends on:* W2, W3, W4.
*Fails before W6 if:* the gate is non-zero. Target state, measured this session with W2-W4's text
applied: `probes: 400 · checker diags: 0 · rustc rc=0 errors=0 · py_compile rc=0`, total ~3.5 s.
*Unit tests:* that a deliberately re-monomorphised `rt::sum` makes the gate fail with `list-sum`
named — a gate no test can fail is not a gate.

### W6 — `differential.py`: typed inputs, recursive encoding, program-mode oracle

*Files:* `backend/differential.py`, new `backend/rust/harness.rs`, new `backend/cases/` (directory),
`bench/tasks/histogram.json`, new `backend/t/test_differential_encoding.py`.
*Change:* four separable parts.

* **(a) Task discovery and inputs.** `main()` loops over `sorted((ROOT/"backend"/"cases").glob("*.json"))`
  plus `bench/tasks/*.json`. Each task gains `"src"`. A case becomes `[[arg, …], expected]`. Argument
  types come from `parse_signature(task["signature"])[0]` — **not** a hand-written `arg_types` field,
  which would be a second source free to drift from the entry's declared type. Admissible input
  types: `String`, `Bool`, `Int32`, `Int64`, `Float64`, `(List X)` of those. Anything else fails
  loudly at generation rather than emitting Rust that will not compile.
  *`backend/cases/`, not `bench/tasks/`*: `bench/harness/run.py:174,189` globs `bench/tasks/*.json`
  and would pick fixture cases up as measurement tasks (§1.9).
* **(b) Recursive return encoding.** New `backend/rust/harness.rs`, included only by the generated
  driver, never by user output: `pub trait J { fn j(&self) -> String; }` with impls for `i32`,
  `i64`, `f64`, `bool`, `String`, `()`, `Option<T>`, `Result<T, E>`, `(A, B)`, `Vec<T>`,
  `BTreeMap<K, V>` and `rt::IoError`. The driver prints `[c.j(), …]`. This replaces per-shape
  generated Rust text with one trait — a flat `return_shape` enum cannot express
  `(Option (List T))`, `(List (Pair K V))` or `(Result (Option Int64) IoError)`, all of which §5
  needs. Encoding is fixed to match `backend/runtime.py`: `Some v`→`["some",v]`, `None`→`["none"]`,
  `Ok v`→`["ok",v]`, `Err e`→`["err",e]`, `(a,b)`→`["pair",a,b]`, `Vec`→array, `BTreeMap`→object,
  `IoError`→its `case()` string.
* **(c) Python-side normalisation.** `run_python`'s driver maps tuples to lists so `_as.NONE`
  (`runtime.py:9`, the tuple `("none",)`) encodes as `["none"]` on both sides, and renders
  non-finite floats as `"nan"`/`"inf"`/`"-inf"` on both sides (`json.dumps(float('nan'))` emits
  bare `NaN`, which is not JSON, and Rust's `{:?}` emits `NaN`). Without this the two sides differ
  on encoding rather than on semantics.
* **(d) Program-mode oracle.** `programs()` cases become
  `(argv, files, expected_stdout, expected_exit)`, where `files` is `{name: (content, mode)}` so a
  case can pre-seed a file and set `0o000` on it. All three of python, rust and expected must
  agree; today only python-vs-rust is compared (`differential.py:101`), so a defect in the shared
  `prelude.json` declaration is invisible.

*Depends on:* nothing structurally; must land before W8. **Rebase onto Phase 1's edit to this file.**
*Blast radius, and the only regression guard the refactor has:* one existing function task
(histogram, 7 cases) and 4 existing program cases.
*Fails before W7 if:* the histogram table printed before and after the refactor is not
byte-for-byte identical (capture the current output first — it is reproduced in §1.1); or the four
program-mode rows change their `python`/`rust`/`exit` columns; or `bench/harness/run.py --help`
stops finding exactly one task.

### W7 — `check_corpus.py`: compile everything that any gate counts

*Files:* `backend/check_corpus.py`.
*Change:* extend `CORPUS` with `sorted((ROOT/"bench").rglob("*.agents"))`. Both bench sources
already pass on both backends (§1.9), so this is a widening with a measured-zero cost today; its
purpose is the invariant — a source `differential.py` executes must also be compile-gated.
*Depends on:* nothing.
*Fails before W8 if:* `check_corpus.py` is non-zero, or its printed row count is not
8 corpus + 2 bench = 10.

### W8 — ten fixtures and their case files

*Files:* `grammar/corpus/valid/09-…` through `18-…` (§5), `backend/cases/*.json`.
*Change:* §5's matrix, in full — programs, entries, literal case inputs, expected outputs.
*Depends on:* W2, W3 (so the `Float64` cases pass first time), W6 (so the cases execute at all).
*Fails before W9 if:* `grammar/validate.py`, `checker/gate.py`, `check_corpus.py` or
`differential.py` is non-zero; or any fixture needs a `SKIP_RUST`/`SKIP_PY` entry (they are
single-module with no qualified names — a skip means something else is wrong); or
`closure_audit.py`'s executed count is below 107.
*Land them one at a time.* Ten fixtures in one commit means ten simultaneous unknowns.

### W9 — the coverage gate

*Files:* `grammar/closure_audit.py`, new `prelude/coverage.lock`.
*Change:* §7's design.
*Depends on:* W6, W8.
*Fails before W10 if:* lowering `coverage.lock`'s floor by hand, or deleting a builtin from
`prelude.json`, or adding a `defun` example to `AGENT_SPEC_CORE.md`, does **not** produce a
failing gate — each of the three must be tried and observed to fail.

### W10 — `ROADMAP.md` §2

*Files:* `ROADMAP.md`.
*Change:* the Rust backend row currently reads as *working*. It was working for `Int64`. Correct
it to state what is now true — generic over `N` and over `PartialOrd` element types as of this
phase, with `defenum`-typed elements still owed by Phase 1 — and note that Phase 3's Wasm route
goes through this backend and inherited the gap.
*Depends on:* W2, W3, W5.
*Fails before W11 if:* the row still claims coverage the Tier-A gate does not report.

### W11 — PCP entries

*Files:* the PCP store (§10).
*Depends on:* W1-W10 green.

---

## 5. Fixture matrix

Ten fixtures under `grammar/corpus/valid/`, numbering on from `08-io.agents`. Together they
execute the **86** builtins §1.3 leaves: 11 + 9 + 6 + 7 + 14 + 10 + 8 + 4 + 7 + 10 = 86, and
21 + 86 = **107/107**, five clear of the 102 floor.

Every case below gives the literal input and the wrong implementation it rules out. Where a case
earns its place only as coverage, that is said rather than dressed up as discrimination.

### `09-io-errors.agents` — program mode — 11 builtins
`print`, `read-all`, `read-line`, `file-append`, `file-exists?`, `not-found`,
`permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`

Program: `argv[1]` is a path. With `--labels`, print `(label (not-found))…(label (other))` joined
by `,` — the §1.8 construction, which executes all six constructors on both backends. Otherwise:
`file-exists?` the path; if present, `read-line` from stdin and `file-append` it, then `file-read`
the path and `print` the whole content; on any failure, `label` the `IoError` and `print` it.

| # | argv / files / stdin | expected stdout, exit | discriminates |
|---|---|---|---|
| 1 | `["log.txt"]`, `log.txt`=`"A\n"` mode 644, stdin `"B"` | `"A\nB\n"`, 0 | `file-append(path, text)` **argument swap** — swapped writes a file named `B` and prints `A\n`. Also append-vs-overwrite: overwrite prints `B\n`. The read-back is what makes it visible; v1's case never read back. |
| 2 | `["absent.txt"]`, no files | `"absent\n"`, 0 | `file-exists?` inverted — the only case where it is false. Case 1 is the true side. |
| 3 | `["nodir/out.txt"]` | `"not-found\n"`, 1 | the host's errno→case mapping for a missing parent |
| 4 | `["noperm.txt"]`, `noperm.txt`=`""` mode `0o000` | `"permission-denied\n"`, 1 | the `permission-denied` arm, which no v1 case reached. Needs W6(d)'s per-case file mode. |
| 5 | `["log.txt"]`, `log.txt`=`"A\n"`, stdin empty | `"A\n"`, 0 | `read-line`'s `none`-at-EOF branch; distinguishes it from an empty-string result, which would append a bare newline |
| 6 | `["--labels"]` | `"not-found,permission-denied,already-exists,invalid-path,interrupted,other\n"`, 0 | all six constructors, and their **spelling**: an `interrupted` that returned `Other` fails here. Measured identical on both backends (§1.8). |
| 7 | `["--slurp"]`, stdin `"x\ny\n"` | `"x\ny\n"`, 0 | `read-all` vs `read-line` — case 5 reads one line, this reads both |

`already-exists` and `invalid-path` are executed **as constructors** by case 6. Their host mappings
(`EEXIST`, `ENOTDIR`) are not reached by any portable case; `interrupted` (`EINTR`) and `other` are
not reachable at all from a deterministic test. **Recorded as such in `coverage.lock`** — the
constructor is covered, the mapping is not, and the lock file distinguishes the two rather than
letting the count imply more than was proven.

### `10-option-result-ctors.agents` — function mode — 9 builtins
`some`, `none`, `ok`, `err`, `is-some?`, `is-none?`, `is-ok?`, `is-err?`, `pair`

`(defun classify [(a String) (b String)] -> (Pair String String))` — each token is parsed with
`string-to-int64`; a `some` becomes `(ok n)`, a `none` becomes `(err tok)`. Each half renders as
`"<some|none>/<ok|err>:<value>|SNOE"` where `SNOE` is `is-some?`/`is-none?`/`is-ok?`/`is-err?` as
`T`/`F`. Returned as a `pair`, positionally.

| case | expected | discriminates |
|---|---|---|
| `["3","x"]` | `["pair","some/ok:3\|TFTF","none/err:x\|FTFT"]` | `pair` **argument swap** — the two halves differ; and every predicate, each of which takes both values across the two halves of this single case |
| `["x","3"]` | `["pair","none/err:x\|FTFT","some/ok:3\|TFTF"]` | the mirror: a `pair` that ignores order passes case 1 alone |
| `["","0"]` | `["pair","none/err:\|FTFT","some/ok:0\|TFTF"]` | empty token, and `0` — a value that is falsy in a backend that confuses "parsed" with "truthy" |

`is-ok?`/`is-err?` swapped flips characters 3-4; `is-some?`/`is-none?` swapped flips 1-2; a
constant-`true` predicate fails because both polarities occur in every case.

### `11-option-result-combinators.agents` — function mode — 6 builtins
`option-map`, `option-to-result`, `result-map`, `result-map-err`, `result-or`, `result-to-option`
(re-exercises `option-or`)

`(defun resolve [(raw String) (fallback Int64)] -> String)`.
`string-to-int64 raw` → `option-map` doubles → `option-to-result` with error text `(str "bad:" raw)`
→ `result-map` adds 1 → `result-map-err` wraps as `E<…>`. Output is three `|`-joined fields:
`(match r ((ok v) (str "ok:" v)) ((err e) (str "err:" e)))`, then
`(result-or (result-map string-from-int64 r) "FB")`, then
`(option-or (result-to-option r) -1)` rendered.

| case | expected | discriminates |
|---|---|---|
| `["21", 0]` | `"ok:43\|43\|43"` | `option-map` then `result-map` **order**: double-then-increment is 43, increment-then-double is 44. v1's design could not tell them apart. |
| `["x", 5]` | `"err:E<bad:x>\|FB\|-1"` | **`result-map-err` replaced by the identity, or by `result-map`** — both give `err:bad:x`. v1's fixture routed the failure through `result-to-option`, which discards the error entirely, so all three implementations were byte-identical. Also `result-or`'s fallback arm and `result-to-option`'s `none` arm. |
| `["", 9]` | `"err:E<bad:>\|FB\|-1"` | empty input still reaches the error path; `(str "bad:" "")` is not `"bad"` |

`result-or`'s arguments are `(Result T E) T` — a swap does not type-check, so it is caught by
`rustc`, not by a case. Stated as coverage, not claimed as discrimination.

### `12-boolean-algebra.agents` — function mode — 7 builtins
`!=`, `<`, `<=`, `>`, `>=`, `and`, `or` (re-exercises `not`, `=`)

`(defun band [(lo Int64) (x Int64) (hi Int64)] -> String)` returning eight `T`/`F` characters:
`(<= lo x)`, `(>= hi x)`, `(< lo x)`, `(> hi x)`, `(!= x lo)`,
`(and (!= x lo) (>= hi x))`, `(or (= x lo) (> x hi))`, `(not (and (<= lo x) (>= hi x)))`.

All cases use `lo=3`, `hi=7`.

| case | expected | discriminates |
|---|---|---|
| `[3,3,7]` | `TTFFF` `F` `T` `F` | **`<=` implemented as `<`** — column 1 is the only place they differ, and it differs only at `x == lo`. v1 had no case on a bound. |
| `[3,7,7]` | `TTTFT` `T` `T` `F` | **`>=` implemented as `>`** — column 2, only at `x == hi` |
| `[3,2,7]` | `FTFFT` `T` `F` `T` | below the range; `!=` true |
| `[3,8,7]` | `TFTFT` `F` `T` `T` | above the range; `>` true |
| `[3,5,7]` | `TTTFT` `T` `F` `F` | interior |

`and`/`or` swap: column 6's operands take `TT` (case 3: `!=`=T, `>=`=T), `FT` (case 1), `TF`
(case 4); column 7's take `FF` (case 5). All four combinations occur, so `and`↔`or` changes at
least one column in at least one case. v1 listed `>=` as covered by a program that used `<=`
twice; here `(>= hi x)` is written explicitly.

### `13-numeric.agents` — function mode, two entries — 14 builtins
`*`, `-`, `/`, `mod`, `abs`, `neg`, `checked-div`, `checked-mod`, `min`, `max`,
`int32-to-int64`, `int64-to-int32`, `int64-to-float64`, `float64-to-int64`

**This is the B2 fixture.** Every `N`-typed builtin runs at `Int64` **and** at `Float64` in the
same case, and at `Int32` where the value permits.

Entry 1 `(defun num [(a Int64) (b Int64)] -> String)` — when `b = 0`, report only the two checked
operations; otherwise report, `|`-joined: the `Int64` leg (`/`, `mod`, `*`, `-`, `abs`, `neg`,
`min`, `max`), the `Float64` leg (the same eight on `(int64-to-float64 a)` / `…b`, rendered with
`string-from-float64`), and the `Int32` leg (`(int64-to-int32 a)`, `option-map`ped through
`int32-to-int64` and back to a string).

| case | expected (abridged — the plan fixes the exact string at implementation) | discriminates |
|---|---|---|
| `[7,2]` | int `3\|1\|14\|5\|7\|-7\|2\|7`; float `3.5\|1.0\|14.0\|5.0\|7.0\|-7.0\|2.0\|7.0`; i32 `some 7` | **`/` and `mod` swapped** (3 ≠ 1); **`min`/`max` swapped** (2 ≠ 7); `-` operand swap (5 ≠ -5); `neg` confused with `abs` (-7 ≠ 7). And the whole float leg is the `Float64` instantiation `/`, `mod`, `min`, `max` never had. |
| `[-7,2]` | int `-3\|-1\|…`; float `-3.5\|-1.0\|…` | **truncation toward zero, not floor** — floor division gives `-4` and `mod` `+1`. `neg(-7)=7` and `abs(-7)=7` coincide here, which is why case 1 carries the distinction. |
| `[5,0]` | `checked-div none \| checked-mod none` | the zero-divisor arm of both; and that the entry does **not** trap |
| `[7,3]` | `checked-div some 2 \| checked-mod some 1`, float `some 2.333…` | **`checked-div`/`checked-mod` swapped** — quotient ≠ remainder. Any case with quotient == remainder cannot see it. |
| `[2147483647,1]` | i32 `some 2147483647` | `int64-to-int32` at the exact boundary |
| `[2147483648,1]` | i32 `none` | boundary + 1 — an off-by-one in `i32::try_from` (`rt.rs:39`) |
| `[-2147483648,1]` | i32 `some -2147483648` | the negative boundary, which is not symmetric |
| `[-2147483649,1]` | i32 `none` | negative boundary − 1 |
| `[9007199254740993,2]` | float leg shows `9007199254740992.0` | `int64-to-float64` at 2⁵³+1 — the exact value `differential.py`'s own docstring names as a known cross-runtime divergence |

Entry 2 `(defun fnum [(a String) (b String)] -> String)` — parses both with `string-to-float64`,
`option-or`s to `0.0`, returns `min | max | float64-to-int64 a` rendered.

| case | expected | discriminates |
|---|---|---|
| `["nan","1.0"]` | `"nan\|nan\|none"` | **the NaN rule**, pinned. §1.4 measured v1's template giving `1.0` here. NaN needs no literal: `(string-to-float64 "nan")` reaches it. |
| `["1.0","nan"]` | `"1.0\|1.0\|some 1"` | the other operand order — Python returns its *first* argument for both `min` and `max`, so this and the previous case together pin the rule rather than one accident of it |
| `["3.9","1.5"]` | `"1.5\|3.9\|some 3"` | `float64-to-int64` truncates toward zero |
| `["-3.9","1.5"]` | `"-3.9\|1.5\|some -3"` | **truncation, not floor** — floor gives `-4` |
| `["2.0","2.0"]` | `"2.0\|2.0\|some 2"` | the tie: `min` and `max` must both return the value, not diverge on equality |

### `14-list-reshaping.agents` — function mode, three entries — 10 builtins
`list`, `list-cons`, `list-append`, `list-reverse`, `list-slice`, `list-tail`, `list-head`,
`list-get`, `range`, `zip`

Entry 1 `(defun reshape [(n Int64)] -> String)` — `xs = (range 0 n)`, `ys = (list 100 200 300)`;
reports `list-cons 9 xs`, `list-append xs ys`, `list-reverse xs`, `list-tail xs`, `list-head xs`,
`list-get xs 1`.

| case | expected | discriminates |
|---|---|---|
| `[4]` | cons `[9,0,1,2,3]`; append `[0,1,2,3,100,200,300]`; reverse `[3,2,1,0]`; tail `some [1,2,3]`; head `some 0`; get `some 1` | **`list-append` operand swap** (the `100,200,300` block moves); reverse is not the identity (≥3 distinct, ascending input); `list-get` at index 1 — neither `0` nor `length-1`, so an off-by-one is visible; `list-cons(x, xs)` swap does not type-check here, which is stated as coverage |
| `[1]` | cons `[9,0]`; tail `some []`; head `some 0`; get `none` | `list-tail` of a one-element list is `some []`, not `none`; `list-get 1` is out of range |
| `[0]` | cons `[9]`; tail `none`; head `none`; get `none` | the empty-list arm of `list-tail`/`list-head`; `range 0 0` is `[]` |

Entry 2 `(defun window [(n Int64) (a Int64) (b Int64)] -> (Option (List Int64)))` — `(list-slice (range 0 n) a b)`.
This is the **composed return shape** (`(Option (List T))`) that W6(b)'s recursive encoder exists
for; a flat shape tag cannot express it.

| case | expected | discriminates |
|---|---|---|
| `[4,1,3]` | `["some",[1,2]]` | half-open `[a,b)`; an inclusive slice gives `[1,2,3]`; an `a`/`b` swap gives `none` |
| `[4,0,4]` | `["some",[0,1,2,3]]` | `b == n` is in range |
| `[4,0,5]` | `["none"]` | `b > n` is out — off-by-one in `rt::list_slice`'s `b > n` |
| `[4,3,1]` | `["none"]` | `b < a` is out |
| `[4,2,2]` | `["some",[]]` | the empty slice is `some []`, not `none` |

Entry 3 `(defun pairs [(n Int64)] -> (List (Pair Int64 String)))` — `(zip (range 0 n) (list "a" "b" "c"))`.
`(List (Pair A B))` is the second composed shape.

| case | expected | discriminates |
|---|---|---|
| `[2]` | `[["pair",0,"a"],["pair",1,"b"]]` | `zip` truncating to the **shorter** list, and pair component order |
| `[5]` | `[["pair",0,"a"],["pair",1,"b"],["pair",2,"c"]]` | truncation from the other side |

A `zip` that swapped its components would not type-check (`Int64` vs `String`) — coverage, not
discrimination, and said so.

### `15-list-aggregation.agents` — function mode, two entries — 8 builtins
`list-empty?`, `list-length`, `list-contains?`, `list-index-of`, `list-sum`, `list-min`,
`list-sort`, `list-sort-by` (re-exercises `list-max`)

Entry 1 `(defun agg [(csv String)] -> String)` over **`(List Float64)`** — split on `,`, parse each
with `string-to-float64`, `option-or` to `0.0`; reports `list-empty?`, `list-length`, `list-sum`,
`list-min`, `list-max`, `list-sort`.

| case | expected | discriminates |
|---|---|---|
| `["3,1,3,2"]` | `F\|4\|9.0\|1.0\|3.0\|[1.0,2.0,3.0,3.0]` | **`list-sort` as the identity** — the input is unsorted and carries a duplicate; **`list-min`/`list-max` swapped** — 1 ≠ 3 with ≥3 distinct values. And this is the `Float64` instantiation of `list-sort`/`list-min`/`list-max`, which is `E0277` today (§1.2). |
| `["0.1,0.2"]` | sum `0.30000000000000004` | float addition is not decimal addition — pins Python and Rust to the same double |
| `[""]` | `T\|1\|0.0\|0.0\|0.0\|[0.0]` | `list-empty?`'s true side… **no**: `(string-split "" ",")` yields `[""]` on both backends, so this is a one-element list. The genuinely empty case is below. |
| `["-2,-9,4"]` | `F\|3\|-7.0\|-9.0\|4.0\|[-9.0,-2.0,4.0]` | **negative values** — a sort keyed on magnitude gives `[-2,4,-9]`; `list-sum` of mixed signs |
| `["5"]` | `F\|1\|5.0\|5.0\|5.0\|[5.0]` | single element: `list-min == list-max`, which is exactly why it cannot be the only case |

Entry 1b `(defun agg-empty [] -> String)` — the same report over `(list)` typed `(List Float64)`:
expected `T|0|0.0|none|none|[]`. This is `list-empty?`'s true side and the empty-sum identity from
§1.5. It is a separate entry because `string-split` cannot produce an empty list.

Entry 2 `(defun lookup [(csv String) (needle Int64)] -> String)` over **`(List Int64)`** — reports
`list-contains?`, `list-index-of`, `list-length`, `list-sum`, `list-sort-by` with `(fn [x] (neg x))`.

| case | expected | discriminates |
|---|---|---|
| `["3,1,3,2", 2]` | `T\|some 3\|4\|9\|[3,3,2,1]` | `list-index-of` returning index **3** — neither `0` nor `length-1`, so an off-by-one or a "return the first index of anything" is visible; `list-sort-by (neg)` is descending, so a `list-sort-by` that ignored its projection gives ascending. This is the exact builtin that shipped with reversed arguments (`ROADMAP.md:204-205`). |
| `["3,1,3,2", 3]` | `T\|some 0\|4\|9\|[3,3,2,1]` | first-occurrence semantics: `3` appears at 0 and 2; `some 2` would be last-occurrence |
| `["3,1,3,2", 9]` | `F\|none\|4\|9\|[3,3,2,1]` | the absent side of `list-contains?`/`list-index-of` — a constant-`true` `list-contains?` passes the other two cases |

`list-sum` therefore runs at `Float64` (entry 1) and `Int64` (entry 2), satisfying §2's `N` rule.

### `16-map-lifecycle.agents` — function mode, two entries — 4 builtins
`map-has?`, `map-keys`, `map-remove`, `map-size` (re-exercises `map-empty`, `map-set`, `map-get`,
`map-from-pairs`, `map-pairs`, `map-values`)

Entry 1 `(defun lifecycle [(words String) (drop String)] -> String)` — build `(Map String Int64)`
counts by folding `map-set`/`map-get` over `(string-split words " ")`; report `map-size` before,
`map-has? drop`, then `map-size` after `map-remove drop`, then `(string-join (map-keys m2) ",")`.

| case | expected | discriminates |
|---|---|---|
| `["a b a c", "a"]` | `3\|T\|2\|b,c` | removing a key that **is** present: size drops. v1's case could not tell a correct `map-remove` from a no-op. |
| `["a b a c", "z"]` | `3\|F\|3\|a,b,c` | removing an absent key is a no-op — printing size before *and* after is what separates the two; and `map-has?`'s false side, without which a constant-`true` passes |
| `["", "a"]` | `0\|F\|0\|` | the empty map; `map-keys` of it is `[]`, joined to `""` |
| `["c b a", "b"]` | `3\|T\|2\|a,c` | `map-keys` is **sorted**, not insertion-ordered — the spec says sorted (`AGENT_SPEC_CORE.md:545`) and the two backends reach it differently (Python `sorted(...)`, Rust `BTreeMap`) |

Entry 2 `(defun counts [(words String)] -> (Map String Int64))` — returns the map itself, the same
shape the histogram task returns, keeping W6(b)'s encoder honest against the one case that existed
before the refactor.

`map-keys` vs `map-values` are type-distinct here (`String` vs `Int64`), so a swap fails to
compile. **Coverage, not discrimination** — stated, not claimed.

### `17-string-query.agents` — function mode, two entries — 7 builtins
`string-length`, `string-index-of`, `string-contains?`, `string-starts-with?`,
`string-ends-with?`, `string-slice`, `string-chars` (re-exercises `string-empty?`)

Entry 1 `(defun query [(hay String) (needle String)] -> String)` — reports `string-length hay`,
`string-index-of hay needle` (rendered as `some N`/`none`), `string-contains?`,
`string-starts-with?`, `string-ends-with?`, `string-empty? hay`, `(list-length (string-chars hay))`.

| case | expected | discriminates |
|---|---|---|
| `["banana","na"]` | `6\|some 2\|T\|F\|T\|F\|6` | **haystack/needle swap** — both arguments are `String`, so a swap type-checks and compiles. `(string-index-of "na" "banana")` is `none`. The case asserts `some 2`, not merely `is-some?`. |
| `["log:hello","log:"]` | `9\|some 0\|T\|T\|F\|F\|9` | needle at the **start only** — `starts-with?`/`ends-with?` swapped is invisible when the needle sits at both ends or when prefix == suffix |
| `["hello.log",".log"]` | `9\|some 5\|T\|F\|T\|F\|9` | needle at the **end only** — the mirror |
| `["abc","abc"]` | `3\|some 0\|T\|T\|T\|F\|3` | the equality boundary: a string is its own prefix and suffix |
| `["abc","z"]` | `3\|none\|F\|F\|F\|F\|3` | the absent side of all three predicates |
| `["","a"]` | `0\|none\|F\|F\|F\|T\|0` | `string-empty?`'s true side; every predicate on an empty haystack |
| `["héllo","l"]` | `5\|some 3\|T\|F\|F\|F\|5` | **char indices, not byte indices** — `rt::str_index_of` (`rt.rs:33-35`) converts a byte offset to a char count and `rt::str_len` counts chars; a lowering that returned `s.find()` directly gives `4` here and `string-length` gives `6`. Python is char-native, so this is exactly the divergence the differential gate exists to pin. |

Entry 2 `(defun cut [(hay String) (a Int64) (b Int64)] -> (Option String))` — `(string-slice hay a b)`,
the third composed return shape.

| case | expected | discriminates |
|---|---|---|
| `["banana",1,3]` | `["some","an"]` | half-open `[a,b)`; inclusive gives `"ana"` |
| `["banana",0,6]` | `["some","banana"]` | `b == length` is in range |
| `["banana",0,7]` | `["none"]` | `b > length` — off-by-one in `rt::str_slice`'s `b > n` |
| `["banana",3,1]` | `["none"]` | `b < a` |
| `["héllo",1,3]` | `["some","él"]` | char slicing, not byte slicing — byte slicing panics or yields mojibake |

### `18-string-transforms.agents` — function mode — 10 builtins
`str`, `string-join`, `string-lower`, `string-upper`, `string-replace`, `string-reverse`,
`string-from-int64`, `string-to-int64`, `string-to-float64`, `string-from-float64`

`(defun transform [(line String)] -> String)` — `|`-joined: `string-lower`, `string-upper`,
`string-reverse`, `(string-replace line "X" "-")`, `(string-join (string-split line " ") "+")`,
`(str "n=" (string-from-int64 (string-length line)))`,
`(string-to-int64 line)` rendered, and `(string-from-float64 (option-or (string-to-float64 line) 0.0))`.

| case | expected | discriminates |
|---|---|---|
| `["aXbXc"]` | replace → `a-b-c` | **`from`/`to` swapped** leaves `aXbXc` unchanged; **replace-first instead of replace-all** gives `a-bXc`. v1 covered only the second. |
| `["Hello World"]` | lower `hello world`; upper `HELLO WORLD`; reverse `dlroW olleH`; join `Hello+World` | `string-lower` as the identity (the input has an uppercase run); `string-upper` and `string-lower` swapped; `string-reverse` as the identity (non-palindromic); `string-join`'s separator argument |
| `["abc"]` | reverse `cba`; `n=3` | reverse on a short non-palindrome; `string-from-int64` |
| `["42"]` | `some 42`; float round-trip `42.0` | `string-to-int64`'s success side; `string-from-float64` renders a whole float as `42.0` on both backends (Python `repr`, Rust `{:?}`), not `42` |
| `["2.5"]` | int `none`; float `2.5` | `string-to-int64` must **not** accept a float; `string-to-float64`'s success side |
| `["0.1"]` | float `0.1` | shortest round-trip rendering agrees — Python `repr(0.1)` and Rust `{:?}` both give `0.1`, not `0.1000000000000000055…` |
| `["x"]` | int `none`; float `0.0` (the `option-or` fallback) | both parsers' failure side |
| `[""]` | `n=0`; join `` | the empty line |

### After Phase 1 lands — the eight `defenum` builtins

Phase 1 owns the `defenum` `Ord`/`Eq` derives (`.plans/ORCHESTRATOR-LOG.md:10-14`;
`.plans/phase-1/PLAN.md:354`, `:520-525`). Phase 2 schedules none of that work. But §2's rule
forbids calling `list-sort`, `list-min`, `list-max`, `map-has?`, `map-remove`, `map-keys`,
`map-pairs`, `map-from-pairs` *covered* on the strength of `Int64`/`String` instantiations alone —
that is the same error as B2.

So: those eight are recorded in `coverage.lock` as covered at their **primitive** instantiations
only, with `defenum` listed as an outstanding instantiation owned by Phase 1. When Phase 1 lands,
W5's generator gains a `defenum`/`defschema` arm (a two-case enum and a two-field record become
additional members of the `T`/`K` domain), Tier A's denominator grows, and fixtures `15`/`16` gain
an enum-keyed and an enum-sorted case. Until then the lock file says *not proven*, not *covered*.

---

## 6. Repair list

Ten builtins. Every "after" below was compiled this session; the whole set was then run against
the full gate suite in a throwaway copy of the repo (`check_corpus.py` 0 failures,
`differential.py` 0 disagreements, `pytest` 47 passed).

| # | builtin(s) | target | defect | before → after |
|---|---|---|---|---|
| 1 | — | `backend/rust/rt.rs` (new) | no way to write one helper over `N` | **after:** a `Num` trait — `pub trait Num: Copy + PartialEq { const ZERO: Self; fn quot(self, b: Self) -> Self; fn rest(self, b: Self) -> Self; fn plus(self, b: Self) -> Self; }` with impls for `i32`, `i64`, `f64`. `quot` on the integers keeps the existing overflow guard (`self.checked_div(b).expect("overflow in division")`); on `f64` it is `self / b`. `rest` is `%` on all three (Rust's `%` and Python's `mod` both take the dividend's sign). |
| 2 | `/` | `rt.rs:10-13` | `pub fn div(a: i64, b: i64) -> i64` against a declared `N N -> N` | `pub fn div<T: Num>(a: T, b: T) -> T { if b == T::ZERO { panic!("division by zero") } a.quot(b) }` — `b == 0.0` traps too, matching `runtime.py:34-40`, which raises `Trap` for any `b == 0` |
| 3 | `mod` | `rt.rs:14-17` | same | `pub fn rem<T: Num>(a: T, b: T) -> T { if b == T::ZERO { panic!("modulo by zero") } a.rest(b) }` |
| 4 | `checked-div` | `rt.rs:18` | same, against `N N -> (Option N)` | `pub fn checked_div<T: Num>(a: T, b: T) -> Option<T> { if b == T::ZERO { None } else { Some(a.quot(b)) } }` |
| 5 | `checked-mod` | `rt.rs:19` | same | `pub fn checked_rem<T: Num>(a: T, b: T) -> Option<T> { if b == T::ZERO { None } else { Some(a.rest(b)) } }` |
| 6 | `list-sum` | `rt.rs:82` | `pub fn sum(xs: Vec<i64>) -> i64` against `(List N) -> N` | `pub fn sum<T: Num>(xs: Vec<T>) -> T { xs.into_iter().fold(T::ZERO, Num::plus) }`. **Not** `T: std::iter::Sum<T>`, which the review verified compiles but which folds `f64` from `-0.0` (§1.5). Measured with the fold: empty `Vec<f64>` → `0.0`; `[0.1, 0.2]` → `0.30000000000000004`, identical to Python. |
| 7 | `min`, `max` | `prelude.json` templates **and** `rt.rs` | `std::cmp::min`/`max` need `Ord`; `f64` has none (`E0277`) | **templates:** `"rs": "std::cmp::min({0}, {1})"` → `"rs": "rt::min({0}, {1})"`, likewise `max`. **rt.rs:** `pub fn min<T: PartialOrd>(a: T, b: T) -> T { if b < a { b } else { a } }` and `pub fn max<T: PartialOrd>(a: T, b: T) -> T { if b > a { b } else { a } }`. Each argument is evaluated **once**; no literal braces to double; the `b`-relative comparison reproduces Python exactly — measured `min(nan,1)=NaN`, `min(1,nan)=1.0`, `max(nan,1)=NaN`, `max(1,nan)=1.0` against Python's `nan / 1.0 / nan / 1.0`. |
| 8 | `list-sort` | `rt.rs:66` | `sort<T: Ord>` — `E0277` on `(List Float64)` | `pub fn sort<T: PartialOrd>(mut xs: Vec<T>) -> Vec<T> { xs.sort_by(\|a, b\| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)); xs }` — measured `[3.0,1.0,2.0]` → `[1.0,2.0,3.0]` |
| 9 | `list-min` | `rt.rs:83` | `least<T: Ord + Clone>` — same | `pub fn least<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> { xs.iter().cloned().reduce(\|a, b\| if b < a { b } else { a }) }` — the reduce is Python's rule, not `iter().min()`'s. Measured `least(&[nan, 1.0]) = Some(NaN)`, matching Python's `min([nan, 1.0]) = nan`. |
| 10 | `list-max` | `rt.rs:84` | `greatest<T: Ord + Clone>` — same | `pub fn greatest<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> { xs.iter().cloned().reduce(\|a, b\| if b > a { b } else { a }) }` |

**Not repaired — narrowed instead (W4).** `map-get`, `map-set`, `map-has?`, `map-remove`,
`map-pairs`, `map-from-pairs` at a `Float64` key: 24 probes, all `E0277`. `BTreeMap` needs `Ord`;
`f64` has no total order; and the spec itself asks for sorted keys (§1.6), which `Float64` cannot
provide. Repairing this would mean replacing the Map representation for every program to support a
key type the specification never intended — rejected. rule-13 removes those 24 instantiations from
the admissible set, which is why Tier A's denominator is 400 and its floor is 100%.

**Compiled proof of the whole set.** With rows 1-10 applied, the §1.2 sweep re-run and restricted
to the post-rule-13 admissible set:

```
probes: 400   checker diags: 0   rustc rc=0 errors=0   py_compile rc=0
gen 0.00s · checker 0.94s · rustc 1.57s · py_compile 1.03s
```

and in a full throwaway copy of the repo with rows 1-10 applied:

```
backend/check_corpus.py    0 failure(s)
backend/differential.py    0 disagreement(s) across 7 function cases + 4 program cases x 2 backends
pytest …                   47 passed
```

**Decision recorded — NaN and ties.** `min`/`max` follow Python: return the **first** argument
unless the second compares strictly past it. This differs from JavaScript, whose `Math.min`
propagates NaN from either position; `prelude.json`'s `js` templates are therefore known-wrong for
NaN today. They are **not** changed in this phase: there is no JS runtime (`backend/` has `rust/`
and `golang/`, no `js/`) and no gate could check the change, so editing them would create an
unverifiable claim. Recorded as a decision for Phase 4 (§10).
`list-sort` with a NaN present is **unspecified** — Python's `sorted` is not a total order either
(`sorted([3.0, nan, 1.0])` → `[3.0, nan, 1.0]`), and no fixture asserts it.
Rounding a half is untouched by this phase and stays an open portability question (§9).

---

## 7. Coverage gate design

`grammar/closure_audit.py` keeps its existing job — undefined call heads, over
`corpus/valid` **plus** the `AGENT_SPEC_CORE.md` fragments, because closure is exactly a claim
about the document. It gains a second, separately-computed number.

**Numerator.** `EXECUTED = differential.executed_sources()` — a new function in `differential.py`
that returns the source paths its task list and its program-mode case list name, so there is one
source of truth and the audit cannot drift from what actually runs. The audit imports it. Spec
fragments and un-executed `corpus/valid` files are **not** in it.

**Denominator.** `len(vocab.builtins())` = 107. Unchanged, and already correct: the 10 operator
heads are in `prelude.json` and `closure_audit.py:34` captures `(call callee: (operator))`.

**`prelude/coverage.lock`** — checked in, JSON, the gate's data:

```json
{ "floor_pct": 95,
  "executed": 107,
  "instantiations": { "list-sum": ["Int64", "Float64"], "…": ["…"] },
  "unproven": { "list-sort": ["defenum — Phase 1"], "…": ["…"] },
  "unexecuted": { } }
```

**The gate fails on any of four conditions**, each printed with the shortfall:

1. `pct < floor_pct` — the floor. 102/107 is 95%; 101 is 94% (integer floor division,
   `closure_audit.py:79-80`).
2. `executed_count < lock["executed"]` — the **ratchet**. A hard floor alone permits a silent
   slide from 107 back to 102. The lock is updated deliberately, in the same commit that earns it.
3. `executed_count > lock["executed"]` — the lock is stale. Forces the number to be recorded, not
   drifted into.
4. any `grammar/corpus/valid/*.agents` that is in no `differential.py` case and not on an explicit
   `UNEXECUTED` list carrying a reason — mirroring `check_corpus.py:22-23`'s `SKIP_RUST`/`SKIP_PY`
   convention. This is what stops nine fixtures landing with no task files.

Exit code becomes `len(undefined) + coverage_failures`, preserving the existing signal (each
undefined head still counts one) while adding the new one. No consumer parses this: the repo has
no `.github/` and no CI config (§1.9), so v1's risk on that point is closed.

**Why each attack from the review fails.**

| attack | outcome |
|---|---|
| add a `defun` example to `AGENT_SPEC_CORE.md` | numerator is the executed set; spec fragments are not in it. **No effect.** |
| delete an unexercised builtin from `prelude.json` | denominator drops **and** so does Tier A's probe count; and the ratchet (condition 3) makes the lock stale, failing the gate. |
| widen a scan root | there is no scan root for the numerator. |
| land fixtures, drop the task files | condition 4 fails, naming each unexecuted fixture. |
| lower the `95` | it is data in `coverage.lock`, and lowering it does not clear the ratchet (condition 2), which is computed against `executed`, not against the floor. |
| exercise a generic builtin at one type and call it done | Tier A (W5) compiles **every** admissible instantiation; the lock records which ones **executed**, and the `N` rule (§2) requires two. |

---

## 8. Acceptance gate

Run from the repo root. All seven must exit 0, plus the new eighth.

```
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/python -m pytest backend/t bench/algo checker/t -q
```

`check_corpus.py`, `monomorphism.py` and `differential.py` invoke `rustup run stable rustc`
internally (`check_corpus.py:57-58`, `differential.py:59-60`, `:80-81`); no bare `cargo` is
reached, so `AGENTS.md`'s broken-shim note does not bite.

| command | expected | what it would **not** catch |
|---|---|---|
| `grammar/validate.py` | 0 failures; 18 valid fixtures | anything semantic. A fixture that parses and means the wrong thing passes. |
| `closure_audit.py` | `OK: spec and corpus are closed`; `executed builtins : 107/107 (100%)`; lock in sync | a builtin executed at one instantiation only — that is Tier A's job, and the lock's `instantiations` field is data the gate does not itself verify against the fixtures. **A wrong `instantiations` entry is only caught by review.** |
| `generate.py --check` | 0 | a template that is well-formed and wrong. `validate_templates` formats with dummy args and catches raised exceptions only (`generate.py:148-169`); a single un-doubled brace with spare dummy args is consumed silently. Exhaustively scanned: `map-empty`'s `py` `"{{}}"` is the only literal-brace template in the vocabulary, and it is correctly doubled. |
| `checker/gate.py` | 0 failures; every semantic fixture rejected **for its declared rule** | a rule the checker does not have. rule-13 exists only because W4 writes it. |
| `check_corpus.py` | 0 failures; 10 rows (8 corpus + 2 bench) | anything about **behaviour**. It runs `--crate-type=lib` and `py_compile`; neither executes a line. This is precisely the gap that let `list-sort-by` ship with reversed arguments. |
| `monomorphism.py` | `400 probes, 0 failures` | behaviour, again — it proves every instantiation *compiles*, not that it *computes*. It also cannot see higher-order, variadic or effectful builtins, which it excludes **and prints**, so the exclusion is auditable rather than silent. |
| `differential.py` | 0 disagreements; the histogram table byte-identical to §1.1; 7 + N function cases, 7 program cases | a defect the two backends share. Both are generated from the same `prelude.json` declaration, so a wrong *declaration* agrees with itself — which is why every case in §5 carries a checked-in **expected** value, and why W6(d) adds one to program mode. It also cannot see a case whose input does not discriminate; §5 is the mitigation and it is a design artefact, not an enforced one. |
| `pytest` | ≥47 passed (47 today, plus W5's and W6's new tests) | whatever no test covers. |

**Not proven by any of the eight, and stated rather than implied:** rounding a half; `Int32`
overflow semantics; `already-exists`/`invalid-path`/`interrupted`/`other` **host mappings** (their
constructors are covered, §5 `09` case 6); every `defenum`-typed instantiation of the eight
builtins §5 lists as Phase 1's; and the JS templates, which have no runtime to run.

---

## 9. Risks and unknowns

1. **W6 is the largest single change and has one regression guard.** Rewriting `run_rust`,
   `run_python`'s driver, `programs()` and `main()` leaves exactly one pre-existing function task
   and four program cases to detect a mistake. Mitigation: capture the current output first (it is
   in §1.1), land W6 in the four separable parts (a)-(d) named in §4, and diff after each.
2. **Phase 1 edits `differential.py` too** (`.plans/phase-1/PLAN.md:431`). W6 must be **rebased**
   onto whatever Phase 1 leaves, not merged into it. If Phase 2 runs first, Phase 1 inherits the
   rebase. Either way one of the two pays; the orchestrator should decide which.
3. **rule-13 is a language narrowing.** It makes a program that type-checks today stop
   type-checking. No corpus, bench or module fixture uses a `Float64` map key (all 440 probes were
   synthetic), so the measured blast radius is zero — but it is a semantic change and belongs in
   the PCP record, not in a commit message.
4. **The `Num` trait is public surface in `rt.rs`,** which ships with every generated program. It
   is `pub` because the generated code names `rt::div::<f64>` implicitly. A future ownership
   decision (`.plans/PHASES.md`, `l-880d`, recorded as blocked) could force it to change shape.
5. **`coverage.lock`'s `instantiations` field is data no gate verifies against the fixtures.** A
   wrong entry is caught by review only. Deriving it automatically would need the checker to
   report the concrete type at each call site — real work, out of proportion here, and named as a
   candidate for a later phase rather than left as an unstated weakness.
6. **Ten fixtures is a lot of new source.** Each must pass four gates. Land them one at a time
   (W8); a batch failure in `differential.py` names the disagreeing case but not which of ten new
   programs is at fault.
7. **Rounding a half is unresolved.** `differential.py`'s own docstring records that Python and
   JavaScript disagree on it. No builtin in the vocabulary rounds, so nothing in this phase
   forces the decision — but Phase 4 will, and Phase 3's Wasm route will inherit whatever is
   chosen. Recorded, not decided here.
8. **Program-mode case 4 needs a file mode of `0o000`.** If the phase is ever run as root, or on a
   filesystem that ignores modes, that case silently becomes a success case. Guard: the case
   asserts `permission-denied`, so it fails loudly rather than passing vacuously.

---

## 10. PCP entries to record

1. **Coverage is redefined and `l-3434` closes at 107/107 executed.** The metric changed from
   "call head in a parsed file" to "called by a source the differential harness executes, in a case
   whose result both backends match against a checked-in expected value". The old metric read 36;
   the same tree under the new metric read **21**. Floor 95% plus a ratchet, both data in
   `prelude/coverage.lock`.
2. **A second, orthogonal gate: `backend/monomorphism.py`.** Every (builtin × admissible
   instantiation) — 400 of them — must compile on both backends. This is the artifact that would
   have caught `filter`, `list-sort-by`, `list-sum`, `/` and `mod`; it replaces a per-builtin
   eyeball with a generated sweep, and it runs in ~3.5 s.
3. **"Exercised" never meant "the lowering works".** It meant "the lowering works at the one type
   someone happened to use". Ten builtins were broken over part of their declared type at head
   `8679362` with every gate green: `/`, `mod`, `checked-div`, `checked-mod`, `list-sum`, `min`,
   `max`, `list-sort`, `list-min`, `list-max`. Two of them were inside the 36 the coverage figure
   called exercised. (Extends the `filter`/`list-sort-by` lesson; supersedes the framing in
   `.plans/phase-2/INVENTORY.md` §3.)
4. **`min`/`max` NaN semantics are decided: Python's rule.** Return the first argument unless the
   second compares strictly past it. Implemented in `rt.rs`, pinned by `13-numeric.agents` entry 2.
   `prelude.json`'s `js` templates (`Math.min`/`Math.max`) propagate NaN from either position and
   are therefore known-wrong; **not changed in this phase** because no JS runtime exists to verify
   the change. Phase 4 owns it.
5. **`list-sort` on `Float64` with a NaN present is unspecified.** Python's `sorted` is not a total
   order either. No fixture asserts it.
6. **rule-13 — a `Map` key must be orderable.** `AGENT_SPEC_CORE.md:123` said `K` needs equality
   while `:545-547` specified sorted keys; `(Map Float64 V)` type-checked and could not lower to
   any backend (24 instantiations, `E0277`). The spec is corrected and the checker now enforces it.
   Language narrowing; measured blast radius on the existing corpus: zero.
7. **`ROADMAP.md` §2's "Rust backend working" is corrected.** It was working for `Int64`. Phase 3's
   Wasm route goes through this backend and inherited the gap. (W10.)
8. **`prelude/generate.py`'s arity heuristic diverged from `vocab.parse_signature` for 34 of 107
   builtins, in two places** (`:31` and `:158`). Shipped in `AGENT_SPEC_CORE.md` §6 —
   `(map-get a b c d)` for a two-argument builtin. Both copies fixed.
9. **`backend/differential.py` generalised** from one hardcoded task with a single `String` input
   and a map-only serializer to a data-driven harness: typed multi-argument inputs derived from the
   entry's declared signature, a recursive JSON encoder (`backend/rust/harness.rs`) driven by the
   parsed return type, Python-side normalisation so `Option`/`Result`/`Pair`/non-finite floats
   encode identically, and an expected-output oracle for program mode. Fixture cases live in
   `backend/cases/`, **not** `bench/tasks/`, which `bench/harness/run.py:189` globs.
10. **Cross-reference, not a new owner:** the `defenum` `Ord`/`Eq` derive gap is **Phase 1's**
    (`.plans/ORCHESTRATOR-LOG.md:10-14`, `.plans/phase-1/PLAN.md:354`). Phase 2 records the eight
    affected builtins in `coverage.lock` as *proven at primitive instantiations only* and schedules
    no work on it. `defschema`'s mirror-image defect — deriving `Ord` unconditionally, so a record
    with a `Float64` field is an illegal `Map` key and an illegal `list-sort` element — belongs
    with the same fix.
