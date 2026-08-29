# Phase 1 — Types across the module boundary  (v2, reconciled)

Gap: PCP `r-ea8c`, `ROADMAP.md:208-211`. Blocks `d-f484` (the module header *is* the Wasm
interface contract) because half that contract — the types in the exported signatures — is
currently inexpressible, and because nothing forces a signature's types to be part of the contract
at all.

Disposition of every review finding: `.plans/phase-1/RECONCILIATION.md`.

---

## 0. What changed from v1

Four blockers and the scope changes they force.

1. **A new conformance rule, `rule-13`, is the phase's real acceptance criterion.** v1 removed the
   *lexical* obstacle to writing `s/Shape` but added no rule forcing a type named in an exported
   signature to itself be exported. `grammar/corpus/valid/06-module.agents:5,11,24` exports
   `area : (sh Shape) -> Float64` while `Shape` is unexported; it checks clean today
   (`checker/gate.py` → `valid/06-module.agents clean - ok`) and would have stayed clean under v1.
   That is verbatim `r-ea8c`'s own scenario (`.pcp/lang/modules.md:47-50`), so v1 would have marked
   `r-ea8c` Resolved with the gap still reachable. §2.5 states the rule; W9 enforces it; W6 adds
   `semantic/private-type-in-exported-signature.agents`; `06-module.agents:5` gains `Shape`.

