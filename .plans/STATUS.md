# Current Status: asl-selfhosted-runtime-v1
- Current Phase: **Phase 9** (Self-Hosted Semantic Type Checker, `packages/asl-checker`) — next after Phase 8 (@pcp:d-8d4c)
- Phases 1–2: lexer/reader/AST (done prior session, verified)
- Phase 3: `asl parse` CLI + benchmark (`tools/native_parser.py`, `tools/tests/test_native_parser.py`) — done
- Phase 4 (escalation): iterative fold-based lexer scanner; `tools/tests/test_native_parse_all.py` parses all 37 `packages/**/*.asl` — done
- Phase 5: full 15-gate CI re-run + acceptance criterion `pcp.js actualize && npm run build:web` — done, 15/15 green
- Phase 6 (escalation): native-parser conformance — `;` comments, floats, signed literals,
  string escapes, module path, positional Nano aliases, a real `(Result ... ParseError)`
  failure path, an iterative reader and renderer, and parity gate (399 passed) — done
- Phase 7: Retiring Lark & Migrating Conformance (`grammar/validate.py`) & Doc Validation (`tools/doc_examples.py`) to Native Self-Hosted Parser — done (zero Lark in the three validation files; full gate battery green)
- Phase 8: Native AST Call-Head Extraction for Closure Audit (`grammar/closure_audit.py`) — done (native walker, exact set-equality vs tree-sitter baseline; full battery green)
- Phase 9: Self-Hosted Semantic Type Checker (`packages/asl-checker`) in pure ASL — next
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
- Phase 7 gates, all green (orchestrator + step-verifier, independently):
  `grammar/validate.py` `0 failure(s)` (native ↔ tree-sitter, Lark surface removed);
  `tools/doc_examples.py --quiet` `31 checked, 15 opted out, 0 failure(s)`;
  `pytest tools/tests/test_native_parity.py` `270 passed`;
  closure `107/107`, `checker/gate.py` `0 failure(s)`, `check_corpus.py` `0 failure(s)`,
  `monomorphism.py` `400 probes`, `differential.py` `132+19 cases, 0 disagreements`,
  `pytest backend/tests bench/algo checker/tests tools/tests` `849 passed`,
  `pcp actualize` 0 breaches, `npm run build:web` ok.
  Zero `lark` imports remain in `grammar/validate.py`, `tools/doc_examples.py`,
  `tools/tests/test_native_parity.py`.
- Phase 8 gates, all green (orchestrator + final step-verifier, independently):
  `grammar/closure_audit.py` → `10 qualified / 107 builtins / 137 defs / 156 call heads`,
  `107/107 (100%)`, `OK: spec and corpus are closed…`, exit 0, zero tree-sitter/subprocess;
  `pytest tools/tests/test_closure_native_equivalence.py` `3 passed` (set-equality vs tree-sitter baseline);
  `pytest backend/tests/test_gate_machinery.py` `32 passed` (4 tests migrated to native surface);
  full battery: validate 0, checker 0, check_corpus 0, monomorphism 400 probes,
  differential `132+19` cases 0 disagreements, `pytest backend/tests bench/algo checker/tests tools/tests`
  `852 passed`.

## Notes
- Phase 3 code landed entangled in `c88c7ed` (parallel-session commit) — see ORCHESTRATOR-LOG.md.
  Phase 4/5 code is staged for its own commit.
- **Phase 7 commit entanglement (3rd occurrence).** `tools/doc_examples.py` was swept into the
  parallel session's `254908f` ("feat(plans): register asl-token-density-v1…"); the rest of
  Phase 7 landed in `6fb458a` ("feat(phase-7): migrate grammar validation and parity suite to
  native parser"). Work is intact and green; the doc_examples.py change is mislabeled. Left
  un-rewritten pending owner decision — do not rewrite.
- **Phase 8 reversion (parallel session).** The parallel session ran `git checkout -- .` and
  reverted the tracked Phase 8 files mid-verification; the `closure-heads` walker was
  unrecoverable (never `git add`ed, not in dangling objects). Re-implemented from the v2 plan
  and committed immediately as `7ba39c8` per the owner's decision to protect against re-revert.
  Lesson recorded: on this shared tree, phase code must be committed the moment it is green.
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
