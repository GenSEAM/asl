# REVIEW-arch — Phase 9 PLAN.md, lens: architectural correctness, runtime limits & memory/recursion feasibility

**Verdict: reject**

## Summary

The plan demonstrates a strong grasp of the three-pass architecture, diagnostic parity, and the need for immutable substitution in pure AgentScript. Core citations across `checker/resolve.py`, `checker/types_.py`, `backend/runtime.py`, and `packages/asl-parser` were verified line-by-line against the repository, and the 129-file baseline was reproduced cleanly with zero failures.

However, the plan has 5 blocking defects across architectural correctness, language constraints, and runtime execution:
1. **Broken Acceptance Criterion**: Cites a non-existent file (`01-primitives.agentscript` instead of `01-basics.agentscript`), causing the acceptance command to fail immediately on a clean tree.
2. **Rule 12 Effect Violation in Module Resolution**: Resolving imported modules from disk uses effectful I/O builtins (`file-exists?`, `file-read`), but `check-module` and `check-source` are declared as pure functions without the required `!` effect annotation, causing the checker to reject itself under Rule 12.
3. **Incomplete Hindley-Milner Unification for Function Types**: Item 2's specification for unifying `ty-var` handles only `ty-var` and `ty-con`, omitting `ty-fun`. This breaks type inference for higher-order functions and callback parameters.
4. **Under-specified Worklist Machine for Deep Expression Recursion**: Core Invariant 3 and FM-2 note the 1000-frame Python recursion limit and add a 2000-deep test, but FM-2's mitigation misleadingly suggests `fold` for sequential children (which does not flatten vertical call nesting). Item 4 lacks the explicit evaluation frame stack / worklist state machine required to prevent `RecursionError`.
5. **Missing Substitution Application in Post-Inference Map Key Rules**: Types recorded in `map-sites` retain uninstantiated metavars; failing to explicitly apply `apply-subst` prior to `unordered?` allows unorderable inferred map keys to slip through.

---

## Verified Claims & Baseline Check

- **Corpus Baseline (`PLAN.md:368-397`)**: Verified directly via `.venv/bin/python checker/gate.py`. Exactly 36 valid fixtures + 6 module fixtures = 42 clean; 47 semantic fixtures matching declared rules; 40 package sources clean. Total: 129 files, 0 failures.
- **Pass Decoupling (`PLAN.md:34-36` ↔ `checker/resolve.py:639-640`)**: Verified. Pass 3 is strictly gated behind `if not self.diags:`.
- **Purely Functional Immutability (`PLAN.md:37-39` ↔ `backend/runtime.py:254-260`)**: Verified. Maps copy on every operation (`m_set` is `{**m, k: v}`).
- **Stack Frame Doubling Budget (`PLAN.md:40-42` ↔ `packages/asl-parser/src/reader.asl:109-122`)**: Verified. `r-run` doubles its budget to drain worklists in $O(\log N)$ frames. Tested live: native reader parsed and rendered 1200-deep nested expressions cleanly, whereas Lark crashed with `RecursionError`.
- **Map Key & Integer Rules (`PLAN.md:43-51` ↔ `checker/types_.py:38,44,325,352-389`)**: Verified. `UNORDERED = {"Float64", "IoError"}`, `INT_RANGE`, and `try` scoping rules match the Python checker exactly.

---

## Blockers

### 1. Non-Existent File Path in Acceptance Criterion (`PLAN.md:8`)
- **Citation**: `PLAN.md:8`
  ```sh
  .venv/bin/python checker/gate.py --native && .venv/bin/python -m pytest tools/tests/test_native_checker.py -q && ./asl check grammar/corpus/valid/01-primitives.agentscript
  ```
- **Finding**: The file `grammar/corpus/valid/01-primitives.agentscript` does not exist in the repository. The primitive types fixture is named `grammar/corpus/valid/01-basics.agentscript`. Executing the stated acceptance command fails immediately with `FileNotFoundError`.
- **Disposition**: Replace `01-primitives.agentscript` with `01-basics.agentscript`.

