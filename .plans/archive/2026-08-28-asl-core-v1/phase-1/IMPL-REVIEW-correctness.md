# Phase 1 implementation review — correctness and regression

## Verdict

**accept-with-fixes** — the module boundary, rule-13 and the type layer hold up under
adversarial probing, but two defects produce wrong runtime behaviour today: `cond` bodies still
drop non-final expressions on both backends, and a binder inside an imported unit that shares a
name with one of that unit's own top-level functions silently resolves to the function.

---

## Findings

### 1. `blocker` — `cond_form` was never converted to `sequence()`; non-final expressions still vanish

`sequence()` was wired into `defun`, `let_form`, `match_arm` and `fn_form`. It was **not** wired
into `cond_clause` / `else_clause`, which still carry the pre-phase discard loop:

`backend/to_rust.py:416-419`
```python
                    v = None
                    for b in ck[1:]:
                        v = self.expr(b, inner, ind + 1)
```
`backend/to_python.py:270-273`
```python
                    v = None
                    for b in self.kids(cl)[1:]:
                        v = self.expr(b, inner, indent + 1)
```

`cond_clause: "(" expr expr+ ")"` and `else_clause: "(" ELSE_KW expr+ ")"` (grammar/agents.lark:85-86)
both admit multi-expression bodies, so this is reachable source.

**Probe A** — `try` in non-final position inside a cond clause:

```lisp
(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Both lines must print."
  (cond
    ((= 1 1)
      (try (println "first"))
      (println "second"))
    (:else
      (try (println "else-first"))
      (println "else-second"))))
```

Checker: clean, `exit 0`. Emitted Rust:

```rust
pub fn main_(args: Vec<String>) -> Result<(), rt::IoError> {
    let t1 = if (1 == 1) {
        rt::println(&"second".to_string())
    } else {
        rt::println(&"else-second".to_string())
    };
    t1
}
```

```
=== PY RUN === exit 0
stdout: 'first\nsecond\n'
=== RS RUN === exit 0
stdout: 'second\n'
```

The whole `(try (println "first"))` is gone from the Rust output — the effect **and** the `?`
propagation. This is the exact defect the implementer's report says was fixed; it is the same
`(println …)?`-vanishes symptom, one form over.

**Probe B** — bare effect (no `try`) in non-final position inside a cond clause:

```lisp
  (cond
    ((= 1 1)
      (println "first")
      (println "second"))
    (:else
      (println "else")))
```

```
=== PY RUN === exit 0   stdout: 'second\n'
=== RS RUN === exit 0   stdout: 'second\n'
```

Both backends drop it, so `differential.py` is blind to Probe B; only Probe A would be caught, and
only if a fixture existed. None does (see the sequence() audit).

**Fix:** replace both loops with `self.sequence(ck[1:], inner, ind + 1)` /
`self.sequence(self.kids(cl)[1:], indent + 1)`, exactly as `match_arm` does. Add a
`corpus/valid` fixture with a `cond` clause and an `else` clause each carrying two expressions,
the first effectful, and a `; run:`/program-mode case that observes both lines.

---

### 2. `blocker` — a binder inside an imported unit that shadows one of that unit's own top-level names is emitted as the top-level path; **silently wrong**

`self.local` maps a unit's top-level names to their prefixed emitted names
(`to_python.py:110`, `to_rust.py:266`), and every identifier reference goes through it
(`to_python.py:457`, `to_rust.py:628`, and the call heads at `to_python.py:357` / `to_rust.py:508`).
Function parameters, `let` binders and lambda parameters are emitted with bare `mangle()` and are
never entered into `self.local`, so a reference to a binder whose name collides with a top-level
`defun` (or a `defenum` case) resolves to the module-qualified top-level path instead.

The implementer flagged this and left it unverified. It is real, and in the higher-order case it is
**silent** — both backends compile, both run, both agree on the wrong answer, so `differential.py`
cannot see it.

**Probe** — `$W/mods/core/sh4.agents`:

