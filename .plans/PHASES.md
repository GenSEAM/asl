# Iteration: asl-selfhosted-runtime-v1
Goal: 100% Self-Hosted Pure ASL Parser & S-Expression Reader (`packages/asl-parser`), Native CLI Integration (`asl parse`), Dual-Projection Native AST & Full Migration.

## Phases

### Phase 1: Native Lexer & Tokenizer in Pure AgentScript (`packages/asl-parser/src/lexer.asl`)
- Goal: Implement tokenization of S-expressions, symbols, strings, numbers, keywords, and comments in pure ASL.
- Checkable Criterion: `.venv/bin/python -m pytest packages/asl-parser/tests/test_lexer.py -q`

### Phase 2: Native S-Expression Reader & Dual-Projection AST (`packages/asl-parser/src/reader.asl`, `ast.asl`)
- Goal: Implement hierarchical S-expression parsing into typed AST nodes (`ModuleNode`, `SchemaNode`, `EnumNode`, `DefunNode`) supporting both Ultra-Nano and Verbose forms natively.
- Checkable Criterion: `.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py -q`

### Phase 3: Native Parser CLI Integration (`asl parse`, `tools/native_parser.py`)
- Goal: Wire native parser into CLI as `asl parse` and provide high-speed parsing benchmark comparing memory/latency against Lark.
- Checkable Criterion: `.venv/bin/python -m pytest tools/tests/test_native_parser.py -q`

### Phase 4: Parser Scalability — iterative scanner (escalation, added 2026-09-03)
- Goal: The lexer's `scan`/`scan-run`/`run-emit` recurse once per character and overflow
  CPython's recursion limit on every real file (>~1 KiB). Rewrite the scanner to be
  non-recursive (fold/range/map over the char stream), and fix any residual per-token/per-form
  recursion in the reader/AST that also overflows. Phase 2 knowingly scoped inputs to ≤2 KiB;
  this phase removes that bound so the parser handles real package files.
- Checkable Criterion: `.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q`
  (parses every `.asl` under `packages/` through the native parser, hard-fails on zero files).

### Phase 5: Full Ecosystem Verification & 7-Gate CI Hardening
- Goal: Parse all 37 `.asl` files across 14 packages with the native parser (post-escalation),
  run the full 7-gate CI pre-commit pipeline plus the AGENTS.md wider gates, verify zero regressions.
- Checkable Criterion: `node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize && npm run build:web`

### Phase 6: Native parser conformance — lexical gaps, real failures, iterative reader, parity gate (escalation, added 2026-09-03)
- Goal: the self-hosted parser is a third encoding of the syntax with no gate holding it
  against the reference grammar, and eight defects lived behind that gap.
  - (a) **WITHDRAWN 2026-09-03.** Originally "`;` line comments are not lexed". The owner
    has since abandoned `;` comments for free-standing string literals, so no effort is
    spent holding the language to `;`. The handling written before the withdrawal stays in
    `lexer.asl` because both reference grammars still ignore `;` today
    (tree-sitter `extras: [/\s/, $.comment]`, Lark `%ignore COMMENT`) and 33 of the 34
    `corpus/valid` fixtures open with one — removing it fails the parity gate on 172 cases.
    Nothing pins `;` as a language rule: the gate asks tree-sitter what `;` means and holds
    the lexer to that answer, so the lexer follows the grammar on the day it changes.
  - (b) **Float literals split.** The numeric run continued over digits only, so `89.99`
    lexed as `89` then `.99`.
  - (c) **Negative literals were symbols.** A leading `-` fell into the symbol run.
    `AGENT_SPEC_CORE.md` §3 is normative: `-1` is one token when the sign touches the
    digits, `- 1` is two.
  - (d) **String escapes ended the string run.** Any `"` closed a string, so `"say \"hi\""`
    terminated early.
  - (e) **The module path was dropped.** `ModuleNode` had no field for it, so
    `(module t/x :doc "d")` rendered as `(module :doc "d")` — and a test assertion pinned
    the loss.
  - (f) **`norm-atom` rewrote every atom.** `:f :c :d :x :i :a` were mapped to their verbose
    spellings anywhere they appeared, so a record `(P :x 1 :d 2)` became
    `(P :export 1 :doc 2)`. A Nano alias is significant in head or option position only;
    the table lives in `prelude/prelude.json` under `projection`, read by `prelude/vocab.py`.
  - (g) **The parser could not fail.** EOF and unbalanced delimiters returned an empty atom
    and any unrecognised top-level form was wrapped in a nameless `DefunNode`.
  - (h) **Reader and renderer recursed per nesting level** and overflowed CPython's stack
    around 3000 levels, an inconsistency with the lexer Phase 4 made iterative.
