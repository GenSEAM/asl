# Orchestrator Log: asl-selfhosted-runtime-v1

## Phase Tiers
- Phase 1: Tier 1 (Pure ASL Lexer & Tokenizer)
- Phase 2: Tier 1 (Pure ASL Reader & AST Schema)
- Phase 3: Tier 1 (CLI Tooling & Benchmark)
- Phase 4: Tier 1 (Full 7-Gate CI Hardening)

## Cross-Phase Decisions
- Standalone self-hosted parser lives in `packages/asl-parser`.
- Manifest scoped as `@genseam/asl-parser`.
- Supports both Ultra-Nano (`dfs`, `dfe`, `df`, `:f`, `:c`) and Verbose (`defschema`, `defenum`, `defun`) transparently without regex pre-processing.

## Resume audit 2026-09-02
- Phase 1 commit `c100e3d` and Phase 2 commit `bb0ccaa` were **skeletal**, not complete:
  `lexer.asl` has no `tokenize`/scan (only single-atom classification); `reader.asl` has no
  token→AST parse and defines only a generic `SExpr`; `ast.asl` and the typed nodes
  `ModuleNode`/`SchemaNode`/`EnumNode`/`DefunNode` named in PHASES.md do not exist; both test
  suites are `check_file`-only with stubbed `.asl` fixtures that return `true`.
- Phase 2 re-planned and re-executed. Tier stays 1 (Standard).
- **Decision (runner):** the mandated test vehicle is transpile-to-Python + `runpy` (the
  `backend/tests` convention). The parser must therefore stay inside the builtin surface
  `backend/to_python.py` actually lowers; a missing lowering is a finding, not a workaround.
- **Decision (AST contract):** `ast.asl` defines `ModuleNode`/`SchemaNode`/`EnumNode`/`DefunNode`
  (shapes from `AGENT_SPEC_CORE.md` §4.0–§4.4). Dual projection is verified by round-trip:
  `parse(nano)` and `parse(verbose)` of the same source render to one canonical verbose form.

## Phase 2 completion 2026-09-02
- Acceptance criterion met: `.venv/bin/python -m pytest packages/asl-parser/tests -q` → 8 passed.
- Full suite: 333 passed (`backend/tests bench/algo checker/tests tools/tests packages/asl-parser/tests`).
- Core gates green: `grammar/validate.py`, `grammar/closure_audit.py`, `prelude/generate.py --check`, `checker/gate.py`.
- ASL lint: 37 files, 0 errors. Clone-check: 0.0963 (< 0.15).
- Whole-repo Ultra-Nano conversion: every package `.asl` file normalized to `dfs`/`dfe`/`df`/`mt`/`:f`/`:c`/`:d`/`:x`/`:i`/`:a`.
- Lexer consolidated: four near-identical scanners merged into one `scan-run` (`RunMode` enum).
- `ast.asl`: `norm-atom` is a table lookup; `render-type-vars`/`render-joined` extracted.
- `tools/module_graph.py`: recognizes Nano forms (`dfs`/`dfe`/`df`, `:d`/`:x`/`:i`/`:a`) alongside Verbose.
- `tools/clone_detector.py`: literal values now stay exact in structural fingerprints (only identifiers alpha-renamed); `min_node_count` default 6 → 10.

## Commit entanglement 2026-09-02
- Parser/Nano/tooling work was committed during a parallel session, but the staged files were swept
  into a concurrent commit (`152d1a1 docs(plans): specify ultra-fast Wasm and client parsers for ASN in Phase 2`)
  alongside `.plans/universal-codec/PHASES.md`; the intended `git commit` returned "no changes added to commit".
  The work is intact on `origin/main`; message is mislabeled and the change is entangled. Left un-rewritten pending an owner decision.

## Phase 3 + Phase 4 planning/review 2026-09-03
- Both phases Tier 1 (Standard): planner `steps-planner`, reviewer `steps-plan-reviewer`.
- Phase 3 plan: `.plans/phase-3/PLAN.md` (5 items). Review `REVIEW-backend.md` → approve-with-amendments.
  Dispositions: A1 tighten item-1 assertion to `"(module"` (ACCEPTED); A2 add missing-file
  BadInput stderr test to item 3 (ACCEPTED); A3 label benchmark arms (ACCEPTED).
  Reviewer confirmed str→String foreign call needs NO wrapper (`backend/to_python.py:209-218`).
- Phase 4 plan: `.plans/phase-4/PLAN.md` (5 items). Review `REVIEW-scope.md` → approve-with-amendments.
  Dispositions: A4 cosmetic line-cite drift (NOTED, no work); A2/A3 clarify item-2 scope includes
  `asl-parser/tests/*.asl` fixtures (ACCEPTED).