```lisp
(module core/sh4
  :doc "A local lambda bound under the name of a top-level function."
  :export [triple apply-it])

(defun triple [(x Int64)] -> Int64
  :doc "Times three."
  (* x 3))

(defun apply-it [(xs (List Int64))] -> (List Int64)
  :doc "Must add 100 to each element, not triple it."
  (let [(triple (fn [(y Int64)] -> Int64 (+ y 100)))]
    (map triple xs)))
```

imported by a root module that prints the first two elements of `(s/apply-it (list 1 2))`.

Checker: clean, `exit 0`. Emitted Rust body of `apply_it`:

```rust
        xs.clone().into_iter().map(crate::core_sh4::triple).collect::<Vec<_>>()
```

```
=== RUSTC === exit 0
=== PY RUN === exit 0   stdout: '3 6\n'
=== RS RUN === exit 0   stdout: '3 6\n'
```

Expected `101 102`. Answer to the brief's question: **silently wrong**, in both backends, in
agreement.

The loud variants exist too — a parameter or `let` binder used arithmetically:

```lisp
(defun use-param [(area Int64)] -> Int64
  :doc "A parameter named like a top-level function; must return area + 1."
  (+ area 1))
```
emits `return (core_sh2__area + 1)` →
`TypeError: unsupported operand type(s) for +: 'function' and 'int'`, and rustc rejects the Rust.

**Control:** the identical program with `apply-it` in the *root* unit prints `101` on both
backends. The prefix is `""` there, so `self.local` is the identity. The regression is introduced
precisely by this phase's prefixing and only bites inside imported units.

**Fix:** `expr()` must consult a lexical scope before `self.local`. Thread the set of names bound
by enclosing `params` / `let` / `fn_params` / match patterns through `expr`/`call`/`atom`, and
consult `self.local` only for names not in it. A fixture belongs in `corpus/modules` where an
imported module binds a local named like one of its own exports.

---

### 3. `major` — a record used as a `Map` key or a `list-sort` element crashes the Python backend at runtime

Records lower to `dict` on the Python backend (`def Tag(n): return {"n": n}`), and a `dict` is
neither hashable nor orderable. The Rust backend derives `Ord` for exactly this shape and works.
The checker accepts the program.

**Probe** — a record with only an `Int64` field, used as a map key:

```lisp
(defschema Tag (:field n Int64 "an index"))

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Use Tag as a map key."
  (let [(m (map-set (map-empty) (Tag :n 1) 7))]
    (println (string-from-int64 (map-size m)))))
```

Checker: clean, `exit 0`.

```
=== RS RUN === exit 0   stdout: '1\n'
=== PY RUN === exit 1   stdout: ''
TypeError: unhashable type: 'dict'
```

A one-sided crash on a checker-clean program. `list-sort` over records has the same shape
(`dict` is not `<`-comparable). **Fix:** either lower records to a hashable/orderable carrier on
the Python backend (a `tuple`, or a `dataclass(frozen=True, order=True)`), or add a checker rule
constraining `Map` keys and `list-sort` elements — the latter also fixes finding 4.

---

### 4. `major` — the `Eq`/`Ord` taint is correct, but nothing keeps a tainted type out of a position that needs `Ord`

The taint itself survived every probe I built. Seeded on `{Float64, IoError}`
(`to_rust.py:45`), it propagates through compounds, through enum cases, through schema fields,
and across a module boundary via the alias table, to a fixpoint.

**Probe — denied a derive it needs.** `(defschema Pt (:field x Float64 "abscissa"))` used as a
`Map` key. Checker: clean, `exit 0`. Emitted `#[derive(Debug, Clone, PartialEq)]` (no `Ord`),
then:

```
=== RUSTC === exit 1
error[E0277]: the trait bound `Pt: Ord` is not satisfied
error: aborting due to 1 previous error
```

Identical failure for `(list-sort (list (Pt :x 2.0) (Pt :x 1.0)))`.

