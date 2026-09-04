# Phase 9 — Self-Hosted Semantic Type Checker (`packages/asl-checker`) in Pure AgentScript (asl-selfhosted-runtime-v1)

*Drafted under the steps protocol (@pcp:d-8d4c). Pure AgentScript self-hosted implementation of §9 semantic rules, module resolution, and Hindley-Milner type inference.*

## Acceptance Criterion

```
.venv/bin/python checker/gate.py --native && .venv/bin/python -m pytest tools/tests/test_native_checker.py -q && ./asl check grammar/corpus/valid/01-basics.agentscript
```

Transpiled `packages/asl-checker` (via `tools/native_checker.py` and `./asl check --native` / `gate.py --native`) checks:
1. All 36 `grammar/corpus/valid/*.agentscript` files and 6 `grammar/corpus/modules/**/*.agentscript` files clean (0 diagnostics).
2. All 47 `grammar/corpus/semantic/**/*.agentscript` fixtures, asserting each fixture's declared `"expect:"` or `"expect-only:"` diagnostic code across all 20 rule categories.
3. All 40 `packages/**/*.asl` package sources clean (0 diagnostics).
4. `tools/tests/test_native_checker.py` passes 100% with pairwise equivalence against Python `checker/resolve.py:check_file`.

---

## Context & Motivation

Phase 7 delivered a 100% self-hosted parser and S-expression reader (`packages/asl-parser`). Phase 8 migrated the closure audit off tree-sitter onto the native AST. Phase 9 self-hosts the semantic checker itself: implementing AGENT_SPEC_CORE §9 semantic rules and Hindley-Milner type inference in pure AgentScript (`packages/asl-checker`).

Today, semantic checking is performed by Python modules:
- `checker/collect.py` (Pass 1: AST declaration collection into `Module` summary).
- `checker/resolve.py` (Pass 1 & Pass 2: module rules, symbol resolution, scoping, arity, totality, effects).
- `checker/types_.py` (Pass 3: Hindley-Milner type inference, unification, literals, map-key ordering, try-in-Result).

Migrating this to pure AgentScript removes the Python checker dependency from the self-hosted compilation pipeline (Phase 10), completing the front-end bootstrap requirement.

---

## Core Invariants

1. **Pass Decoupling & Gated Synthesis (`checker/resolve.py:639-640`)**:
   Pass 1 (module-level validation) and Pass 2 (symbol & structural resolution) run before Pass 3 (type synthesis and HM unification). If Pass 1 or Pass 2 records any diagnostic, Pass 3 **must not run**. Running inference on an unbound name or unresolvable module produces cascading `type` errors that violate `"expect-only:"` fixture contracts (e.g. `semantic/unbound-name.agentscript`, `semantic/export-bare-case.agentscript`).

2. **Purely Functional Immutability & Defun-Local Scoping (`backend/runtime.py:254-260`)**:
   In the Python checker, `Var.ref` was mutated in place (`var.ref = other`). ASL has no in-place mutation or pointers. Metavariable substitutions must be threaded as an immutable `Subst` record `(Map Int64 Type)`. Metavariable IDs must be total integers (`Int64`) to satisfy the Map key total ordering requirement. Because all top-level functions declare parameter and return types, metavariables never escape a function boundary; `Subst` is scoped per `defun` to prevent unbounded dictionary growth and map copying overhead.

3. **Stack Frame Bound & Iterative Worklist Machine (`packages/asl-parser/src/reader.asl:109-122`)**:
   Transpiled ASL runs on Python with a default 1000-frame recursion limit. Deeply nested AST expressions (e.g. 2000-deep arithmetic expressions) overflow the Python call stack if evaluated recursively. Expression evaluation in Pass 3 must be executed via an explicit evaluation frame stack machine driven by a doubling-budget worklist loop (`infer-run` / `infer-tick`), ensuring execution completes in $O(\log N)$ call frames.

4. **Map Key Total Ordering (`checker/types_.py:38,325,352-375`)**:
   Map keys require total order. Types reaching `Float64` (IEEE-754 NaN has no total order) or `IoError` (opaque host pointer) must be rejected with diagnostic `map-key-order`. This includes nested member types in user schemas (`defschema`) and user enums (`defenum`), whether explicitly annotated or inferred through metavariables. All types recorded in `map-sites` must be resolved through `apply-subst subst ty` before evaluating `unordered?`.