- Decisions (runner): `asl parse <file>` takes a path; `--benchmark`/`--bench` compares
  native parse+render vs Lark parse (perf_counter + tracemalloc, setup excluded). "Full 7-gate CI"
  = installed `.git/hooks/pre-commit` 7 gates PLUS AGENTS.md wider gates (check_corpus,
  monomorphism, differential, pytest). Roadmap "24 packages" is stale → 37 `.asl` files across 14
  packages. Phase 4 binds to Phase 3's landed `tools.native_parser` API, so it runs after Phase 3.

## Escalation 2026-09-03 — parser recursion (Tier 1.5, hidden-coupling)
- Trigger: Phase 3 implementer reported the native parser recurses out on real files; orchestrator
  re-verified: `native_render` raises `maximum recursion depth exceeded` on lexer.asl (6296 B),
  reader.asl (2379 B), ast.asl (17628 B), sh.asl (1114 B), lint.asl (2995 B). Root cause: lexer
  `scan`/`scan-run`/`run-emit` recurse once per character; Phase 2 scoped inputs to ≤2 KiB and
  flagged deeper input as an accumulator-style rewrite, so this is the first time real files hit it.
- Language has NO `while`/`loop`; iteration is `fold`/`map`/`filter`/`range`/`string-chars`, all
  lowered to Python loops (verified: `fold` → `_agentscript.fold(f,init,xs)`, `range` →
  `list(range(a,b))`, `map` → comprehension). Scanner must be rewritten as a fold-based state machine.
- Escalated to Tier 1.5: plan via `steps-planner`, extra review lens `steps-architect-pro`.
- Roadmap updated: new Phase 4 (scalability) inserted; former Phase 4 renumbered Phase 5.
  Gate: `.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q`.
- Note: no package `.asl` currently uses `;` line comments (verified by grep), though the Lark
  grammar declares `%ignore COMMENT`. Comment support is NOT required to parse the 37 files; out of
  scope for this phase, noted for later.

## Commit entanglement 2026-09-03 (Phase 3)
- Orchestrator staged Phase 3 files (`agentscript`, `tools/native_parser.py`,
  `tools/tests/test_native_parser.py`, `.plans/phase-3/`), then a parallel session committed
  `c88c7ed` ("feat: add dual MIT/Apache-2.0 license, guarantee background gutters, polish
  InBrowserAgent and wire protocol") which swept the staged parser files into its own web/license
  commit. Phase 3 work is intact in HEAD (verified: `git show HEAD:agentscript | grep -c cmd_parse`
  → 2), but the commit is mislabeled and entangled — same failure mode as `152d1a1`. Left un-rewritten
  pending owner decision; do not rewrite.

## Phase 4-scalability plan review 2026-09-03
- Plan: `.plans/phase-4-scalability/PLAN.md` (4 items). Architect review `REVIEW-architect.md` →
  approve-with-amendments (4 blocking). Dispositions (all ACCEPTED):
  - F1: red set is 20 files, not 5 (orchestrator re-verified exact 20-file list by direct probe).
    Item 1 records the 20-file list verbatim; Item 2 declares all 20 green post-rewrite except
    `ast.asl` deferred to Item 3.
  - F2: Item 3 selector `-k ast` also matches `ast_driver.asl`; use `ast.asl and not ast_driver`.
  - F3: Item 4 runs the full AGENTS.md gate set, with a per-gate "input set excludes packages/"
    justification for any omission. `fold`/`string-chars` already in coverage.lock instantiations
    (executed: 107), so the lock cannot move from this change.
  - F4: closure_audit scans `grammar/corpus/valid` + spec examples only (closure_audit.py:76);
    rewrite is invisible to it — correct the rationale, do not touch the audit.
  - Non-blocking F5 (drifted line cites) + sharp-edge-2 (asymmetric run-opener pre-consumption:
    `"` and `:` pre-consume, digit does not) folded into the implementer brief.

## Phase 7 planning 2026-09-03 — Retiring Lark & Migrating Conformance to Native Parser (@pcp:d-8d4c)
- Tier 1 (Standard): planner `steps-planner`.
- Plan: `.plans/phase-7-selfhost-validation/PLAN.md` (4 items).
- Scope: Migrate `grammar/validate.py` and `tools/doc_examples.py` to `tools.native_parser.native_parse` (pure self-hosted parser), delete retired Lark secondary tests from `tools/tests/test_native_parity.py`.
- Checkable Criterion: `.venv/bin/python grammar/validate.py && .venv/bin/python tools/doc_examples.py --quiet && .venv/bin/python -m pytest tools/tests/test_native_parity.py -q`.
- Pre-requisites verified: 399/399 parity tests pass, all 37 package sources parse natively.

## Phase 7 completion 2026-09-03 — Lark retired from validation (@pcp:d-8d4c)
- Tier 1 (Standard). Scope review `REVIEW-scope.md` → **reject** (4 blocking). All 4 accepted and
  reconciled into `PLAN.md` v2 + `RECONCILIATION.md`:
  F1 API is `native_render`/`NativeParserError`, not `native_parse`; F2 `validate.py` deletes the
  whole Lark surface incl. `lark_spans`/`token_identity`/`PROBES` (the native reader emits no spans,
  so the span-identity probes have no native side); F3 keep the verbose `defun` wrap in
  `doc_examples.py`; F4 delete both Lark imports in the parity test.
- Implemented (steps-implementer): `grammar/validate.py` compares tree-sitter vs `native_render`;
  `tools/doc_examples.py` parses via `native_render`; `tools/tests/test_native_parity.py` drops the
  Lark secondary arm. Checker/backends/fmt/linter/transcoder keep Lark until Phases 9–10 (out of scope).
- Gates, all green (orchestrator re-ran the acceptance criterion, step-verifier ran the full battery):
  validate 0 failures; doc_examples 31/15/0; parity 270 passed; closure 107/107; checker 0;
  check_corpus 0; monomorphism 400 probes; differential 132+19 cases 0 disagreements;
  pytest (backend/bench/checker/tools) 849 passed; pcp actualize 0 breaches; build:web ok.
  Zero `lark` imports remain in the three validation files.
- **Commit entanglement (3rd occurrence).** The parallel session swept `tools/doc_examples.py` into
  `254908f` ("feat(plans): register asl-token-density-v1…"), leaving the rest of Phase 7 in `6fb458a`
  ("feat(phase-7): migrate grammar validation and parity suite to native parser"). Work is intact and
  green; the doc_examples.py change is mislabeled. Same failure mode as `152d1a1`/`c88c7ed`; left
  un-rewritten pending owner decision — do not rewrite.

## Phase 8 planning 2026-09-03 — Native AST Call-Head Extraction for Closure Audit (@pcp:d-8d4c)
- Tier 1.5 (Middle): planner `steps-planner`, extra plan-review lens `steps-architect-pro`.
  Reason: the scout surfaced the coupling risk that the native AST drops node-kind tags, so the
  walker must re-derive tree-sitter's `call` classification from head text (PascalCase → record
  construction, not a call; special-form heads → not a call; `/` → qualified). Exact set-equality
  against the tree-sitter baseline is the only guard against silently drifting the gate's counts.