- Landed mid-phase and folded in: the Nano projection gained a **type axis**
  (`Int64`/`I64`, `String`/`Str`, in `prelude.json` under `types.aliases` and
  `types.nano`), so `resolve-type-text` maps every name in type position to its Core
  spelling; and the grammar gained `toplevel: ... | note`, a bare string bound to
  nothing, which the parser accepts and erases as every backend does.
- Work: `lexer.asl` gains comment, float, sign, escape and error-token handling;
  `ast.asl` gains `ParseError`, an explicit-frame-stack reader, positional alias resolution,
  a `path` field on `ModuleNode` and structural validation of every declaration head;
  `reader.asl` renders from an explicit work list drained in doubling batches, so its own
  call depth is O(log n) in node count rather than O(nesting depth). `parse` returns
  `(Result (List TopForm) ParseError)`; `tools/native_parser.py` and `asl parse` surface it
  as a located diagnostic and a non-zero exit.
- Checkable Criterion:
  `.venv/bin/python -m pytest packages/asl-parser/tests tools/tests/test_native_parser.py tools/tests/test_native_parse_all.py tools/tests/test_native_parity.py -q`
  `.venv/bin/python grammar/validate.py` · `.venv/bin/python checker/gate.py` · `.venv/bin/python grammar/closure_audit.py`
  `checker/gate.py` now reads every `packages/**/*.asl`, not only `grammar/corpus/`, so the
  package's own drivers and fixtures are inside it: adding a record field or an enum case
  breaks the fixtures that construct or match on them, and the gate is where that surfaces.
  `tools/tests/test_native_parity.py` is the gate that was missing: every
  `grammar/corpus/{valid,semantic,modules}` fixture and every `packages/**/*.asl` must be
  accepted by the native parser wherever the reference grammar accepts it, its verbose
  rendering must re-parse under the reference grammar, every `grammar/corpus/invalid`
  fixture must be rejected with a located diagnostic, and `ast.asl`'s duplicated alias
  tables (heads, options, types) must equal `prelude/vocab.py`'s. Hard-fails on zero files.
  **tree-sitter is the reference and Lark is a secondary check**, because Lark is being
  retired; retiring it means deleting `_lark_accepts`, `test_lark_still_agrees_with_the_reference`
  and the `lark` import, and nothing else in that file.

### Phase 7: Retiring Lark & Migrating Conformance & Doc Validation to Native Parser (@pcp:d-8d4c)
- Goal: Remove Lark dependency from CI pipeline. Replace Lark in `grammar/validate.py` and `tools/doc_examples.py` with `tools/native_parser.py` (which executes `packages/asl-parser` transpiled output). Every corpus fixture and every doc example is validated by the self-hosted parser against the tree-sitter reference.
- Checkable Criterion:
  - `grammar/validate.py` runs and verifies all fixtures using Native Parser vs tree-sitter reference (0 failures).
  - `tools/doc_examples.py` runs using Native Parser without importing `lark`.
  - Lark is cleanly removed from pre-commit hooks and gate checks.

### Phase 8: Native AST Call-Head Extraction for Closure Audit (`grammar/closure_audit.py`) (@pcp:d-8d4c)
- Goal: Port the call-head extractor in `grammar/closure_audit.py` from tree-sitter S-expression queries to the native AST generated by `packages/asl-parser` (`ModuleNode`, `DefunNode`, `TopForm`).
- Checkable Criterion:
  - `.venv/bin/python grammar/closure_audit.py` successfully audits all 107 builtins using the native self-hosted AST, matching `prelude/coverage.lock` exactly.

### Phase 9: Self-Hosted Semantic Type Checker (`packages/asl-checker`) (@pcp:d-8d4c)
- Goal: Implement §9 semantic and typing rules in pure AgentScript (`packages/asl-checker`):
  - Rule checks: arity, totality, reserved prefixes, mandatory `:doc`, nominal union typing, `try` within `Result`, and Hindley-Milner unification.
  - Expose via `asl check <file.asl>`.
- Checkable Criterion:
  - Transpiled `packages/asl-checker` checks the entire `corpus/valid`, `corpus/semantic` (verifying named rule rejection headers), and all `packages/**/*.asl`.

### Phase 10: Complete Self-Hosted Bootstrap & Native CI Pipeline (@pcp:d-8d4c)
- Goal: Multi-target compiler frontend (`packages/asl-compiler`) written in pure ASL.
  - The native compiler compiles `packages/asl-parser`, `packages/asl-checker`, and `packages/asl-compiler` into native binaries (via Rust/Go/Wasm).
  - The compiler checks and builds itself (reproducible bootstrap).
  - All CI pre-commit gates execute natively via `asl check` and `asl test`.
- Checkable Criterion:
  - 100% self-hosted compilation round-trip with byte-for-byte deterministic output.

## Out of Scope
- Modifying tree-sitter C syntax highlighting grammar for VS Code (textmate/syntax highlighting is preserved for editors).
- Breaking existing Lark grammar file used by external Python LLM constrained decoders (vLLM/Outlines compatibility preserved).
