# Phase 2 — Vocabulary coverage  (v3, re-planned onto landed Phase 1)

Closes PCP `l-3434` / `ROADMAP.md` §6 / `.plans/PHASES.md:30-33`.
Supersedes v2 in full, which superseded v1 in full. `INVENTORY.md` is retained only as a raw
table; every number this plan needs has been re-derived from the tree **as it stands with Phase 1
landed and its two fix passes applied**, and is restated in §1. No implementation was performed
writing this plan — every experiment ran in the session scratchpad, and the working tree is
unchanged.

---

## 0. What changed from v2

v2 was verified (`REVIEW-v2.md`) and returned **approve-with-amendments**: three amendments parked
until Phase 1 landed, because two of them depended on what Phase 1 actually took. Phase 1 has since
landed, been reviewed, and taken two fix passes. This section names every amendment and every figure
that moved. Everything below §0 is written as one plan, not as v2 plus errata.

### 0.1 The three parked amendments, resolved

**A1 — B1 (the coverage numerator) is closed by a tracer, not by a scan.**
v2's numerator was `run_query(differential.executed_sources())` — the same tree-sitter static scan
`closure_audit.py:32-50` runs today, over fewer files. The verifier demonstrated the fake rather
than describing it: a ten-line fixture whose single case takes the `else` arm moved the reported
figure **21 → 32 with zero of the eleven builtins executed**.

A working precedent now exists. The session that rewrote `ROADMAP.md` built the tracer the fix
called for and used it to produce §6's honest figures: every builtin's Python lowering template is
wrapped in a recorder before transpiling, then every program the gates execute is run. Re-derived
this session against the current tree rather than taken from `ROADMAP.md`:

```
programs executed             : 18
builtins defined in section 6 : 107
EXECUTED builtins             : 33/107  (30%)

mentioned : 38
executed  : 33
mentioned-but-never-executed : 17 ['-', '/', '<', '>', 'abs', 'list-get', 'list-head',
  'list-sort-by', 'max', 'mod', 'option-to-result', 'range', 'string-chars', 'string-length',
  'string-slice', 'string-to-int64', 'zip']
executed-but-not-in-scan-set : 12 ['err', 'list', 'list-max', 'map-from-pairs', 'map-pairs',
  'map-values', 'none', 'not', 'ok', 'option-or', 'some', 'string-empty?']
union                        : 50
neither                      : 57
```

38 − 17 = **21 counted and executed**; **33 executed overall**; **57 neither mentioned nor
executed**. `ROADMAP.md` §6's numbers reproduce exactly. That mechanism becomes §7's numerator and
lives in a new `backend/exec_coverage.py` (§4 W9). A call head in an arm no case takes records
nothing, which is precisely the fake v2 could not see.

**A2 — the rule-code collision is resolved by name, not by a number.**
v2 planned `rule-13`; `checker/resolve.py:266` reports it for a private type in an exported
signature and `AGENT_SPEC_CORE.md:695-700` is checklist item 13. The parked amendment said "use
rule-14". **That instruction is now wrong.** Phase 1's fix pass established PCP `d-bad1`: a check
with no §9 checklist entry is coded **by name**, never the next free rule number — `type-arity` and
`internal` are the two existing instances, and `ROADMAP.md` §6 records the resulting asymmetry.
§9's items 1-13 were read in full; none covers the domain of a `Map` key (item 6 governs mixing
numeric *operands*, not key types). So W4's check is coded **`map-key-order`**, and its fixture is
`grammar/corpus/semantic/map-float-key.agents` with `; expect-only: map-key-order`. No checklist
item is minted; adding one is a specification change and is not in scope here.

**A3 — the fixtures renumber to `19`–`28`.**
`grammar/corpus/valid/` now runs to `18-pattern-binders.agents` (18 fixtures). The verifier's
"renumber to 13–22" was written when the corpus held 12. Verified listing in §1.1. v2's ten
fixtures become `19-io-errors` … `28-string-transforms` (§5).

### 0.2 Figures that moved

| figure | v2 | v3 | how re-derived |
|---|---|---|---|
| unit tests | 47 | **79** | `.venv/bin/python -m pytest backend/t bench/algo checker/t -q` → `79 passed in 0.55s` |
| `corpus/valid` fixtures | 8 | **18** | `ls grammar/corpus/valid/` |
| `corpus/semantic` fixtures | — | **34** (32 files + `import-cycle/{a,b}`) | `ls grammar/corpus/semantic/` |
| `closure_audit.py` mentioned figure | `36/107 (33%)` | **`38/107 (35%)`** | `.venv/bin/python grammar/closure_audit.py` |
| executed baseline (the numerator that matters) | 21/107 | **33/107 (30%)** | scratchpad `execcov.py`: 18 gate-executed programs, LOWER-wrapper recorder |
| builtins left to execute | 86 | **74** | 107 − 33; enumerated in §1.3 |
| `differential.py` cases | 7 function + 4 program | **7 function + 7 program** | `.venv/bin/python backend/differential.py` |
| new fixture numbers | 09–18 | **19–28** | §1.1 |
| W4's diagnostic code | `rule-13` | **`map-key-order`** | PCP `d-bad1`; §9 checklist read in full |
| `check_corpus.py` scope | 8 corpus rows, `SKIP_RUST`/`SKIP_PY` | **18 corpus rows, no skip lists, five columns** (`python compile run rust rustc`), 10 rows with a `run` verdict | `.venv/bin/python backend/check_corpus.py` |
| `HANDBOOK.md` baseline | 12,078 chars | **12,281 chars** (12,311 bytes) | `len(open('prelude/HANDBOOK.md').read())` |
| `generate.py` arity heuristic sites | `:31`, `:158` | **`:30`, `:162`** | `grep -n 'split("->")' prelude/generate.py` |
| Tier A probe count | 440 → 400 | **440 → 400, unchanged** | re-derived: 56 probed builtins; 9 effectful / 2 variadic / 7 higher-order / 33 monomorphic excluded; 10 `Map` builtins × `K=Float64` × 4 `V` = 40 removed |
| Tier A failures today | 39 over 16 builtins | **39 over 16 builtins, unchanged** | full sweep re-run, 39.7 s (§1.2) |
| arity mismatches | 34 | **34, unchanged** | §1.7 |
| W1 handbook delta | −98 chars | **−98 chars, unchanged** | §1.7 |

### 0.3 What Phase 1 already did — v2 items that no longer apply as written

* **`programs()` gained a declared-output oracle.** `differential.py:92-121` now takes cases as
  `(argv, fixture, *declared)` and fails a case when `python`'s stdout differs from the declared
  string, even with both backends agreeing (`:104`, `:110`, `:114`). v2's W6(d) is therefore **half
  landed**: what remains is the per-case `files` map with modes (fixture `19` case 4 needs `0o000`)
  and the expected **exit status**. Rescoped in §4 W6.