5. **Fixed Integer Literal Ranges (`checker/types_.py:44,381-389`)**:
   Unsuffixed integer literals take contextual width (`Int32` or `Int64`, default `Int64`). Literals outside range `[-2^31, 2^31 - 1]` for `Int32` or `[-2^63, 2^63 - 1]` for `Int64` must emit diagnostic `literal-range`.

6. **Defun-Scoped `try` Form (`checker/types_.py:576-589`)**:
   `try` unwraps `Result` and early-returns errors from the enclosing `defun`. Using `try` inside a `fn` lambda or inside a `defun` whose return type is not `(Result _ E)` must emit diagnostic `rule-5`.

7. **Export Visibility & Private Type Leaks (`checker/resolve.py:240-273`)**:
   Exported signatures cannot reference private local types (`rule-13`). Exported members must be explicitly declared in the module `:export` vector, and exported types must be PascalCase (`rule-2`).

8. **Rule 12 Effect Invariant & Purity Separation (`prelude/prelude.json:1364-1374`, `checker/resolve.py:534-547`)**:
   The AST semantic type checker (`check-module`, `check-source`) is purely functional: it takes an in-memory map of module summaries `(Map String ModuleSummary)` and returns diagnostics without performing filesystem I/O. File loading and dependency discovery are isolated in dedicated effectful functions marked with `!` (`check-file!`, `load-module-deps!`).

---

## Failure Modes & Concrete Interleavings

- **FM-1: Loss of Unification State via Dropped Map Threading**:
  In an expression `(f (fn [x] (+ x 1)) 42)` where `f` has signature `{A} ((fn [A] -> A) A -> A)`. Fresh metavar `?1` is bound to `Int64` when checking argument 1. If the updated `Subst` is not threaded into argument 2, argument 2 unifies `?1` freshly or against an unconstrained variable, leaving `A` undetermined and triggering a spurious `annotation` diagnostic.
  *Prevention*: `infer-expr` threads an `InferState` record carrying the accumulating `(Map Int64 Type)`.

- **FM-2: Stack Overflow on Deep AST Nesting**:
  A deeply chained expression `(+ 1 (+ 1 (+ 1 ...)))` at depth > 1000 frames. If `infer-expr` is implemented with naive recursive function calls, Python crashes with `RecursionError: maximum recursion depth exceeded`.
  *Prevention*: Flatten expression evaluation using an explicit evaluation frame stack machine with iterative doubling-budget queues (`infer-run` / `infer-tick`), running in $O(\log N)$ stack frames.

- **FM-3: Spurious Cascading Errors on Broken Resolution**:
  A file has `(df g [] -> Int64 (+ x 1))` where `x` is unbound (`rule-2`). If Pass 3 runs despite the Pass 2 error, `x` is either treated as unknown or fails type lookup, reporting `type: expected Int64, found unknown`. The gate for `semantic/unbound-name.agentscript` asserts `"expect-only: rule-2"` and fails if `type` is also reported.
  *Prevention*: Invariant 1 gate check: Pass 3 is strictly bypassed if Pass 1 or Pass 2 has non-empty diagnostics.

- **FM-4: Occurs Check Bypass & Cyclic Substitution**:
  Unifying `?1` with `(List ?1)` or transitively chained metavars. If `occurs-in?` is omitted or fails to recursively prune subterms via `apply-subst`, cyclic substitution causes infinite loops during type printing or map key checks.
  *Prevention*: `occurs-in?` prunes every subterm through `apply-subst` and checks whether the metavar ID appears inside before extending `Subst`.

- **FM-5: Shallow Map Key Check Missing Inferred Keys or Record Field Transitivity**:
  An inferred map key (e.g. `(map-from-pairs pairs)` where `pairs` yields key `Float64`) or nested schema key. If `map-key-rules` inspects `map-sites` without first applying `apply-subst subst ty`, or fails to inspect schema fields with cycle detection, `Float64` escapes detection.
  *Prevention*: `map-key-rules` resolves all types via `apply-subst` before calling `map-keys` and recursively checks member fields of schemas and cases of enums with cycle detection.

