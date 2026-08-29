# Phase 2 implementation review — coverage integrity and gates

Reviewed: working tree against `a635ab4`. Tree restored byte-identical after every attack
(`git status --porcelain` diff empty, `coverage.lock` / fixtures `04`, `17`, `28` all
`diff`-identical), and the five fast gates re-run at `rc=0`.

## Verdict

**accept-with-fixes** — 107/107 is a real number (101 of 107 mutants killed by an executed
oracle, and a hand-built regression was caught by name), and no gate checks less than it did
at `a635ab4`; but the phase's *other* headline, "a `Map` key must be orderable and `Float64`
no longer is one", is false as stated — the narrowing is annotation-only and an ordinary
program still reaches `f64: Ord` at `rustc`.

## Attacks on 107/107

I did not re-run the implementer's five. Mine:

| # | attack | caught? | by which condition | what would have caught it |
|---|---|---|---|---|
| 1 | New fixture `99-attack-dead-branch.agents`: 26 distinct builtin heads inside an `if` else-arm the `; run:` header never takes | **n/a — no inflation** | figure stayed `107/107`, `0 coverage failure(s)`, `instantiations` unchanged | design is correct here; the old scanned metric would have moved by 26 |
| 2 | Push a builtin's *only* executed site onto a dead branch: added a hand-written `rev` to `28-string-transforms.agents`, rewrote the call as `(if (< 1 0) (string-reverse line) (rev line))`, outputs unchanged | **caught** | cond. 2 (ratchet-down) **and** cond. 5 (instantiations equality), naming `string-reverse` | — |
| 3 | Replace `28`'s run header with `; run: len(transform("aXbXc")) >= 0` | **NOT caught** | — | nothing requires a `; run:` expression to be an assertion |
| 4 | Same on `04-longest-run.agents` (spec §7 worked example, whose *only* oracle is its run header), then invert the algorithm (`(> n (.-second best))` → `(< n …)`) | **NOT caught** | — | a non-vacuity check on `; run:`, or a differential case file for the 14 run-only fixtures |
| 5 | Delete `17-nested-cons.agents`'s run header, park it as `"17-nested-cons.agents": "not executed"` on `coverage.lock.unexecuted` | **NOT caught** | cond. 4's reason guard is `any(key in reason for key in lock)`; `"executed"` is a lock key, so it is a substring of almost any parking reason | a real predicate on the reason, or no `unexecuted` list at all |
| 6 | Break a builtin (attack 2), then `backend/exec_coverage.py --write` | **NOT caught** | `--write` re-recorded `executed: 106` with no warning; `floor_pct: 95` permits `102` | `--write` refusing a *lower* count without an explicit flag |
| 7 | `Float64` map key reached by **inference**, no `Map` annotation anywhere: `(defun b [(ps (List (Pair Float64 Int64)))] -> Int64 (map-size (map-from-pairs ps)))` | **NOT caught** by the checker; `rustc` rejects | — | `map-key-order` applied to inferred types, not only to written ones |
| 8 | Same via `zip`: `(map-keys (map-from-pairs (zip ks vs)))` with `ks : (List Float64)` | **NOT caught**; `rustc` rejects | — | as #7 |
| 9 | `Float64` reaching a key through a user type: `defschema Point{x,y:Float64}` as `(Map Point Int64)`; and `defenum Wrapped(:case scalar [(v Float64)])` | **NOT caught**; `rustc` rejects both | — | disclosed in `.pcp/lang/checker.md` d-2c8f "Deliberately not covered"; not disclosed in `ROADMAP.md` or `HANDBOOK.md` |
| 10 | Recorded at both `Int64` and `Float64` where only one instantiation runs — the check is a *substring* test over **all** arg types, not the `N` positions | **not exploitable today** | all 12 `N`-typed builtins have `N` in every argument, so no non-`N` `Float64` can satisfy the rule | latent; see finding 8 |

Attack 2, verbatim:

```
programs executed : 58
executed builtins : 106/107  (99%)
never evaluated   : string-reverse
  executed 106 is below the recorded 107: a builtin stopped running. Never evaluated: string-reverse
  instantiations[<]: the lock claims ['Int64'], the executed sites give ['Int64', 'an integer']
  instantiations[list-reverse]: the lock claims ['(List Int64)'], the executed sites give ['(List Int64)', '(List String)']
  instantiations[string-reverse]: the lock claims ['String'], the executed sites give None

4 coverage failure(s)
```