### 2. Rule 12 Effect Invariant Violation in Module Loader / `check-module` (`PLAN.md:210-212, 281-286`)
- **Citation**: `PLAN.md:210-212` (`Module loader: resolves imported modules against search roots (find logic: .agentscript and .asl file existence)`) and `PLAN.md:281-286` (`check-module [(top-forms ...) (roots ...)] -> (List Diagnostic)`).
- **Codebase Evidence**: `prelude/prelude.json:1364-1374` defines `file-exists?` as `"effect": true`. `backend/runtime.py:312-338` shows `file_read` and `file_exists` perform filesystem I/O. `checker/resolve.py:534-547` (`Rule 12`) rejects any effectful call inside a pure defun or lambda not declared with `!`.
- **Finding**: Item 3 specifies that `ModuleLoader` searches the filesystem to locate and parse imported modules. If `check-module` or `check-source` performs this I/O directly without being declared with `!`, it violates Rule 12. Consequently, when `packages/asl-checker` is checked by `asl check` (Item 5, 6 and Acceptance Criterion 3), it will fail with `rule-12: effect in pure defun`.
- **Disposition**: Either:
  1. Decouple `check-module` as a purely functional core accepting an in-memory module summary cache `(Map String ModuleSummary)`, leaving I/O to an explicit effectful wrapper `(df ! check-file! [(path String) (roots (List String))] -> ...)` that pre-loads dependencies; OR
  2. Declare `check-module!`, `check-source!`, and the module loader functions explicitly with `!` (`(df ! check-module! ...)`).

### 3. Incomplete Hindley-Milner Unification for Function Types (`PLAN.md:184-188`)
- **Citation**: `PLAN.md:184-188`
  ```
  - If `t1` is `ty-var id`:
    - If `t2` is `ty-var id2`: narrow kinds via `kind-narrow`. If compatible, `map-set subst id (ty-var id2 narrowed-kind)`.
    - If `t2` is `ty-con`: check if allowed by `kind` (`num` requires `is-numeric-type?`, `int` requires `is-integral-type?`). Check `occurs-in? id t2 subst`. If clean, `map-set subst id t2`.
  - If `t2` is `ty-var`: symmetric handling.
  ```
- **Codebase Evidence**: `checker/types_.py:115-126` handles `Var` unification against any `other` type: if `var.kind == "any"`, it binds `var.ref = other` regardless of whether `other` is `Con` or `Fun`.
- **Finding**: The unification specification in Item 2 omits the case where `t2` is `ty-fun`. In ASL, higher-order functions (such as `map`, `fold`, or user callbacks) frequently unify an unconstrained metavar (`ty-var id "any"`) with a function signature `(ty-fun params ret)`. Under the specification as written, unifying a metavar with a `ty-fun` is not handled, causing valid higher-order expressions to be rejected as mismatches.
- **Disposition**: In Item 2, specify:
  - If `t2` is `ty-fun`: if `kind == "any"`, verify `occurs-in? id t2 subst` and bind `map-set subst id t2`; if `kind` is `"num"` or `"int"`, return `(u-err "cannot unify function with numeric kind" false)`.

