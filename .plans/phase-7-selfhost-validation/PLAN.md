# Phase 7 — Retiring Lark & Migrating Conformance & Doc Validation to Native Parser (asl-selfhosted-runtime-v1)

## Acceptance criterion

```
.venv/bin/python grammar/validate.py && .venv/bin/python tools/doc_examples.py --quiet && .venv/bin/python -m pytest tools/tests/test_native_parity.py -q
```

A command sequence that runs both gates and the parity suite with **zero Lark imports and zero Lark execution**, validating the entire corpus, all package sources, and all markdown documentation blocks via the self-hosted AgentScript parser (`packages/asl-parser`) against the tree-sitter reference grammar.

## Context & Motivation (@pcp:d-8d4c)

The AgentScript syntax has historically carried four encodings:
1. `grammar/tree-sitter-agentscript/grammar.js` (reference tooling grammar)
2. `grammar/agentscript.lark` (Earley parser; legacy constrained-decoding path)
3. `packages/asl-parser/src/{lexer,reader,ast}.asl` (100% pure self-hosted parser)
4. `tools/transcoder.py` (Nano/Verbose projection rewriter)

In `ROADMAP.md`, `test_native_parity.py`, and architectural decision `@pcp:d-8d4c`, the project formally retired Lark. The self-hosted parser (`packages/asl-parser`) is now fully scalable (iterative scanner in Phase 4) and has demonstrated 100% parity across 399 tests (`tools/tests/test_native_parity.py`).

However, two critical validation gates in the CI pre-commit pipeline still imported Lark:
- `tools/doc_examples.py`: parsed embedded Markdown examples with Lark.
- `grammar/validate.py`: compared tree-sitter against Lark Earley rather than our self-hosted parser.

This phase executes the retirement of Lark from validation:
1. `tools/doc_examples.py` switches to `tools.native_parser.native_parse` (self-hosted parser).
2. `grammar/validate.py` validates `corpus/valid`, `corpus/semantic`, `corpus/modules`, and `corpus/invalid` against `native_parser` alongside `tree-sitter`.
3. `tools/tests/test_native_parity.py` drops the retired Lark secondary test assertions.

---

## Work Items

### Item 1 — Migrate `tools/doc_examples.py` to Native Self-Hosted Parser

**What.** Edit `tools/doc_examples.py`. Remove `from parse import parse_text`. Import `from tools.native_parser import native_parse, NativeParserError`. Update `parses(src: str) -> str | None` to invoke `native_parse(src)`. Handle bare expression wrapping via `(df agentscript-doc-example [] -> Unit\n{src}\n())` using the compact default syntax.

**Why.** `tools/doc_examples.py:28` explicitly states: *"Lark is being retired; when it goes, point parses() at the tree-sitter grammar or at the self-hosted parser in packages/asl-parser."* This directly validates that published documentation parses under our own self-hosted engine.

**Gate.**
```
.venv/bin/python tools/doc_examples.py --quiet
```
Must pass: `31 block(s) checked, 15 opted out, 0 failure(s)`.

---

### Item 2 — Migrate `grammar/validate.py` to Compare Tree-Sitter vs Native Self-Hosted Parser

**What.** Edit `grammar/validate.py`. Replace `lark_accepts(path)` with `native_accepts(path)` backed by `tools.native_parser.native_parse`. Retain `treesitter_accepts(path)` as the reference. Ensure all fixtures in `grammar/corpus/valid/`, `grammar/corpus/semantic/`, and `grammar/corpus/modules/` are accepted by BOTH tree-sitter and the native parser, and all fixtures in `grammar/corpus/invalid/` are rejected by BOTH.

**Why.** The conformance gate proves that the self-hosted parser and the reference grammar agree on the language. Comparing the native parser directly in `validate.py` ensures any future syntax additions or regressions are caught immediately without Lark.

**Gate.**
```
.venv/bin/python grammar/validate.py
```
Must exit 0 with 0 failures across all corpus categories.

---

### Item 3 — Retire Lark Secondary Checks from `tools/tests/test_native_parity.py`

**What.** Edit `tools/tests/test_native_parity.py`. Follow lines 12–15: delete `_lark()`, `_lark_accepts()`, `test_lark_still_agrees_with_the_reference()`, and `from lark import Lark`.

**Why.** As documented in Phase 6: *"retiring it means deleting _lark_accepts, test_lark_still_agrees_with_the_reference and the lark import — every other test in this file is already written against tree-sitter and needs no change."*

**Gate.**
```
.venv/bin/python -m pytest tools/tests/test_native_parity.py -q
```
Must pass cleanly with all parity tests green.

---

### Item 4 — Verification of All Pre-Commit CI Gates

**What.** Run the full gate battery to guarantee no broken assumptions or toolchain regressions:
- `grammar/validate.py` (Tree-sitter + Native Parser)
- `grammar/closure_audit.py`
- `prelude/generate.py --check`
- `checker/gate.py`
- `tools/doc_examples.py --quiet`
- `backend/check_corpus.py`
- `backend/monomorphism.py`
- `backend/differential.py`
- `pytest backend/tests checker/tests tools/tests -q`
- `node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize`
- `npm run build:web`

**Why.** Fulfills the self-hosted validation migration mandate (@pcp:d-8d4c) without weakening any invariant or breaking CI.