Attack 4, verbatim (algorithm inverted, header vacuous):

```
OK: spec and corpus are closed, and every builtin is executed
0 failure(s)          # checker/gate.py
0 failure(s)          # backend/check_corpus.py
executed builtins : 107/107  (100%)
0 coverage failure(s)
```

Attack 6, verbatim:

```
wrote /Users/purplelephant/projects/asex/prelude/coverage.lock (106/107 executed)
--- gate after --write ---
executed builtins : 106/107  (99%)
never evaluated   : string-reverse

0 coverage failure(s)
OK: spec and corpus are closed, and every builtin is executed
lock.executed = 106 | floor = 95 | unproven kept = 12
```

Note the last line of the gate's own output: `closure_audit.py` prints **"every builtin is
executed"** while its own line above reads `106/107` and `string-reverse` was never evaluated.

## Tracer blind spots

First, the mechanical question: is anything outside the tracer's reach at all?

```
LOWER keys 107 declared 107
declared not in LOWER: []
LOWER not declared: []
```

`to_python.Transpiler.call` is the single dispatch point and consults `LOWER` for every
builtin head; there is no constant-folding or inlining path around it. So **zero of the 107
go through a path the tracer cannot see**. The `hit()` wrapper is placed on the template
*before* `.format`, and `and`/`or` short-circuit correctly (the operand's own `hit` does not
fire when the operand is skipped).

The real blind spot is that `hit()` fires *outside* the template, so it records that the
expression was evaluated, not that the work inside it happened. To measure how much that
costs, I ran a full mutation test: for each of the 107, rewrite its Python lowering as
`_mut.m(<template>)` (perturb the result — bool negated, int/float +1, string suffixed, list
head-dropped, dict key-dropped, tuple last-element perturbed) or, for the 9 effect builtins,
as `_mut.eat(args…)` (the effect deleted entirely); then run only the gate programs that
reach it, asserting the `; run:` header, the differential function-case expected values, and
the program-mode stdout+exit.

```
rows 107
SURVIVED 6
  already-exists fired
  file-write     fired
  interrupted    fired
  invalid-path   fired
  map-empty      MUTATION-NEVER-CHANGED-A-VALUE
  other          fired
```

**101 of 107 mutants are killed by an executed oracle.** That is the strongest evidence the
number is real. The six survivors:

- `already-exists`, `invalid-path`, `interrupted`, `other` — executed only in
  `19-io-errors.agents`'s `labels`, where `label` compares `e` against `(already-exists)`
  etc. The constructor is compared *only to itself*, so perturbing it is invisible; the
  printed label comes from the string literal in the `cond` arm. These are the four already
  on `unproven`, but the reason there ("the constructor is executed") credits the hit with
  more than it carries.
- `file-write` — its only executed site in the whole suite is `program:08-io.agents#2`, the
  `nodir/out.txt` failing case whose oracle is `stdout ""`, `exit 1`. Deleting the write
  entirely produces a Python traceback, which is also `stdout ""`, `exit 1`. The successful
  write path is never executed, and the failing path's oracle cannot distinguish an error
  return from a crash (stderr is not compared).
- `map-empty` — lowering is the literal `{{}}`; there is nothing to perturb. Inconclusive
  rather than surviving, but equally: evaluating `{}` proves nothing.

Latent (not live, because the suite's inputs happen to be non-degenerate — every one of these
was killed): `map`/`filter` over an empty list record a hit while the callback never runs;
`list-sort`/`list-sort-by` over ≤1 element record a hit with no comparison; `map-keys`/
`map-values`/`map-pairs`/`fold` over an empty container likewise. And `int32-to-int64` lowers
to `{0}` — its hit records the evaluation of the argument.

One structural limit, correctly documented in the source: the `site()` wrapper is applied only
when `self.prefix == ""`, so a builtin executed **only** inside an imported module's body
counts toward `names` but contributes no `instantiations` entry. That fails conservatively
(the `N` rule would report it missing), so it is not exploitable.

## Gate integrity