### 4. Under-Specified Evaluation Worklist Machine for Deep Expression Trees (`PLAN.md:63-66, 254-275, 319`)
- **Citation**: `PLAN.md:63-66` (FM-2), `PLAN.md:254-275` (Item 4), and `PLAN.md:319` (`test_iterative_depth_safety: Evaluates a 2000-deep nested expression (+ 1 (+ 1 ...))`).
- **Codebase Evidence**: `packages/asl-parser/src/reader.asl:109-122` implements an explicit queue `RState` with `r-tick` and doubling-budget `r-run` to avoid recursion. In Python runtime, default stack limit is 1000 frames. Live test in this session confirmed that Python's existing recursive checker crashes on a 1200-deep nested expression with `RecursionError` (wrapped as diagnostic `internal`).
- **Finding**: FM-2 claims: *"Prevention: Flatten expression evaluation worklists using iterative doubling-budget queues, or use fold for sequential child evaluations."*
  Using `fold` over sequential child evaluations only handles horizontal sibling lists (e.g. statements in a function body or parameters). It does **not** prevent stack overflow for vertical AST nesting such as `(+ 1 (+ 1 (+ 1 ...)))`, where each nested call is an argument to the parent call. If Item 4 implements `infer-expr` via recursive function calls, transpiled Python will crash at ~400-500 levels, failing `test_iterative_depth_safety`. Item 4 lacks the concrete specification for an explicit evaluation frame stack / worklist machine (e.g., `(dfe InferFrame ...)` with doubling-budget queue).
- **Disposition**: Remove the misleading "or use fold for sequential child evaluations" from FM-2. In Item 4, explicitly specify the non-recursive evaluation frame stack or trampoline architecture used by `infer-expr` to evaluate expressions to arbitrary depth.

### 5. Missing Substitution Application in Post-Inference Map Key Rules (`PLAN.md:278`)
- **Citation**: `PLAN.md:278`
  ```
  - `map-key-rules`: inspects all types in `map-sites`. For every `Map K V`, checks `unordered? K`. Recursively inspects user schema fields and enum cases with visited set. Emits `map-key-order` if `Float64` or `IoError` is reachable.
  ```
- **Codebase Evidence**: `checker/types_.py:363-365` iterates `self.map_sites` and calls `map_keys(ty)`. In Python, `ty` was mutated in-place by `unify` via `Var.ref`.
- **Finding**: In pure ASL, `map-sites` accumulates types at the point of expression visitation when metavars are still unbound. For expressions where the map key type is determined via inference (e.g. `(map-from-pairs pairs)` where `pairs` determines key type `Float64`, as tested in `semantic/map-key-inferred.agentscript`), the type in `map-sites` contains `(ty-var id)`. If `map-key-rules` inspects `map-sites` without applying `apply-subst subst ty`, `unordered?` will see a `ty-var` instead of `Float64`, miss the unorderable key, and fail `semantic/map-key-inferred.agentscript`.
- **Disposition**: Explicitly specify in Item 4 that `map-key-rules` and `map_keys` resolve all types through `apply-subst subst ty` before evaluating `unordered?`.

---

## Non-Blocking Observations

1. **System `python3` vs `.venv/bin/python` in Gates (`PLAN.md:151, 198, 238, 295, 355`)**:
   The gates in Items 1, 2, 3, 4, and 6 invoke `python3 -c "..."`. On systems where default `python3` is the OS Python (such as macOS `/usr/bin/python3`), `lark` is not in site-packages, causing immediate `ModuleNotFoundError: No module named 'lark'`. The gates should invoke `.venv/bin/python` consistently with line 8 and Item 5.
2. **Defun-Local Substitution Scope**:
   AgentScript requires all top-level functions (`df`) to declare parameter types and return types. Because type variables never escape the enclosing function boundary, `subst: (Map Int64 Type)` can be scoped and cleared per function rather than accumulated monotonically across the entire module. This keeps `(Map Int64 Type)` small and minimizes dictionary copying overhead during `m_set`.
3. **Recursive Metavar Pruning in `occurs-in?`**:
   `occurs-in?` should explicitly prune/resolve subterms through `subst` at each step of traversing child arguments of `ty-con` and `ty-fun`, ensuring transitively chained metavars cannot introduce hidden cycles.
4. **Set Representation in Pure ASL**:
   Item 3 and 4 refer to a "visited set" and "set of bound variable names". Since AgentScript has no native `Set` type in §6, the plan should clarify their representation as `(Map String Bool)` or `(List String)` with `list-contains?`.

---

## Unverified Claims

None. All cited lines, rule codes, test fixture counts, and runtime behaviors were verified directly against the active codebase and tested live.
