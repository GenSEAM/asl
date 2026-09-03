# Phase 7 — Retiring Lark & Migrating Conformance & Doc Validation to Native Parser (asl-selfhosted-runtime-v1)

> v2 — reconciliation of REVIEW-scope.md (verdict: reject, 4 blocking findings). All four
> findings are folded in: the parser entry point is `native_render` (not `native_parse`),
> Item 2 deletes the full Lark surface of `grammar/validate.py` (not just `lark_accepts`),
> Item 1 keeps the verbose `defun` wrap, and Item 3 deletes both Lark imports plus the
> claim about pre-commit hooks is scoped to the gates this phase actually touches. The v2
> text below is the whole plan, not a diff.

## Acceptance criterion

```
.venv/bin/python grammar/validate.py && .venv/bin/python tools/doc_examples.py --quiet && .venv/bin/python -m pytest tools/tests/test_native_parity.py -q
```

A command sequence that runs both gates and the parity suite with **zero Lark imports and
zero Lark execution in those three files**, validating the entire corpus, all package
sources, and all markdown documentation blocks via the self-hosted AgentScript parser
(`packages/asl-parser`) against the tree-sitter reference grammar.

## Context & Motivation (@pcp:d-8d4c)

The AgentScript syntax has historically carried four encodings:
1. `grammar/tree-sitter-agentscript/grammar.js` (reference tooling grammar)
2. `grammar/agentscript.lark` (Earley parser; legacy constrained-decoding path)
3. `packages/asl-parser/src/{lexer,reader,ast}.asl` (100% pure self-hosted parser)
4. `tools/transcoder.py` (Nano/Verbose projection rewriter)

In `ROADMAP.md`, `test_native_parity.py`, and architectural decision `@pcp:d-8d4c`, the
project formally retired Lark. The self-hosted parser (`packages/asl-parser`) is now fully
scalable (iterative scanner in Phase 4) and has demonstrated 100% parity across 399 tests
(`tools/tests/test_native_parity.py`).

However, two critical validation gates in the CI pre-commit pipeline still import Lark:
- `tools/doc_examples.py`: parsed embedded Markdown examples with Lark.
- `grammar/validate.py`: compared tree-sitter against Lark Earley rather than the
  self-hosted parser.

This phase executes the retirement of Lark from those two validation gates and from the
parity suite's secondary Lark arm:
1. `tools/doc_examples.py` switches to `tools.native_parser.native_render` (self-hosted
   parser).
2. `grammar/validate.py` deletes its Lark surface entirely and validates `corpus/valid`,
   `corpus/semantic`, `corpus/modules`, and `corpus/invalid` against the self-hosted
   parser alongside tree-sitter.
3. `tools/tests/test_native_parity.py` drops the retired Lark secondary test assertions.

The checker, backends, formatter, linter and transcoder keep Lark until Phases 9–10 and
are out of scope here.

---

## Work Items

### Item 1 — Migrate `tools/doc_examples.py` to Native Self-Hosted Parser

**What.** Edit `tools/doc_examples.py`. Remove `from parse import parse_text`. Import
`from tools.native_parser import native_render, NativeParserError` — the module's only
parser entry point is `native_render(src: str) -> str`, which parses with the self-hosted
parser and returns the verbose rendering on success and raises `NativeParserError`
(carrying `.message`, `.line`, `.col`) on rejection; there is no `native_parse`. Update
`parses(src: str) -> str | None` to call `native_render(src)`, catching
`NativeParserError` and reporting its message with the offending line and column. Keep
the existing bare-expression wrap unchanged, in the **verbose** form
`(defun agentscript-doc-example [] -> Unit\n{src}\n())` — do not switch to a Nano
`(df ...)` wrap; the wrap string itself must parse cleanly under `native_render`.

**Why.** `tools/doc_examples.py:28` explicitly states: *"Lark is being retired; when it
goes, point parses() at the tree-sitter grammar or at the self-hosted parser in
packages/asl-parser."* This directly validates that published documentation parses under
our own self-hosted engine.

**Gate.**
```
.venv/bin/python tools/doc_examples.py --quiet
```
Must pass: `31 block(s) checked, 15 opted out, 0 failure(s)`.

---

### Item 2 — Migrate `grammar/validate.py` to Compare Tree-Sitter vs Native Self-Hosted Parser

**What.** Edit `grammar/validate.py` and delete its **entire** Lark surface, not just the
accept function:

- Delete the import lines `from lark import Token`, `from lark.exceptions import
  LarkError`, and `from parse import parse_file, parse_text`.
- Delete `lark_accepts(path)`, `lark_spans(...)`, `token_identity()`, and the `PROBES`
  list, together with the `failures += token_identity()` call site in `main()`.
- Add `from tools.native_parser import native_render, NativeParserError`.
- Add `native_accepts(path)` backed by `native_render(src)`; the corpus loop's
  `lark_accepts(path)` call is replaced with `native_accepts(path)`.
- Retain `treesitter_accepts(path)` as the reference arm.

The span-identity PROBES are deleted outright because they were a Lark-vs-tree-sitter
token-span equality check and the self-hosted parser offers no native side to compare
against: `packages/asl-parser/src/reader.asl` emits no token spans, and the only
line/col on the public surface is on a rejected `NativeParserError`. Preserve the
per-fixture "why" diagnostic by formatting the native rejection as
`f"line {exc.line}:{exc.col}: {exc.message}"`.

Ensure all fixtures in `grammar/corpus/valid/`, `grammar/corpus/semantic/`, and
`grammar/corpus/modules/` are accepted by BOTH tree-sitter and the native parser, and all
fixtures in `grammar/corpus/invalid/` are rejected by BOTH.

**Why.** The conformance gate proves that the self-hosted parser and the reference
grammar agree on the language. Comparing the native parser directly in `validate.py`
ensures any future syntax additions or regressions are caught immediately without Lark —
and with the deletions above, the file's zero-Lark claim in the acceptance criterion
becomes literal rather than aspirational.

**Gate.**
```
.venv/bin/python grammar/validate.py
```
Must exit 0 with 0 failures across all corpus categories.

---

### Item 3 — Retire Lark Secondary Checks from `tools/tests/test_native_parity.py`

**What.** Edit `tools/tests/test_native_parity.py`. Follow lines 12–15: delete
`_lark()`, `_lark_accepts()`, `test_lark_still_agrees_with_the_reference()`, and **both**
Lark import lines — `from lark import Lark` and `from lark.exceptions import LarkError`
(deleting `_lark_accepts` removes `LarkError`'s only remaining use).

**Why.** As documented in Phase 6: *"retiring it means deleting _lark_accepts,
test_lark_still_agrees_with_the_reference and the lark import — every other test in this
file is already written against tree-sitter and needs no change."*

Scope note: this claim is literal only for what this phase touches — Lark is removed from
the two validation gates (`grammar/validate.py`, `tools/doc_examples.py`) and from the
parity suite's secondary test. The pre-commit chain as a whole is not Lark-free after
this phase: the checker, backends, formatter, linter and transcoder keep Lark until
Phases 9–10 (out of scope).

**Gate.**
```
.venv/bin/python -m pytest tools/tests/test_native_parity.py -q
```
Must pass cleanly with all parity tests green.

---

### Item 4 — Verification of All Pre-Commit CI Gates

**What.** Run the full gate battery to guarantee no broken assumptions or toolchain
regressions:
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

**Why.** Fulfills the self-hosted validation migration mandate (@pcp:d-8d4c) without
weakening any invariant or breaking CI.