The *derive decision* is right — `f64` has no `Ord`, so `Pt` must not claim one. The gap is that
no rule keeps a checker-clean program from asking for it, so the phase's own mechanism produces
uncompilable Rust from accepted source.

**Probe — gets a derive it should not.** I could not build one. Every orderless Rust carrier
reachable from the AgentS type language is spelled by a `TYPE_NAME` the scan sees: `Map` lowers to
`BTreeMap` (which *is* `Ord`), `Unit`→`()`, `List`→`Vec`, `Option`/`Result`/`Pair` are all
conditionally `Ord`, and `f64` / `rt::IoError` are both seeded. Cross-module propagation verified:

```
core/pt   → #[derive(Debug, Clone, PartialEq)]  pub struct Pt
holder    → #[derive(Debug, Clone, PartialEq)]  pub struct Holder
error[E0277]: the trait bound `Holder: Ord` is not satisfied
```

One over-denial, harmless today: `derives()` emits `Eq, PartialOrd, Ord` as a unit, so a type
reachable from `IoError` also loses `Eq` — even though `rt::IoError` does derive `Eq`
(`backend/rust/rt.rs:101`). Nothing in the emitted code needs `Eq` without `Ord` (maps are
`BTreeMap`), so this costs nothing yet. Split the seed if a `HashMap`/`HashSet` ever appears.

---

### 5. `minor` — a module-path mangle collision raises an uncaught `ValueError` while the checker reports the program clean

The implementer's claim that both backends raise is correct; no fixture exercises it, so I built
one. `a/b-c` and `a/b/c` both mangle to prefix `a_b_c__`:

```
--- checker
 exit 0
--- py backend
ValueError: module paths a/b-c and a/b/c mangle alike
--- rs backend
ValueError: module paths a/b-c and a/b/c mangle alike
```

A legal, checker-clean program crashes the transpiler with a Python traceback rather than
producing a diagnostic — which is the failure mode `check_file`'s own docstring exists to prevent
for the measurement harness. Note also that the collision set is built from `deps` only
(`to_python.py:100-103`, `to_rust.py:245-248`); the root module's path is never compared, which is
safe today only because the root's prefix is `""`.

**Fix:** give it a checker rule and a `corpus/semantic` fixture, and keep the backend `raise` as
the assertion behind it.

---

### 6. `minor` — `modules.closure` never marks the root module seen; a cycle through the root yields the root twice

`grammar/modules.py:49-66` adds each *dependency* path to `seen` but never the path of the tree it
was called on. `resolve()` then appends the root again:

```
--- modules.resolve order
['cyc/x', 'cyc/y', 'cyc/x']
```

for `cyc/x` ↔ `cyc/y`. The Python backend emits `cyc/x` twice — once prefixed, once bare:

```python
def cyc_x__fx():
    return 1

def cyc_y__fy():
    return 2

def fx():
    return 1
```

The docstring's promise "A module reached twice appears once" is false for the root, and the
compilation unit contains a duplicate. It does not hang (the other half of the docstring holds)
and rule-11 does report the cycle (`rule-11: import cycle: cyc/x -> cyc/y -> cyc/x`), so the only
exposure is a backend invoked without the checker — which is exactly how `check_corpus.py` and
`differential.py` invoke it. **Fix:** seed `seen` with `declared_path(tree)` in `resolve()`.

Two other `modules.py` hazards from the brief are closed by the grammar, not by the resolver:
`MOD_PATH: /[a-z][a-z0-9]*(-[a-z0-9]+)*(\/[a-z][a-z0-9]*(-[a-z0-9]+)*)+/` (grammar/agents.lark:197)
admits no `.` and no uppercase, so `../escape` is unwritable and a `core/Shapes` import cannot be
spelled at all — macOS case-insensitivity can only ever resolve a lowercase import to a
differently-cased *file*, whose declared path is itself forced lowercase. `find()` is nonetheless
one `Path(root) / (mod_path + ".agents")` away from a traversal if a caller ever loosens that
terminal.

