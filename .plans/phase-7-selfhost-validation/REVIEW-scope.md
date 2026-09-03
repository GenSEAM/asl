# Phase 7 — Scope & Correctness Review

Lens: scope & correctness. Items 1–3 of the parent brief, plus the
literal-claim check on pre-commit.

## Verdict: reject

The plan's acceptance criterion requires `grammar/validate.py`,
`tools/doc_examples.py` and the parity suite to import no Lark and execute
no Lark. As written, Item 2 does not retire enough Lark; Item 1 names an
entry point that does not exist; and Item 3's framing of "drop Lark's
secondary arm from the parity test" collides with `validate.py`'s token
identity PROBES, which the plan does not name.

The plan can be made to pass with three concrete amendments; nothing
structural is wrong, but as filed it would be implemented against a
misnamed API and would leave `from lark import Token` /
`from lark.exceptions import LarkError` / `from parse import parse_text,
parse_file` alive in `validate.py`, in violation of the stated criterion.

---

## Blocking findings

### F1 [blocking] `native_parse` does not exist; only `native_render` is exported

Evidence:
- `tools/native_parser.py:64` defines `def native_render(src: str) -> str:`. The
  module exposes `NativeParserError` and `native_render` only.
  `tools/tests/test_native_parity.py:51` confirms by importing
  `NativeParserError, native_render` (no `native_parse`).
- A repo-wide search turns up no `native_parse` symbol
  (`grep -rn "native_parse\|native_render"` finds 23 hits, every one
  is `native_render`).
- The plan names `native_parse` in **both** the Item 1 instruction
  (`from tools.native_parser import native_parse, NativeParserError`,
  PLAN.md line implied by `Update parses(src: str)`) and the Item 2
  rationale (`backed by tools.native_parser.native_parse`, PLAN.md §2
  "What"). Implementing the plan as written would `ImportError` at gate
  startup.

Disposition: amend the plan to refer to `native_render` exclusively. The
parser's only observable output today is the verbose render — that is
fine for `parses()` (it just needs accept/reject), but Item 2's body
needs to take the absence of a parse-then-tree entry point into account
(see F2).

### F2 [blocking] Item 2 as filed does not retire Lark from `validate.py`

The plan says: "Replace `lark_accepts(path)` with `native_accepts(path)`
backed by `tools.native_parser.native_parse`" (PLAN.md §2 "What"). The
file's Lark surface is wider than that one call:

- `grammar/validate.py:24` `from lark import Token`
- `grammar/validate.py:25` `from lark.exceptions import LarkError`
- `grammar/validate.py:27` `from parse import parse_file, parse_text`
- `grammar/validate.py:35` `lark_accepts(path)` — the function Item 2 names
- `grammar/validate.py:103` `lark_spans(src, terminal)` — powers `token_identity()`
- `grammar/validate.py:117` `token_identity()` — runs the 13 PROBES
- `grammar/validate.py:145` call site `lark_ok, lark_why = lark_accepts(path)`

Even if `lark_accepts` is replaced, the acceptance criterion still imports
`lark.Token`, `lark.exceptions.LarkError`, and `parse.parse_text`, and still
calls `lark_spans` (which loads the Lark Earley parser) in
`token_identity()`. The plan does not say what to do with these.

There are two coherent moves, and the plan needs to pick one:

(a) **Drop the PROBES entirely.** The PROBES were a Lark-vs-tree-sitter
    span equality check (`validate.py:49-78`); they were never a
    native-vs-anything check. `tools.native_parser.native_render` does
    not expose token spans — `packages/asl-parser/src/reader.asl` emits
    bare `SExpr`s with no `line`/`column`/`start_column` fields, and the
    only line/col on the public surface is on a rejected
    `NativeParserError` (`ast.asl:7-10` `ParseError` is the only
    position-bearing record exported). F1 confirms `native_parse` is
    not exposed either. So the 13 PROBES have no native side to compare
    against and must be deleted along with `lark_spans`, `PROBES`,
    `token_identity`, the `Token` import, and the call to
    `failures += token_identity()` in `main()` (`validate.py:172`).

(b) **Re-express the PROBES as `treesitter_spans` × native verbosity
    checks.** Possible in principle but a substantial expansion of
    scope. Not what Item 2's text describes.