2. **W2 (Rust codegen, v1's W7) is scoped to all 13 rustc errors, enumerated, and covers `defun`.**
   v1 quoted 2 errors and scoped the fix to `defenum`/`defschema`. Reproduced: 13 errors, and
   `backend/to_rust.py:150-151` drops `defun`'s `type_params` by the same filter, producing
   `pub fn swap(p: (A, B)) -> (B, A)` — 4 of the 13. **New, found while reconciling:** emitting
   `pub fn swap<A, B>` alone raises 2 *new* errors (`E0599: no method named clone found for type
   parameter B`), because the emitter clones every value; the generic list must carry `Clone`
   bounds. Measured milestone with bounds: 13 → 4. The `defenum` `Eq`/`Ord` derive fix the
   orchestrator log assigns to this phase is folded in here, and measured to require a
   *conditional* derive (`f64: Eq` is not satisfied).

3. **W9 (`resolve.py`, v1's W5) covers `_ctor` and `_field_access`.** `checker/resolve.py:300-305`
   looks a ctor head up in `self.mod.schemas` only, so a `QUALIFIED_TYPE` head reports `rule-2`;
   `checker/resolve.py:410` then runs the type layer only `if not self.diags`, so one such
   spurious diagnostic blanks the whole type layer for that fixture and `imported-type-mismatch`
   reports nothing either. `checker/resolve.py:322-327` has the same shape for `.-field`.

4. **Fixtures come before the checker work, and every work item names something that can fail.**
   v1 ordered W4-W6 (checker) before W11 (fixtures), so the only harness that exercises those
   files (`checker/gate.py`, over the corpus) did not yet contain a case — the fixtures would have
   been shaped by the implementation, which is what `AGENTS.md:55-58` exists to prevent. The whole
   fixture matrix is now W6, before W8/W9/W10, and `checker/gate.py` is expected to **fail loudly**
   at the end of W6.

Scope changes that make the plan cheaper or honest:

* **v1's risk 2 (lexical ambiguity) is downgraded and its mitigation automated.** Both reviewers
  independently applied the W3/W4 edits to grammar copies and measured: `s/Shape` is one token in
  both grammars in param, type-app, ctor and export position; `(/ a b)` is still division; no new
  ambiguity. `grammar/parse.py:32` sets `ambiguity="resolve"`, and the *unmodified* grammar is
  already ambiguous for `(s/concat …)` and for every `match`. v1's manual eyeball (W12) becomes a
  ~15-line automated token-identity assertion inside `grammar/validate.py` — gate #1 — in W5.
* **v1 §1.4's "not valid Python" is refuted.** `py_compile` exits 0 on today's
  `s/concat(s/upper(x), "!")` (reproduced). So un-skipping `06-module.agents` from `SKIP_PY` proves
  nothing on its own. W13 adds an **execution** step for the Python column.
* **`grammar/validate.py` never parses `corpus/modules`** (`:63-74` lists `valid`, `invalid`,
  `semantic` only), which is where most of the new grammar forms live. W5 adds it.
* **`:export [circle]` is legal today** (`checker/resolve.py:120` exempts case names) and
  contradicts §2.1.3. §2.6 rules that the new reading wins; W9 removes the allowance.
* **`transpile()` takes text, not a path**, at all five call sites, and
  `bench/harness/run.py:133` has no file at all. W11 fixes the signature explicitly rather than
  "threading a `--root`".

---

## 1. Problem, restated from evidence

Every claim below was read out of the file cited, or produced by running the command shown.

### 1.1 The grammars admit no type on the export list and no type in qualified position

* `grammar/agents.lark:26` — `module_opt: ... | EXPORT_KW "[" IDENT* "]"`. `IDENT` is
  `/[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?/` (`:184`); `TYPE_NAME` is `/[A-Z][A-Za-z0-9]*/` (`:183`).
  A PascalCase name cannot appear there.
* `grammar/tree-sitter-agents/grammar.js:38` — `seq(':export', '[', repeat(field('export',
  $.ident)), ']')`. Same restriction. **Both grammars agree**, so the drift gate is blind to it,
  exactly as `r-ea8c` records.
* `grammar/agents.lark:58-59` — `type: TYPE_NAME | "(" TYPE_NAME type+ ")"`. No qualified form.
  `grammar.js:103-104` — `_type: choice($.type_name, $.type_app)`. Same.
* `grammar/agents.lark:192` — the `QUALIFIED` terminal is `/[a-z]…\/[a-z]…[?!]?/`: lowercase member
  only. `grammar.js:236` is the identical regex. `alias/Type` is not a token in either grammar.
* `grammar/agents.lark:114` — `ctor: "(" TYPE_NAME ctor_arg* ")"`; an imported record cannot be
  constructed. `grammar/agents.lark:89` — `pattern: "(" IDENT pattern* ")" -> enum_pattern`
  (`grammar.js:216-218` matches); an imported union case cannot be matched.

Verified by running the project parser (`.venv/bin/python`, `grammar/parse.py:parse_text`):

| source | Lark verdict |
|---|---|
| `(module m :doc "d" :export [Shape])` | **REJECT** — `No terminal matches 'S' … line 1 col 29` |
| `(defun f [(x o/Point)] -> Int64 …)` | **REJECT** — `No terminal matches 'o' … line 2 col 14` |
| `(defun f [] -> (List o/Point) …)` | **REJECT** — `No terminal matches 'o' … line 2 col 22` |
| `(o/Point :x 1)` | **REJECT** — `No terminal matches 'P' … line 2 col 34` |
| `(module m :doc "d" :export [f])` | PARSE |

### 1.2 Nothing forces an exported signature's types to be public

This is the half of `r-ea8c` v1 missed, and it is a defect *independent* of 1.1.

* `grammar/corpus/valid/06-module.agents:5` — `:export [shout area tally]`.
* `grammar/corpus/valid/06-module.agents:11` — `(defenum Shape …)`, not exported.
* `grammar/corpus/valid/06-module.agents:24` — `(defun area [(sh Shape)] -> Float64 …)`, exported.
* `checker/gate.py` over that fixture → `valid/06-module.agents  clean  -  ok`. Reproduced.
* `checker/resolve.py:115-122` (`module_rules`) is the only export-list rule: a name must be a
  local fun or a local case name. Nothing looks at the *types* in an exported signature.
* `.pcp/lang/modules.md:47-50` — `r-ea8c`'s scenario: "a module declares a domain union and a
  function returning it, exports the function, and no other module can write the type of what it
  receives".
* `ROADMAP.md:78` — the property this is all for: the header is "readable without the body".
* `.pcp/lang/wasm.md:8-11` (`d-f484`) — modules "composed through declared interface contracts".
  A contract whose signatures mention private types is not a contract.

`AGENT_SPEC_CORE.md:640-661` (§9) has 12 rules; none of them is this one.

### 1.3 A bare union case is exportable today, which contradicts the design

`checker/resolve.py:120` — `elif name not in self.mod.case_owner:` — so `:export [circle]` with
`Shape` absent is accepted: a module can publish a constructor for a type nobody can name. That is
a second, independent route to publishing a case, and it manufactures instances of 1.2.
No fixture in the tree uses it (`grep -rn ":export" grammar/corpus prelude bench backend/t` — every
export list holds function names only), so removing it breaks nothing existing.

### 1.4 The specification says the same thing

* `AGENT_SPEC_CORE.md:86` — `qualified ::= ident "/" ident`. Both sides lowercase.
* `AGENT_SPEC_CORE.md:152-154` — `:export` is "the public surface"; imported members "are then
  reached as `alias/name`". Nothing states a type may be either.
* `AGENT_SPEC_CORE.md:654-655` (rule 9) — "Every qualified name `alias/member` uses an alias bound
  in `:import`, and the member is exported by that module." Written for values only.
* `AGENT_SPEC_CORE.md:301-302` — case names "are used as both constructors and patterns, exactly
  like the built-in `ok`/`some`". No longer true across a boundary, where they are `s/circle`.
* `AGENT_SPEC_CORE.md:625-637` (§8) — the mangling table has rows for `parse-html-url`, `Point`,
  `empty?`, `set!`. **No row for a qualified name**, and `:635-637`'s collision rule speaks of
  identifiers only, not module paths.

### 1.5 The checker is local-only for types, by construction

* `checker/collect.py:113-114` — `mod.exports += [str(t) for t in opt.children[1:]]`: one flat list
  of raw tokens, no value/type distinction (there cannot be one — 1.1).
* `checker/resolve.py:98` — `self.known_types = type_names() | set(mod.schemas) | set(mod.enums)`.
  Prelude names plus **this module's** declarations. Nothing imported.
* `checker/resolve.py:157-168` (`qualified_names`) — scans only `QUALIFIED` tokens and tests
  `member not in target.exports`. The only pass that reads another module's contract.
* `checker/resolve.py:186-192` (`check_type`) — scans `TYPE_NAME` tokens; unknown ⇒ `rule-10`.
  Its only caller is `type_var_rules` (`:172-184`).
* `checker/resolve.py:300-305` (`_ctor`) — `schema = self.mod.schemas.get(name)`; a qualified head
  gets `rule-2`.
* `checker/resolve.py:322-327` (`_field_access`) — `self.field_names` (`:102`) is local schemas
  plus `PAIR_FIELDS`; `.-value` on an imported record gets `rule-2`.
* `checker/resolve.py:380-386` (`exhaustive`) — `enums = {owner[h] for h in heads}` is a set of
  **bare** enum names, so a local `Shape` and `core/shapes`'s `Shape` collapse to one string and
  the arms-mix check cannot fire.
* `checker/resolve.py:410` — `if not self.diags: Types(...)`. One spurious resolve-layer diagnostic
  suppresses the entire type layer for that file.
* `checker/collect.py:61-69` — `case_owner` / `case_params` iterate local enums only.
* `checker/types_.py:53-57` — `Con(name, args)` carries a **bare string**; `unify` (`:113-115`)
  compares `a.name != b.name`. Type identity is the unqualified spelling.
* `checker/types_.py:115` — `numeric = a.name in NUMERIC and b.name in NUMERIC`; `:155` —
  `name = self.aliases.get(name, name)`. Both key on the unqualified string.
* `checker/types_.py:159` — a rigid type variable is encoded as `Con("#" + name)` and `show` (`:77`)
  strips the `#`. Any new `Con` field must not collide with that encoding.
* `checker/types_.py:186-191` (`qualified`) — resolves an alias-qualified name only when
  `member in target.funs`. Imported constructors and imported record types are unreachable.
* `checker/resolve.py:235-237` — a call whose callee is not an `IDENT` returns before the arity
  check, so `(s/circle)` with the wrong argument count gets no `arity` diagnostic from `resolve`.

The machinery to *load* another module exists and is used: `checker/resolve.py:73-88` (`Loader`)
resolves a module path over an ordered root list and calls `collect`; `checker/gate.py:22,39` drives
it with `ROOTS = [corpus/modules]`. **The imported module's `schemas` and `enums` are already
collected and simply never consulted.** This matches `ROADMAP.md:143-144`.

### 1.6 Neither backend lowers a module boundary at all

* `backend/to_python.py:66-81` — `transpile` iterates top-level nodes and handles only `defenum`,
  `defschema`, `defun`. `module_decl` is silently dropped; no import is followed.
* `backend/to_python.py:375` — an unrecognised atom falls through to `mangle(s)`, and `mangle`
  (`:30-37`) only rewrites `-`, `?`, `!`. A `QUALIFIED` token passes through with its slash intact.
  `.venv/bin/python backend/to_python.py grammar/corpus/valid/06-module.agents` emits
  `return s/concat(s/upper(x), "!")`.
* **That output is valid Python.** `.venv/bin/python -m py_compile` on it exits **0** (reproduced).
  It is a division expression. `backend/check_corpus.py:38-49` runs exactly `py_compile`, so the
  Python column of that gate cannot distinguish a correct lowering from any syntactically
  well-formed wrong one.
* `backend/to_rust.py:286-295` reaches the same outcome: `s/concat(s/upper(x.clone()),
  "!".to_string())`.
* `backend/check_corpus.py:22-23` — `SKIP_RUST = {"06-module.agents"}`, `SKIP_PY =
  {"06-module.agents"}`. The only two skips in the file. The one corpus fixture with a module
  header is excluded from both target-compiler checks.
* `transpile()` takes **text, not a path**: `backend/to_python.py:66`, `backend/to_rust.py:95`, and
  every call site passes a string — `backend/differential.py:30,46,72,79`,
  `bench/harness/run.py:133`. The last has no file at all, and `bench/harness/run.py` is not on the
  acceptance list.

### 1.7 The Rust lowering is broken for the shapes this phase needs — 13 errors, enumerated

* `backend/to_rust.py:124-132` (`defschema`), `:134-147` (`defenum`) and `:149-151` (`defun`) all
  filter `type_params` out of their children and emit no generic list.
* `backend/to_rust.py:137` derives `Debug, Clone, PartialEq` for an enum; `:128` derives
  `Debug, Clone, PartialEq, Eq, PartialOrd, Ord` for a struct, unconditionally.

Reproduced exactly as `backend/check_corpus.py:53-59` does it —
`.venv/bin/python backend/to_rust.py grammar/corpus/valid/06-module.agents > lib.rs`,
`cp backend/rust/rt.rs .`, `rustup run stable rustc --edition 2021 --crate-type=lib lib.rs`:

| # | class | count | site | cause |
|---|---|---|---|---|
| 1 | `E0412 cannot find type T` | 1 | `lib.rs:14:10` | `(defenum {T} Tree …)` binder dropped ⇒ `Node(T, Tree, Tree)` |
| 2 | `E0412 cannot find type T` | 2 | `lib.rs:19:16` | `(defschema {T} Box …)` binder dropped ⇒ `pub struct Box { pub value: T }` |
| 3 | `E0412 cannot find type A / B` | 4 | `lib.rs:22:17,20,28,31` | `(defun {A B} swap …)` binder dropped ⇒ `pub fn swap(p: (A, B)) -> (B, A)` |
| 4 | `E0072 recursive type Tree has infinite size` | 1 | `lib.rs:12:1` | no indirection for the recursive case |
| 5 | `E0391 cycle detected when computing when Tree needs drop` | 1 | `lib.rs:12:1` | fallout of 4 |
| 6 | `E0425 cannot find value s` | 2 | `lib.rs:36:5,14` | `s/concat` / `s/upper` lowered with a bare slash |
| 7 | `E0423 expected function, found macro concat` | 1 | `lib.rs:36:7` | same; `concat!` is a std macro, so the failure is *not* a syntax error |
| 8 | `E0425 cannot find function upper` | 1 | `lib.rs:36:16` | same |

Total 13. Classes 1-5 (9 errors) are **W2**; classes 6-8 (4 errors) are **W12**.

Two further facts measured while scoping W2, neither of which either review found:

* Emitting `pub fn swap<A, B>(…)` alone raises **two new** errors —
  `E0599: no method named clone found for type parameter B` at `lib.rs:23:10` and `A` at `:23:23` —
  because the body is `(p.1.clone(), p.0.clone())` and the emitter clones everywhere. With
  `pub fn swap<A: Clone, B: Clone>` the file drops to exactly the 4 `s/…` errors. **W2 must emit
  `Clone` bounds on `defun` type parameters.**
* Adding `Eq, PartialOrd, Ord` to the `defenum` derive list unconditionally does **not** compile:
  `#[derive(Eq, Ord)] pub enum Shape { Circle(f64), … }` gives
  `E0277: the trait bound f64: Eq is not satisfied` (and the same for `Ord`). Measured. The derive
  must be conditional on no `Float64` appearing (transitively) in any case parameter. Generic
  parameters are fine: `#[derive(Eq, Ord)] pub enum Tree<T> { … }` compiles, because derive emits
  `T: Eq` bounds itself. `backend/to_rust.py:128` has the mirror-image latent bug today — a
  `Float64`-bearing `defschema` would not compile — and is fixed by the same rule.

This whole class is invisible today only because `06-module.agents` is on both skip lists (1.6).

### 1.8 Baseline, measured now

`checker/gate.py` → `0 failure(s)` (26 rows). `.venv/bin/python -m pytest backend/t bench/algo
checker/t -q` → `47 passed`. `wc -c prelude/HANDBOOK.md` → `12078` ≈ 3,020 tokens at the project's
chars/4 approximation. `backend/check_corpus.py` → `0 failure(s)`, with
`06-module.agents ok skipped ok skipped`.

Two harness facts that bear on what the gates prove:

* `backend/t` contains `smoke.agents`, `smoke.py`, `test_smoke.py`, and
  `backend/t/test_smoke.py:10` is `import smoke as s` — a **checked-in, pre-generated** file.
  `bench/algo/test_histogram.py:13` likewise imports the checked-in
  `bench/algo/histogram_agents.py`. **No gate regenerates or diffs either against its `.agents`
  source**, so `AGENTS.md:75-76` ("`backend/t` runs AgentS source through the transpiler and
  executes the result") is not true of the mainline tree. `smoke.py` happens to be in sync now.
* `checker/gate.py:58` is `ok = want in codes`, not equality. A fixture reporting its declared rule
  **plus** spurious extra codes passes. Two existing fixtures already report two codes
  (`try-in-lambda`, `try-outside-result` → `rule-5,type`), so a blanket exact-set assertion is not
  available; see W7.

---

## 2. Design decision

### 2.1 Chosen surface

**A type is exported by listing its name on the existing `:export` vector. An importer names it
`alias/TypeName`, and its union cases `alias/case-name`. Export is transparent.**

```lisp
; core/shapes.agents
(module core/shapes
  :doc "Plane figures and their measurements."
  :export [Shape area])                     ; Shape is a type; area is a function

(defenum Shape
  (:case circle    [(radius Float64)]                 "A circle")
  (:case rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))

(defun area [(sh Shape)] -> Float64
  :doc "Area of a shape."
  (match sh ((circle r) (* 3.14159 (* r r))) ((rectangle w h) (* w h))))
```

```lisp
; text/report.agents
(module text/report
  :doc "Rendering for shapes."
  :export [describe unit-square]
  :import [(core/shapes :as s)])

(defun describe [(sh s/Shape)] -> String        ; alias/TypeName in type position
  :doc "One line per shape."
  (match sh
    ((s/circle r)      (str "circle "    (float64-to-string r)))
    ((s/rectangle w h) (str "rectangle " (float64-to-string w)))))

(defun unit-square [] -> s/Shape
  :doc "The 1x1 rectangle."
  (s/rectangle 1.0 1.0))                        ; alias/case as a constructor
```

Four sub-decisions, each justified against an existing convention:

1. **One export list, not two.** `d-f99b` makes the export list *the* contract, singular and
   machine-readable; a second `:export-types` vector makes it two contracts that can disagree about
   what is public. Case decides the kind without a keyword: `AGENT_SPEC_CORE.md:88-89` already
   fixes type names as PascalCase and `:85` fixes identifiers as lowercase, so
   `:export [describe Shape]` is unambiguous under rules the language already has.
   This is the one place in the language where **spelling decides a kind**, and
   `ROADMAP.md:79-80` states the opposite stance for type variables ("a name is a type variable
   because it was declared one, never because of how it is spelled"). It is a deliberate exception,
   on the same footing as `AGENT_SPEC_CORE.md:101-102`'s division/qualification split, and W1 says
   so in the spec so the two statements do not read as a contradiction.
2. **`alias/TypeName`, reusing the qualified shape.** `AGENT_SPEC_CORE.md:154` already defines
   `alias/name` as *the* way to reach anything in another module. Extending it by the case of the
   member's first letter adds no new namespace mechanism and no new punctuation. The token is a
   single lexeme (measured — §6.2), so `AGENT_SPEC_CORE.md:102`'s division/qualification
   disambiguation carries over unchanged.
3. **Transparent, not opaque.** Exporting a `defenum` exports its cases; exporting a `defschema`
   exports its fields for construction and `.-field` access. Forced by totality: `match` must be
   exhaustive (`AGENT_SPEC_CORE.md:649`) and case names are both constructors and patterns
   (`:301-302`), so an importer that cannot see every case cannot write a total `match` — an opaque
   union would be unusable, not merely restricted. The stronger reason to defer opacity is that the
   opaque form maps to an abstract handle whose semantics depend on an ownership model that is
   explicitly unrecorded (`ROADMAP.md:214-215`, PCP `l-880d`): deciding opacity now decides
   ownership by accident. The syntax is left additive — a bare `Shape` entry can grow
   `(Shape :opaque)` later without invalidating any program written now.
4. **Cases are reached qualified, not brought into scope bare.** `(s/circle r)` as a pattern and
   `(s/circle 2.0)` as a constructor. An unqualified import would create a second, implicit
   namespace path — the thing `d-f99b` exists to avoid — and would collide silently whenever two
   imported unions share a case name.

### 2.2 What the contract is, now that export is transparent

Once `:export [Shape]` also publishes `circle`, `rectangle`, `radius`, `width` and `height`, the
export vector is no longer the whole public surface — it is a **seed** for it. `d-f99b`
(`.pcp/lang/modules.md:29-31`) claims the surface "can be extracted mechanically"; that stays true,
but the extractor now reads *the header together with the declarations of the types it names*, and
those declarations are in the same file. **A module's interface contract is the header plus the
declarations of the types on its export list.** This is a real narrowing of `d-f99b` and W17 records
it rather than letting `d-f99b` read as unchanged.

For `d-f484`'s stated role — "a typed glue layer between ecosystems that meet as compiled modules …
composed through declared interface contracts" (`.pcp/lang/wasm.md:8-11`) — transparent is the form
to ship: data crossing a component boundary must be described structurally for the host to marshal
it. Opacity returns later as the *resource* case, not as a general visibility knob.

### 2.3 Type identity

**Nominal, keyed by (defining module path, type name).** `core/shapes` `Shape` and a locally
declared `Shape` are *different types*; `core/shapes` `Shape` reached through alias `s` and through
alias `shapes` are *the same type*. The alias is module-local (`AGENT_SPEC_CORE.md:164`) and
therefore cannot participate in identity.

Implementation constraint (`checker/types_.py`): `Con.name` **stays unqualified** and the defining
module goes in a separate field, because `:115` (`a.name in NUMERIC`) selects the numeric-mixing
diagnostic and `:155` (`self.aliases.get(name, name)`) is the prelude type-alias map (`Int` →
`Int64`), and both key on the bare string. The new field is added as the **third** positional
parameter — `checker/t/test_types.py:44,50,55` construct `Con(name, args)` positionally, so a third
position breaks nothing and a second position would break every one. It must not be folded into the
`Con("#" + name)` rigid-variable encoding at `:159`, which `show` (`:77`) strips.

Rejected: structural identity (two records with the same fields are interchangeable) — it
contradicts the tagged runtime representation both backends already emit (`backend/to_python.py:
121-122`, `backend/to_rust.py:146`) and would make `defenum`'s closed-union guarantee meaningless
across a boundary.

Rejected: identity by alias — makes a type's name change when an importer renames its alias, which
breaks the property `d-f99b` is for.

Two modules defining a same-named type, both imported, are distinct `Con`s with distinct spellings
`s/Shape` and `t/Shape`. Nothing is ambiguous.

### 2.4 Transitivity and re-export

`core/shapes` exports `Shape`; `text/report` imports it and exports
`(defun describe [(sh s/Shape)] -> String …)`; a third module `C` imports `text/report` as `r`.

* **`C` may call `(r/describe v)` without importing `core/shapes`.** Rule 9
  (`AGENT_SPEC_CORE.md:654-655`) constrains the qualified names *`C` writes*, and `C` writes none of
  `core/shapes`'s. Type identity is by defining module (§2.3), so the checker resolves the parameter
  type through the `Loader` regardless of `C`'s import list.
* **`C` must import `core/shapes` the moment it needs to *name* the type** — a `let` binding's
  type, a helper's parameter, a `match` over the value. That follows from §2.1.4 and from aliases
  being module-local.
* **There is no re-export.** `text/report` listing `Shape` on its own `:export` is a `rule-2`,
  because `Shape` is not in *its* `schemas`/`enums`. Stated so the diagnostic does not read as a bug.

### 2.5 The export-closure rule (new **rule 13**)

> **Rule 13.** Every type named in the signature of an exported `defun`, and in every field type of
> an exported `defschema` and every case-parameter type of an exported `defenum`, is a §3 built-in,
> a type variable bound in that declaration's `{ }`, or a type exported by its defining module.

Why a **new code** rather than an extension of `rule-2`: `checker/gate.py` asserts the *specific*
code a fixture declares (`AGENTS.md:55-58`, PCP `c-099a`), and "exported but not defined" and
"a private type escapes through the contract" are different defects with different fixes. Reusing
`rule-2` would make one fixture's verdict satisfiable by the other's bug.

Why it is the phase's acceptance criterion rather than an extra: without it, `r-ea8c`'s requirement
(`.pcp/lang/modules.md:45-46`) is half met, `06-module.agents` still exports a function whose
parameter type no importer can write, and W17 would record a false resolution. Adding the rule later
is a *new rejection of already-accepted programs*, including a corpus fixture — cheap now,
breaking later.

Consequences taken deliberately:

* `grammar/corpus/valid/06-module.agents:5` becomes `:export [shout area tally Shape]`. Chosen over
  demoting the fixture to `semantic/`, because the fixture's job is to demonstrate a working module
  header and W13 promotes it to a fully gated backend fixture.
* `backend/t/smoke.agents:3,5,10` has the same defect (`area [(sh Shape)]` exported, `Shape` not).
  It is not on any checker gate's path, but it is fixed in W14 so the tree contains no known
  violation.
* The rule is checked against the **defining** module's export list, so it composes with §2.4: a
  type exported by `core/shapes` and used in `text/report`'s exported signature satisfies rule 13
  without `text/report` re-exporting anything.

### 2.6 A bare union case is not exportable

`checker/resolve.py:120` accepts `:export [circle]` today (1.3). **The new reading wins: a case
name on the export list is a `rule-2`, and cases travel only with their type.** Two independent
routes to publishing a case contradict `d-f99b`'s single contract, and the surviving route publishes
a constructor for a type nobody can name — an instance of exactly what rule 13 exists to stop.
Nothing in the tree uses the allowance (1.3), so removing it costs one line and one fixture.

### 2.7 Diagnostic codes

| situation | code | why this code |
|---|---|---|
| `:export [Missing]` — no such type in this module | `rule-2` | same code `checker/resolve.py:121` already uses for an exported-but-undefined value |
| `:export [circle]` — a bare case name | `rule-2` | §2.6; the allowance at `checker/resolve.py:120` is removed |
| `text/report` re-exports an imported `Shape` | `rule-2` | §2.4; `Shape` is not in *its* `schemas`/`enums` |
| exported signature names an unexported type | **`rule-13`** | §2.5 |
| `s/Shape` where `Shape` is not on `core/shapes`'s export list | `rule-9` | `AGENT_SPEC_CORE.md:655` |
| `q/Shape` where `q` is not in `:import` | `rule-9` | `checker/resolve.py:162`, unchanged wording |
| `s/circle` where the owning enum is not exported | `rule-9` | a case is public exactly when its type is |
| `(p/Vault :x 1)` — qualified *ctor* head not exported | `rule-9` | reported from `_ctor`, a different code path from `qualified_types` |
| `(t/Cell)` — imported record, field without `:default` omitted | `ctor` | `AGENT_SPEC_CORE.md` §4.1's construction rules, unchanged across the boundary |
| `match` on `s/Shape` missing a case | `rule-4` | exhaustiveness, `AGENT_SPEC_CORE.md:649` |
| `match` arms mixing a local case and an imported one | `rule-4` | arms-mix, `checker/resolve.py:384`, keyed on (module, enum) |
| local `Shape` value passed where `s/Shape` is wanted | `type` | nominal identity, reported by the unifier |

Two situations named in the phase brief are **not** errors under this design:

* **Local/imported name collision.** A module may declare `Shape` and import `s/Shape`. Distinct
  types, distinct spellings; a *valid* fixture pins the non-collision.
* **A type variable named after an imported type.** `(defun {Shape} f [(x Shape)] …)` alongside
  `:import [(core/shapes :as s)]` is legal: the binder shadows nothing, because the imported type is
  only ever spelled `s/Shape`. Also a valid fixture. (A `{ }` binder shadowing a **local** declared
  type is a pre-existing hole — §6.4.)

### 2.8 Lowering strategy

**Both backends link the transitive import closure into one output unit**, rather than emitting one
target module per AgentS module.

Rationale: `backend/check_corpus.py:26-29` and `backend/differential.py:69-84` both build exactly one
target artifact from exactly one source path. Per-module emission would require a build driver, a
package layout and a link step on each target before a single fixture could be gated. Whole-closure
linking reuses the module resolution the checker already has (`checker/resolve.py:73-88`) and keeps
every gate driving a single artifact.

* **Rust:** each imported AgentS module becomes a nested `pub mod <path-mangled>` inside the emitted
  file; `s/Shape` → `core_shapes::Shape`, `s/circle` → `core_shapes::Shape::Circle`, `s/area` →
  `core_shapes::area`.
* **Python:** the closure is emitted flat with a module-derived prefix; `s/area` →
  `core_shapes__area`, `s/circle` → `core_shapes__circle`. Python has no nominal types at runtime — a
  schema is a dict (`backend/to_python.py:106`), an enum case a tagged tuple (`:122`) — so only the
  *function* names need namespacing.
* **The prefix is derived from the defining module path, never from the alias.** Two aliases for one
  module must produce one name; `valid/11` and the W15 differential case both exercise it.
* **The tuple tag stays the bare case name** (`("circle", r)`). Qualifying it would change the output
  of every existing single-module fixture and the assertions in `backend/t` and `bench/algo`, both of
  which pin bare tags — for a collision the checker's nominal rule already makes unobservable.
  Recorded as a risk in §6.3.
* **§8 gains a normative row** for qualified names, and its collision rule (`:635-637`) is extended
  to module paths: `core/shapes` and a module named `core-shapes` collide under either scheme.

---

## 3. Work items

Order is top to bottom and is the corrected order from the executability review, re-slotted for the
new items. Every item names a **fail condition that can be observed before the next item starts**.

### W1 — Specification amendment (blocks everything)
**Files:** `AGENT_SPEC_CORE.md`
**Changes:**
* §2 (`:83-97`): add `qualified-type ::= ident "/" type-name` beside `qualified` at `:86`.
* §4.0 (`:151-154`): `:export` admits type names; exporting a type exports its cases and fields
  (transparent); an importer writes `alias/TypeName` and `alias/case-name`; opacity does not exist
  in v0.2 and why (`l-880d`); a **bare case name is not exportable** (§2.6); **no re-export**, and
  a consumer of B need not import A to call through it but must to name the type (§2.4); the
  contract is the header **plus the declarations of the exported types** (§2.2); one sentence
  acknowledging that the export list is the single place where spelling decides a kind (§2.1.1).
* §4.1 (`:262-264`) and §4.4: a `defschema` / `defenum` is exportable on the same list.
* `:301-302`: case names are constructors and patterns "exactly like `ok`/`some`" **within their
  own module**; across a boundary they are written `alias/case-name`.
* §8 (`:625-637`): one table row for a qualified name — `s/parse-html-url` and `s/Point` — giving the
  Python and Rust spellings §2.8 fixes; and one clause extending the collision rule to module paths.
* §9 (`:640-661`): rule 9's "member" covers a type name and a union case name; **new rule 13** as
  worded in §2.5; the "Rules 2, 5, 6, 7-12 are semantic" sentence at `:659` becomes `7-13`.
**Why:** `AGENT_SPEC_CORE.md` is normative (`AGENTS.md:5-6`); a grammar change ahead of it is drift.
**Do not touch** §6 tables — generated (`AGENTS.md:83-84`).
**Fails before W2 if:** `.venv/bin/python grammar/closure_audit.py` stops printing
`OK: spec and corpus are closed` — it extracts call heads from the spec's own code blocks, so a new
example using an undefined head is caught here.

### W2 — Rust codegen: generics, bounds, recursion, conditional derives
**Files:** `backend/to_rust.py`
**Changes:**
1. `defenum` (`:134-147`), `defschema` (`:124-132`) and `defun` (`:149-151`) stop filtering
   `type_params` out and emit it as a Rust generic list.
2. `defun`'s generic list carries **`Clone` bounds** (`pub fn swap<A: Clone, B: Clone>`). Measured
   requirement, not a precaution: without it the emitter's clone-everywhere strategy raises
   `E0599 no method named clone found for type parameter B` (§1.7).
3. A case field or struct field whose type mentions the type being declared is emitted behind
   `::std::boxed::Box<…>` — fully qualified, because a user schema named `Box` is legal and present
   in the corpus (`grammar/corpus/valid/06-module.agents:8`).
4. **Derive fix (orchestrator log: Phase 1 owns the whole `defenum` codegen fix, derives included;
   Phase 2's 8 blocked builtins — `list-sort`, `list-min`, `list-max`, `map-has?`, `map-remove`,
   `map-keys`, `map-pairs`, `map-from-pairs` — depend on it).** Both `defenum` and `defschema` derive
   `Debug, Clone, PartialEq` always, and additionally `Eq, PartialOrd, Ord` **only when no field or
   case-parameter type is transitively `Float64`**. A bare type variable does *not* block it — derive
   emits its own `T: Eq` bound. Measured: unconditional `Eq`/`Ord` on `Shape` gives
   `E0277: the trait bound f64: Eq is not satisfied`; `#[derive(Eq, Ord)] pub enum Tree<T>` with
   `Box` indirection compiles. This also repairs `defschema`'s existing unconditional derive
   (`:128`), which is latently wrong for a `Float64`-bearing record.
   Transitivity is computed over user types, so the emitter must resolve a case parameter naming
   another local `defenum`/`defschema`; a forward reference is a known hazard (§6.1).
**Why:** verified broken (§1.7) and it blocks W13. Independently reproducible **today**, before any
grammar change — which is why it runs second.
**Fails before W3 if** any of these is false:
* `.venv/bin/python backend/to_rust.py grammar/corpus/valid/06-module.agents > lib.rs`, `rt.rs`
  copied alongside, `rustup run stable rustc --edition 2021 --crate-type=lib lib.rs` reports
  **exactly 4 errors**, all in class 6-8 of §1.7's table (`s`, `concat`, `upper`). 13 → 4.
* `.venv/bin/python backend/check_corpus.py` still reports `0 failure(s)` with `06-module.agents`
  still on both skip lists.
* `.venv/bin/python -m pytest backend/t bench/algo checker/t -q` still `47 passed`.

### W3 — Lark grammar
**Files:** `grammar/agents.lark`
**Changes:**
1. New terminal beside `QUALIFIED` (`:192`), at the same priority:
   `QUALIFIED_TYPE.2: /[a-z][a-z0-9]*(-[a-z0-9]+)*\/[A-Z][A-Za-z0-9]*/`.
2. `:26` — `EXPORT_KW "[" (IDENT|TYPE_NAME)* "]"`.
3. `:58-59` — `type: TYPE_NAME | QUALIFIED_TYPE | "(" (TYPE_NAME|QUALIFIED_TYPE) type+ ")"`.
4. `:114` — `ctor: "(" (TYPE_NAME|QUALIFIED_TYPE) ctor_arg* ")"`.
5. `:89` — `pattern: "(" (IDENT|QUALIFIED) pattern* ")" -> enum_pattern`.
**Depends on:** W1. **Parallel with:** W4 (same author, one commit).
**Fails before W5 if:** `.venv/bin/python grammar/validate.py` is not `0 failure(s)` on the existing
corpus, or prints `GRAMMARS DISAGREE` on any row.

### W4 — tree-sitter grammar + regeneration
**Files:** `grammar/tree-sitter-agents/grammar.js`, then regenerate `src/`
**Changes:** the same five, at `:38` (export field becomes `choice($.ident, $.type_name)`),
`:103-104` (`_type` gains `$.qualified_type`), `:104` (`type_app` head), `:181` (`ctor` type field),
`:216-218` (`enum_pattern` case field becomes `choice($.ident, $.qualified)`), plus the
`qualified_type` terminal beside `:236`. Regenerate with
`cd grammar/tree-sitter-agents && ../../node_modules/.bin/tree-sitter generate` (`AGENTS.md:96-100`);
`src/` is generated and git-ignored.
**Why:** `AGENTS.md:102-104` — both grammars change together or the constrained-decoding arm and the
tooling enforce different languages.
**Fails before W5 if:** `tree-sitter generate` exits non-zero, or `grammar/validate.py` reports
`GRAMMARS DISAGREE`.

### W5 — Conformance gate: scan `corpus/modules`, and assert token identity
**Files:** `grammar/validate.py`
**Changes:**
1. `:63-74` — add `cases += [(p, True) for p in sorted((ROOT/"corpus"/"modules").rglob("*.agents"))]`.
   `corpus/modules` appears nowhere in that file today, so the module fixtures — where the
   `:export [Shape …]` and exported-generic-`defenum` forms live — are parsed by tree-sitter by no
   gate at all.
2. A new **token-identity** block, ~15 lines, replacing v1's manual W12. For a small probe set
   (`s/Shape` as a param type, inside `(List s/Shape)`, as a return type, as a `ctor` head, as an
   `enum_pattern` head via `s/circle`, and `(/ a b)` alongside), assert:
   * the Lark tree contains exactly one `QUALIFIED_TYPE` token whose text is `s/Shape`, and no
     `OPERATOR` `/` adjacent to it;
   * `tree-sitter parse` output contains exactly one `qualified_type` node covering the same span
     (the CLI prints `(qualified_type [l, c] - [l, c])`, and `treesitter_accepts` at `:38-53`
     already shells out to it);
   * `(/ a b)` still lexes as `OPERATOR`.
   It lives here, not in `checker/t`, because this file already owns the tree-sitter CLI invocation
   and is gate #1.
**Why:** PCP `c-40b5` — the conformance gate compares accept/reject verdicts, not trees (`:85-90`),
and `(s/concat x)` silently became a call to `s` once. Both reviewers measured that the W3/W4 edits
introduce no new ambiguity, so this is a cheap **regression** guard rather than a discovery step,
and it survives the next terminal in a way a one-time eyeball would not.
**Fails before W6 if:** `grammar/validate.py` does not list `modules/core/strings.agents` in its
fixture table, or the token-identity block does not run and print a per-probe verdict.

### W6 — Corpus fixtures — the whole matrix, before any checker change
**Files:** `grammar/corpus/modules/`, `grammar/corpus/valid/`, `grammar/corpus/semantic/`
See §4 for the matrix. Includes editing `grammar/corpus/valid/06-module.agents:5` to
`:export [shout area tally Shape]` (§2.5).
**Why here:** `checker/gate.py` is the only harness that exercises `checker/resolve.py` and
`checker/types_.py`, and it drives corpus fixtures (`:39,:49`). Writing the checker first and the
fixtures second is the failure mode `AGENTS.md:55-58` was written about.
**Depends on:** W3, W4 (they must parse).
**Fails before W7 if** either of these is false:
* `.venv/bin/python grammar/validate.py` → `0 failure(s)`; every new fixture parses under **both**
  grammars, including the module fixtures now that W5 scans them.
* `.venv/bin/python checker/gate.py` → **a nonzero failure count with one named failure per new
  fixture**: each `modules/…` and `valid/…` row FAILs (the checker cannot yet see across the
  boundary), and each `semantic/…` row FAILs with `expected <code>, got …`. This failing table is
  the deliverable of W6; it is what W8-W10 turn green one row at a time.

### W7 — `checker/gate.py`: exact-code assertion for the new fixtures
**Files:** `checker/gate.py`
**Changes:** `:58` is `ok = want in codes`, so a fixture reporting its declared rule **plus**
spurious extras passes — which is exactly what a half-done W9 produces (`rule-4` from
`exhaustive()` alongside a spurious `rule-2: s/circle is not a case of any union` from `:358`).
A blanket exact-set assertion is not available: `semantic/try-in-lambda.agents` and
`semantic/try-outside-result.agents` legitimately report `rule-5,type` today (measured). So add an
opt-in header — a fixture whose first line is `; expect-only: <code>` is asserted as
`set(codes) == {code}`; `; expect:` keeps today's `want in codes`. Every fixture added by this phase
uses `; expect-only:`.
**Depends on:** W6.
**Fails before W8 if:** the gate does not report a distinct verdict for an `; expect-only:` fixture
that reports a second code, or any pre-existing fixture's verdict changes.

### W8 — `checker/collect.py`: split the export list
**Files:** `checker/collect.py`
**Changes:** at `:113-114`, partition `:export` entries by token type — `IDENT` into `mod.exports`,
`TYPE_NAME` into a new `mod.exported_types: list[str]`. Add one derived accessor for the cases and
fields of exported types (the transparent-export set), so W9 and W10 read one definition of
"publicly reachable member".
**Why:** without the split, `module_rules` (`checker/resolve.py:115-122`) reports `rule-2` on every
exported type.
**Depends on:** W6, W7.
**Fails before W9 if:** `checker/gate.py`'s row for `valid/06-module.agents` still reports
`rule-2` on `Shape`, or `semantic/export-undefined-type.agents` does not now report `rule-2`.

### W9 — `checker/resolve.py`: cross-boundary resolution, rule 13, case-export removal
**Files:** `checker/resolve.py`
**Changes:**
1. `module_rules` (`:115-122`) — an entry in `exported_types` must be in `mod.schemas` or
   `mod.enums`, else `rule-2` (this is also what makes re-export a `rule-2`, §2.4). **Remove the
   `case_owner` allowance at `:120`** so a bare case name on the export list is a `rule-2` (§2.6).
2. New rule 13 pass — for every exported `defun`, `defschema` and `defenum`, walk the declared
   types and report `rule-13` on any `TYPE_NAME` that is local, unexported, and not bound in that
   declaration's `{ }`; a `QUALIFIED_TYPE` is checked against the *defining* module's
   `exported_types` (§2.5).
3. New pass `qualified_types()`, modelled on `qualified_names` (`:157-168`): scan `QUALIFIED_TYPE`
   tokens; unbound alias → `rule-9`; member not in the target's `exported_types` → `rule-9`.
4. `qualified_names` (`:167`) — a member is exported if it is in `target.exports` **or** is a case of
   an exported enum. This is what makes `(s/circle 2.0)` legal and `(s/hidden-case …)` a `rule-9`.
5. `_ctor` (`:300-320`) — a `QUALIFIED_TYPE` head resolves through the `Loader` to the target
   module's schema; unexported → `rule-9`; keys/missing fields validated against *that* schema
   (missing field ⇒ `ctor`). Without this the head reports `rule-2`, and `:410` then suppresses the
   whole type layer for that file.
6. `_field_access` (`:322-327`) — `self.field_names` (`:102`) additionally admits the fields of
   imported exported schemas. §2.1.3 promises `.-field` access on an imported record.
7. `pattern` (`:347-375`) and `exhaustive` (`:377-395`) — a `QUALIFIED` pattern head resolves its
   owning enum in the imported module; the `enums` set at `:382` is keyed on **(defining module,
   enum name)**, not the bare name, so a local `Shape` and `core/shapes`'s `Shape` in one `match`
   report `rule-4` arms-mix instead of collapsing to one string.
8. `check_type` (`:186-192`) needs **no skip logic** — `QUALIFIED_TYPE` is a single terminal, so
   `Shape` inside `s/Shape` is never a `TYPE_NAME` token. What it does need is to be *reached*:
   `type_var_rules` (`:172-184`) is its only caller, and a qualified type must be routed to the new
   pass 3 rather than silently ignored.
9. `known_types` (`:98`) unchanged for bare names; qualified ones resolve through pass 3 instead of
   joining a flat set, so a local `Shape` and `s/Shape` cannot be confused.
**Why:** this is the pass that "gains the ability to see across a module boundary for types"
(`ROADMAP.md:143-144`), plus the rule that makes the boundary a contract (§2.5).
**Depends on:** W8.
**Fails before W10 if:** `checker/gate.py` does not show every row green **except**
`semantic/imported-type-mismatch.agents` (a type-layer verdict, W10's job) — and in particular the
four `modules/…` rows and `valid/09`, `valid/10`, `valid/11`, `valid/12`, `valid/06-module` must all
read `clean … ok`. A `modules/…` row that is not clean makes every `rule-9` verdict resting on it
worthless (`checker/gate.py:35-38`).

### W10 — `checker/types_.py`: nominal identity across modules, with its unit tests
**Files:** `checker/types_.py`, `checker/t/test_types.py`
**Changes:**
1. `Con` (`:53-57`) carries the defining module path as a **third positional** field (§2.3), so
   `unify` (`:113-115`) distinguishes two modules' `Shape`. `.name` stays unqualified; `:115`
   (`NUMERIC`) and `:155` (prelude aliases) keep working. `show` (`:71-78`) renders the type back as
   the importer wrote it (`s/Shape`), never as an internal key. Must not collide with the
   `Con("#" + name)` rigid encoding at `:159`.
2. `declared` (`:150-161`) — a `QUALIFIED_TYPE` node resolves through the `Loader` to the defining
   module and yields that module's `Con`. A locally declared type yields this module's.
3. `lookup` (`:169-184`) / `qualified` (`:186-191`) — `qualified` currently resolves only
   `target.funs`; extend to an imported enum case (constructor type) and an imported schema.
4. `_ctor` (`:369-382`) — a `QUALIFIED_TYPE` head constructs the imported record, with the imported
   schema's fields and type variables.
5. `pattern_types` (`:429-458`) — a qualified case head resolves in the imported module and unifies
   the scrutinee with that module's `Con`.
6. **`checker/t/test_types.py` gains two assertions, in this item, not a trailing test item:**
   two `Con`s with the same name and different defining modules do **not** unify; two `Con`s with
   the same name and the same defining module (reached through different aliases) **do**. A unifier
   that accepts everything leaves every gate green (`AGENTS.md:78-79`), and the *second* direction
   is asserted nowhere else in the corpus — a program that gets it wrong only shows up as a spurious
   `type` error on a valid fixture that uses two aliases for one module.
**Why:** without 1, `(defenum Shape …)` here and `(defenum Shape …)` there unify, which is the one
silent failure this phase must not ship.
**Depends on:** W8, W9.
**Fails before W11 if:** the two new `checker/t` assertions do not fail before the change and pass
after; or `checker/gate.py` is not `0 failure(s)` — `semantic/imported-type-mismatch.agents` must now
report exactly `type`, and `pytest checker/t` must still pass its other 16 cases (`Con(name, args)`
is called positionally at `:44,:50,:55`).

### W11 — Backend module loading
**Files:** `backend/to_python.py`, `backend/to_rust.py`, one shared resolution module,
`backend/differential.py`, `bench/harness/run.py`, `backend/check_corpus.py`
**Changes:**
1. `transpile()` takes text, not a path, at `backend/to_python.py:66` and `backend/to_rust.py:95`,
   and every one of the five call sites passes a string. Signature becomes, explicitly:
   `transpile(self, src: str, *, path: Path | None = None, roots: Sequence[Path] = ())`. A
   text-only call keeps working and resolves no imports — this is what keeps
   `bench/harness/run.py:133` alive, which transpiles model-generated text that has no file at all
   and is not on the acceptance list.
2. Both transpilers accept a repeatable `--root` on the CLI (same semantics as
   `checker/check.py:18-20`: the file's own directory is always searched) and resolve the transitive
   import closure with the same path→file rule as `checker/resolve.py:80-88`.
3. **Do not duplicate the resolution logic a third time** — factor it where the checker and both
   backends read one copy.
4. Emission order stays enums → schemas → funs (`backend/to_python.py:66-81`,
   `backend/to_rust.py:99-109`), imported modules first, per §2.8.
**Depends on:** W2 (Rust side).
**Fails before W12 if** any of these is false:
* a new unit test asserts the resolver returns the closure for `06-module.agents` as
  `[core/strings, text/casing]`, in that order, and fails before the change;
* `.venv/bin/python -m pytest backend/t bench/algo checker/t -q`, `backend/check_corpus.py` and
  `backend/differential.py` are all unchanged-green — the text-only call sites at
  `backend/differential.py:30,46,72,79` and `bench/harness/run.py:133` must not break.

### W12 — Qualified name and qualified type lowering
**Files:** `backend/to_python.py`, `backend/to_rust.py`
**Changes:**
* Python: `atom` (`:366-375`) and `call` (`:266-282`) map a `QUALIFIED` token to the
  module-path-derived prefixed name instead of letting the slash through (`:375`); `ctor`
  (`:253-259`) accepts a `QUALIFIED_TYPE` head; `pattern` (`:310-364`) accepts a qualified case
  head.
* Rust: `rtype` (`:78-91`) maps a `QUALIFIED_TYPE` to `core_shapes::Shape`; `call` (`:273-295`) and
  `pattern` (`:343-393`) map a qualified case head to `core_shapes::Shape::Circle`; `ctor`
  (`:262-266`) to `core_shapes::Point { … }`.
* The prefix is derived from the **defining module path**, never the alias (§2.8).
**Depends on:** W11.
**Fails before W13 if** either is false:
* `rustc` on the `06-module` Rust output reports **0 errors** (4 → 0, closing classes 6-8 of §1.7);
* a `backend/t` case that transpiles `06-module.agents` **at test time** into a tempdir and executes
  it asserts `shout("hi") == "HI!"` — an imported *function* call, which is the exact form the skip
  list was hiding and which W15's imported-union case does not cover.

### W13 — Un-skip the module fixture, and make the Python column mean something
**Files:** `backend/check_corpus.py`
**Changes:**
1. Delete `06-module.agents` from `SKIP_RUST` and `SKIP_PY` (`:22-23`) and the stale comment at
   `:21-23`; pass the corpus module root (`grammar/corpus/modules`) to both transpilers.
2. **Add an execution step for the Python column.** `:38-49` runs `py_compile` only, which exits 0
   on today's broken `s/concat(...)` output (§1.6) — so un-skipping alone proves nothing, and after
   W12 an emitter producing `core_shapes__area` where it should produce `core_shapes__describe`, or
   prefixing with the *alias*, still compiles cleanly. Add a `run` column that imports the emitted
   module (`runpy`) and calls a fixture-declared entry, alongside `py_compile`.
**Why:** this is the observable proof the gap is closed.
**Depends on:** W2, W11, W12.
**Fails before W14 if:** `.venv/bin/python backend/check_corpus.py` does not print `ok` in the
`compile`, `run` **and** `rustc` columns for the `06-module.agents` row. **This item cannot be
declared done on an exit code** — a `skipped` where `ok` is expected is a failure of this phase even
though the exit code is 0; that is precisely how §1.6 and §1.7 stayed hidden.

### W14 — Tests and the remaining tree fixes
**Files:** `backend/t/`, `backend/t/smoke.agents`
**Changes:**
1. A `backend/t` case that transpiles a **two-module** program at test time (tempdir, `--root`) and
   executes it, asserting the imported union's behaviour from the specification rather than from
   what the transpiler emitted. `backend/t` today only imports the checked-in `smoke.py`
   (`test_smoke.py:10`), so this is new machinery, not an addition to an existing pattern.
2. One assert that the checked-in `backend/t/smoke.py` still equals
   `Transpiler().transpile(smoke.agents)` — the phase is changing the emitter, and nothing regenerates
   or diffs that file today.
3. `backend/t/smoke.agents:3` gains `Shape` on its export list — `area [(sh Shape)]` is exported and
   `Shape` is not, the same rule-13 violation as `06-module` (§2.5). No checker gate covers this
   file, so it is fixed here rather than left as a known violation.
**Depends on:** W12.
**Fails before W15 if:** `pytest` count does not rise above `47 + 2` (W10's two), or the smoke drift
assert does not fail when `smoke.py` is perturbed.

### W15 — Differential gate case
**Files:** `backend/differential.py`
**Changes:** thread the search root through **all four** transpile call sites — `:30` and `:46`
(function mode) as well as `:72` and `:76-84` (program mode); v1 named only the last two. Add **one
program case** to the list at `:128-132`: a `main` that
* imports a module defining a `defenum`, matches a value of it and prints the result, **and**
* calls an imported *function*, **and**
* reaches the imported module through **two different aliases** in the same program,

compared on stdout *and* exit status.
**Why the two aliases:** it is the cheap discriminator for a lowering keyed on the alias rather than
the module path, and no other planned artifact tests it. **Why a differential case at all:** the two
targets represent an imported union completely differently — a tagged tuple on one
(`backend/to_python.py:122`), a namespaced Rust variant on the other (§2.8) — and each derives that
representation independently. `check_corpus.py` proves each side compiles and runs; only running both
proves they agree. Same argument `AGENTS.md:69-73` makes for the I/O surface, and program mode is the
only gate that has ever caught a defect in how one form nests inside another (PCP `c-15f3`).
**Depends on:** W12, W6.
**Fails before W16 if:** `.venv/bin/python backend/differential.py` does not list the new case in its
program table with `0 disagreement(s)`, or the function-mode cases regress.

### W16 — Handbook and generated artifacts
**Files:** `prelude/generate.py`, then regenerate `prelude/HANDBOOK.md`
**Changes:** two blocks, not one — v1 cited only the first.
* `prelude/generate.py:66-69` is the **module header** block; the export line at `:68`
  (`"  :export [f]                   ; NOTHING is public unless listed"`) gains a type name.
* `prelude/generate.py:74-75` is the `Shape` block; one line showing `o/Type` in a signature.
`prelude/prelude.json` is **not** touched — no vocabulary changes — so the §6 tables are unchanged.
**Cost:** baseline `wc -c prelude/HANDBOOK.md` = 12,078 chars ≈ 3,020 tokens (measured). Two added
lines ≈ +85 chars ≈ +21 tokens, +0.7% on the per-call cost. **Report the measured figure after
regenerating, not this estimate.**
**Fails before W17 if:** `.venv/bin/python prelude/generate.py --check` is not exit 0 — it fails
until the regenerated file is committed.

### W17 — PCP entries
See §7. **Depends on:** everything.
**Fails if:** `r-ea8c` is marked Resolved while `semantic/private-type-in-exported-signature.agents`
is absent or not reporting `rule-13`, or while `06-module.agents:5` does not export `Shape`.

---

## 4. Fixture matrix

`corpus` column: `modules` = search-path companion, checked clean by `checker/gate.py:39` and (after
W5) parsed by `grammar/validate.py`; `valid` = must parse, check clean, transpile and be accepted by
both target compilers; `semantic` = must parse under **both** grammars (`grammar/validate.py:73-74`)
and be rejected by the checker under the exact code its `; expect-only:` header names
(`checker/gate.py:49-62`, hardened in W7). Multi-file semantic cases live in a subdirectory and every
file carries the header, as `semantic/import-cycle/{a,b}.agents` already do.

| fixture path | corpus | must parse? | checker verdict | rule code | what a wrong implementation does here |
|---|---|---|---|---|---|
| `modules/core/shapes.agents` — `defenum Shape` (circle/rectangle), `area`; `:export [Shape area]` | modules | yes | clean | — | W8 not splitting the list ⇒ `rule-2` on `Shape`; W9 rule 13 over-firing ⇒ `rule-13` on `area` |
| `modules/core/trees.agents` — `defenum {T} Tree` (recursive, parameterised), `defschema {T} Cell`, `tree-size`; all exported | modules | yes | clean | — | W2's Box indirection missing ⇒ rustc `E0072` downstream; W10 not instantiating `{T}` across the boundary ⇒ spurious `type` |
| `modules/core/private.agents` — declares enum `Hidden` (case `secret`) and schema `Vault`, exports one function over builtins only | modules | yes | clean | — | removing too much of `:120` (W9.1) ⇒ spurious `rule-2` |
| `modules/text/report.agents` — imports `core/shapes` as `s`; exports `describe : (s/Shape) -> String` and `unit-square : () -> s/Shape` | modules | yes | clean | — | rule 13 checked against the *importing* module ⇒ spurious `rule-13`; this row is what pins §2.5's "defining module" wording |
| `valid/06-module.agents` (existing, edited `:5` to `:export [shout area tally Shape]`) | valid | yes | clean | — | rule 13 not implemented ⇒ row still clean with `Shape` removed, and the phase's real criterion is unmet |
| `valid/09-imported-types.agents` — `s/Shape` in a signature, `match` over `(s/circle r)`, construct `(s/rectangle 1.0 1.0)` | valid | yes | clean | — | W9.5/W9.6 omitted ⇒ `rule-2` from `_ctor`, which via `resolve.py:410` also blanks the type layer |
| `valid/10-imported-generic-types.agents` — `(t/Tree Int64)` in a signature, recursive `match`, `(t/Cell :value 1)`, `.-value` on it | valid | yes | clean | — | `_field_access` not extended ⇒ `rule-2: no record in this module has a field value` |
| `valid/11-name-coexistence.agents` — declares a local `Shape`, imports `core/shapes` under **two** aliases `s` and `sh`, passes a value between the two spellings; a `{Shape}` binder on an unrelated `defun` | valid | yes | clean | — | identity keyed on the alias ⇒ spurious `type` on the `s`↔`sh` hand-off. **The only corpus artifact covering the "two aliases must unify" direction** |
| `valid/12-transitive-use.agents` — imports `text/report` as `r`; one function calls `(r/describe (r/unit-square))` **without** importing `core/shapes`; a second imports `core/shapes` and names `s/Shape` | valid | yes | clean | — | rule 9 read as "every type in a signature I touch must be imported by me" ⇒ spurious `rule-9`; this row pins §2.4 |
| `semantic/export-undefined-type.agents` — `:export [Missing]` | semantic | yes | reject | `rule-2` | W8 splitting the list but not validating `exported_types` ⇒ nothing reported |
| `semantic/export-bare-case.agents` — `:export [circle]`, `Shape` absent from the list | semantic | yes | reject | `rule-2` | `checker/resolve.py:120` allowance left in place ⇒ clean (this fixture is the only thing that pins §2.6) |
| `semantic/private-type-in-exported-signature.agents` — exported `defun` whose parameter is a locally declared, unexported type | semantic | yes | reject | `rule-13` | rule 13 absent ⇒ clean, and `r-ea8c` is falsely resolved. **The phase's acceptance criterion** |
| `semantic/import-unexported-type.agents` — `p/Hidden` from `core/private` | semantic | yes | reject | `rule-9` | `qualified_types()` checking `target.exports` instead of `target.exported_types` ⇒ clean |
| `semantic/import-unexported-case.agents` — `(p/secret)` constructor from `core/private` | semantic | yes | reject | `rule-9` | W9.4's "or a case of an exported enum" written as "or a case of any enum" ⇒ clean |
| `semantic/qualified-ctor-unexported.agents` — `(p/Vault :x 1)` | semantic | yes | reject | `rule-9` | goes through `_ctor` (W9.5), a different code path from `qualified_types()`; an implementation that only did the latter reports `rule-2` here, not `rule-9`, and `; expect-only:` catches it |
| `semantic/wrong-alias-type.agents` — two imports; `Shape` reached through the alias that does not define it | semantic | yes | reject | `rule-9` | "module exists but has no such type" and "has it but does not export it" share one code path; this covers both |
| `semantic/unimported-alias-type.agents` — `q/Shape`, `q` absent from `:import` | semantic | yes | reject | `rule-9` | the new pass not scanning type position at all ⇒ clean |
| `semantic/non-exhaustive-imported-match.agents` — `match` on `s/Shape` omitting `rectangle` | semantic | yes | reject | `rule-4` | `pattern()` fixed but `exhaustive()` left keyed on local `case_owner` ⇒ `rule-2: s/circle is not a case of any union` *plus* `rule-4`; `; expect:` would pass this, `; expect-only:` does not |
| `semantic/mixed-module-match.agents` — arms mix local `(circle r)` and `(s/circle r)` | semantic | yes | reject | `rule-4` | `enums` set at `resolve.py:382` keyed on the bare name ⇒ both collapse to `"Shape"`, `len(enums) > 1` false, **clean** |
| `semantic/imported-type-mismatch.agents` — local `Shape` value passed where `s/Shape` is required | semantic | yes | reject | `type` | `Con` not carrying the defining module ⇒ they unify, clean. **The only fixture that pins §2.3's "different modules must not unify" direction** |
| `semantic/imported-ctor-missing-field.agents` — `(t/Cell)` omitting `value`, which has no `:default` | semantic | yes | reject | `ctor` | `_ctor` resolving the imported schema for the head but validating keys against the local table ⇒ nothing reported |

Notes:

* No `exported-type-without-doc` fixture: §4.0 does not require a `:doc` on a type, only on the
  module and on exported functions (`AGENT_SPEC_CORE.md:653`).
* Every `valid/` fixture is also scanned by `grammar/closure_audit.py:57` (spec + `corpus/valid`).
  Its query (`:32-37`) buckets a qualified head separately and defers it to the checker (`:73-75`),
  and a `ctor` head is not queried at all — so a qualified case constructor will not be reported as
  an undefined head, but the fixture must still use only vocabulary names for everything else.
* `modules/` fixtures are checked clean by `checker/gate.py:35-40` for a reason stated in that file:
  a search-path module that did not itself check clean would make every `rule-9` verdict resting on
  it worthless.

---

## 5. Acceptance gate

All seven were green at the start of the phase (`AGENTS.md:23-41`) and must be green at the end.
Run from the repository root. Each row says what the command does **not** catch, because the reviews
found two places where a stated proof proved nothing.

```bash
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/differential.py
.venv/bin/python -m pytest backend/t bench/algo checker/t -q
```

| command | expected | what it does NOT catch |
|---|---|---|
| `grammar/validate.py` | `0 failure(s)`; no `GRAMMARS DISAGREE`; `corpus/modules` rows present (W5.1); every token-identity probe `ok` (W5.2) | It compares accept/reject **verdicts**, not trees (`:85-90`). Both grammars can accept every fixture while disagreeing about the *shape* around `s/Shape` — W5.2 pins the token, not the surrounding bracketing (ctor vs call, `enum_pattern` head). A general tree-comparison gate stays out of scope. |
| `grammar/closure_audit.py` | `0 undefined heads`; `OK: spec and corpus are closed` | It never scans `bench/` (orchestrator log), and a `ctor` head is not queried at all (`:32-37`), so `(t/Cell :value 1)` is invisible to it in either direction. It says nothing about types. |
| `prelude/generate.py --check` | exit 0 | Only that the generated artifact is not stale. It does not check that the added example is *correct* AgentS — `closure_audit.py` covers the spec's blocks, not `HANDBOOK.md`'s. |
| `checker/gate.py` | `0 failure(s)`; every `modules/` and `valid/` row `clean … ok`; every new semantic row reporting **exactly** its `; expect-only:` code | `:58` is `want in codes` for the pre-existing `; expect:` fixtures, so an old fixture reporting spurious extras still passes (`try-in-lambda` already reports `rule-5,type`). And `resolve.py:410` runs the type layer only `if not self.diags` — a `valid/` row that is clean proves the type layer ran; a `semantic/` row that reports a resolve-layer code proves the type layer **did not**. |
| `backend/check_corpus.py` | `0 failure(s)` **and** the `06-module.agents` row reading `ok` in `compile`, `run` (new, W13.2) and `rustc` | The exit code is not the verdict: `skipped` in a column still exits 0. That is how §1.6 and §1.7 stayed hidden. Even with the `run` column, it exercises one entry point of one fixture — a wrong lowering of a form `06-module` does not use is invisible here. |
| `backend/differential.py` | `0 disagreement(s)`; the new import case in the program table | It compares the two backends against **each other**, not against the specification: a shared misconception (both prefixing with the alias in the same way) agrees and passes. The two-alias requirement in W15 is what makes that particular shared misconception impossible, but only that one. |
| `pytest backend/t bench/algo checker/t -q` | `>= 50 passed` (47 today, + 2 from W10, + W14's cases) | `bench/algo/test_histogram.py:13` and `backend/t/test_smoke.py:10` import **checked-in generated files**; only W14.2's drift assert ties `smoke.py` to its source, and nothing ties `bench/algo/histogram_agents.py` to its source at all. |

Preconditions and non-negotiables:

* `grammar/tree-sitter-agents/src/` regenerated after any `grammar.js` edit (`AGENTS.md:96-100`) —
  `validate.py` will otherwise gate the old parser and report agreement that does not exist.
* Rust is invoked as `rustup run stable <cmd>`; the `~/.cargo/bin` shims are broken
  (`AGENTS.md:19-21`). `backend/check_corpus.py:57` and `backend/differential.py:59,80` already do
  this.
* `bench/harness/run.py:133` is **not** on this list and calls `Transpiler().transpile(code)` on
  text with no file. W11's signature keeps it working; run it once by hand before declaring the
  phase done, because `EXPERIMENT.md` is pre-registered and a silent break there is unrecoverable.

---

## 6. Risks and unknowns

### 6.1 Trait bounds on generic declarations (highest)
W2 emits `Clone` bounds on `defun` type parameters because the emitter clones everywhere — measured
(§1.7). There is **no bound inference**: a generic `defun` whose body uses `=`, `<`, or `list-sort`
over a type variable will still not compile, and no planned fixture exercises it. The conditional
`Eq`/`Ord` derive (W2.4) covers declarations, not function bodies. Related, and also unresolved: the
transitive "does this type support `Eq`" computation must resolve a case parameter naming another
local user type, and the emitter processes `defenum` before `defschema` before `defun`
(`backend/to_rust.py:99-109`), so a forward reference from an enum to a schema is a hazard the
implementer must handle or explicitly reject. If either turns out to need a semantics change to the
emitted code, record it rather than absorbing it.

### 6.2 Grammar drift the gate structurally cannot see
PCP `c-40b5`: `grammar/validate.py:85-90` compares verdicts. **Downgraded from v1's ranking**: both
reviewers independently applied the W3/W4 edits to grammar copies and measured that `s/Shape` is one
token in both grammars in every planned position, that `(/ a b)` is still division, and that
`(module core/deep/mod …)` still lexes as `MOD_PATH`; the uppercase tail makes `QUALIFIED_TYPE`
lexically disjoint from `QUALIFIED`, `MOD_PATH` and `TYPE_NAME`. What remains: `grammar/parse.py:32`
sets `ambiguity="resolve"`, and under `ambiguity="explicit"` the **unmodified** grammar is already
ambiguous for `(s/concat …)` and for *every* `match` form. Correctness rests entirely on `resolve`
plus terminal priority, for the whole grammar, not just this terminal. W5.2 makes the token identity
a gate; the bracketing around it is still ungated.

### 6.3 Bare enum tags in the Python lowering, and cross-boundary equality
§2.8 keeps `("circle", r)` unqualified. The argument that a cross-module tag collision is
unobservable rests entirely on the checker enforcing nominal identity (W10). If W10 ships incomplete,
Python will silently match — or compare `=` equal — a foreign module's case while Rust will not
typecheck it at all, and W15 is the only thing that would catch it. This covers `=` and `Map` key
equality as well as `match`: two values from different modules that share a tag shape are
indistinguishable at the Python runtime and are different types in Rust.

### 6.4 A `{ }` binder shadowing a locally declared type — pre-existing, not fixed here
`checker/types_.py:157` tests `if name in rigid` **before** treating a name as a declared type, so
`(defun {Shape} f [(x Shape)] -> Shape …)` in a module that also declares `Shape` silently types `x`
as the rigid variable. Not created by this phase, not in the `r-ea8c` gap; recorded so it is not
mistaken for something this phase introduced.

### 6.5 Arity of an imported call is unchecked — made reachable by this phase
`checker/resolve.py:235-237` returns before the arity check whenever the callee is not an `IDENT`,
so `(s/circle)` with the wrong argument count gets no `arity` diagnostic from `resolve` — only
whatever `types_.py` happens to catch. Pre-existing; the new fixtures make it reachable for the first
time. Not fixed here; no fixture asserts it.

### 6.6 Module-name collision in the cycle detector — made reachable by this phase
`checker/resolve.py:140-153` keys the visit stack on the module's *declared* name (`stack.append(
mod.name)`, `mod.name` from the header at `collect.py:106`), so two files declaring the same
`(module …)` name are conflated. Pre-existing; a four-module corpus makes it materially more
reachable.

### 6.7 Unverified claims
Stated here rather than in §1-§3, because they were not checked:
* Whether nested `pub mod` blocks coexist with the file-level `mod rt;` at `backend/to_rust.py:98`
  without a `use super::rt;` in each nested module. **This is the most likely W12 surprise.**
* Whether §8's mangling scheme needs a reserved namespace for generated type and module names.
  `agents-` (`AGENT_SPEC_CORE.md:104`) is lowercase-only, so it reserves nothing in `TYPE_NAME`
  space, and §2.8 now generates target module names (`core_shapes`) from user paths. W1 adds the
  collision clause; a reserved prefix would be a language change and is out of scope.
* Whether the transparent-export decision is sufficient for the Phase 3 interface contract
  (`d-f484`), or whether that phase will want opacity after all. §2.1.3 keeps the syntax additive
  against that possibility but does not settle it; `l-880d` (ownership) has to land first.
* Struck from v1's list, now resolved: tree-sitter's `word: $ => $.ident` (`grammar.js:22`) already
  coexists with the `qualified` regex token (`:236`), which has the same shape as `qualified_type`;
  keyword extraction applies to anonymous string tokens. And `checker/t/test_types.py` was read —
  16 tests, `Con(name, args)` called positionally at `:44,:50,:55`, so a third positional field
  breaks nothing (§2.3).

---

## 7. PCP entries to record

Write after the work holds, not before. One line each; entries carry motivation and decisions, never
code or file maps (`ROADMAP.md:259-260`).

1. **`d-…` Types cross a module boundary on the existing export list, alias-qualified.** Why one
   contract rather than a second `:export-types` vector, and why the member's case decides its kind —
   against `d-f99b` and `AGENT_SPEC_CORE.md:88-89`. Names the deliberate exception to
   `ROADMAP.md:79-80`'s "never because of how it is spelled".
2. **`d-…` Type identity is nominal, keyed by defining module and name, never by alias.** Why
   structural identity is incompatible with tagged unions, and why an alias cannot participate in
   identity when aliases are module-local.
3. **`d-…` An exported type is transparent; opacity is deferred and the syntax left additive.**
   Exhaustive `match` forces it — an importer that cannot see every case cannot write a total match.
   The stronger reason is `l-880d`: the opaque form is an abstract handle, and deciding it now would
   decide the unrecorded ownership model by accident. **Records the narrowing of `d-f99b`**: the
   export list names the surface; for a type, the declaration completes it, and a mechanical
   extractor now reads header plus exported-type declarations.
4. **`d-…` An exported signature may only name public types (rule 13).** Why this and not the
   lexical fix is what makes the header an interface contract (`d-f484`, `.pcp/lang/wasm.md:8-11`),
   why it needs its own diagnostic code rather than an extension of rule 2, and that it forced one
   corpus fixture and one test fixture to widen their export lists.
5. **`d-…` Backends link the import closure into one output unit** rather than emitting one target
   module per AgentS module. What that buys (every gate keeps driving a single artifact) and what it
   costs (no separate compilation, no per-module target packaging — revisit at the Wasm target).
6. **`c-…` The Rust lowering dropped every `{ }` binder — `defenum`, `defschema` *and* `defun` —
   had no indirection for a recursive case, and derived `Eq`/`Ord` on records unconditionally while
   deriving neither on unions.** 13 rustc errors on one fixture. Invisible because that fixture was
   on the backend gate's skip list, and a skip-list entry reads as a known gap rather than as an
   untested defect. Names the Phase 2 link: the same missing derives blocked 8 builtins.
7. **`c-…` A gate that asserts `want in codes` lets a half-implemented rule pass with spurious
   company**, and `py_compile` accepts a wrong lowering that is syntactically well-formed. Records
   the two hardenings (`; expect-only:`, the `run` column) and that the conformance gate still
   compares verdicts rather than trees, now with a token-identity assertion in front of it.
8. **`r-ea8c` → Resolved**, with an update line naming what closed it — the export list admits type
   names, `alias/TypeName` is a lexeme, the checker resolves types across the boundary, **and rule 13
   forces an exported signature's types to be public** — and what it deliberately did not close:
   opacity, separate compilation, arity of an imported call (§6.5), and the cycle detector's
   declared-name keying (§6.6).