| gate file | what changed | more/less/same | evidence |
|---|---|---|---|
| `grammar/validate.py` | unchanged | same | absent from `git diff a635ab4 --stat` |
| `checker/gate.py` | unchanged | same | absent from the diffstat; new fixture `map-float-key.agents` uses the strong `; expect-only:` form |
| `grammar/closure_audit.py` | `exercised builtins` line deleted; exit code `len(undefined)` → `len(undefined) + len(coverage)` | **more** | at `a635ab4` the deleted line was **pure print** — `return len(undefined)` never referenced `calls & builtins`. Nothing it caught is now uncaught, because it caught nothing. The gate now additionally fails on all five coverage conditions. Only regression: the "OK: … every builtin is executed" line prints even when the count is short (attack 6) |
| `backend/check_corpus.py` | `CORPUS` extended with `bench/**/*.agents`; docstring hardened | **more** | 2 extra sources now compile-gated on both backends |
| `prelude/generate.py` | arity via `parse_signature` instead of `type.split("->")[0].split()`; handbook gains the Map-key line | **more** | the old arity was **wrong for 34 of 107** builtins (e.g. `map-size '(Map K V) -> Int64'` → 3 instead of 1). `validate_templates` was formatting with too many args, so a template with an out-of-range placeholder passed. Now it cannot |
| `backend/differential.py` | 1 function task → 18; 7 program cases → 14; `declared_ok` was `want is None or stdout == want`, now `(stdout, exit) == (want_out, want_exit)` unconditionally; per-backend working dirs; typed literal marshalling from the entry's own declaration instead of everything-as-String | **more**, substantially | old `main()` hard-coded `histogram.json` + four 08-io cases of which only two declared any expected output and none declared an exit status |
| `backend/monomorphism.py` | new | n/a | 400 probes through checker + `rustc` + `py_compile`, lock-pinned |
| `backend/exec_coverage.py` | new | n/a | five conditions; conditions 2, 3, 5 are strong (attack 2), condition 4's reason guard is not (attack 5) |
| `backend/t/*` | three new files, none modified | more | `test_exec_coverage.py` tests the dead-branch case and a forged lock |
| `backend/runtime.py`, `backend/rust/rt.rs`, `prelude.json` | float `mod` → `fmod`; `min`/`max` → `rt::` generics; `string-from-float64` → `repr(float(…))`; `zip` → `_as.zip_` | more (fixes that widen the working domain) | — |

**No gate checks less than it did at `a635ab4`.**

On the six `; run:` headers added to `01`-`05`, `07`: this is closing a real hole, not editing
the inputs. Those six were already in `corpus/valid` and already counted by `check_corpus`,
and their `run` column read `-` — they were compile-gated only. Adding a header makes them
assert something they previously asserted nowhere; the alternative (an `unexecuted` entry)
would have recorded the absence and left it. The implementer's reasoning is right, and the
evidence backs it: `run:03-strings.agents` is the mutant-killer for `string-upper`,
`run:07-lambda-elision.agents` for the `mod`-inside-lambda path. **But** see finding 4 — those
14 headers are now load-bearing and nothing checks they say anything.

## The Map narrowing

**Verdict: the narrowing is right on the merits and wrong in extent. `ROADMAP.md`'s
"`Float64` no longer is one" is false as stated.**

On merits: yes. An ordinary program does not key a map by a float — equality on `f64` is a
bug in almost every context, §6 specifies `map-keys` as sorted, and `BTreeMap` needs `Ord`.
Repairing it would mean a different `Map` representation for every program to support a key
type nobody wants. Measured blast radius zero. Narrowing was the correct call.

It is stated where a model sees it — `prelude/HANDBOOK.md:81`, "A `Map` key must be orderable:
`Float64` is not a legal key type", inside the type-rules block that precedes the vocabulary.
It is **not** in `AGENT_SPEC_CORE.md`, which `AGENTS.md` calls normative; `ROADMAP.md` already
flags that §9 has no checklist item for `map-key-order`.

The probes. `checker/resolve.py`'s `map_key_order` walks *declared type trees* only, so it
sees an annotation and nothing else:

```
### p1.agents   (defun a [(m (Map Float64 Int64))] -> Int64 (map-size m))
p1.agents:1:19: map-key-order: Float64 inside a Map key in function a has no total order; …
### p2.agents   (defun b [(ps (List (Pair Float64 Int64)))] -> Int64 (map-size (map-from-pairs ps)))
### p3.agents   (defun c [(ks (List Float64)) (vs (List Int64))] -> (List Float64) (map-keys (map-from-pairs (zip ks vs))))
### p4.agents   (defun d [(m (Map String Float64))] -> Int64 (map-size m))        <- correctly clean, value position
### p5.agents   (defun e [(ps (List (Pair Float64 Int64))) (k Float64)] -> Bool (map-has? (map-from-pairs ps) k))
```

p2, p3, p5 produce **no diagnostic**. They then do exactly what d-2c8f says the defect used
to do:

```
error[E0277]: the trait bound `f64: Ord` is not satisfied
   --> lib.rs:5:17
    |
  5 |     (rt::m_from(ps.clone()).len() as i64)
    |      ---------- ^^^^^^^^^^ the trait `Ord` is not implemented for `f64`
    |      |
    |      required by a bound introduced by this call
```

`zip` two lists and `map-from-pairs` the result is not a contrived shape. Nothing in the
decision record, `ROADMAP.md` or `HANDBOOK.md` says the restriction only binds where a `Map`
type is written down.

Through a user type, both directions:

```
### q3   (defschema Point (:field x Float64 …) (:field y Float64 …)) ; (Map Point Int64)
  checker: CLEAN
  rustc rc=1
error[E0277]: the trait bound `Point: Ord` is not satisfied
### q4   (defenum Wrapped (:case scalar [(v Float64)] …))            ; (Map Wrapped Int64)
  checker: CLEAN
  rustc rc=1
error[E0277]: the trait bound `Wrapped: Ord` is not satisfied
```

These two are disclosed — d-2c8f "Deliberately not covered" names the `defschema` case
explicitly and assigns it to Phase 1. The inference case (p2/p3/p5) is disclosed nowhere.

Not reachable around via an alias: the only alias is `Int → Int64`.

## unproven audit

`unproven` is read by exactly one line in the entire tree:

```
./backend/exec_coverage.py:259:            "unproven": old.get("unproven", {}),
```

That is `build_lock`'s passthrough. **Nothing validates an entry, nothing fails on one, and
nothing expires one.** So the question "does parking something there make it stop mattering?"
has a precise answer: nothing in it ever mattered to a gate in the first place, so parking
costs nothing and buys nothing. It is a register, not a skip list — it cannot suppress a
failure because no failure was available to suppress. That makes it honest *in kind*. Two of
the three groups are not honest *in content*:

| entry | honest register or skip list? |
|---|---|
| `already-exists`, `invalid-path`, `interrupted`, `other` — "the constructor is executed; the host … mapping is reached by no portable case" | **register, but overstated.** The unreachability claim is true. "The constructor is executed" is true and empty: mutating the constructor's value is invisible to every gate (all four survived mutation), because `19-io-errors.agents`'s `label` compares the constructor only against itself |
| `list-sort`, `list-min`, `list-max`, `map-has?`, `map-remove`, `map-keys`, `map-pairs`, `map-from-pairs` — "defenum/defschema element/key — Phase 1 owns the Ord/Eq derives" | **stale.** `to_rust.py` already emits `#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]`, and both `(list-sort (List Color))` and `(map-has? (Map Color Int64))` over a plain `defenum` check clean and compile at `rustc rc=0` today. What Phase 1 actually owns is the *unconditional* derive (q3/q4 above), not the absence of one. The statement "no `defenum`-typed instantiation exists in the suite" is true; the attributed cause is not |
| "`instantiations` covering root-unit call sites only" | **absent.** The implementer's report lists it; the lock does not contain it. It lives only in `exec_coverage.py`'s and `resolve.py`'s docstrings |

`unexecuted` is the opposite case — see finding 2. It *is* a working skip list.

## Rust is not traced — is 107/107 honest for a two-backend project?

Rust executes only inside `differential.py`: 18 function tasks + 14 program cases. The
`; run:` fixtures are Python-only. Reading the per-program trace by label:

```
builtins reachable on the Rust side (differential only): 105 / 107
executed on Python but NEVER executed on Rust: none some
```

The `some` and `none` *lowerings* are compiled by Tier A but never run on Rust (`Option`
values reaching Rust come out of runtime helpers such as `checked-div`).

Defect classes, concretely:

- **Caught on Python, missed on Rust.** A Rust lowering that compiles and is wrong, in a
  fixture whose only oracle is a `; run:` header. `16-recursive-schema.agents` (`some` at a
  recursive `defschema Node`), `17-nested-cons.agents` (nested slice patterns — the exact
  defect class commit `8679362` had to fix), `18-pattern-binders.agents`, `09`-`12` (module
  and imported-type lowerings) are all Python-run + `rustc`-compiled only. A Rust `cons`
  lowering that binds the wrong slice element would compile and no gate would run it.
- **Caught on Rust, missed on Python.** `rustc` is a type checker over every fixture and all
  400 Tier-A probes; `py_compile` is a parser. A `map-key-order`-class defect (`f64: Ord`) is
  invisible to `py_compile` and to the tracer — Python happily keys a dict by a float — and
  only `rustc` sees it. That is exactly how the Map defect was found, and exactly why
  probes p2/p3/p5 still get through: the Python side cannot notice.

**107/107 needs qualifying in `ROADMAP.md`.** §6's gap bullet already carries it correctly
("execution is recorded on the Python side only"). The status table at line 47 does not:
"**107/107 builtins evaluated** while the gate suite runs". One word fixes it —
"107/107 builtins evaluated on the Python lowering". Same for the `AGENTS.md` blurb.

## Findings

**1 — blocker — `map-key-order` is annotation-only; the `ROADMAP` claim is false as stated.**
`checker/resolve.py:map_key_order` scans declared type trees. A `Float64` map key reached by
inference is admitted and fails at `rustc` with the same `f64: Ord` error the check exists to
prevent.
```
$ cat p2.agents
(defun b [(ps (List (Pair Float64 Int64)))] -> Int64
  (map-size (map-from-pairs ps)))
$ checker → CLEAN
$ rustc  → error[E0277]: the trait bound `f64: Ord` is not satisfied
```
Also true via `zip` (p3) and for `map-has?` (p5). Consequence beyond the claim:
`monomorphism.py`'s premise that "admissible = what the checker accepts" is weaker than
advertised — `tier_a.narrowed: 40` counts annotation-level narrowing only, so Tier A's 100%
floor rests on a checker that still admits the instantiation by another route.
*Fix:* run `map-key-order` over the inferred type of every `Map`-producing call site
(`map-empty`, `map-from-pairs`, `map-set`) in `types_.py`, not only over declared annotations;
add the inference case to d-2c8f and a semantic fixture `map-float-key-inferred.agents`.
Until then, `ROADMAP.md`'s "`Float64` no longer is one" and `HANDBOOK.md:81` should say
*where a `Map` type is written*, or the claim should be withdrawn.

**2 — major — `coverage.lock.unexecuted` is a working skip list.** Condition 4's reason guard
is `any(key in reason for key in lock)`, and `"executed"` is a lock key:
```
'' -> False
'TODO' -> False
'not executed' -> True
'unexecuted for now' -> True
'flaky' -> False
'see instantiations' -> True
```
End to end (attack 5): strip `17-nested-cons.agents`'s run header, park it with the reason
`"not executed"` → `0 coverage failure(s)`, `0 failure(s)` from `check_corpus.py`, and
closure_audit prints `OK: … every builtin is executed`. `check_corpus.py`'s own docstring says
"There is no skip list, and there is not going to be one."
*Fix:* drop the guard's pretence — either delete `unexecuted` (a corpus fixture nothing
executes is a defect, and 28 of 28 are covered today) or require the reason to name a PCP id
matched by a regex.

**3 — major — `--write` silently ratchets down, and the floor has 5 builtins of slack.**
Attack 6: with `string-reverse` broken, `--write` printed `wrote … (106/107 executed)` in the
same tone as a success and every gate went green. `pct = 100*hit//107`, so the 95% floor does
not bite until 101. And `closure_audit.py` printed `OK: spec and corpus are closed, and every
builtin is executed` while its own line above read `106/107` and named `string-reverse` as
never evaluated — the summary line is simply false.
*Fix:* `--write` refuses a count below the recorded one without `--allow-regression`; gate the
"every builtin is executed" line on `not stats["unreached"]`.