---

## Sequential Ordering & Dependencies

The work is strictly ordered to prevent building on unverified representations:
```
Item 1 (asl.json, types.asl, harness.py)
   │
   ▼
Item 2 (unify.asl: functional HM unification & occurs check)
   │
   ▼
Item 3 (resolve.asl: Passes 1 & 2 module/scope/symbol/rules)
   │
   ▼
Item 4 (check.asl: Pass 3 inference, gates & entry points)
   │
   ▼
Item 5 (native_checker.py, agentscript CLI & parity pytest)
   │
   ▼
Item 6 (checker/gate.py --native & full battery sweep)
```
- Item 2 depends on Item 1 for `Type`, `BuiltinSig`, and type string parsing.
- Item 3 depends on Item 1 for module summaries, diagnostics, and AST nodes.
- Item 4 depends on Items 2 and 3 for unification and Pass 1/2 environments.
- Item 5 depends on Item 4 for executable `check-source` and `check-file!`.
- Item 6 depends on Item 5 for the Python bridge to plug into CI gates.

---

## Work Items

### Item 1 — Package Manifest, Type AST & Builtins Representation (`packages/asl-checker`)

**What.**
1. Create `packages/asl-checker/asl.json`:
   Package manifest `@genseam/asl-checker`, version 1.0.0, entry `src/check.asl`, dependency `@genseam/asl-parser`.
2. Create `packages/asl-checker/src/types.asl`:
   - Data structures:
     - `Type` enum:
       - `ty-con [(name String) (args (List Type)) (mod (Option String)) (shown (Option String))]`
       - `ty-var [(id Int64) (kind String)]` (`kind`: `"any"`, `"num"`, `"int"`)
       - `ty-fun [(params (List Type)) (ret Type)]`
     - `Diagnostic` schema:
       - `(:f code String)`
       - `(:f message String)`
       - `(:f line Int64)`
       - `(:f col Int64)`
       - `(:f path String)`
       - Source coordinate fallback: diagnostics inherit `line` and `col` from the enclosing `PosForm` when available; unlocated subexpressions default to `0, 0`.
     - `parse-type-str [(s String) (typevars (List String))] -> Type`:
       Parses canonical type strings (e.g. `(List Int64)`, `(Result A String)`, `(fn [Int64] -> Bool)`) into `Type` trees. Maps type aliases (`Int` -> `Int64`, `Num` -> `Float64`, `Str` -> `String`). Names in `typevars` parse as `ty-var`.
     - `show-type [(t Type)] -> String`:
       Renders `Type` back to canonical human string (e.g. `_`, `a number`, `an integer`, `(fn [Int64] -> Bool)`).
     - Static lookup tables (mirrored from `prelude/prelude.json` per `@pcp:c-adc8`):
       - `builtin-sig [(name String)] -> (Option (Pair (List String) (Pair Bool String)))`:
         Returns `(params, (variadic, return-type))` for all 107 §6 builtins.
       - `unordered-type? [(name String)] -> Bool`:
         Returns true for `"Float64"` and `"IoError"`.
       - `int-range-bounds [(name String)] -> (Option (Pair Int64 Int64))`:
         Returns `(-2147483648, 2147483647)` for `"Int32"` and `(-9223372036854775808, 9223372036854775807)` for `"Int64"`.
       - `prelude-union-cases [(case-name String)] -> (Option String)`:
         Maps `some`/`none` -> `"Option"`, `ok`/`err` -> `"Result"`, `list`/`cons` -> `"List"`, `not-found`/`other` etc. -> `"IoError"`.
3. Create `packages/asl-checker/tests/harness.py`:
   Transpilation harness linking `packages/asl-checker/src` and `packages/asl-parser/src`.
4. Create test driver `packages/asl-checker/tests/types_test.asl`:
   Exports `test-types` verifying parsing, rendering, alias resolution, and builtin signatures.

**Why.**
All downstream passes require the algebraic representation of types, diagnostic formatting, and builtin vocabulary.

