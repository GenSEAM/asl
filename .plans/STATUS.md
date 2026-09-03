# Current Status: asl-selfhosted-runtime-v1
- Current Phase: **Phase 7** (Retiring Lark & Migrating Conformance & Doc Validation to Native Parser, opened 2026-09-03) — planned (@pcp:d-8d4c)
- Phases 1–2: lexer/reader/AST (done prior session, verified)
- Phase 3: `asl parse` CLI + benchmark (`tools/native_parser.py`, `tools/tests/test_native_parser.py`) — done
- Phase 4 (escalation): iterative fold-based lexer scanner; `tools/tests/test_native_parse_all.py` parses all 37 `packages/**/*.asl` — done
- Phase 5: full 15-gate CI re-run + acceptance criterion `pcp.js actualize && npm run build:web` — done, 15/15 green
- Phase 6 (escalation): native-parser conformance — `;` comments, floats, signed literals,
  string escapes, module path, positional Nano aliases, a real `(Result ... ParseError)`
  failure path, an iterative reader and renderer, and parity gate (399 passed) — done
- Phase 7: Retiring Lark & Migrating Conformance (`grammar/validate.py`) & Doc Validation (`tools/doc_examples.py`) to Native Self-Hosted Parser — planned in `.plans/phase-7-selfhost-validation/PLAN.md`
- Phase 8: Native AST Call-Head Extraction for Closure Audit (`grammar/closure_audit.py`) — scheduled
- Phase 9: Self-Hosted Semantic Type Checker (`packages/asl-checker`) in pure ASL — scheduled
- Phase 10: Complete Self-Hosted Bootstrap & Native CI Pipeline (`packages/asl-compiler`) — scheduled

## Measured this session (2026-09-03)
- Phase 4 gate: `.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q` → `38 passed`
- Phase 5: 15/15 CI gates green (validate, closure 107/107, prelude --check, checker, check_corpus,
  monomorphism 400 probes, differential 0 disagreements, pytest 369, parser tests 8, lint 37/37,
  clone-check 10.02%, check-tokens, deploy_check, pcp actualize 0 breaches, npm run build:web).
- Phase 6 gates, all green after the mid-session checker/grammar landings:
  pytest (asl-parser tests + native parser/parse-all/parity) `321 passed`;
  `grammar/validate.py` `0 failure(s)`; `checker/gate.py` `0 failure(s)`;
  `grammar/closure_audit.py` `107/107 (100%)` executed, spec and corpus closed.

## Notes
- Phase 3 code landed entangled in `c88c7ed` (parallel-session commit) — see ORCHESTRATOR-LOG.md.
  Phase 4/5 code is staged for its own commit.
- **`;` line comments: Phase 6 item (a) is withdrawn.** The owner has abandoned `;` comments
  for free-standing string literals, and a parallel session is converting existing ones. The
  handling written before that decision stays in `lexer.asl` because both reference grammars
  still ignore `;` and 33 of 34 `corpus/valid` fixtures use one; removing it today fails the
  parity gate on 172 cases. Nothing asserts `;` as a language rule — the gate derives the
  answer from tree-sitter, so the lexer follows the grammar automatically when it changes.
- The self-hosted parser is a third encoding of the syntax (Lark, tree-sitter, this parser,
  and the transcoder make four). `tools/tests/test_native_parity.py` is what holds it against
  the reference grammar; without it every Phase 6 defect was invisible to CI.
- Reported from here and since fixed on the main line: the `and`/`or` arity hole (the checker
  accepted extra arguments and the backend dropped everything past the second — the instance
  was this package's `is-symbol-char`, now pinned by `corpus/semantic/builtin-arity.agentscript`),
  the missing `:json-case` rule in both grammars, and cross-package import resolution in
  `checker/gate.py`.
