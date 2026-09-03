# Phase 7 — Reconciliation (v2)

Source: `REVIEW-scope.md` (lens: scope & correctness, verdict: **reject**, 4 blocking
findings). Findings in: 4. Rows out: 4. Every finding accepted; nothing rejected, nothing
dropped.

| # | Finding | Disposition | Amendment made in PLAN.md v2 |
|---|---------|-------------|------------------------------|
| F1 | [blocking] `native_parse` does not exist; `tools/native_parser.py` exports only `native_render(src: str) -> str` and `NativeParserError` (`.message`, `.line`, `.col`) — the plan's imports in Items 1 and 2 would `ImportError` at gate startup. | ACCEPTED | Both Items 1 and 2 amended to `from tools.native_parser import native_render, NativeParserError`. Item 1's "What" now states the module's only entry point is `native_render`, that there is no `native_parse`, and that `parses()` calls `native_render(src)`. The `native_parse` name no longer appears anywhere in the plan. |
| F2 | [blocking] Item 2 replaced only `lark_accepts(path)`, leaving `from lark import Token` (`grammar/validate.py:24`), `from lark.exceptions import LarkError` (`:25`), `from parse import parse_file, parse_text` (`:27`), `lark_spans()` (`:103`), `PROBES`, and `token_identity()` (`:117`) alive — the "zero Lark imports and zero Lark execution" criterion would be unmet. | ACCEPTED | Item 2's "What" now enumerates the full deletion: the three import lines, `lark_accepts`, `lark_spans`, `token_identity`, the `PROBES` list, and the `token_identity()` call site in `main()`. The corpus loop calls `native_accepts(path)` backed by `native_render`; `treesitter_accepts(path)` is kept as the reference arm. The plan also records *why* the PROBES are deleted rather than re-expressed: the self-hosted reader emits no token spans, so the span-identity check has no native side to compare against (option (a) of the review). |
| F3 | [blocking] Item 1 instructed a Nano wrap `(df agentscript-doc-example [] -> Unit\n{src}\n())`, but current code (`tools/doc_examples.py:69-74`) wraps in the verbose `(defun ...)` form; the plan was silent on what the wrap means under `native_render`. | ACCEPTED | Item 1 amended to keep the existing verbose `(defun agentscript-doc-example [] -> Unit\n{src}\n())` wrap unchanged, explicitly forbidding the Nano `(df ...)` wrap, and stating the wrap string itself must parse cleanly under `native_render`. `parses()` catches `NativeParserError` and reports its message with the offending line and column. |
| F4 | [blocking] Item 3 deleted `from lark import Lark` but not `from lark.exceptions import LarkError` (`tools/tests/test_native_parity.py:49`), and the claim "Lark is cleanly removed from pre-commit hooks and gate checks" is literal-false (checker, backends, formatter, linter, transcoder keep Lark until Phases 9–10). | ACCEPTED | Item 3's "What" now deletes **both** import lines plus `_lark()`, `_lark_accepts()`, and `test_lark_still_agrees_with_the_reference()` (the function deletion removes `LarkError`'s only remaining use). The false claim is replaced with an accurate scope note: Lark is removed from the two validation gates and the parity suite's secondary test; the pre-commit chain as a whole is not Lark-free after this phase, with the remaining users named and deferred to Phases 9–10. |

## Notes carried for the implementer (from the review, non-blocking)

- The per-fixture "why" diagnostic in `validate.py` should be formatted from
  `NativeParserError` as `f"line {exc.line}:{exc.col}: {exc.message}"` so failure reports
  stay actionable (review N2; baked into Item 2's "What").
- Whether `native_render` rejects every `corpus/invalid` fixture is runtime work covered
  by `test_native_rejects_invalid_corpus`; run the full parity suite before declaring
  Item 2 done (review U1).

## Item ordering

Unchanged from v1: Items 1–4 in the same order. The acceptance criterion is unchanged in
form and spirit: `grammar/validate.py && tools/doc_examples.py --quiet &&
pytest tools/tests/test_native_parity.py -q` with zero Lark imports and zero Lark
execution in those three files.