**Gate.** Fails now with `ModuleNotFoundError: No module named 'harness'`; passes when done.
```
.venv/bin/python -c "import sys; from pathlib import Path; sys.path.insert(0, 'packages/asl-checker/tests'); from harness import run_asl; d = run_asl('packages/asl-checker/tests/types_test.asl'); assert d['test_types']() == 'ok'"
```
Current verbatim output:
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import sys; from pathlib import Path; sys.path.insert(0, 'packages/asl-checker/tests'); from harness import run_asl; d = run_asl('packages/asl-checker/tests/types_test.asl'); assert d['test_types']() == 'ok'
                                                                                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'harness'
```

---

### Item 2 — Purely Functional Hindley-Milner Unification (`src/unify.asl`)

**What.**
Create `packages/asl-checker/src/unify.asl`:
- Functional substitution `Subst`: represented as `(Map Int64 Type)`.
- Core functions:
  - `apply-subst [(subst (Map Int64 Type)) (ty Type)] -> Type`:
    Iteratively resolves metavar chains in `ty` until a fixed point or non-bound metavar is reached.
  - `occurs-in? [(id Int64) (ty Type) (subst (Map Int64 Type))] -> Bool`:
    Prunes `ty` via `apply-subst subst ty`. If `ty` is `(ty-var id2 _)`, returns `id == id2`. Traverses child arguments of `ty-con` and `ty-fun`, pruning each child subterm via `apply-subst` before testing or recursing, ensuring transitively chained metavars cannot introduce hidden cycles.
  - `kind-narrow [(k1 String) (k2 String)] -> (Option String)`:
    Lattice order: `any < num < int`. Returns narrowed kind or `none` if incompatible.
  - `is-numeric-type? [(name String)] -> Bool`: True for `Int32`, `Int64`, `Float64`.
  - `is-integral-type? [(name String)] -> Bool`: True for `Int32`, `Int64`.
  - `(dfe UnifyOutcome (:c u-ok [(subst (Map Int64 Type))]) (:c u-err [(msg String) (numeric Bool)]))`:
    Returns updated immutable substitution or structured mismatch.
  - `unify [(t1 Type) (t2 Type) (subst (Map Int64 Type))] -> UnifyOutcome`:
    - Prunes `t1` and `t2` via `apply-subst`.
    - If both are identical, return `(u-ok subst)`.
    - If `t1` is `ty-var id`:
      - If `t2` is `ty-var id2`: narrow kinds via `kind-narrow`. If compatible, `map-set subst id (ty-var id2 narrowed-kind)`. If incompatible, return `(u-err "kind mismatch" false)`.
      - If `t2` is `ty-con`: check if allowed by `kind` (`num` requires `is-numeric-type?`, `int` requires `is-integral-type?`). Check `occurs-in? id t2 subst`. If clean, `map-set subst id t2`. If kind disallowed, return `(u-err "type mismatch" is-numeric)`.
      - If `t2` is `ty-fun`: if `kind == "any"`, check `occurs-in? id t2 subst`. If clean, `map-set subst id t2`. If `kind` is `"num"` or `"int"`, return `(u-err "cannot unify function with numeric kind" false)`.
    - If `t2` is `ty-var`: symmetric handling.
    - If both are `ty-con`: verify `name == name2`, `mod == mod2`, `args.length == args2.length`. Fold `unify` across child arguments threading `subst`. If mismatched and both are numeric, flag `numeric: true` (for `rule-6`).
    - If both are `ty-fun`: verify parameter lengths match, fold `unify` across parameters, then unify return types.
- Create test driver `packages/asl-checker/tests/unify_test.asl`:
  Tests metavar binding, occurs-check failure, kind narrowing, numeric mismatch distinction (`rule-6`), higher-order function unification, and map-key threading.

**Why.**
Hindley-Milner unification with immutable substitution is the mathematical core of ASL's type inference.

**Gate.** Fails now with `ModuleNotFoundError: No module named 'harness'`; passes when done.
```
.venv/bin/python -c "import sys; from pathlib import Path; sys.path.insert(0, 'packages/asl-checker/tests'); from harness import run_asl; d = run_asl('packages/asl-checker/tests/unify_test.asl'); assert d['test_unify']() == 'ok'"
```

---

### Item 3 — Pass 1 & Pass 2 Symbol Resolution & Rule Checks (`src/resolve.asl`)

**What.**
Create `packages/asl-checker/src/resolve.asl`:
- Module Summary Collection:
  - Input: `(List a/TopForm)` parsed by `a/parse`.
  - Collects `funs`, `schemas`, `enums`, `imports`, `exports`, `exported-types`, `exported-cases`, `exported-fields`.
  - Sets represented as `(Map String Bool)` for $O(1)$ membership checks, and `(List String)` for ordered scope and dependency chains.
- Dependency Loading (Rule 12 effect separation):
  - Pure resolution assumes pre-loaded module summaries `deps: (Map String ModuleSummary)`.
  - Effectful loader `(df ! load-module-deps! [(roots (List String)) (imports (List String))] -> (Result (Map String ModuleSummary) IoError))` searches filesystem (`.agentscript` and `.asl`), parses headers, and populates `deps`.
- Pass 1: Module-level semantic checks:
  - `unresolved-import`: imported module not present in `deps` or search roots.
  - `rule-8`: Missing `:doc` on module header (`.-has-header` and empty `docstring`) or on exported function (`is-exported` and empty `docstring`).
  - `rule-2`: Name in `:export` not defined in module; type in `:export` not defined in module.
  - `rule-7`: Reserved identifier check (`agentscript-` prefix).
  - `rule-11`: Cyclic imports check: iterative DFS cycle detector across module import dependencies using `(Map String Bool)` visited set.
  - `rule-9`: Unimported alias; unexported member or type; unexported qualified constructor.
  - `rule-13`: Private type in exported signature: local schema/enum referenced in exported defun param/ret or exported schema field without being in `:export`.
  - `rule-10`: Unbound type variable in signature: type name in annotation that is neither a known builtin/declared type nor bound in enclosing `{ }`.
  - `type-arity`: Type constructor argument count mismatch against declared arity (`CONSTRUCTOR_ARITY` or schema/enum typevars length).
- Pass 2: Body symbol resolution & structural rules:
  - Lexical scope tracking with `(Map String Bool)` for bound variable names and `(List (Map String Bool))` for scope stack.
  - `rule-2`: Unbound identifier in expression, unknown record constructor, unknown pattern case.
  - `rule-12`: Effect in pure defun or pure lambda: effectful callee called inside a defun or lambda not marked `!`.
  - `builtin-reference`: Builtin name in value/argument position without wrapping `fn`.
  - `not-callable`: Literal in call head e.g. `(-1 2)` where head atom is integer/float/string/bool/unit.
  - `arity`: Callee arity mismatch against declared parameter count; pattern arity mismatch.
  - `ctor`: Record constructor missing non-defaulted fields, duplicate field keys, or unknown field keys.
  - `rule-4`: Match pattern exhaustiveness and union coherence: arms mix different unions or miss unhandled union cases.
- Create test driver `packages/asl-checker/tests/resolve_test.asl`:
  Asserts diagnostic codes across representative probe sources for all Pass 1 and Pass 2 rules.

**Why.**
Pass 1 and Pass 2 enforce syntax-adjacent semantics, name visibility, and scoping rules, protecting Pass 3 from unbound or ill-formed modules.

**Gate.** Fails now with `ModuleNotFoundError: No module named 'harness'`; passes when done.
```
.venv/bin/python -c "import sys; from pathlib import Path; sys.path.insert(0, 'packages/asl-checker/tests'); from harness import run_asl; d = run_asl('packages/asl-checker/tests/resolve_test.asl'); assert d['test_resolve']() == 'ok'"
```

---

### Item 4 — Pass 3 Expression Type Inference & Semantic Gate (`src/check.asl`)

**What.**
Create `packages/asl-checker/src/check.asl`:
- `InferState`:
  - `subst`: `(Map Int64 Type)` (scoped per `defun`, reset after each top-level function)
  - `next-var`: `Int64` (scoped per `defun`, reset after each top-level function)
  - `int-sites`: `(List (Pair String Int64))` (literal token string, metavar ID)
  - `map-sites`: `(List (Pair Type String))` (inferred types, scope label)
  - `lambdas`: `(List (Pair (List Type) Type))` (inferred lambda parameter and return types)
  - `diags`: `(List Diagnostic)`
- Non-Recursive Evaluation Frame Stack Machine:
  - To eliminate `RecursionError` on deeply nested expressions (e.g. 2000-deep arithmetic calls), `infer-expr` avoids deep call-stack recursion by using an explicit evaluation frame stack:
    - Frame variants:
      - `f-eval [(expr rd/SExpr)]` (evaluate expression next)
      - `f-call [(callee Type) (args-done (List Type)) (args-pending (List rd/SExpr)) (pos Int64)]` (call argument evaluation continuation)
      - `f-let [(name String) (tail (List rd/SExpr))]` (let-binding continuation)
      - `f-if [(then-expr rd/SExpr) (else-expr rd/SExpr)]` (branch continuation)
      - `f-try [(enclosing-ret Type)]` (try continuation)
    - Worklist driver: `(df infer-run [(frames (List InferFrame)) (values (List Type)) (st InferState) (budget Int64)] -> (Pair (List Type) InferState))`
      Executes frames in doubling-budget batches via `infer-tick`, reducing call-stack depth to $O(\log N)$ frames.
- Pass 3 Expression Inference over `rd/SExpr` bodies:
  - Literals:
    - Integer: creates fresh metavar `(ty-var id "int")`, records in `int-sites`.
    - Float: `(ty-con "Float64" (list) (none) (none))`.
    - String: `(ty-con "String" (list) (none) (none))`.
    - Bool: `(ty-con "Bool" (list) (none) (none))`.
    - Unit: `(ty-con "Unit" (list) (none) (none))`.
  - Variables & qualified names: environment lookup, instantiation of type variables with fresh metavars.
  - Calls: Callee type inference. Unifies arguments against parameter types. If unification reports numeric mismatch, emit `rule-6`; otherwise emit `type`.
  - Let forms: sequential binding inference, extending lexical type environment.
  - If & Cond forms: condition expression unifies with `Bool`; branch expressions unify with each other.
  - Fn forms: lambda parameter metavars (fresh if elided), return type metavar, body inference. Records lambda in `lambdas`.
  - Try forms (`rule-5`):
    - Disallows `try` inside `fn` lambda (returns from enclosing defun).
    - Checks enclosing `defun` declared return type is `(Result T E)`.
    - Unifies inner expression with `(Result V E)` and yields `V`.
  - Constructors (`ctor`): unifies field argument expressions with declared schema field types.
  - Field access (`.-field`):
    - Record field access: unifies target with schema, yields field type.
    - Pair field access: `.-first` yields `T1`, `.-second` yields `T2`.
  - Match forms: scrutinee inference, pattern type extraction, arm body unification against result metavar.
- Post-Inference Validation Passes:
  - `undetermined-lambdas`: if any lambda parameter or return remains an unconstrained metavar (`ty-var`), emit `annotation`.
  - `map-key-rules`: inspects all types in `map-sites`. For every `(Pair Type String)` site, first resolves the type through `apply-subst subst ty`. Recursively extracts map key types via `map-keys`. For each key type `K`, evaluates `unordered? K` (inspecting user schemas and enums with a `(Map String Bool)` visited set). Emits `map-key-order` if `Float64` or `IoError` is reachable.
  - `literal-ranges`: inspects all literals in `int-sites`. Resolves width metavar via `apply-subst`: if `Int32`, checks `[-2^31, 2^31 - 1]`; if `Int64` or unconstrained, checks `[-2^63, 2^63 - 1]`. Emits `literal-range` on overflow.
- Main Entry Points (Rule 12 Effect Separation):
  - Pure functions:
    - `check-module [(forms (List a/TopForm)) (deps (Map String ModuleSummary)) (path String)] -> (List Diagnostic)`:
      Runs Pass 1 & 2. If diagnostics exist, returns them immediately (Invariant 1). Otherwise runs Pass 3 (scoping `subst` per `df`) and returns all diagnostics sorted by line, col, code.
    - `check-source [(src String) (deps (Map String ModuleSummary)) (path String)] -> (List Diagnostic)`:
      Parses `src` via `a/parse src`:
      - On `(ok forms)`: runs `check-module forms deps path`.
      - On `(err pe)`: returns `(list (Diagnostic :code "parse" :message (.-msg pe) :line (.-line pe) :col (.-col pe) :path path))`.
  - Effectful functions:
    - `(df ! check-file! [(path String) (roots (List String))] -> (Result (List Diagnostic) IoError))`:
      Reads source file via `file-read`, parses module header, resolves and loads dependency summaries via `load-module-deps!`, and runs pure `check-module`.
- Test Driver `packages/asl-checker/tests/checker_test.asl`:
  Exports `check-source`, `check-file!`, and `test-corpus-smoke`.

**Why.**
Pass 3 completes Hindley-Milner type inference, totality checks, and post-inference semantic rules while upholding Rule 12 effect separation.

**Gate.** Fails now with `ModuleNotFoundError: No module named 'harness'`; passes when done.
```
.venv/bin/python -c "import sys; from pathlib import Path; sys.path.insert(0, 'packages/asl-checker/tests'); from harness import run_asl; d = run_asl('packages/asl-checker/tests/checker_test.asl'); res = d['check_source']('(module m :d \"d\" :x [f]) (df f [] -> Int64 42)', {}, 'm.asl'); assert res == [], res"
```

---

### Item 5 — Python Bridge (`tools/native_checker.py`), CLI Integration (`agentscript`), and Equivalence Suite (`tools/tests/test_native_checker.py`)

**What.**
1. Create `tools/native_checker.py`:
   - Singleton cached driver pattern mirroring `tools/native_parser.py`.
   - Loads `packages/asl-checker/tests/checker_test.asl` via `run_asl`.
   - Exposes:
     - `native_check_source(src: str, path: str = "<source>", roots: list[Path] | None = None) -> list[Diagnostic]`
     - `native_check_file(path: Path, roots: list[Path] | None = None) -> list[Diagnostic]`
   - Unwraps ASL `Diagnostic` records into `checker.resolve.Diagnostic` objects.
2. Update `agentscript` CLI:
   - In `cmd_check` (`agentscript:87-123`), add `--native` argument.
   - When `--native` is active (or set by default), invoke `native_check_file`.
3. Create `tools/tests/test_native_checker.py`:
   - Parity test suite mirroring `tools/tests/test_native_parity.py`:
     1. `test_valid_corpus_checks_clean`: Every file in `grammar/corpus/valid/*.agentscript` returns 0 diagnostics.
     2. `test_semantic_fixtures_reject_with_expected_code`: Every fixture in `grammar/corpus/semantic/**/*.agentscript` matches its `"expect:"` or `"expect-only:"` declared code across all 20 rule categories.
     3. `test_packages_check_clean`: Every `.asl` source in `packages/**/*.asl` returns 0 diagnostics.
     4. `test_python_checker_equivalence`: For every file in valid, semantic, and packages, asserts that `native_check_file(p)` output matches `checker.resolve.check_file(p)` diagnostic codes.
     5. `test_iterative_depth_safety`: Evaluates a 2000-deep nested expression `(+ 1 (+ 1 ...))` to verify no `RecursionError` occurs under the Python runtime stack limit.
     6. `test_checker_static_tables_match_prelude`: Asserts that `types.asl` lookup tables (`builtin-sig`, `unordered-type?`, `int-range-bounds`, `prelude-union-cases`) match `prelude/vocab.py` and `prelude/prelude.json` per `@pcp:c-adc8`.

**Why.**
Provides Python toolchain and CLI consumers access to the self-hosted checker, and guarantees 100% equivalence across the entire existing test corpus.

**Gate.** Fails now with `ERROR: file or directory not found: tools/tests/test_native_checker.py`; passes when done.
```
.venv/bin/python -m pytest tools/tests/test_native_checker.py -q
```

---

### Item 6 — Primary CI Gate `--native` Mode & Full Battery Regression Sweep

**What.**
1. Update `checker/gate.py`:
   - Add `--native` CLI argument support (`sys.argv`).
   - When `--native` is supplied, use `tools.native_checker.native_check_file` as the checker function for valid corpus, semantic corpus, and package sources.
2. Run full repository gate sweep:
   - `grammar/validate.py`
   - `grammar/closure_audit.py`
   - `prelude/generate.py --check`
   - `checker/gate.py` (legacy Python checker)
   - `checker/gate.py --native` (self-hosted native checker)
   - `bench/token_frames.py --check`
   - `bench/token_projection.py --check`
   - `backend/check_corpus.py`
   - `backend/monomorphism.py`
   - `backend/differential.py`
   - `pytest tools/tests/test_native_checker.py` and full pytest battery.

**Why.**
Ensures the native checker passes the official project gate in CI and causes zero regressions across the codebase.

**Gate.** Fails now with `ModuleNotFoundError: No module named 'tools.native_checker'`; passes when done.
```
.venv/bin/python -c "from tools.native_checker import native_check_file; from checker.gate import main; import sys; sys.argv.append('--native'); sys.exit(main())" && .venv/bin/python -m pytest tools/tests/test_native_checker.py -q
```
Current verbatim output:
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    from tools.native_checker import native_check_file; from checker.gate import main; import sys; sys.argv.append('--native'); sys.exit(main())
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'tools.native_checker'
```