---

### 7. `minor` — every non-final effect emits a `unused_must_use` warning in the Rust output

`sequence()` emits `{last};`, and every I/O lowering returns `Result<_, rt::IoError>`. The crate
attribute allows `dead_code, unused_variables, unused_mut, unused_parens` — not `unused_must_use`.
A three-function probe produced three of them:

```
warning: unused `Result` that must be used
 --> main.rs:5:5
  |
5 |     rt::println(&"defun-1".to_string());
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  = note: this `Result` may be an `Err` variant, which should be handled
help: use `let _ = ...` to ignore the resulting value
```

`check_corpus.py` runs `rustc` without `-D warnings`, so it stays green — but any consumer who
turns warnings up finds them, and the warning is arguably correct: an AgentS program *is*
discarding a `Result`. **Fix:** emit `let _ = {last};` from the Rust `sequence()` when the
discarded expression is not already `?`-propagated.

---

### 8. `minor` — type diagnostic swaps expected/found when one side is an unresolved numeric literal

```
argument to println: expected an integer, found String
```
for `(println 42)`. `println` takes `String`; the argument is the integer. The correct
rendering appears when both sides are concrete:
```
argument to println: expected String, found Int64
```
Same class in `return of unwrap: expected Int64, found (t/Cell an integer)`, where a literal-class
placeholder leaks into a rendered type application.

---

## sequence() audit

| what | result |
|---|---|
| Pre-existing fixtures, Python output old vs new | **byte-identical**, all 7 unchanged sources (01-basics, 02-match, 03-strings, 04-longest-run, 05-constructors, 07-lambda-elision, 08-io) |
| Pre-existing fixtures, Rust output old vs new | **byte-identical**, same 7 |
| 06-module | excluded — the fixture source itself changed this phase |
| Method | old backend from `snap-phase1/` over `snap-phase1/`'s own fixture sources vs current backend over current sources, `diff` on stdout |

**The identity is vacuous.** A parse-tree sweep of the entire corpus for bodies with more than one
expression — `defun` bodies, `let` bodies, `cond`/`else` clause bodies, match-arm bodies, lambda
bodies — returns exactly one hit:

```
grammar/corpus/valid/13-module-program.agents [('let_body', 2)]
```

which is new this phase. No pre-existing fixture ever reached the changed code path, so
byte-identity was guaranteed regardless of what `sequence()` does. The behavioural claim is
supported by my own probes, not by the corpus.

Behaviour of the converted paths, verified by running:

| position | evaluated | `try` propagates | note |
|---|---|---|---|
| `defun` body | exactly once | yes (`(twice(…))?;`, `if _t3[0] == "err": return _t3`) | both backends print `defun-1` then `defun-2` |
| `let` body | exactly once | yes | |
| `match_arm` body | exactly once | yes | |
| `fn_form` (lambda) body | exactly once | yes | |
| **`cond_clause` / `else_clause` body** | **zero times** | **no — dropped** | finding 1 |

No double-evaluation path found: forms that need statements (`if` with impure arms, `cond`,
`match`, `try`) return a temp name or an index into one, so `sequence()` re-emitting the returned
string is a no-op statement rather than a second evaluation. The cost is finding 7 (`t1;` and
discarded `Result`s) and nothing worse. A non-final expression whose value is `Unit` behaves the
same as one whose value is discarded; Rust does not error, it warns.

---

## rule-13 holes

Every shape probed as a copy in a temp directory; the corpus was not touched. Private declaration
in each is a local `defenum Shape` (or `defschema Priv`) absent from `:export`.