**4 — major — 14 of 28 valid fixtures have a `; run:` header as their only value oracle, and
nothing requires it to assert anything.** The 14 with no differential case file:
`01`, `02`, `03`, `04`, `05`, `06`, `07`, `09`, `10`, `11`, `12`, `16`, `17`, `18`.
Attack 3 gutted `28`'s header to `len(transform("aXbXc")) >= 0` — all gates green. Attack 4
did the same to `04` and then inverted `run-length`'s comparison, turning §7's worked example
into a *shortest*-run finder — `checker/gate.py`, `check_corpus.py`, `closure_audit.py` and
`exec_coverage.py` all reported success at `107/107`. Phase 2 made this hole load-bearing by
adding six more headers.
*Fix:* `declared_run` rejects a header whose expression contains no `==`; better, require each
run-only fixture to carry a `backend/cases/*.json` so its values are also checked on Rust.

**5 — major — `file-write` is executed only on a path where it fails, and the failing-path
oracle cannot tell an error return from a crash.** Its sole site is
`program:08-io.agents#2` (`nodir/out.txt`, `stdout ""`, `exit 1`). Deleting the write
entirely (`_mut.eat`) leaves the mutant alive, because a Python traceback is also `""`/`1`.
Nothing in the suite ever writes a file successfully and reads it back through `file-write`.
*Fix:* add a `08-io` case that writes to a valid destination and a following case (or a
`files`-seeded read) that observes the content; compare stderr emptiness on the exit-0 cases.

**6 — minor — `unproven`'s eight `defenum` entries are stale and can never expire.**
`to_rust.py` emits `#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]`; `list-sort` over
`(List Color)` and `map-has?` over `(Map Color Int64)` both check clean and compile at
`rustc rc=0`. What Phase 1 owns is the derive being *unconditional* (findings from q3/q4), not
its absence. `build_lock` copies `unproven` forward verbatim forever, so no gate will ever
notice when Phase 1 lands.
*Fix:* restate the eight reasons as "no executed instantiation in the suite"; add a gate
condition that fails when an `unproven` entry's builtin *does* acquire an executed
instantiation.

**7 — minor — `unproven` omits the caveat the implementer's report claims for it.**
"`instantiations` covers root-unit call sites only" is in `exec_coverage.py`'s and
`resolve.py`'s docstrings, not in the lock. The register is incomplete.

**8 — minor — the `N`-domain rule is a substring test over all arguments, and skips `Int32`.**
`missing = [t for t in ("Int64","Float64") if not any(t in shown for shown in seen)]` matches
`"Float64"` inside `"(List Float64)"` — correct today (all 12 `N` builtins take `N` in every
argument, verified), latent the moment a builtin like `N (List Float64) -> N` is declared.
Separately, `DOMAINS["N"]` is `[Int32, Int64, Float64]` but the executed rule demands only two
of the three; `+` is never *executed* at `Int32` on either backend, only compiled.
*Fix:* record the instantiation per `N`-position rather than per call, and either add `Int32`
to the executed rule or say in `ROADMAP.md` that `Int32` arithmetic is compile-gated only.

**9 — minor — `tier_a.narrowed` is a bare count.** `check_lock` compares `40 == 40`; the
candidate total is fixed by generation, so swapping one narrowed probe for a different one
keeps both `probes` and `narrowed` unchanged and is invisible.
*Fix:* record the sorted `label(p)` list, not the length.

**10 — minor — the status table's headline drops the qualifier §6 carries.** `ROADMAP.md:47`
and the `AGENTS.md` blurb say "107/107 builtins evaluated" with no backend named; §6 says
"execution is recorded on the Python side only". Measured Rust-side reachability is 105/107
(`some`, `none` never run there).
*Fix:* "107/107 builtins evaluated on the Python lowering; the Rust lowering is compile-gated
and 105/107 are executed under `differential.py`".

---

### What held up

- No builtin escapes the tracer: `LOWER` and the declared vocabulary are 1:1 with no
  inlining path around `Transpiler.call`.
- 101 of 107 mutants killed. The `; run:` headers and the differential expected values are
  doing real work; this is not a number resting on evaluation alone.
- The ratchet works: attack 2 was caught by two independent conditions and named the builtin.
- Adding call heads on dead branches moves nothing — the historical defeat is closed.
- Every gate that changed checks strictly more, and `generate.py` in particular fixed an
  arity computation that was wrong for 34 of 107 builtins.