* **Both emitters gained a lexical shadow stack, and `sequence()` covers all six
  multi-expression-body positions** (`14-sequenced-bodies.agents`, `15-shadowed-binders.agents`,
  both with `; run:` headers and both in `differential.py`'s program list). Multi-expression bodies
  are no longer a coverage hole, and §5's fixtures may use them freely.
* **The resolve pass no longer skips `cond` clause bodies**, and `semantic/unbound-in-cond.agents`
  pins it. §5's `cond`-using fixtures were re-checked against the landed checker (§1.10).
* **Rust lowering defects fixed:** nested `cons` (`17-nested-cons.agents`), boxed `defschema`
  fields (`16-recursive-schema.agents`), slice-pattern head binders (`18-pattern-binders.agents`).
* **`check_corpus.py` was rewritten** — no skip lists, a `run` column driven by a fixture's `; run:`
  header, five columns. v2's W7 acceptance ("8 corpus + 2 bench = 10 rows") is void; restated as an
  invariant without a count.
* **`ROADMAP.md` §2 and §6 were already corrected.** The Rust-backend row reads *working for
  `Int64`* and §6 carries the `Int64`-only bullet naming Phase 2 as the owner. v2's W10 ("the row
  currently reads as working — correct it") no longer applies; W10 becomes *retire* those two
  statements when the repairs land, and rewrite §6's coverage bullet against the new metric.
* **PCP `d-bad1` exists** and decides A2. v2's §10 entry 6 is rewritten accordingly.

### 0.4 The premise, retained from v2

v1's organising premise was *a builtin named in a parsed file is exercised, and an exercised
builtin's lowering works.* Both halves are false. v2 replaced the first half with execution and the
second with a compiled monomorphism sweep. v3 keeps both and closes the remaining gap: v2's
"execution" was still measured by a static scan. It is now measured by running the code.

---

## 1. Verified findings

Everything below was run this session against the tree as it stands. `python` means
`.venv/bin/python` from the repo root; `rustc` means `rustup run stable rustc --edition 2021` (the
cargo shim is broken — `AGENTS.md`).

### 1.1 Baseline — all seven gates green, 79 tests, 18 valid fixtures

| gate | exit | note |
|---|---|---|
| `grammar/validate.py` | 0 | `0 failure(s)`; 34 semantic-only fixtures listed |
| `grammar/closure_audit.py` | 0 | `distinct call heads : 56`; `exercised builtins : 38/107 (35%)`; `OK: spec and corpus are closed` |
| `prelude/generate.py --check` | 0 | |
| `checker/gate.py` | 0 | `0 failure(s)` |
| `backend/check_corpus.py` | 0 | `0 failure(s)`; 18 rows, columns `python compile run rust rustc`; 10 rows carry a `run` verdict |
| `backend/differential.py` | 0 | `0 disagreement(s) across 7 function cases + 7 program cases x 2 backends` |
| `pytest backend/t bench/algo checker/t -q` | 0 | `79 passed in 0.55s` |

`grammar/corpus/valid/`, in full:

```
01-basics 02-match 03-strings 04-longest-run 05-constructors 06-module 07-lambda-elision
08-io 09-imported-types 10-imported-generic-types 11-name-coexistence 12-transitive-use
13-module-program 14-sequenced-bodies 15-shadowed-binders 16-recursive-schema 17-nested-cons
18-pattern-binders
```

Ten of them carry a `; run:` header (`06`, `09`, `10`, `11`, `12`, `14`, `15`, `16`, `17`, `18`);
`check_corpus.py` evaluates that expression over the emitted names and requires it true. This is
the state v3 must restore at the end, with the additions §8 names.

### 1.2 The monomorphism sweep — still 16 builtins, still 39 instantiations

Re-run this session, unchanged mechanically from v2 (scratchpad `audit.py`): for every
non-effectful, non-variadic, non-higher-order builtin whose declared type contains a type variable,
substitute each admissible concrete type (`N` → `Int32`/`Int64`/`Float64`; any other variable →
`Int64`/`Float64`/`String`/`Bool`), emit `(defun probe [(a0 T0) …] -> R (name a0 …))`, run
`checker/resolve.check_file`, then `to_rust.py` + `rustc --crate-type=lib`.

```
total 440   ok 401   checker_reject 0   bad 39          (39.7 s wall, one process per probe)
  /            2      list-sum      2      map-from-pairs 4      map-remove 4
  checked-div  2      list-max      1      map-get        4      map-set    4
  checked-mod  2      list-min      1      map-has?       4      max        1
  mod          2      list-sort     1      map-pairs      4      min        1
```

The domain arithmetic, derived independently of the sweep: 107 builtins = 9 effectful + 2 variadic
+ 7 higher-order + 33 with no type variable + **56 probed**, and the 56 generate **440** probes. Ten
`Map` builtins each carry `{K, V}` over the four-element domain, so `K=Float64` is 4 probes each =
**40**; removing them leaves **400** (§4 W4). The verifier's correction to v2's prose is folded in
here: the rule removes 40 instantiations, of which 24 fail today.

The checker rejected **nothing**: all 440 probes check clean. The checker's admissible set is
strictly larger than the Rust backend's, at 39 points. `/` and `mod` are inside the 38 the current
figure calls *exercised* — and, per §1.3, neither is ever executed.

### 1.3 The executed baseline is 33/107; 74 builtins remain

Measured by the tracer, not by a scan (§0.1). The recorder rewrites each entry of `to_python.LOWER`
as `(hit('<name>') or (<template>))` — `hit` returns `None`, so `or` always yields the original
expression, and it fires exactly when that expression is evaluated. The 18 programs run are the ones
the gates already execute: the 10 `; run:` fixtures, `08-io.agents` at its four argv shapes,
`13`/`14`/`15` as whole programs, and `variants/tight.agents` through the histogram task's 7 cases.

```
EXECUTED (33): * + = eprintln err file-read file-write filter fold list list-cons list-max map
map-empty map-from-pairs map-get map-pairs map-set map-values none not ok option-or println some
str string-empty? string-from-float64 string-from-int64 string-join string-split string-trim
string-upper
```

The **74** that remain:

```
!= - / < <= > >= abs already-exists and checked-div checked-mod file-append file-exists?
float64-to-int64 int32-to-int64 int64-to-float64 int64-to-int32 interrupted invalid-path is-err?
is-none? is-ok? is-some? list-append list-contains? list-empty? list-get list-head list-index-of
list-length list-min list-reverse list-slice list-sort list-sort-by list-sum list-tail map-has?
map-keys map-remove map-size max min mod neg not-found option-map option-to-result or other pair
permission-denied print range read-all read-line result-map result-map-err result-or
result-to-option string-chars string-contains? string-ends-with? string-index-of string-length
string-lower string-replace string-reverse string-slice string-starts-with? string-to-float64
string-to-int64 zip
```

They partition exactly across §5's ten fixtures: 11 + 5 + 6 + 7 + 13 + 8 + 8 + 4 + 7 + 5 = **74**,
and 33 + 74 = **107/107**, five clear of the 102 floor.

Seventeen builtins are counted by `closure_audit.py` and never run — `/`, `mod`, `-`, `<`, `>`,
`abs`, `max`, `list-get`, `list-head`, `list-sort-by`, `option-to-result`, `range`, `string-chars`,
`string-length`, `string-slice`, `string-to-int64`, `zip`. Twelve run in files the scan root does
not cover (the module fixtures and the bench variant). The scan is therefore wrong in **both**
directions, which is why §7 replaces it as the numerator rather than widening it.

### 1.4 `min`/`max`: double evaluation and inverted NaN, both still live

`prelude.json` still declares `"rs": "std::cmp::min({0}, {1})"` and `std::cmp::max`. Probe:

```
(defun p [(a Float64) (b Float64)] -> Float64 (min a b))
→ checker exit 0
→ error[E0277]: the trait bound `f64: Ord` is not satisfied
  note: required by a bound in `std::cmp::min`
```

v1's inline-`if` template `(if {0} <= {1} {{ {0} }} else {{ {1} }})` puts its first argument in the
output twice — measured in v2 with a call counter, and unchanged by anything Phase 1 did, since the
template is untouched. `E0382` does **not** reproduce: every `N` is `Copy`, so a duplicated argument
never moves; the defect is duplicated *evaluation* of a pure expression.

NaN, measured on both sides (v2, reproduced by the verifier verbatim):

```
python  min(nan,1.0)=nan   min(1.0,nan)=1.0   max(nan,1.0)=nan   max(1.0,nan)=1.0
v1 tpl  min(nan,1)=1.0     min(1,nan)=NaN                        <-- inverted, both ways
W2 fix  min(nan,1)=NaN     min(1,nan)=1.0     max(nan,1)=NaN     max(1,nan)=1.0
```

### 1.5 The `Sum` identity diverges on an empty `Float64` list

```
rust  rt::sum(Vec<f64>::new()) = -0.0        (std's Sum for f64 folds from -0.0)
py    sum([])                  = 0    (int)
```

Real, and **invisible to the current comparator**: `differential.py` compares Python objects and
`-0.0 == 0` is `True`. W2 removes it at the source by folding from `T::ZERO`; measured
`sum2_empty_f64=0.0`, `sum2(vec![0.1,0.2])=0.30000000000000004` (identical to Python). `rt.rs:82` is
still `pub fn sum(xs: Vec<i64>) -> i64`, so the repair is still owed.

### 1.6 `(Map Float64 V)` is a spec contradiction, not just a lowering gap

`AGENT_SPEC_CORE.md:123` — ``| `(Map K V)` | Immutable keyed collection; `K` must support equality |``.
`AGENT_SPEC_CORE.md:576-578` — `map-keys` "Keys, **sorted**"; `map-values`/`map-pairs` "ordered by
sorted key". Sorting needs an order, not equality. The checker enforces neither (§1.2: 40 probes
clean, 24 of them failing at `rustc`), `rt.rs` picks `BTreeMap` which needs `Ord`, and `f64` has no
total order. The declaration is wider than any backend can implement. Confirmed still live:

```
(defun p [(m (Map Float64 Int64)) (k Float64)] -> (Option Int64) (map-get m k))
→ checker exit 0
→ error[E0277]: the trait bound `f64: Ord` is not satisfied
  note: required by a bound in `m_get`
```

### 1.7 The arity heuristic — 34 mismatches, in two places, both still present

`len(b["type"].split("->")[0].split())` vs `len(parse_signature(b["type"])[0])` over all 107:
**34** mismatches (`string-join` 3→2, `list-empty?` 2→1, `list-append` 4→2, `map-from-pairs` 4→1,
`map-set` 5→3, …). Visible in both shipped artifacts: `AGENT_SPEC_CORE.md:571` and
`HANDBOOK.md:182` both render two-argument `map-get` as `(map-get a b c d)`.

The heuristic exists **twice**: `prelude/generate.py:30` (in `signature()`) and
`prelude/generate.py:162` (in `validate_templates()`). Measured replacement delta: **−98
characters** in `HANDBOOK.md` and **−98** in `AGENT_SPEC_CORE.md`; the handbook goes 12,281 →
12,183 characters.

### 1.8 The six `IoError` constructors *are* executable

They are unreachable as *host-raised* errors; they are ordinary nullary calls. Probe, checker CLEAN,
both backends:

```
(defun label [(e IoError)] -> String (cond ((= e (not-found)) "not-found") … (:else "other")))
(defun labels [] -> String (string-join (list (label (not-found)) … (label (other))) ","))

rust:   not-found,permission-denied,already-exists,invalid-path,interrupted,other
python: not-found,permission-denied,already-exists,invalid-path,interrupted,other
```

All six constructors execute and agree. Fixture `19` executes all six (§5).

### 1.9 Miscellaneous, all confirmed this session

| claim | verdict |
|---|---|
| `closure_audit.py:57` is the whole scan root; `:41-46` appends spec markdown blocks | yes |
| `closure_audit.py:88` `return len(undefined)` — coverage printed, never enforced | yes |
| `100*102//107 = 95`, `100*101//107 = 94` — 102 builtins is the 95% floor | yes |
| the 107 denominator already includes the 10 operator heads | yes (`closure_audit.py:33-34`) |
| `check_corpus.py:24` globs `corpus/valid` only; it never reaches `bench/` | yes — W7 still owed |
| `check_corpus.py` no longer carries `SKIP_RUST`/`SKIP_PY`; it has a `run` column instead | yes |
| `differential.py` function mode is still hardcoded: one task path (`:125`), a single `String` input per case (`:39`, `:51`), a map-only Rust serializer (`:57-61`), a no-op normalisation (`:70`) | yes |
| `programs()` **does** now compare against a declared stdout (`:104`, `:110`, `:114`) — but has no `files` map, no per-file mode, and no expected exit status | yes |
| `bench/harness/run.py:174,189` globs `bench/tasks/*.json` | yes — fixture case files must NOT go there (§4 W6) |
| no `.github/` or any CI config in the repo | yes — v1's "exit code consumer" risk is moot |
| `cond`'s fallback is `:else`, not `else` (`grammar/agents.lark`) | yes |
| `rt.rs` is untouched by Phase 1 on the numeric surface: `div`/`rem`/`checked_div`/`checked_rem` `i64`, `sum` `Vec<i64>`, `sort`/`least`/`greatest` `T: Ord`, `m_*` `K: Ord` | yes (`rt.rs:10,14,18,19,66,82,83,84,86-95`) |
| `prelude/coverage.lock` does not exist | yes |
| `backend/cases/` does not exist | yes |

### 1.10 §5's fixtures are single-module, and that claim is now checkable

v2 asserted its fixtures were single-module and therefore independent of Phase 1. Checked against
real code rather than against a plan: three representative fixture bodies were written and put
through `checker/check.py`, `to_rust.py`, `to_python.py` and `rustc --crate-type=lib`.

| probe | checker | to_rust | to_python | rustc |
|---|---|---|---|---|
| `band` — `<= >= < > != and or not =` over `Int64` (fixture `22`) | 0 | 0 | 0 | clean |
| `classify` — `pair`, `cond`/`:else`, `is-some?`, `is-none?` (fixture `20`) | 0 | 0 | 0 | clean |
| `agg` — `map`/`fn`, `string-split`, `option-or`, `list-sum` over `(List Float64)` (fixture `25`) | 0 | 0 | 0 | **2 × `E0308`** |