---

## Measured Corpus Baseline (This Session)

Verified and measured directly on the active repository:
- `grammar/corpus/valid/*.agentscript`: **36** files
- `grammar/corpus/modules/**/*.agentscript`: **6** files
- `grammar/corpus/semantic/**/*.agentscript`: **47** fixtures
  - Diagnostic breakdown:
    - `annotation`: 1
    - `arity`: 3
    - `builtin-reference`: 2
    - `ctor`: 1
    - `literal-range`: 2
    - `map-key-order`: 6
    - `not-callable`: 1
    - `rule-10`: 1
    - `rule-11`: 2
    - `rule-12`: 2
    - `rule-13`: 1
    - `rule-2`: 5
    - `rule-4`: 4
    - `rule-5`: 2
    - `rule-6`: 1
    - `rule-7`: 1
    - `rule-8`: 1
    - `rule-9`: 6
    - `type`: 3
    - `type-arity`: 2
- `packages/**/*.asl`: **40** files
- Total files checked by `checker/gate.py`: **129** files.

---

## Risks & Mitigations

- **Risk 1: Transpiled ASL runtime performance on 129 files**.
  *Assessment*: `packages/asl-checker` transpiles to Python via `Transpiler().transpile(...)` and is compiled with `py_compile`. Transpiling 129 files sequentially in a single process could add seconds to gate runtime.
  *Mitigation*: Caching the transpiled driver module via `_driver()` singleton in `tools/native_checker.py` means compilation occurs exactly once per test session. The 129 files then execute as compiled Python bytecode.