| shape tried | caught? | code reported |
|---|---|---|
| bare private type as parameter (baseline fixture) | yes | `rule-13` |
| `(List Shape)` parameter | yes | `rule-13: Shape in exported function f …` |
| `(Option Shape)` return | yes | `rule-13` |
| `(Map String Shape)` parameter | yes | `rule-13` |
| `(List (Option (Pair String Shape)))` parameter | yes | `rule-13` |
| function-typed parameter `(Fn Shape Float64)` | yes | `rule-13` ×2 (plus `rule-10: Fn … neither a known type nor bound`) |
| return position only, `-> Shape` | yes | `rule-13` |
| exported `defschema` field of a private enum | yes | `rule-13: Shape in exported field Box.inner …` |
| exported `defschema` field of a private schema | yes | `rule-13: Priv in exported field Wrap.p …` |
| exported `defenum` case parameter of a private type | yes | `rule-13: Shape in case only of exported Wrap …` |
| private type beside a bound typevar in one signature | yes | `rule-13` |
| type alias | n/a | the language has none |
| private type of an *imported* module | by design not rule-13 | rule-9 owns it (`public_type` docstring) |
| **typevar declared with the same spelling as a private local type** — `(defun {Shape} f [(x Shape)] -> Shape …)` | **no** | clean, `exit 0` |

**One hole, and it is not a leak.** In the last row `Shape` *is* the typevar, so the exported
signature reads `∀Shape. Shape → Shape` — public. Attempting to leak through it is caught one
layer down by the type checker:

```
type: return of f: expected Shape, found Shape
```

for a body that returns the concrete private `(circle 1.0)`. Two residual notes: nothing warns
that a typevar shadows a declared type, and that diagnostic renders both sides as `Shape`, which
is unreadable. `corpus/valid/11-name-coexistence.agents` relies on exactly this shadowing
deliberately, so the shadowing itself is intended.

Net: **0 exploitable holes**, 1 cosmetic.

---

## Verified claims

| implementer's claim | how I checked | holds? |
|---|---|---|
| "an effect lowered as a pure expression vanished … fixed with a shared `sequence()` in each emitter" | read both `sequence()`; ran probes in `defun`/`let`/`match_arm`/`fn_form` on both backends | **partly** — fixed in four positions, **not** in `cond_clause`/`else_clause` (finding 1) |
| "root-unit output is byte-identical to pre-phase" | old backend from `snap-phase1/` vs current, both backends, 7 unchanged fixtures | yes — but vacuous: no pre-existing fixture has a multi-expression body |
| "a discarded non-final expression is evaluated exactly once" | ran the seq probe; inspected temp-name returns for double evaluation | yes in the converted positions; **zero** times in `cond` |
| "`try` in non-final position still propagates" | `(try (twice …))` in a `defun` body, both backends | yes in converted positions; **dropped** in a `cond` clause on Rust |
| "probed every new valid fixture with a deliberate mismatch and each reported a `type` diagnostic" | independently perturbed 09, 10, 11, 12, 13 and `core/shapes` | yes — 6/6 reported `type:` (`return of unit: expected s/Shape, found String`; `return of unwrap: expected Int64, found (t/Cell an integer)`; `argument to imported-name: expected sh/Shape, found Shape`; `return of show: expected Int64, found String`; `return of describe: expected Int64, found String`; `match arms: expected Float64, found String`). The `if not self.diags` gate does not hide anything in `corpus/valid` — those fixtures are clean, so the type layer always runs |
| "the `Eq`/`Ord` taint seeds on `{Float64, IoError}` and propagates" | probes for both directions, incl. across a module boundary | yes — no false derive found; taint reaches an imported type through the alias table |
| "a local binder whose name equals one of that unit's own top-level function names would be emitted as the qualified top-level path" (left unverified) | built the case | **yes, and worse than stated** — the higher-order form is silently wrong on both backends (finding 2) |
| "both backends raise on two module paths that mangle alike, but no fixture exercises it" | built `a/b-c` + `a/b/c` | yes, both raise — as an uncaught `ValueError`, on a program the checker calls clean (finding 5) |
| `modules.closure` — "a module reached twice appears once, and a cycle is broken rather than diagnosed" | `resolve()` on a two-module cycle | **no** for the first half — the root appears twice (finding 6). The "does not recurse for ever" half holds |