The claim **holds**, with the one dependency v2 already stated: the `Float64` legs fail on the
W2/W3 repairs, not on anything Phase 1 owns. `cond`-bodied fixtures survive the now-strict resolve
pass. Two corrections to the claim's *scope*: the fixtures are not independent of Phase 1's
**numbering** (A3) nor of its `; run:` convention, which they should adopt so `check_corpus.py`
gives them a `run` verdict rather than a `-`.

---

## 2. What "covered" means

The gate enforces two independent properties. Neither can be satisfied by editing prose, by a
fixture that is never run, or by a branch that is never taken.

**Tier A — compiles at every admissible instantiation.**
An *instantiation* is a builtin paired with one concrete assignment to every type variable in its
declared signature. The admissible set is generated from `prelude.json` by
`prelude/vocab.parse_signature`, not hand-listed. Every admissible instantiation must produce a
probe that the checker accepts, `to_rust.py` lowers, `rustc --crate-type=lib` accepts, and
`py_compile` accepts. **Denominator = 400** after W4 narrows Map keys (440 before). Floor: 100%, no
exceptions, no skip list — a failure is either a lowering bug (fix it) or a signature the language
should not admit (narrow it, as W4 does).

*Why this cannot be faked:* the probe corpus is generated from `prelude.json` and compiled by
`rustc`. Adding a markdown example changes nothing. Deleting a builtin removes it from **both**
sides. There is no scan root to widen. Shrinking the sweep is caught because the probe count, the
domains and the exclusion list are recorded in `coverage.lock` and checked three ways (§7).

**Tier B — executes and agrees.**
A builtin is **covered** when its lowering is **evaluated** while running a program the gate suite
executes, in a case whose result is checked against a value written down in the repository. The
numerator is produced by a tracer, not by a scan: the builtin's emitted expression must actually
run. Denominator = 107 declared builtins. Floor **95%** (`.plans/PHASES.md:32`) **plus a ratchet** on
the exact count, both stored as data in `prelude/coverage.lock`.

Execution is recorded on the Python side; agreement is proven by `differential.py`, which runs the
same source on both backends and compares. So *covered* means: the Python lowering ran, the Rust
lowering compiled (Tier A) and ran on the same case, and the result matched a checked-in expected
value. The two halves are separate gates on purpose — a tracer that also had to be a comparator
would be a second implementation of `differential.py`.

Additionally, for every builtin whose signature mentions `N`, Tier B requires an executed case at
`Int64` **and** at `Float64`. That is the rule that would have caught `/`, `mod` and `list-sum`, and
it is recorded per builtin in `coverage.lock` — derived from the checker's own inference (W9b), not
hand-written, because a hand-written field is exactly the second source W6(a) rejects `arg_types`
for.

**In two lines, for the gate's error message:**

> Covered = the builtin's lowering was *evaluated* while the gate suite ran a program, in a case
> whose result is checked against a value in the repository. Being mentioned in `corpus/valid` or in
> the spec's markdown does not count, nor does sitting in a branch no case takes, and every
> `N`-typed builtin must be executed at `Int64` and at `Float64`.

---

## 3. Strategy and sequencing

**Repair, then narrow, then prove mechanically, then generalise the harness, then execute, then
measure execution.**

1. The isolated cleanup (W1, `generate.py` arity) goes first: it touches nothing else, and it fixes
   the agent-facing artifact.
2. The repairs (W2, W3) come before the fixtures. Every one is proven broken by §1.2 and §6 with a
   compiled counter-example — writing a fixture first would only reproduce a known failure. §1.10's
   `agg` probe shows a §5 fixture failing on exactly these repairs and nothing else.
3. W4 narrows the language where no backend can follow it. Doing this before W5 is what lets Tier
   A's floor be 100% rather than "100% minus a skip list".
4. W5 makes Tier A mechanical and permanent. Measured cost: 400 probes, one checker pass, one
   `rustc`, one `py_compile`, ~3.5 s.
5. W6 must land before W8: a fixture with no executed case contributes nothing to Tier B.
6. W8's ten fixtures then execute the 74.
7. W9 lands the tracer and the lock. It lands **last** among the mechanical items because its
   ratchet must be written against the state the phase actually reaches, not against a projection.