- Scout digest: `closure_audit.py` has two halves — call-head extraction (one tree-sitter query) and
  coverage (delegated to `exec_coverage.check()`, untouched by this port). `coverage.lock` matching is
  therefore unaffected; the port only replaces the query half.

## Phase 8 completion 2026-09-03 — closure audit on the native AST (@pcp:d-8d4c)
- Tier 1.5 (Middle). Reviews: scope → approve-with-amendments (0 blocking); architect →
  approve-with-amendments (**3 blocking**). Reconciled into `PLAN.md` v2 + `RECONCILIATION.md`:
  B1 rule 9 disambiguates qualified-ctor vs qualified-callee by head spelling (tail PascalCase vs
  lowercase, grammar.js:266/:269), not "second element is a keyword"; B2 rule 11 buckets only
  `ident`/`operator` heads, never a literal head (`(-1 2)` is a call node the query captures nothing
  from); B3 the expr-position `cons` rule is pinned in the probe (`cons ∈ calls`). N1/N2: line-cite
  and Item-4 wording.
- Implemented (steps-implementer + steps-fixer): `closure-heads` ASL walker in
  `packages/asl-parser/tests/reader_test.asl` (iterative doubling-budget work list, rules 1–12);
  `grammar/closure_audit.py` ported (deletes `QUERY`/`run_query`/`TS_BIN`/subprocess, adds
  `_native_buckets`/`collect_sources`); 4 stale `test_gate_machinery.py` tests migrated to the native
  surface. Exact set-equality is pinned by `tools/tests/test_closure_native_equivalence.py`
  (tree-sitter baseline kept inside the test, not the gate).
- **Reversion incident.** The parallel session ran `git checkout -- .` and reverted the tracked
  Phase 8 files mid-verification. The walker was unrecoverable (never `git add`ed, absent from
  dangling objects); `closure_audit.py` and the test fixes were re-applied from the plan. Per the
  owner's decision, the phase was re-implemented and committed immediately as `7ba39c8`. The
  equivalence test and `.plans/phase-8/` survived (untracked).
- Gates, all green (final step-verifier, independent): closure `10/107/137/156`, `107/107 (100%)`,
  zero tree-sitter/subprocess; equivalence `3 passed`; gate-machinery `32 passed`; validate 0;
  checker 0; check_corpus 0; monomorphism 400 probes; differential `132+19` 0 disagreements;
  pytest (backend/bench/checker/tools) `852 passed`.