- **Risk 2: Node Span and Position Accuracy on S-Expressions**.
  *Assessment*: The parser (`packages/asl-parser/src/ast.asl`) attaches line/col to `PosForm` top-level declarations and `ParseError`, but inner expressions in `DefunNode.body` are generic `rd/SExpr`.
  *Mitigation*: The semantic test harness tests exact diagnostic codes (e.g. `rule-4`, `map-key-order`) and file paths. For line/col inside bodies, diagnostics inherit the enclosing `PosForm` coordinates or default to `0, 0`. `checker/gate.py` asserts diagnostic code matching (`d.code == want`).
- **Risk 3: Memory footprint of immutable substitutions**.
  *Assessment*: Functional `(Map Int64 Type)` creates new map copies on each `map-set`.
  *Mitigation*: Substitutions and `next-var` are scoped per function definition (`df`) rather than accumulated across the entire module, bounding dictionary size and minimizing map copying overhead.
- **Risk 4: Deep AST nesting stack overflow**.
  *Assessment*: Default Python recursion limit is 1000 frames; deep arithmetic nesting exceeds this.
  *Mitigation*: Pass 3 evaluates expressions iteratively using an evaluation frame stack (`InferFrame`) driven by doubling-budget execution loops (`infer-run` / `infer-tick`), completing in $O(\log N)$ stack frames.

---

## Out of Scope

- Self-hosted backend compiler / native binary generation (deferred to Phase 10 `packages/asl-compiler`).
- Tree-sitter C syntax highlighting grammar modifications (VS Code highlighting preserved).
- Lark grammar modifications (retained for external constrained decoders).
- Mutating existing `prelude/prelude.json` vocabulary.
