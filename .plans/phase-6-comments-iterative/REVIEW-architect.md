# REVIEW-architect — Phase 6 plan (`.plans/phase-6-comments-iterative/PLAN.md`)

Lens: algorithmic / cross-cutting (Tier 1.5 extra plan-review).
Verdict: **reject**

## Why: the plan's entire substrate was replaced between drafting and review

PLAN.md (mtime Sep 3 09:31) was drafted against a snapshot of
`packages/asl-parser/src/ast.asl` that no longer exists. During this review
session the files were rewritten: `ast.asl` grew 400 → 715 lines (mtime 10:28),
`lexer.asl` 9.1K → 11.8K (10:19), `reader.asl` 2.4K → 4.9K (10:12), and
`.plans/PHASES.md` itself was rewritten (uncommitted `M`, line 32 now reads
"Native parser conformance — lexical gaps, real failures, iterative reader,
parity gate" with eight defects (a)–(h), not two). All five plan items now
describe work that is already landed under different designs, with semantics
the plan's gates assert the opposite of.

Findings, ranked:

1. **All four implementation items are already delivered under different designs.**
   - Item 1 (comment run-mode): implemented as `run-comment` + a `RunStep`
     algebra — `step-drop` discards the run at `"\n"`
     (`lexer.asl:102,104-108,113`), `open-char` opens it at `";"`
     (`lexer.asl:242`), `run-emits? false` keeps it out of `run-token` and
     `flush` (`lexer.asl:154-157,259-266`). This is strictly more robust than
     the plan's `flush` special-case. Probe: `native_render` of the Item-1 gate
     input equals its comment-free twin (True), and `;` inside a string literal
     survives (`(module m :doc "a ; not a comment")` round-trips byte-exact).
   - Item 2 (iterative reader): implemented as an explicit `Frame` stack fold —
     `ReadState`, `push-frame`/`close-frame`/`finish-read`, `read-step` fold,
     `read-forms` (`ast.asl:155-166,276-326,339-353`). Probe: 3000-deep input
     no longer raises `RecursionError`.
   - Item 3 (renderer): implemented as a work-list renderer, NOT the plan's
     cached `text` field — `RItem`/`RState`/`r-tick`/`r-run` drained in
     doubling-budget batches, recursion O(log n) in node count
     (`reader.asl:73-129`). Probe: the Item-3 gate renders depth-3000
     byte-exact (True). The `SExpr` enum was never changed — design decision
     (a) is moot.
   - Item 4 (`decl-forms` fold): already a fold with `decl-step` and a final
     `list-reverse` inside `result-map` (`ast.asl:431-449`); order preserved.

2. **The plan's declared malformed-input semantics now contradict the phase.**
   PLAN.md Item 2's characterization table (stray closer → own atom, mismatched
   closer → atom item, unterminated seq → atom `""` discarding the rest) pins
   exactly the lenient behavior the rewritten PHASES.md names as defect (g):
   "The parser could not fail … any unrecognised top-level form was wrapped in
   a nameless `DefunNode`" (`.plans/PHASES.md:53-55`). The current parser
   raises located diagnostics instead: "unexpected closing delimiter" /
   "mismatched closing delimiter" (`ast.asl:311-320`), "unclosed delimiter"
   (`ast.asl:322-326`), "not a declaration head" (`ast.asl:440-450`). Writing
   the plan's Item-5 characterization tests would FAIL against the correct
   implementation and tempt a regression to the old semantics. Verified:
   `proj_parse('('*3000+')'*3000)` now returns `"1:1: not a declaration head: ''"`
   — neither the plan's expected `module||0|0|1` nor `RecursionError`.

3. **Every gate command and baseline is stale.** PLAN.md's "44 passed" baseline
   is now 49 for the same command (re-run this session:
   `49 passed in 16.25s`). Item 1 and Item 3 gates already pass; Item 4's gate
   (`native_render('(a)\n'*2000)` expecting `(module :doc )` + 1,999 retained
   defuns) now raises `NativeParserError: not a declaration head: 'a'` — its
   expected value depends on `retained-defun`, which was deleted
   (`ast.asl` no longer defines it; PHASES.md defect (g)).

4. **The acceptance criterion changed.** The rewritten phase gate is
   `.venv/bin/python -m pytest packages/asl-parser/tests
   tools/tests/test_native_parser.py tools/tests/test_native_parse_all.py
   tools/tests/test_native_parity.py -q` with a Lark-parity requirement
   (`.plans/PHASES.md:65-71`); PLAN.md's criterion names only the two tools
   suites and omits the parity gate. Re-running the new criterion this
   session: **321 passed in 47.69s**.

5. **The flipped-test decision landed stronger than proposed.** The plan wanted
   to flip the deep-nesting-failure test to assert success. The current tree
   has `test_cli_parse_deep_nesting_succeeds` asserting returncode 0 AND
   byte-exact stdout at depth 3000 (`tools/tests/test_native_parser.py:110-119`),
   with the CLI error channel covered more strongly than before:
   `test_cli_parse_error_reports_located_diagnostic` pins line/col/message JSON
   (`tools/tests/test_native_parser.py:82-107`) plus the bad-file test
   (line 64). No gate was weakened.

6. **Risk: unattributed concurrent modification.** ~70 files are modified
   uncommitted (`git status`), `git log` HEAD shows unrelated web commits, and
   the parser rewrite happened inside this review window (10:12–10:28). The
   orchestrator must establish who made this change and whether it is final
   before re-planning; a second re-plan against an unstable tree will suffer
   the same fate.

## What was verified about the CURRENT implementation (anchors for verify)

- Comment run: `run-continues?`-style continuation replaced by `run-next`
  (`lexer.asl:110-131`); a trailing unterminated comment hits `flush` →
  `emit-run` → `run-emits?` false → dropped (`lexer.asl:206-217,259-266`). No
  `run-token` comment case needed; the defensive one at `lexer.asl:145` is
  unreachable-by-construction.
- Checker enforces match totality (probe: a match omitting one case of a
  three-case enum yields `rule-4: match is not exhaustive: c unhandled`), so
  every `RunMode`/`SExpr` match in the new files is totality-checked by
  `resolve.check_file`, which `test_lexer.py::test_lexer_files_check_clean`
  and `test_reader.py::test_reader_files_check_clean` run over all four files.
- Expressibility probes (run this session): fold steps capturing let-bound and
  function-parameter variables both work (36, 306); two-field enum cases match
  correctly (`xy`). The `decl-forms` fold shape is proven.
- Residual, non-blocking: `r-tick` uses `list-append` per expansion
  (`reader.asl:103-105`), worst-case quadratic time — depth-3000 passes in
  practice (CLI deep test green), but a timing check at 5000+ would confirm.

## Census requested by the orchestrator

21 `sexpr-list`/`sexpr-vect`/`make-list`/`make-vect` sites on the current
tree: 6 construction calls (`ast.asl:219,226,303,304` via `make-list`/
`make-vect`; `reader.asl:17,21` direct case construction) and 15 match sites
(`reader.asl:27-28,34-35,41-42,48,53-54,103,105`; `ast.asl:178-179,225,227`).
The enum's arity never changed — the work-list renderer replaced the
cached-text design — so cached-text is moot and every site is payload-safe.
(`rd/sexpr-atom` sites at `ast_driver.asl:54,66` are atoms, out of the census.)

## Required action for the orchestrator

Do not implement this plan. If any Phase-6 work remains after attributing the
concurrent rewrite, re-plan against `.plans/PHASES.md:32-71` (the rewritten
eight-defect scope) — and the evidence above suggests the correct next stage
is verify/review of the already-landed implementation, not implementation.