Option (a) is the only one consistent with the stated criterion. The
plan must be amended to say so explicitly, and Item 4 must be amended
to name the deleted code (otherwise "Lark is cleanly removed from
pre-commit hooks" — see F4 — would be a false claim).

Disposition: amend Item 2 to:
- replace `lark_accepts(path)` with a `native_accepts(path)` backed by
  `native_render`,
- delete `lark_spans`, `PROBES`, `token_identity`, and the `token_identity`
  call site,
- delete the `from lark import Token`, `from lark.exceptions import
  LarkError`, and `from parse import parse_file, parse_text` imports,
- add `from tools.native_parser import native_render, NativeParserError`.

Acceptance criterion ("zero Lark imports and zero Lark execution")
becomes literal with this amendment.

### F3 [blocking] Item 1's doc_examples fallback wrap is not valid ASL

Evidence:
- The plan's bare-expression wrap is
  `(df agentscript-doc-example [] -> Unit\n{src}\n())` (PLAN.md §1
  "What"). `df` (alias for `defun`) in Core syntax takes an arrow
  (`->`) and a body of expressions, but the unit type's only value is
  `()` and a body of expressions is returned, not executed; a body
  containing a single literal `()` parses but is not what current
  `parses()` produces today.
- Current behavior: `tools/doc_examples.py:69-74` wraps as
  `(defun agentscript-doc-example [] -> Unit\n{src}\n())` (long form,
  `defun`). That works because `grammar/agentscript.lark` accepts both
  forms and `validate.py` round-trips both.
- Under `native_render` the wrapping string itself will be parsed and
  rendered verbose before the inner block is examined. If the plan's
  Nano wrap is rendered verbose, the rendered inner source is then
  reparsed — that's fine for the `native_render`-only `parses()`
  function. But the **wrap shape** must be a valid program under both
  verbose and Nano forms, and `(df ...)` with no doc option is verbose
  for `(defun ...)` — confirming that works is an implementation check,
  not a plan check.

The deeper problem is **what the wrap means under the new API**. With
Lark, `parse_text(src)` accepts either a bare expression or a top-level
form (the `start` rule permits a sequence of declarations). With
`native_render`, the same source must be parseable through
`packages/asl-parser/src/ast.asl:384` `(df parse ...)` — whose grammar
expects a single module header optionally followed by declarations
(see `ast.asl:415` `build-module` and the comment block at
`ast.asl:399-413`). A bare `(str "a" b)` is not a module header and
not a declaration; under the self-hosted parser it is rejected.

The plan needs to state that the fallback wrap is unchanged (long form
`defun`) AND that `native_render` accepts the wrapped form. This is
verifiable (the parity suite's `test_native_render_reparses_under_the_reference`
parametrizes on every file in `corpus/valid/`, and a wrap with a
`defun` body of one or more expressions would, if the wrap itself is
valid ASL, parse cleanly), but the plan should not be silent about it.

Disposition: amend Item 1's instruction to (a) keep the **verbose**
`(defun agentscript-doc-example [] -> Unit\n{src}\n())` wrap rather
than the Nano form the plan currently states, and (b) name the actual
exported symbol `native_render` in the import.

### F4 [blocking] Item 4 / Item 3 context claim that "Lark is cleanly removed from pre-commit hooks" is literal-false

Evidence:
- The pre-commit hook at `tools/hooks/pre-commit` runs 16 gates. Of
  these, the ones that still import Lark after Item 1/2/3 land are:
  - gate 9 `$PYTHON backend/monomorphism.py` — does **not** import
    Lark (verified).
  - gate 10 `$PYTHON backend/differential.py` — does **not** import
    Lark (verified).
  - gate 8 `$PYTHON backend/check_corpus.py` — does **not** import
    Lark (verified).
  - gate 1 `$PYTHON grammar/validate.py` — imports Lark unless F2 is
    amended; the plan as filed leaves `Token`, `LarkError`, and
    `parse_text` imported, so this gate still loads Lark.
  - gate 5 `$PYTHON tools/doc_examples.py --quiet` — imports Lark
    unless F3 is amended.
  - gate 11 `$PYTHON -m pytest ... tools/tests -q` — runs the parity
    suite; unless Item 3 deletes the Lark imports, this gate still
    loads Lark. After Item 3 lands **as the plan describes** (delete
    `_lark`, `_lark_accepts`, `test_lark_still_agrees_with_the_reference`,
    `from lark import Lark`; PLAN.md §3), the `from lark.exceptions
    import LarkError` at `tools/tests/test_native_parity.py:49` is
    still present. The plan says "delete `_lark()`, `_lark_accepts()`,
    `test_lark_still_agrees_with_the_reference()`, and `from lark
    import Lark`" — it does **not** name `from lark.exceptions import
    LarkError`.
  - gate 12 `$PYTHON -m pytest packages/asl-parser/tests -q` — does
    not import Lark.
  - gate 13 `$PYTHON agentscript lint packages` — agentscript at
    `agentscript:577` imports `from lark import Lark`. The `lint`
    subcommand is in scope of the pre-commit chain but not in Phase 7.
  - gate 14 `$PYTHON agentscript clone-check packages` — drives
    `tools/clone_detector.py:18` `from lark import Token, Tree`.
    Phase 9–10 deferred.

So after Phase 7 as filed, three pre-commit gates still load Lark:
gate 1 (`grammar/validate.py`), gate 5 (`tools/doc_examples.py`), and
gate 11 (parity suite, via the leftover `LarkError` import).
Additionally the broader deferred users (`agentscript` CLI, backends,
checker, etc.) still load Lark, but those are out of scope.

The plan's Item 3 context block says "Lark is cleanly removed from
pre-commit hooks and gate checks." That is false as a literal claim;
it is true only for the subset `{tools/doc_examples.py, parity suite's
secondary arm, grammar/validate.py's accept loop}` — and the last of
those three is only true if F2 is amended.

Disposition: amend the Item 3 framing. The accurate statement is:
"Lark is removed from the two validation gates and from the parity
suite's secondary test"; and tighten Item 3's instruction to delete
**both** `from lark import Lark` and `from lark.exceptions import
LarkError` at `tools/tests/test_native_parity.py:48-49`. (Confirm
whether `LarkError` is otherwise referenced — `grep -n LarkError`
in the file shows only the import and the catch in `_lark_accepts`
at line 87; deleting the function removes the use.)

---

## Non-blocking

### N1 [non-blocking] `native_render` accepts a `(defun …)` wrap, but the plan should name it

The current `parses()` wrap string
`(defun agentscript-doc-example [] -> Unit\n{src}\n())` is a
top-level declaration with a body of `s-expr`s. The self-hosted parser
treats the body of a `(df ...)` as expressions (`ast.asl:530` `fun-node`
and downstream). A body containing a bare expression like `(str "a" b)`
will be parsed as a list literal then rendered verbose; that round
trip parses cleanly under the reference grammar because the rendered
form is the verbose projection. No additional plan work needed beyond
F3's "keep verbose form".

### N2 [non-blocking] `NativeParserError` carries `line` and `col`, but the per-fixture diagnostic in `validate.py` currently renders Lark's exception string

`validate.py:36-37` returns `str(exc).splitlines()[0]` for Lark's error.
After F2, the equivalent of `lark_why` is `f"line {exc.line}:{exc.col}: {exc.message}"`
for the native parser. The plan does not specify the diagnostic shape
under the native parser. This is not a Phase 7 blocker (the criterion
is "zero Lark imports"; the diagnostic format is presentation), but
the implementer should preserve the per-fixture "why" string so the
gate's failure report stays actionable. Flag for the implementer, not
the plan.

### N3 [non-blocking] Item 4 verification list is reasonable but understates the Lark surface

Item 4 (PLAN.md §4) names the gates the implementer must rerun. It
correctly omits `grammar/parse.py` (not a gate, even though it imports
Lark) and `agentscript` CLI subcommands (not in the listed gates
except for `lint` and `clone-check`). It does not name
`tools/hooks/pre-commit` itself; a verify pass that runs Item 4's
gates individually but not the hook would miss drift if a new Lark
import lands in a file the hook does not execute. Recommend adding
`tools/hooks/pre-commit` to Item 4's verification list, or
alternatively confirming by `grep -L "lark"` over the 16 gate
commands' source files.

---

## Unverified

### U1 [unverified] Whether `native_render` rejects every fixture in `corpus/invalid/`

`tools/tests/test_native_parity.py:155-158` `test_native_rejects_invalid_corpus`
asserts this; the file says "everything in corpus/invalid". The plan
references this as part of Phase 6. If it has held since Phase 6, the
gate continues to enforce it; the implementer should run the full
suite before declaring Item 2 done. Cannot verify from the plan text
alone — verifying it is implementation work.

### U2 [unverified] Whether `(df agentscript-doc-example [] -> Unit\n{src}\n())` parses under `native_render`

The plan instructs a Nano wrap; see F3. Whether the **Nano** wrap is
parseable as a self-hosted-program is a runtime check. I have not run
it. The verbose wrap is well-formed and renders back, based on the
existing parity suite's structure; the Nano form should be too, but
this is a runtime assertion.

---

## Files inspected

- `/Users/purplelephant/projects/asex/.plans/phase-7-selfhost-validation/PLAN.md`
- `/Users/purplelephant/projects/asex/grammar/validate.py`
- `/Users/purplelephant/projects/asex/grammar/parse.py`
- `/Users/purplelephant/projects/asex/tools/doc_examples.py`
- `/Users/purplelephant/projects/asex/tools/native_parser.py`
- `/Users/purplelephant/projects/asex/tools/tests/test_native_parity.py`
- `/Users/purplelephant/projects/asex/tools/tests/test_native_parse_all.py`
- `/Users/purplelephant/projects/asex/packages/asl-parser/src/ast.asl` (excerpts)
- `/Users/purplelephant/projects/asex/packages/asl-parser/src/reader.asl` (full)
- `/Users/purplelephant/projects/asex/packages/asl-parser/tests/reader_test.asl` (full)
- `/Users/purplelephant/projects/asex/tools/hooks/pre-commit` (full)
- `/Users/purplelephant/projects/asex/agentscript` (excerpts: `:577`, CLI driver)
- `grammar/tree-sitter-agentscript/grammar.js` (qualified / operator rules)

No source files were edited. The plan file was not edited. Only
`/Users/purplelephant/projects/asex/.plans/phase-7-selfhost-validation/REVIEW-scope.md`
was created.
