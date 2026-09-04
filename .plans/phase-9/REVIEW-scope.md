# Review: Scope & Gate Completeness (Phase 9)

- **Lens**: Scope & Gate Completeness
- **Verdict**: approve-with-amendments
- **Reviewer**: steps-plan-reviewer (Antigravity)
- **Target**: `.plans/phase-9/PLAN.md`

## Summary

The plan for Phase 9 is exceptionally well-structured, accurately measuring all 47 fixtures across the 20 diagnostic categories and defining a sound 3-pass architecture that strictly enforces pass decoupling, immutable substitution threading, and doubling-budget stack recursion limits. However, two blocking defects must be amended before implementation: (1) Gates for Items 1, 2, 3, 4, and 6 specify bare `python3` instead of `.venv/bin/python`, which will cause immediate `ModuleNotFoundError: No module named 'lark'` failures during execution because the host Python environment lacks project dependencies; (2) Item 4's `check-source` specification overlooks that `ast/parse` returns `(Result (List TopForm) ParseError)` rather than a bare list, omitting the required error-unwrapping and mapping to the `"parse"` diagnostic code. Three non-blocking enhancements are also noted for completeness.

## Blockers

### B-1: Gate Commands Specify Host `python3` Missing `lark` Dependency
- **Citation**: `PLAN.md:152` (Item 1), `PLAN.md:198` (Item 2), `PLAN.md:238` (Item 3), `PLAN.md:295` (Item 4), `PLAN.md:355` (Item 6)
- **Evidence**:
  Host `python3` resolves to `/usr/local/bin/python3`, which does not have `lark` installed (`python3 -c "import lark"` fails with `ModuleNotFoundError: No module named 'lark'`).
  - `packages/asl-checker/tests/harness.py` imports `to_python.Transpiler` (`backend/to_python.py:21`), which imports `from lark import Tree, Token`.
  - `checker/gate.py:21` imports `from resolve import check_file`, which imports `from lark import Token, Tree` (`checker/resolve.py:21`).
  - During test drafting, the gates failed early at `from harness import run_asl` or `from tools.native_checker import ...`, masking this downstream dependency crash. Once those files are created, all five gates will fail under `python3`.
  - In contrast, the top-level Acceptance Criterion (`PLAN.md:8`) and Item 5 gate (`PLAN.md:326`) explicitly use `.venv/bin/python`.
- **Required Amendment**: Update the gate commands in Items 1, 2, 3, 4, and 6 to execute via `.venv/bin/python` instead of bare `python3`.

### B-2: Interface Type Mismatch on `a/parse` Result Handling in Entry Points
- **Citation**: `PLAN.md:283-286` (Item 4), `packages/asl-parser/src/ast.asl:384`
- **Evidence**:
  - `ast.asl:384` declares: `(df parse [(src String)] -> (Result (List TopForm) ParseError))`.
  - Item 4 specifies: "`check-source [(src String) (path String) (roots (List String))] -> (List Diagnostic)`: Parses `src` with `a/parse`, runs `check-module`."
  - Passing the return value of `a/parse` directly into `check-module` violates the type signature of `check-module` (which takes `(List a/TopForm)`).
  - Furthermore, on syntax rejection (`ParseError`), Python's reference checker (`checker/resolve.py:679-680`) maps `LarkError` to `[Diagnostic("parse", str(exc).splitlines()[0], line, col, path)]`.
- **Required Amendment**: Clarify in Item 4 that `check-source` matches on the result of `a/parse src`: on `(ok forms)`, it invokes `check-module forms roots path`; on `(err pe)`, it returns `(list (Diagnostic :code "parse" :message (.-msg pe) :line (.-line pe) :col (.-col pe) :path path))`.

## Non-blocking

### N-1: Omission of `unresolved-import` in Diagnostic Scope
- **Citation**: `PLAN.md:209-220` (Item 3), `checker/resolve.py:184-186`
- **Finding**: While all 20 diagnostic categories present in `grammar/corpus/semantic/**/*.agentscript` are covered, `checker/resolve.py:184` also emits `unresolved-import` when an imported module cannot be found on the search roots. For complete parity with `checker/resolve.py` in `tools/tests/test_native_checker.py`, `resolve.asl` should emit `Diagnostic :code "unresolved-import"` when `loader.load` returns `none`.

### N-2: Missing Static Table Parity Test against `prelude/vocab.py`
- **Citation**: `PLAN.md:133-141` (Item 1), `PLAN.md:313-320` (Item 5), `tools/tests/test_native_parity.py:207-225`
- **Finding**: Item 1 duplicates static lookup tables (`builtin-sig`, `unordered-type?`, `int-range-bounds`, `prelude-union-cases`) in `types.asl`. Per `@pcp:c-adc8`, duplicated tables must be held against `prelude/vocab.py` to prevent silent drift. Item 5's parity suite should include a test (mirroring `test_native_parity.py:test_ast_alias_tables_match_prelude`) verifying that `types.asl` tables match `prelude/vocab.py`.

### N-3: Source Coordinate Fallback Specification
- **Citation**: `PLAN.md:123-128` (Item 1), `PLAN.md:405-408` (Risk 2), `packages/asl-parser/src/ast.asl:46-60`
- **Finding**: `TopForm` and `rd/SExpr` discard token line/col spans. While `checker/gate.py:100` only compares `d.code`, CLI formatting (`agentscript:121`) sorts and displays `line` and `col`. Specifying default coordinates (e.g. line 0, col 0, or top-level form line when available) in Item 1 avoids arbitrary implementer divergence.

## Unverified

- None. All 47 fixtures, 20 diagnostic categories, parser AST definitions, and gate commands were verified against the live repository state and runtime environment.