**Phase 1 is landed, so "rebase" is now "read the file".** Every work item below names line numbers
verified this session. Two of Phase 1's own follow-ups touch this plan's surface and are *not* owned
here: the `defenum`/`defschema` `Ord`/`Eq` derives (`.plans/ORCHESTRATOR-LOG.md`, "Phase 1 owns the
whole fix"), and imported-call arity. §5 records the eight builtins whose `defenum` instantiations
stay unproven until the derives land.

---

## 4. Work items

Twelve. Each states the files it touches, what changes, what it depends on, and **how it can fail
before the next item starts** — a check that is run and observed, not assumed.

### W1 — `prelude/generate.py`: one arity source, both copies

*Files:* `prelude/generate.py`, `prelude/HANDBOOK.md`, `AGENT_SPEC_CORE.md` (§6 tables, generated).
*Change:* replace the word-count heuristic at **`:30`** (in `signature()`) **and** at **`:162`** (in
`validate_templates()`) with `len(parse_signature(b["type"])[0])`
(`from vocab import parse_signature`; `generate.py` already lives in `prelude/`). Regenerate both
artifacts.
*Depends on:* nothing.
*Fails before W2 if:* `generate.py --check` is non-zero after regeneration; or `git diff` shows any
line moving other than the 34 call-form cells (`string-join` 3→2, `list-empty?` 2→1,
`list-append` 4→2, `map-from-pairs` 4→1, `map-set` 5→3, and the other 29); or `closure_audit.py`
changes its numbers (it must not — call forms in a table are not `lisp` blocks).
*Measure:* `HANDBOOK.md` 12,281 → **12,183** characters; `AGENT_SPEC_CORE.md` −98. Both predicted,
both to be observed.

### W2 — `rt.rs`: the numeric family over the whole of `N`

*Files:* `backend/rust/rt.rs`, `prelude/prelude.json` (`min`, `max` `rs` templates).
*Change:* §6 rows 1-7. A `Num` trait with `ZERO`/`quot`/`rest`/`plus` implemented for `i32`, `i64`,
`f64`; `div`/`rem`/`checked_div`/`checked_rem`/`sum` generic over it; `min`/`max` as `PartialOrd`
helpers in the runtime, with the templates changed to `rt::min({0}, {1})` / `rt::max({0}, {1})`.
*Depends on:* nothing.
*Fails before W3 if:* the §1.2 sweep still reports any `E0308`/`E0277` for
`/ mod checked-div checked-mod list-sum min max`; or the NaN probe does not print
`min(nan,1)=NaN min(1,nan)=1.0 max(nan,1)=NaN max(1,nan)=1.0`; or `rt::sum` of an empty `Vec<f64>`
is not `0.0`; or `generate.py --check` is non-zero (the templates feed the spec tables); or §1.10's
`agg` probe still fails to compile.

### W3 — `rt.rs`: ordering helpers off `Ord`

*Files:* `backend/rust/rt.rs`.
*Change:* §6 rows 8-10. `sort`, `least`, `greatest` bounded by `PartialOrd` instead of `Ord`.
`least`/`greatest` are written as a `reduce` with the *Python* tie/NaN rule, not `iter().min()`.
*Depends on:* nothing (independent of W2, but sequence after it so one sweep rerun covers both).
*Fails before W4 if:* the sweep still reports `E0277` for `list-sort`/`list-min`/`list-max`; or
`rt::least(&[nan, 1.0])` is not `Some(NaN)` (Python's `min([nan,1.0])` is `nan`).

### W4 — `map-key-order`: a `Map` key must be orderable

*Files:* `checker/resolve.py` (new check, coded **`map-key-order`**), `AGENT_SPEC_CORE.md:123`,
`prelude/generate.py` (one line in the `## Types` prose block) + regenerated `prelude/HANDBOOK.md`,
new `grammar/corpus/semantic/map-float-key.agents`.
*Change:* reject any type where `Float64` occurs anywhere inside a `Map`'s **first** argument,
recursively (`(Map Float64 V)`, `(Map (Pair Float64 T) V)`, `(Map (List Float64) V)`). Spec line 123
becomes "`K` must support ordering — `map-keys` is specified to return keys sorted, which `Float64`
cannot provide". The fixture carries `; expect-only: map-key-order`; a probe of exactly that program
reports nothing today (§1.6, checker exit 0), so `expect-only` is safe rather than optimistic.

**Why a name and not `rule-14`.** PCP `d-bad1`: diagnostic codes are rule numbers exactly where §9
has a corresponding checklist item, and descriptive names everywhere else. §9's items 1-13 were read
in full; none covers the domain of a `Map` key (item 6 governs mixing numeric *operands*, not key
types). Minting item 14 is a specification change and is out of scope for a phase about vocabulary
coverage. `map-key-order` therefore joins `type-arity` and `internal` as a named check, and
`ROADMAP.md` §6's `d-bad1` bullet gains it as the second instance (W10).

**The narrowing must reach the model-facing artifact.** `HANDBOOK.md:79` lists `(Map …)` unqualified
and `## Rules that have no exceptions` (`:32`) says nothing about key ordering — a model writes
`(Map Float64 Int64)`, the checker rejects it under a rule the handbook never mentioned, and the
phase has made the language narrower without making the normative artifact narrower. W4 adds one
line to `generate.py`'s Types block (≈ +60 chars ≈ +15 tokens) and regenerates. Net handbook cost of
the phase: −98 + 60 ≈ **−38 characters**.

*Depends on:* nothing.
*Fails before W5 if:* `checker/gate.py` is non-zero; or the new semantic fixture is not rejected
with `map-key-order` **and nothing else**; or any existing `corpus/valid`, `corpus/modules` or
`corpus/semantic` file starts failing; or `generate.py --check` is non-zero.
*Deliberately out of scope, cross-referenced not re-owned:* `defschema` derives `Ord`
unconditionally, so a record with a `Float64` field is an equally illegal Map key and an equally
illegal `list-sort` element. That is the `defenum`/`defschema` derive defect **Phase 1 owns**.
`map-key-order` as written covers the primitive case; extending it through user types belongs with
the derive fix.

### W5 — `backend/monomorphism.py`: the Tier-A gate

*Files:* new `backend/monomorphism.py`, new `backend/t/test_monomorphism.py`.
*Change:* generate the admissible instantiation set from `prelude.json` via `parse_signature` (skip
effectful, variadic and higher-order builtins — recorded, with the reason, in the gate's own output
**and** in `coverage.lock`, so the exclusion is auditable rather than silent). Emit **one** `.agents`
source containing every probe, check it once, transpile it once per backend, and run **one**
`rustc --crate-type=lib` and **one** `py_compile`. Exit code = number of failing probes. On failure,
re-emit the failing probes individually to name the builtin and instantiation.

Write `tier_a: {probes, domains, excluded}` into `coverage.lock` and check it three ways, exactly as
§7 checks `executed`: fewer probes than the lock → regression; more → stale lock; a different domain
or exclusion set → fail. Without this, dropping `Float64` from the `N` domain or adding a builtin to
the exclusion list removes probes *and* removes failures, and the gate reports success.
*Depends on:* W2, W3, W4.
*Fails before W6 if:* the gate is non-zero. Target state: `probes: 400 · checker diags: 0 · rustc
rc=0 errors=0 · py_compile rc=0`, total ~3.5 s. (Today, one probe per process, the same sweep takes
39.7 s — the batched form is the design, not an optimisation added later.)
*Unit tests:* that a deliberately re-monomorphised `rt::sum` makes the gate fail with `list-sum`
named; and that deleting `Float64` from the `N` domain makes the gate fail on `tier_a.domains`
rather than reporting fewer failures. A gate no test can fail is not a gate.

### W6 — `differential.py`: typed inputs, recursive encoding, task discovery, program-mode files

*Files:* `backend/differential.py`, new `backend/rust/harness.rs`, new `backend/cases/` (directory),
`bench/tasks/histogram.json`, new `backend/t/test_differential_encoding.py`.
*Change:* four separable parts. Part (d) is **half landed** — see §0.3.

* **(a) Task discovery and typed inputs.** `main()` currently reads exactly one path (`:125`). It
  loops over `sorted((ROOT/"backend"/"cases").glob("*.json"))` plus `bench/tasks/*.json`. Each task
  gains `"src"`. A case becomes `[[arg, …], expected]`. Argument types come from
  `parse_signature(task["signature"])[0]` — **not** a hand-written `arg_types` field, which would be
  a second source free to drift from the entry's declared type. Admissible input types: `String`,
  `Bool`, `Int32`, `Int64`, `Float64`, `(List X)` of those. Anything else fails loudly at generation
  rather than emitting Rust that will not compile. The single-`String` assumptions at `:39` (Python
  driver) and `:51` (Rust `.to_string()` inputs) both go.
  *`backend/cases/`, not `bench/tasks/`*: `bench/harness/run.py:174,189` globs `bench/tasks/*.json`
  and would pick fixture cases up as measurement tasks (§1.9).
* **(b) Recursive return encoding.** New `backend/rust/harness.rs`, included only by the generated
  driver, never by user output: `pub trait J { fn j(&self) -> String; }` with impls for `i32`,
  `i64`, `f64`, `bool`, `String`, `()`, `Option<T>`, `Result<T, E>`, `(A, B)`, `Vec<T>`,
  `BTreeMap<K, V>` and `rt::IoError`. The driver prints `[c.j(), …]`. This replaces the map-only
  serializer at `:57-61`; a flat `return_shape` enum cannot express `(Option (List T))`,
  `(List (Pair K V))` or `(Result (Option Int64) IoError)`, all of which §5 needs. Encoding is fixed
  to match `backend/runtime.py`: `Some v`→`["some",v]`, `None`→`["none"]`, `Ok v`→`["ok",v]`,
  `Err e`→`["err",e]`, `(a,b)`→`["pair",a,b]`, `Vec`→array, `BTreeMap`→object, `IoError`→its
  `case()` string.
* **(c) Python-side normalisation.** The no-op at `:70` (`raw.replace("{", "{")`) goes.
  `run_python`'s driver maps tuples to lists so `_as.NONE` (`runtime.py`, the tuple `("none",)`)
  encodes as `["none"]` on both sides, and renders non-finite floats as `"nan"`/`"inf"`/`"-inf"` on
  both sides (`json.dumps(float('nan'))` emits bare `NaN`, which is not JSON, and Rust's `{:?}`
  emits `NaN`). Without this the two sides differ on encoding rather than on semantics.
* **(d) Program-mode inputs and exit status.** `programs()` already compares against a declared
  stdout (`:104`, `:110`, `:114`) — Phase 1 landed that half, and fixture `19` inherits it. What is
  missing: the fixture argument is a single `sample.txt` body (`:107`). It becomes
  `files: {name: (content, mode)}` so a case can pre-seed several files and set `0o000` on one, and
  the case gains an **expected exit status** alongside the expected stdout. All three of python,
  rust and expected must agree on both.

*Depends on:* nothing structurally; must land before W8.
*Blast radius, and the only regression guard the refactor has:* one existing function task
(histogram, 7 cases) and 7 existing program cases.
*Fails before W7 if:* the histogram table printed before and after the refactor is not
byte-for-byte identical (capture the current output first, from the actual run, not from this
document); or any of the seven program-mode rows changes its `python`/`rust`/`exit` columns; or
`bench/harness/run.py --tasks` stops finding exactly one task; or `pytest` drops below 79.

### W7 — `check_corpus.py`: compile everything that any gate counts

*Files:* `backend/check_corpus.py`.
*Change:* extend `CORPUS` (`:24`) with `sorted((ROOT/"bench").rglob("*.agents"))`. Both bench
sources already transpile and compile on both backends, so this is a widening with a measured-zero
cost today; its purpose is the invariant — a source the differential gate or the tracer executes
must also be compile-gated.
*Depends on:* nothing.
*Fails before W8 if:* `check_corpus.py` is non-zero; or any `grammar/corpus/valid/*.agents` or
`bench/**/*.agents` is absent from its table. **No row count is asserted** — the count moved twice
already (8 → 18 → 28) and an assertion on it is an assertion on the wrong thing.

### W8 — ten fixtures and their case files

*Files:* `grammar/corpus/valid/19-…` through `28-…` (§5), `backend/cases/*.json`.
*Change:* §5's matrix, in full — programs, entries, literal case inputs, expected outputs. Every
function-mode fixture also carries a `; run:` header so `check_corpus.py` gives it a `run` verdict
rather than a `-`; the header is a second, cheaper oracle and costs one line.
*Depends on:* W2, W3 (so the `Float64` cases pass first time), W6 (so the cases execute at all).
*Fails before W9 if:* `grammar/validate.py`, `checker/gate.py`, `check_corpus.py` or
`differential.py` is non-zero; or any fixture needs an exclusion of any kind (they are single-module
with no qualified names — §1.10 — so an exclusion means something else is wrong); or the tracer's
executed count is below 107.
*Land them one at a time.* Ten fixtures in one commit means ten simultaneous unknowns.

### W9 — `backend/exec_coverage.py`: the executed-coverage tracer, and the lock

*Files:* new `backend/exec_coverage.py`, new `backend/t/test_exec_coverage.py`,
`grammar/closure_audit.py`, new `prelude/coverage.lock`.
*Change:* §7's design — the tracer, the lock file, and the five gate conditions.
*Depends on:* W6, W8.
*Fails before W9b if:* any of the following, tried and observed, does **not** produce a failing
gate: lowering `coverage.lock`'s floor by hand; deleting a builtin from `prelude.json`; adding a
`defun` example to `AGENT_SPEC_CORE.md`; **or adding the verifier's dead-branch fixture** — a
ten-line `corpus/valid` file whose single case takes the `else` arm past sixty builtin calls. The
last is the whole point of the item: under v2's design it moved the figure 21 → 32; under W9's it
must move nothing, and condition 4 must name the fixture.

### W9b — executed instantiations, from the checker rather than by hand

*Files:* `checker/resolve.py` (an emit flag), `backend/exec_coverage.py`, `prelude/coverage.lock`.
*Change:* `coverage.lock`'s `instantiations` field is, in v2, the **sole** enforcement point of §2's
`N`-at-both-types rule — which is the entire Tier-B regression guard for the defect class this phase
exists to close — and it is hand-written. Derive it instead.

The checker already computes the substitution: `checker/types_.py:131` (`from_json(spec, fresh)`)
and `:160-165` (`declared(..., fresh=…)` — "if `fresh` is given they instead become shared
metavariables, which is instantiation"). Add `--emit-instantiations`, which prints one JSON record
per builtin call site: `{path, line, col, builtin, args: [concrete types]}`. This is serialization
of inference that already runs, not new inference.

The tracer keys its recorder by the same triple. `to_python.Transpiler.call` (`:367-383`) reaches
the head as a Lark `Token`, which carries `.line`/`.column`; the tracer monkeypatches that method in
its own process to emit `(_rec(path, line, col) or (<lowered>))`. Intersecting the recorded sites
with the checker's map gives the **executed** instantiations exactly — not the checked ones, which
is the distinction that matters: a builtin may be called at `Float64` on a line no case reaches.
`coverage.lock`'s `instantiations` is then generated with a `--check` mode, the pattern
`prelude/generate.py` already uses. Sites are keyed by `(source path, line, col)` because linked
imports put several files' call sites in one artifact.
*Depends on:* W9.
*Fails before W10 if:* hand-editing `instantiations` to claim `["Int64","Float64"]` for a builtin
executed only at `Int64` does not fail the gate.
*If this is judged out of proportion at implementation time,* the fallback is **not** to leave the
field as it is: it is to delete `instantiations` from the lock and demote §2's `N` rule to "enforced
by review" in the gate's own error message, so the lock stops implying enforcement it does not have.

### W10 — `ROADMAP.md` §2 and §6

*Files:* `ROADMAP.md`.
*Change:* Phase 1's session already corrected these to current truth, so this item **retires**
statements rather than fixing overclaims. §2's Rust-backend row reads *working for `Int64`* with
"Phase 2 owns the repair" — replace it with what W2/W3/W5 make true (generic over `N` and over
`PartialOrd` element types, every admissible instantiation compile-gated, `defenum`-typed elements
still owed by Phase 1). §6's "The Rust backend is numerically `Int64`-only" bullet is deleted. §6's
coverage bullet ("reported as 35%, and the number that means anything is 19%") is rewritten against
the new metric and the new figure. §6's `d-bad1` bullet gains `map-key-order` as the second named
check. Note that Phase 3's Wasm route goes through this backend and inherited the gap.
*Depends on:* W2, W3, W5, W9.
*Fails before W11 if:* any row or bullet claims coverage the Tier-A gate or the tracer does not
report.

### W11 — PCP entries

*Files:* the PCP store (§10).
*Depends on:* W1-W10 green.

---

## 5. Fixture matrix

Ten fixtures under `grammar/corpus/valid/`, numbering on from `18-pattern-binders.agents`. Together
they execute the **74** builtins §1.3 leaves: 11 + 5 + 6 + 7 + 13 + 8 + 8 + 4 + 7 + 5 = 74, and
33 + 74 = **107/107**, five clear of the 102 floor. Counts below are *newly executed* builtins; each
fixture re-exercises more, which is stated rather than counted twice.

Every case gives the literal input and the wrong implementation it rules out. Where a case earns its
place only as coverage, that is said rather than dressed up as discrimination.

### `19-io-errors.agents` — program mode — 11 new
`print`, `read-all`, `read-line`, `file-append`, `file-exists?`, `not-found`,
`permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`

Program: `argv[1]` is a path. With `--labels`, print `(label (not-found))…(label (other))` joined by
`,` — the §1.8 construction, which executes all six constructors on both backends. Otherwise:
`file-exists?` the path; if present, `read-line` from stdin and `file-append` it, then `file-read`
the path and `print` the whole content; on any failure, `label` the `IoError` and `print` it.

| # | argv / files / stdin | expected stdout, exit | discriminates |
|---|---|---|---|
| 1 | `["log.txt"]`, `log.txt`=`"A\n"` mode 644, stdin `"B"` | `"A\nB\n"`, 0 | `file-append(path, text)` **argument swap** — swapped writes a file named `B` and prints `A\n`. Also append-vs-overwrite: overwrite prints `B\n`. The read-back is what makes it visible. |
| 2 | `["absent.txt"]`, no files | `"absent\n"`, 0 | `file-exists?` inverted — the only case where it is false. Case 1 is the true side. |
| 3 | `["nodir/out.txt"]` | `"not-found\n"`, 1 | the host's errno→case mapping for a missing parent |
| 4 | `["noperm.txt"]`, `noperm.txt`=`""` mode `0o000` | `"permission-denied\n"`, 1 | the `permission-denied` arm. Needs W6(d)'s per-case file mode — the one case that cannot be written until W6 lands. |
| 5 | `["log.txt"]`, `log.txt`=`"A\n"`, stdin empty | `"A\n"`, 0 | `read-line`'s `none`-at-EOF branch; distinguishes it from an empty-string result, which would append a bare newline |
| 6 | `["--labels"]` | `"not-found,permission-denied,already-exists,invalid-path,interrupted,other\n"`, 0 | all six constructors, and their **spelling**: an `interrupted` that returned `Other` fails here. Measured identical on both backends (§1.8). |
| 7 | `["--slurp"]`, stdin `"x\ny\n"` | `"x\ny\n"`, 0 | `read-all` vs `read-line` — case 5 reads one line, this reads both |

`already-exists` and `invalid-path` are executed **as constructors** by case 6. Their host mappings
(`EEXIST`, `ENOTDIR`) are not reached by any portable case; `interrupted` (`EINTR`) and `other` are
not reachable at all from a deterministic test. **Recorded as such in `coverage.lock`** — the
constructor is covered, the mapping is not, and the lock distinguishes the two rather than letting
the count imply more than was proven.

### `20-option-result-ctors.agents` — function mode — 5 new
`is-some?`, `is-none?`, `is-ok?`, `is-err?`, `pair` (re-exercises `some`, `none`, `ok`, `err`, all
four of which already execute — §1.3)

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

### `21-option-result-combinators.agents` — function mode — 6 new
`option-map`, `option-to-result`, `result-map`, `result-map-err`, `result-or`, `result-to-option`
(re-exercises `option-or`)

`(defun resolve [(raw String) (fallback Int64)] -> String)`.
`string-to-int64 raw` → `option-map` doubles → `option-to-result` with error text `(str "bad:" raw)`
→ `result-map` adds 1 → `result-map-err` wraps as `E<…>`. Output is three `|`-joined fields:
`(match r ((ok v) (str "ok:" v)) ((err e) (str "err:" e)))`, then
`(result-or (result-map string-from-int64 r) "FB")`, then `(option-or (result-to-option r) -1)`
rendered.

| case | expected | discriminates |
|---|---|---|
| `["21", 0]` | `"ok:43\|43\|43"` | `option-map` then `result-map` **order**: double-then-increment is 43, increment-then-double is 44 |
| `["x", 5]` | `"err:E<bad:x>\|FB\|-1"` | **`result-map-err` replaced by the identity, or by `result-map`** — both give `err:bad:x`. Routing the failure through `result-to-option` instead discards the error entirely, which is how v1's fixture made all three implementations byte-identical. Also `result-or`'s fallback arm and `result-to-option`'s `none` arm. |
| `["", 9]` | `"err:E<bad:>\|FB\|-1"` | empty input still reaches the error path; `(str "bad:" "")` is not `"bad"` |

`result-or`'s arguments are `(Result T E) T` — a swap does not type-check, so it is caught by
`rustc`, not by a case. Stated as coverage, not claimed as discrimination.

### `22-boolean-algebra.agents` — function mode — 7 new
`!=`, `<`, `<=`, `>`, `>=`, `and`, `or` (re-exercises `not`, `=`)

`(defun band [(lo Int64) (x Int64) (hi Int64)] -> String)` returning eight `T`/`F` characters:
`(<= lo x)`, `(>= hi x)`, `(< lo x)`, `(> hi x)`, `(!= x lo)`, `(and (!= x lo) (>= hi x))`,
`(or (= x lo) (> x hi))`, `(not (and (<= lo x) (>= hi x)))`. Compiled clean on both backends this
session (§1.10).

All cases use `lo=3`, `hi=7`.

| case | expected | discriminates |
|---|---|---|
| `[3,3,7]` | `TTFFF` `F` `T` `F` | **`<=` implemented as `<`** — column 1 is the only place they differ, and only at `x == lo` |
| `[3,7,7]` | `TTTFT` `T` `T` `F` | **`>=` implemented as `>`** — column 2, only at `x == hi` |
| `[3,2,7]` | `FTFFT` `T` `F` `T` | below the range; `!=` true |
| `[3,8,7]` | `TFTFT` `F` `T` `T` | above the range; `>` true |
| `[3,5,7]` | `TTTFT` `T` `F` `F` | interior |

`and`/`or` swap: column 6's operands take `TT` (case 3), `FT` (case 1), `TF` (case 4); column 7's
take `FF` (case 5). All four combinations occur, so `and`↔`or` changes at least one column in at
least one case.

### `23-numeric.agents` — function mode, two entries — 13 new
`-`, `/`, `mod`, `abs`, `neg`, `checked-div`, `checked-mod`, `min`, `max`, `int32-to-int64`,
`int64-to-int32`, `int64-to-float64`, `float64-to-int64` (re-exercises `*`)

**This is the B2 fixture.** Every `N`-typed builtin runs at `Int64` **and** at `Float64` in the same
case, and at `Int32` where the value permits.

Entry 1 `(defun num [(a Int64) (b Int64)] -> String)` — when `b = 0`, report only the two checked
operations; otherwise report, `|`-joined: the `Int64` leg (`/`, `mod`, `*`, `-`, `abs`, `neg`,
`min`, `max`), the `Float64` leg (the same eight on `(int64-to-float64 a)` / `…b`, rendered with
`string-from-float64`), and the `Int32` leg (`(int64-to-int32 a)`, `option-map`ped through
`int32-to-int64` and back to a string).

| case | expected (abridged — the exact string is fixed at implementation) | discriminates |
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

### `24-list-reshaping.agents` — function mode, three entries — 8 new
`list-append`, `list-reverse`, `list-slice`, `list-tail`, `list-head`, `list-get`, `range`, `zip`
(re-exercises `list`, `list-cons`)

Entry 1 `(defun reshape [(n Int64)] -> String)` — `xs = (range 0 n)`, `ys = (list 100 200 300)`;
reports `list-cons 9 xs`, `list-append xs ys`, `list-reverse xs`, `list-tail xs`, `list-head xs`,
`list-get xs 1`.

| case | expected | discriminates |
|---|---|---|
| `[4]` | cons `[9,0,1,2,3]`; append `[0,1,2,3,100,200,300]`; reverse `[3,2,1,0]`; tail `some [1,2,3]`; head `some 0`; get `some 1` | **`list-append` operand swap** (the `100,200,300` block moves); reverse is not the identity (≥3 distinct, ascending input); `list-get` at index 1 — neither `0` nor `length-1`, so an off-by-one is visible |
| `[1]` | cons `[9,0]`; tail `some []`; head `some 0`; get `none` | `list-tail` of a one-element list is `some []`, not `none`; `list-get 1` is out of range |
| `[0]` | cons `[9]`; tail `none`; head `none`; get `none` | the empty-list arm of `list-tail`/`list-head`; `range 0 0` is `[]` |

Entry 2 `(defun window [(n Int64) (a Int64) (b Int64)] -> (Option (List Int64)))` —
`(list-slice (range 0 n) a b)`. This is the **composed return shape** (`(Option (List T))`) that
W6(b)'s recursive encoder exists for; a flat shape tag cannot express it.

| case | expected | discriminates |
|---|---|---|
| `[4,1,3]` | `["some",[1,2]]` | half-open `[a,b)`; an inclusive slice gives `[1,2,3]`; an `a`/`b` swap gives `none` |
| `[4,0,4]` | `["some",[0,1,2,3]]` | `b == n` is in range |
| `[4,0,5]` | `["none"]` | `b > n` is out — off-by-one in `rt::list_slice`'s `b > n` |
| `[4,3,1]` | `["none"]` | `b < a` is out |
| `[4,2,2]` | `["some",[]]` | the empty slice is `some []`, not `none` |

Entry 3 `(defun pairs [(n Int64)] -> (List (Pair Int64 String)))` —
`(zip (range 0 n) (list "a" "b" "c"))`. `(List (Pair A B))` is the second composed shape.

| case | expected | discriminates |
|---|---|---|
| `[2]` | `[["pair",0,"a"],["pair",1,"b"]]` | `zip` truncating to the **shorter** list, and pair component order |
| `[5]` | `[["pair",0,"a"],["pair",1,"b"],["pair",2,"c"]]` | truncation from the other side |

A `zip` that swapped its components would not type-check (`Int64` vs `String`) — coverage, not
discrimination, and said so.

### `25-list-aggregation.agents` — function mode, three entries — 8 new
`list-empty?`, `list-length`, `list-contains?`, `list-index-of`, `list-sum`, `list-min`,
`list-sort`, `list-sort-by` (re-exercises `list-max`, `map`, `option-or`, `string-split`)

Entry 1 `(defun agg [(csv String)] -> String)` over **`(List Float64)`** — split on `,`, parse each
with `string-to-float64`, `option-or` to `0.0`; reports `list-empty?`, `list-length`, `list-sum`,
`list-min`, `list-max`, `list-sort`. This body was compiled this session: checker clean, both
backends transpile, `rustc` gives 2 × `E0308` on the `list-sum` `Float64` leg and nothing else
(§1.10) — the fixture is blocked on W2 and on nothing else.

| case | expected | discriminates |
|---|---|---|
| `["3,1,3,2"]` | `F\|4\|9.0\|1.0\|3.0\|[1.0,2.0,3.0,3.0]` | **`list-sort` as the identity** — the input is unsorted and carries a duplicate; **`list-min`/`list-max` swapped** — 1 ≠ 3 with ≥3 distinct values. And this is the `Float64` instantiation of `list-sort`/`list-min`/`list-max`, which is `E0277` today (§1.2). |
| `["0.1,0.2"]` | sum `0.30000000000000004` | float addition is not decimal addition — pins Python and Rust to the same double |
| `[""]` | `F\|1\|0.0\|0.0\|0.0\|[0.0]` | `(string-split "" ",")` yields `[""]` on both backends, so this is a **one-element** list, not the empty one. Recorded because it is the case a reader assumes is the empty-list case; the genuine one is entry 1b. |
| `["-2,-9,4"]` | `F\|3\|-7.0\|-9.0\|4.0\|[-9.0,-2.0,4.0]` | **negative values** — a sort keyed on magnitude gives `[-2,4,-9]`; `list-sum` of mixed signs |
| `["5"]` | `F\|1\|5.0\|5.0\|5.0\|[5.0]` | single element: `list-min == list-max`, which is exactly why it cannot be the only case |

Entry 1b `(defun agg-empty [] -> String)` — the same report over `(list)` typed `(List Float64)`:
expected `T|0|0.0|none|none|[]`. This is `list-empty?`'s true side and the empty-sum identity from
§1.5. It is a separate entry because `string-split` cannot produce an empty list.

Entry 2 `(defun lookup [(csv String) (needle Int64)] -> String)` over **`(List Int64)`** — reports
`list-contains?`, `list-index-of`, `list-length`, `list-sum`, `list-sort-by` with `(fn [x] (neg x))`.

| case | expected | discriminates |
|---|---|---|
| `["3,1,3,2", 2]` | `T\|some 3\|4\|9\|[3,3,2,1]` | `list-index-of` returning index **3** — neither `0` nor `length-1`, so an off-by-one or a "return the first index of anything" is visible; `list-sort-by (neg)` is descending, so a `list-sort-by` that ignored its projection gives ascending. This is the builtin that shipped with reversed arguments. |
| `["3,1,3,2", 3]` | `T\|some 0\|4\|9\|[3,3,2,1]` | first-occurrence semantics: `3` appears at 0 and 2; `some 2` would be last-occurrence |
| `["3,1,3,2", 9]` | `F\|none\|4\|9\|[3,3,2,1]` | the absent side of `list-contains?`/`list-index-of` — a constant-`true` `list-contains?` passes the other two cases |

`list-sum` therefore runs at `Float64` (entry 1) and `Int64` (entry 2), satisfying §2's `N` rule.

### `26-map-lifecycle.agents` — function mode, two entries — 4 new
`map-has?`, `map-keys`, `map-remove`, `map-size` (re-exercises `map-empty`, `map-set`, `map-get`,
`map-from-pairs`, `map-pairs`, `map-values`)

Entry 1 `(defun lifecycle [(words String) (drop String)] -> String)` — build `(Map String Int64)`
counts by folding `map-set`/`map-get` over `(string-split words " ")`; report `map-size` before,
`map-has? drop`, then `map-size` after `map-remove drop`, then `(string-join (map-keys m2) ",")`.

| case | expected | discriminates |
|---|---|---|
| `["a b a c", "a"]` | `3\|T\|2\|b,c` | removing a key that **is** present: size drops. A no-op `map-remove` is indistinguishable without the before-and-after size. |
| `["a b a c", "z"]` | `3\|F\|3\|a,b,c` | removing an absent key is a no-op — printing size before *and* after is what separates the two; and `map-has?`'s false side, without which a constant-`true` passes |
| `["", "a"]` | `0\|F\|0\|` | the empty map; `map-keys` of it is `[]`, joined to `""` |
| `["c b a", "b"]` | `3\|T\|2\|a,c` | `map-keys` is **sorted**, not insertion-ordered — the spec says sorted (`AGENT_SPEC_CORE.md:576`) and the two backends reach it differently (Python `sorted(...)`, Rust `BTreeMap`) |

Entry 2 `(defun counts [(words String)] -> (Map String Int64))` — returns the map itself, the same
shape the histogram task returns, keeping W6(b)'s encoder honest against the one case that existed
before the refactor.

`map-keys` vs `map-values` are type-distinct here (`String` vs `Int64`), so a swap fails to compile.
**Coverage, not discrimination** — stated, not claimed.

### `27-string-query.agents` — function mode, two entries — 7 new
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

Entry 2 `(defun cut [(hay String) (a Int64) (b Int64)] -> (Option String))` —
`(string-slice hay a b)`, the third composed return shape.

| case | expected | discriminates |
|---|---|---|
| `["banana",1,3]` | `["some","an"]` | half-open `[a,b)`; inclusive gives `"ana"` |
| `["banana",0,6]` | `["some","banana"]` | `b == length` is in range |
| `["banana",0,7]` | `["none"]` | `b > length` — off-by-one in `rt::str_slice`'s `b > n` |
| `["banana",3,1]` | `["none"]` | `b < a` |
| `["héllo",1,3]` | `["some","él"]` | char slicing, not byte slicing — byte slicing panics or yields mojibake |

### `28-string-transforms.agents` — function mode — 5 new
`string-lower`, `string-replace`, `string-reverse`, `string-to-int64`, `string-to-float64`
(re-exercises `str`, `string-join`, `string-upper`, `string-from-int64`, `string-from-float64`,
`string-split`, `option-or`)

`(defun transform [(line String)] -> String)` — `|`-joined: `string-lower`, `string-upper`,
`string-reverse`, `(string-replace line "X" "-")`, `(string-join (string-split line " ") "+")`,
`(str "n=" (string-from-int64 (string-length line)))`, `(string-to-int64 line)` rendered, and
`(string-from-float64 (option-or (string-to-float64 line) 0.0))`.

| case | expected | discriminates |
|---|---|---|
| `["aXbXc"]` | replace → `a-b-c` | **`from`/`to` swapped** leaves `aXbXc` unchanged; **replace-first instead of replace-all** gives `a-bXc` |
| `["Hello World"]` | lower `hello world`; upper `HELLO WORLD`; reverse `dlroW olleH`; join `Hello+World` | `string-lower` as the identity (the input has an uppercase run); `string-upper` and `string-lower` swapped; `string-reverse` as the identity (non-palindromic); `string-join`'s separator argument |
| `["abc"]` | reverse `cba`; `n=3` | reverse on a short non-palindrome |
| `["42"]` | `some 42`; float round-trip `42.0` | `string-to-int64`'s success side; `string-from-float64` renders a whole float as `42.0` on both backends (Python `repr`, Rust `{:?}`), not `42` |
| `["2.5"]` | int `none`; float `2.5` | `string-to-int64` must **not** accept a float; `string-to-float64`'s success side |
| `["0.1"]` | float `0.1` | shortest round-trip rendering agrees — Python `repr(0.1)` and Rust `{:?}` both give `0.1`, not `0.1000000000000000055…` |
| `["x"]` | int `none`; float `0.0` (the `option-or` fallback) | both parsers' failure side |
| `[""]` | `n=0`; join `` | the empty line |

### The eight `defenum` builtins, still owed by Phase 1

Phase 1 owns the `defenum`/`defschema` `Ord`/`Eq` derives (`.plans/ORCHESTRATOR-LOG.md`). Phase 2
schedules none of that work. But §2's rule forbids calling `list-sort`, `list-min`, `list-max`,
`map-has?`, `map-remove`, `map-keys`, `map-pairs`, `map-from-pairs` *covered* on the strength of
`Int64`/`String` instantiations alone — that is the same error as B2. They are recorded in
`coverage.lock` as covered at their **primitive** instantiations only, with `defenum` listed as an
outstanding instantiation owned by Phase 1. When that lands, W5's generator gains a
`defenum`/`defschema` arm (a two-case enum and a two-field record join the `T`/`K` domain), Tier A's
denominator grows and the new number goes into `coverage.lock` in the same commit, and fixtures
`25`/`26` gain an enum-sorted list and an enum-keyed map. Until then the lock says *not proven*, not
*covered*.

---

## 6. Repair list

Ten builtins, all **re-probed this session against the landed tree** and all still broken. Each row
carries the verbatim first `rustc` error from its own single-builtin probe; the checker exited 0 on
every one, so none of these is caught before `rustc`.

| # | builtin(s) | target | still-broken evidence | before → after |
|---|---|---|---|---|
| 1 | — | `backend/rust/rt.rs` (new) | — | **after:** a `Num` trait — `pub trait Num: Copy + PartialEq { const ZERO: Self; fn quot(self, b: Self) -> Self; fn rest(self, b: Self) -> Self; fn plus(self, b: Self) -> Self; }` with impls for `i32`, `i64`, `f64`. `quot` on the integers keeps the existing overflow guard (`self.checked_div(b).expect("overflow in division")`); on `f64` it is `self / b`. `rest` is `%` on all three (Rust's `%` and Python's `mod` both take the dividend's sign). |
| 2 | `/` | `rt.rs:10` — `pub fn div(a: i64, b: i64) -> i64` | `Int32`: ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``. `Float64`: same error, ``expected `i64`, found `f64` `` | `pub fn div<T: Num>(a: T, b: T) -> T { if b == T::ZERO { panic!("division by zero") } a.quot(b) }` — `b == 0.0` traps too, matching `runtime.py`, which raises `Trap` for any `b == 0` |
| 3 | `mod` | `rt.rs:14` — `pub fn rem(a: i64, b: i64) -> i64` | `Int32`: ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``. `Float64`: ``expected `i64`, found `f64` `` | `pub fn rem<T: Num>(a: T, b: T) -> T { if b == T::ZERO { panic!("modulo by zero") } a.rest(b) }` |
| 4 | `checked-div` | `rt.rs:18` | `Int32`: ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``. `Float64`: ``expected `i64`, found `f64` `` | `pub fn checked_div<T: Num>(a: T, b: T) -> Option<T> { if b == T::ZERO { None } else { Some(a.quot(b)) } }` |
| 5 | `checked-mod` | `rt.rs:19` | `Int32`: ``error[E0308]: arguments to this function are incorrect`` / ``expected `i64`, found `i32` ``. `Float64`: ``expected `i64`, found `f64` `` | `pub fn checked_rem<T: Num>(a: T, b: T) -> Option<T> { if b == T::ZERO { None } else { Some(a.rest(b)) } }` |
| 6 | `list-sum` | `rt.rs:82` — `pub fn sum(xs: Vec<i64>) -> i64` | `Int32`: ``error[E0308]: mismatched types`` / ``expected `Vec<i64>`, found `Vec<i32>` ``. `Float64`: ``expected `Vec<i64>`, found `Vec<f64>` `` | `pub fn sum<T: Num>(xs: Vec<T>) -> T { xs.into_iter().fold(T::ZERO, Num::plus) }`. **Not** `T: std::iter::Sum<T>`, which compiles but folds `f64` from `-0.0` (§1.5). Measured with the fold: empty `Vec<f64>` → `0.0`; `[0.1, 0.2]` → `0.30000000000000004`, identical to Python. |
| 7 | `min`, `max` | `prelude.json` templates **and** `rt.rs` | `min` at `Float64`: ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `std::cmp::min` ``. `max`: the same, ``in `std::cmp::max` `` | **templates:** `"rs": "std::cmp::min({0}, {1})"` → `"rs": "rt::min({0}, {1})"`, likewise `max`. **rt.rs:** `pub fn min<T: PartialOrd>(a: T, b: T) -> T { if b < a { b } else { a } }` and `pub fn max<T: PartialOrd>(a: T, b: T) -> T { if b > a { b } else { a } }`. Each argument is evaluated **once**; no literal braces to double; the `b`-relative comparison reproduces Python exactly (§1.4). |
| 8 | `list-sort` | `rt.rs:66` — `sort<T: Ord>` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `sort` `` | `pub fn sort<T: PartialOrd>(mut xs: Vec<T>) -> Vec<T> { xs.sort_by(\|a, b\| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)); xs }` — measured `[3.0,1.0,2.0]` → `[1.0,2.0,3.0]` |
| 9 | `list-min` | `rt.rs:83` — `least<T: Ord + Clone>` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `least` `` | `pub fn least<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> { xs.iter().cloned().reduce(\|a, b\| if b < a { b } else { a }) }` — the reduce is Python's rule, not `iter().min()`'s. Measured `least(&[nan, 1.0]) = Some(NaN)`, matching Python's `min([nan, 1.0]) = nan`. |
| 10 | `list-max` | `rt.rs:84` — `greatest<T: Ord + Clone>` | ``error[E0277]: the trait bound `f64: Ord` is not satisfied`` / ``note: required by a bound in `greatest` `` | `pub fn greatest<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> { xs.iter().cloned().reduce(\|a, b\| if b > a { b } else { a }) }` |

**Not repaired — narrowed instead (W4).** `map-get`, `map-set`, `map-has?`, `map-remove`,
`map-pairs`, `map-from-pairs` at a `Float64` key: 24 probes, all
``error[E0277]: the trait bound `f64: Ord` is not satisfied`` (``required by a bound in `m_get` ``
and its siblings). `BTreeMap` needs `Ord`; `f64` has no total order; and the spec itself asks for
sorted keys (§1.6). Repairing this would mean replacing the Map representation for every program to
support a key type the specification never intended — rejected. `map-key-order` removes `K=Float64`
across **all ten** `Map` builtins — **40** instantiations, of which 24 fail today — which is why
Tier A's denominator is 440 − 40 = **400** and its floor is 100%.

**Expected state after rows 1-10.** The §1.2 sweep, restricted to the post-narrowing admissible set,
must read `probes: 400 · checker diags: 0 · rustc rc=0 errors=0 · py_compile rc=0`, and the full
gate suite must return to §1.1's state with the new fixtures added. v2 measured that in a throwaway
copy of the repo against a 47-test tree; the number to hit now is 79 tests plus W5's, W6's and W9's,
and it is to be measured at the time rather than quoted from here.

**Decision recorded — NaN and ties.** `min`/`max` follow Python: return the **first** argument unless
the second compares strictly past it. This differs from JavaScript, whose `Math.min` propagates NaN
from either position; `prelude.json`'s `js` templates are therefore known-wrong for NaN today. They
are **not** changed in this phase: there is no JS runtime (`backend/` has `rust/` and `golang/`, no
`js/`) and no gate could check the change, so editing them would create an unverifiable claim.
Recorded as a decision for Phase 4 (§10).
`list-sort` with a NaN present is **unspecified** — Python's `sorted` is not a total order either
(`sorted([3.0, nan, 1.0])` → `[3.0, nan, 1.0]`), and no fixture asserts it.
Rounding a half is untouched by this phase and stays an open portability question (§9).

---

## 7. Coverage gate design

`grammar/closure_audit.py` keeps its existing job — undefined call heads, over `corpus/valid`
**plus** the `AGENT_SPEC_CORE.md` fragments, because closure is exactly a claim about the document.
Its `exercised builtins` line (`:79-80`) is **deleted**: it is the number §1.3 shows to be wrong in
both directions, and leaving it beside a correct one invites the wrong one to be quoted. The audit
gains, in its place, a number it imports rather than computes.

### 7.1 `backend/exec_coverage.py` — the tracer

**Where it lives.** `backend/`, because it needs `to_python`'s search-root handling and the executed
source set. `closure_audit.py` imports `exec_coverage.executed()` and prints it; it does not
reimplement it. One source of truth.

**What it runs.** `exec_coverage.programs()` returns the union of everything the gate suite already
executes:

* every `grammar/corpus/valid/*.agents` carrying a `; run:` header, run with that expression
  asserted — the same header `check_corpus.py` reads, parsed by the same helper;
* every program-mode case in `differential.py` (`differential.program_cases()`, a new accessor);
* every function-mode task under `backend/cases/` and `bench/tasks/`
  (`differential.function_tasks()`), run over all of that task's cases.

Nothing else. A file outside that union contributes nothing, and condition 4 makes its absence
explicit rather than silent.

**What it counts.** Before transpiling, every entry of `to_python.LOWER` is rewritten in-process as
`(_rec.hit('<name>') or (<template>))`. `hit` returns `None`, so `or` always yields the original
expression; the placeholders (`{0}`, `{*}`, doubled literal braces) are untouched because the
rewrite happens on the template, before `.format`. The recorder therefore fires **exactly when that
expression is evaluated** — not when it is emitted, not when it is parsed. Hits are appended to a
file named by an environment variable and read back after every program has run. A builtin is
*executed* iff it appears in that file.

This is monkeypatching in the tracer's own process only. The differential gate, `check_corpus.py`
and every other consumer transpile unwrapped code; the tracer's job is reachability, the differential
gate's is agreement, and neither runs the other's artifact.

**How it fails.** Exit code = number of failed conditions (§7.3). On failure it prints, per
condition, the shortfall: which builtins the lock claims and the run did not reach, which fixtures
contributed nothing, which lock field is stale.

**Cost per gate run.** Measured this session with exactly this mechanism over the current tree:
**1.354 s wall for 18 programs** (`real 0m1.354s`, 33 builtins recorded), ~75 ms per program
including transpile and subprocess. §5 adds ten fixtures — nine function entries, whose cases batch
into one process each, plus one program-mode fixture with seven runs. Projected **≤ 3.5 s**. The
budget is stated so a future slowdown is a visible regression rather than an accepted cost.

**What it does not prove, stated rather than implied.** Execution is recorded on the Python side
only. A builtin whose Python lowering ran has its Rust lowering compile-gated by Tier A and executed
by `differential.py` on the same source and the same case, with the two results compared — but the
tracer itself sees one backend. A Rust-only lowering with no Python counterpart would be invisible
to it; no such builtin exists, and W5's exclusion list would show one if it appeared.

### 7.2 `prelude/coverage.lock`

Checked in, JSON, the gate's data:

```json
{ "floor_pct": 95,
  "executed": 107,
  "tier_a": { "probes": 400,
              "domains": { "N": ["Int32", "Int64", "Float64"],
                           "*": ["Int64", "Float64", "String", "Bool"] },
              "excluded": { "effect": ["…9…"], "variadic": ["…2…"],
                            "higher-order": ["…7…"], "monomorphic": ["…33…"] } },
  "instantiations": { "list-sum": ["Int64", "Float64"], "…": ["…"] },
  "unproven": { "list-sort": ["defenum — Phase 1"], "…": ["…"] },
  "unexecuted": { } }
```

`tier_a` exists because without it, dropping `Float64` from the `N` domain or adding a builtin to
the exclusion list removes probes *and* removes failures, and W5's exit code — the failure count —
goes down. `instantiations` is generated by W9b, not hand-written.

### 7.3 The gate fails on any of five conditions

1. `pct < floor_pct` — the floor. 102/107 is 95%; 101 is 94% (integer floor division).
2. `executed_count < lock["executed"]` — the **ratchet**. A hard floor alone permits a silent slide
   from 107 back to 102. The lock is updated deliberately, in the same commit that earns it.
3. `executed_count > lock["executed"]` — the lock is stale. Forces the number to be recorded, not
   drifted into.
4. any `grammar/corpus/valid/*.agents` that no program in `exec_coverage.programs()` runs, and that
   is not on an explicit `unexecuted` list carrying a reason — and the reason must name a
   `coverage.lock` key, so the two lists cannot silently disagree. This is what stops fixtures
   landing with no case files.
5. `tier_a` disagrees with what `monomorphism.py` reports — fewer probes than the lock, more probes
   than the lock, or a different domain or exclusion set.

Exit code becomes `len(undefined) + coverage_failures`, preserving the existing signal (each
undefined head still counts one) while adding the new one. No consumer parses this: the repo has no
`.github/` and no CI config (§1.9).

### 7.4 Why each attack fails

| attack | outcome |
|---|---|
| add a `defun` example to `AGENT_SPEC_CORE.md` | the numerator is what ran; spec fragments run nothing. **No effect.** |
| **a fixture whose builtins sit in a branch no case takes** | the recorder never fires for them. This is the fake that moved v2's figure 21 → 32; under W9 it moves nothing, and condition 4 additionally names the fixture if no case runs it at all. W9's acceptance requires this to be tried and observed. |
| delete an unexercised builtin from `prelude.json` | the denominator drops **and** Tier A's probe count drops, so conditions 3 and 5 both fire. |
| widen a scan root | there is no scan for the numerator. |
| land fixtures, drop the case files | condition 4 fails, naming each unexecuted fixture. |
| lower the `95` | it is data in `coverage.lock`, and lowering it does not clear the ratchet (condition 2), which is computed against `executed`, not against the floor. |
| shrink Tier A's domain or grow its exclusion list | condition 5 fails on `tier_a`. |
| exercise a generic builtin at one type and call it done | Tier A compiles **every** admissible instantiation; `instantiations` records which ones **executed**, derived from the checker (W9b), and the `N` rule requires two. |
| park a fixture on the `unexecuted` list with an invented reason | it cannot *raise* the count, so the impact is bounded; the reason must name a `coverage.lock` key, which makes an invented one visible. |
| **regenerate a case's `expected` from the harness's own output** | **not caught, and it cannot be** — see §9 risk 9. Both backends are generated from the same `prelude.json` declaration, so a wrong declaration agrees with itself. Mitigations are procedural: no `--regen` path in the harness; each case carries §5's "rules out" note as a field, so a regenerated value is visibly unaccompanied by a claim; Phase 6's reference interpreter is the only real third oracle. |

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

`closure_audit.py` reports the tracer's figure (§7.1); running `backend/exec_coverage.py` directly
is the same computation with per-fixture detail. `check_corpus.py`, `monomorphism.py` and
`differential.py` invoke `rustup run stable rustc` internally; no bare `cargo` is reached, so
`AGENTS.md`'s broken-shim note does not bite.

| command | expected | what it would **not** catch |
|---|---|---|
| `grammar/validate.py` | 0 failures; 28 valid fixtures, 35 semantic | anything semantic. A fixture that parses and means the wrong thing passes. |
| `closure_audit.py` | `OK: spec and corpus are closed`; `executed builtins : 107/107 (100%)`; lock in sync on all five conditions | a case whose input does not discriminate. §5 is the mitigation and it is a design artefact, not an enforced one. |
| `generate.py --check` | 0 | a template that is well-formed and wrong. `validate_templates` formats with dummy args and catches raised exceptions only; a single un-doubled brace with spare dummy args is consumed silently. Exhaustively scanned: `map-empty`'s `py` `"{{}}"` is the only literal-brace template in the vocabulary, and it is correctly doubled. |
| `checker/gate.py` | 0 failures; every semantic fixture rejected **for its declared rule**, `map-float-key.agents` reporting `map-key-order` and nothing else | a rule the checker does not have. `map-key-order` exists only because W4 writes it. |
| `check_corpus.py` | 0 failures; every `corpus/valid` and every `bench/**` source present, `ok` in `python`, `compile`, `rust`, `rustc`, and `ok` rather than `-` in `run` for every fixture carrying a `; run:` header | anything about **behaviour** beyond the one `; run:` expression. |
| `monomorphism.py` | `400 probes, 0 failures`, `tier_a` matching the lock | behaviour — it proves every instantiation *compiles*, not that it *computes*. It cannot see higher-order, variadic or effectful builtins, which it excludes, prints **and records in the lock**. |
| `differential.py` | 0 disagreements; the histogram table byte-identical to the pre-W6 capture; 7 + N function cases, 7 + 7 program cases | a defect the two backends share. Both are generated from the same `prelude.json`, which is why every case in §5 carries a checked-in **expected** value and why W6(d) completes the program-mode oracle. |
| `pytest` | ≥ 79 plus W5's, W6's and W9's new tests | whatever no test covers. |

**Not proven by any of the eight, and stated rather than implied:** rounding a half; `Int32`
overflow semantics; `already-exists`/`invalid-path`/`interrupted`/`other` **host mappings** (their
constructors are covered, §5 `19` case 6); every `defenum`-typed instantiation of the eight builtins
§5 lists as Phase 1's; the JS templates, which have no runtime to run; and an `expected` value
regenerated from the harness's own output (§9 risk 9).

---

## 9. Risks and unknowns

1. **W6 is the largest single change and has one regression guard.** Rewriting `run_rust`,
   `run_python`'s driver, `programs()` and `main()` leaves one pre-existing function task and seven
   program cases to detect a mistake. Mitigation: capture the current output first **from the actual
   run**, land W6 in the four separable parts, and diff after each.
2. **`map-key-order` is a language narrowing.** It makes a program that type-checks today stop
   type-checking. No corpus, bench or module fixture uses a `Float64` map key (all 440 probes were
   synthetic), so the measured blast radius is zero — but it is a semantic change and belongs in the
   PCP record, not in a commit message.
3. **The `Num` trait is public surface in `rt.rs`,** which ships with every generated program. It is
   `pub` because the generated code names `rt::div::<f64>` implicitly. A future ownership decision
   (PCP `l-880d`) could force it to change shape.
4. **W9b is real work in the checker.** Emitting per-call-site instantiations is serialization of
   inference that already runs (`types_.py:131`, `:160-165`), but it adds a flag and a format to a
   file two phases are editing. If it is cut, §2's `N` rule must be **demoted in the gate's own
   error message**, not left implied — the failure mode this plan exists to close is exactly a claim
   whose enforcement nobody checked.
5. **The tracer records one backend.** §7.1 states the limit. Tier A plus `differential.py` cover the
   Rust side, but "executed" is a Python-side measurement and should be read as such.
6. **Ten fixtures is a lot of new source.** Each must pass five gates. Land them one at a time (W8);
   a batch failure in `differential.py` names the disagreeing case but not which of ten new programs
   is at fault.
7. **Rounding a half is unresolved.** `differential.py`'s own docstring records that Python and
   JavaScript disagree on it. No builtin in the vocabulary rounds, so nothing in this phase forces
   the decision — but Phase 4 will, and Phase 3's Wasm route will inherit whatever is chosen.
8. **Program-mode case 4 needs a file mode of `0o000`.** If the phase is ever run as root, or on a
   filesystem that ignores modes, that case silently becomes a success case. Guard: the case asserts
   `permission-denied`, so it fails loudly rather than passing vacuously.
9. **An `expected` value regenerated from the harness's own output is uncatchable inside this
   repo.** A contributor who pastes the harness's output into `backend/cases/*.json` defeats every
   mitigation §7 has, because both backends descend from one declaration. Stated, not designed away:
   no `--regen` path in the harness; each case carries its "rules out" note as a field so an
   unaccompanied expected value is visible in review; Phase 6's reference interpreter is the only
   real third oracle.
10. **The eight `defenum` instantiations stay unproven until Phase 1's derives land**, and
    `coverage.lock` says so. If that fix is deferred indefinitely, the lock's `unproven` block is the
    only record of it — which is the intent, but it is a record, not a gate.

---

## 10. PCP entries to record

1. **Coverage is redefined and `l-3434` closes at 107/107 executed.** The metric changed from "call
   head in a parsed file" to "the builtin's lowering was evaluated while the gate suite ran a
   program, in a case checked against a value in the repository". The old metric read 38; the same
   tree under the new metric read **33**, of which only **21** were in the old count. Seventeen
   counted builtins had never run and twelve running builtins were outside the scan root, so the old
   number was wrong in both directions. Floor 95% plus a ratchet, both data in
   `prelude/coverage.lock`.
2. **The numerator is traced, not scanned.** A static scan counts a call head in a branch no case
   takes: a ten-line fixture with one case taking the `else` arm moved the previous design's figure
   **21 → 32 with nothing executed**. `backend/exec_coverage.py` wraps every Python lowering
   template in a recorder and runs the programs the gates already run; a builtin counts only if its
   emitted expression was evaluated. Measured cost 1.354 s for 18 programs.
3. **A second, orthogonal gate: `backend/monomorphism.py`.** Every (builtin × admissible
   instantiation) — 400 of them — must compile on both backends. This is the artifact that would
   have caught `filter`, `list-sort-by`, `list-sum`, `/` and `mod`; it replaces a per-builtin eyeball
   with a generated sweep. Its probe count, domains and exclusions are recorded in `coverage.lock`
   and checked three ways, because a sweep whose size nothing records can be shrunk instead of fixed.
4. **"Exercised" never meant "the lowering works".** It meant "the lowering works at the one type
   someone happened to use". Ten builtins were broken over part of their declared type at head
   `8679362` and remain so after Phase 1, with every gate green: `/`, `mod`, `checked-div`,
   `checked-mod`, `list-sum`, `min`, `max`, `list-sort`, `list-min`, `list-max`. Two of them are
   inside the set the coverage figure calls exercised — and neither has ever been executed. (Extends
   the `filter`/`list-sort-by` lesson; supersedes `.plans/phase-2/INVENTORY.md` §3.)
5. **`min`/`max` NaN semantics are decided: Python's rule.** Return the first argument unless the
   second compares strictly past it. Implemented in `rt.rs`, pinned by `23-numeric.agents` entry 2.
   `prelude.json`'s `js` templates propagate NaN from either position and are therefore known-wrong;
   **not changed in this phase** because no JS runtime exists to verify the change. Phase 4 owns it.
6. **`list-sort` on `Float64` with a NaN present is unspecified.** Python's `sorted` is not a total
   order either. No fixture asserts it.
7. **`map-key-order` — a `Map` key must be orderable, and it is a *named* check.**
   `AGENT_SPEC_CORE.md:123` said `K` needs equality while `:576-578` specified sorted keys;
   `(Map Float64 V)` type-checked and could not lower to any backend (40 instantiations narrowed, 24
   of them failing `rustc`). §9's checklist has no item for the domain of a map key, so per `d-bad1`
   the check is coded by name rather than taking `rule-14`; it is the second such check after
   `type-arity`, and the checklist/diagnostic asymmetry `d-bad1` records grows by one. Language
   narrowing; measured blast radius on the existing corpus: zero. The handbook gains the rule (≈ +60
   chars) so the narrowing reaches the artifact the model actually reads.
8. **`prelude/generate.py`'s arity heuristic diverged from `vocab.parse_signature` for 34 of 107
   builtins, in two places** (`:30` and `:162`). Shipped in both generated artifacts —
   `(map-get a b c d)` for a two-argument builtin. Both copies fixed; −98 characters each.
9. **`backend/differential.py` generalised** from one hardcoded task with a single `String` input and
   a map-only serializer to a data-driven harness: typed multi-argument inputs derived from the
   entry's declared signature, a recursive JSON encoder (`backend/rust/harness.rs`) driven by the
   parsed return type, Python-side normalisation so `Option`/`Result`/`Pair`/non-finite floats
   encode identically, and per-case files with modes plus an expected exit status in program mode.
   (Phase 1 had already added the declared-stdout half of the program-mode oracle, after a `cond`
   clause dropping its leading effect was dropped by *both* backends and agreement reported green.)
   Fixture cases live in `backend/cases/`, **not** `bench/tasks/`, which `bench/harness/run.py:189`
   globs.
10. **Cross-reference, not a new owner:** the `defenum`/`defschema` `Ord`/`Eq` derive gap is
    **Phase 1's**. Phase 2 records the eight affected builtins in `coverage.lock` as *proven at
    primitive instantiations only* and schedules no work on it. `defschema`'s mirror-image defect —
    deriving `Ord` unconditionally, so a record with a `Float64` field is an illegal `Map` key and an
    illegal `list-sort` element — belongs with the same fix.
