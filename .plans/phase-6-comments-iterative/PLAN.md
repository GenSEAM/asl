# Phase 6 — `;` comments + iterative reader/renderer

Iteration: `asl-selfhosted-runtime-v1`. Acceptance criterion (`.plans/PHASES.md`, Phase 6):
`.venv/bin/python -m pytest tools/tests/test_native_parser.py tools/tests/test_native_parse_all.py -q`
with comment round-trips and deep-nesting cases added; the existing 14 + 38 stay green —
except one test whose *premise* this phase deletes (see Item 5 and the flagged decision).

Baseline measured this session: the phase gate currently reports **44 passed** (all probes
below re-run and captured verbatim today).

## Design decision — renderer: option (a), cached canonical text at construction

`render-sexpr` is called on arbitrary constructed `SExpr` values, not only on parsed tokens:
`ast.asl:262` (fun-node ret-type), `ast.asl:279` (param-node type), `ast.asl:300` (field-node
type), `ast.asl:379` (render-defun body), `reader_test.asl:117` (head-decl body), and
`ast_driver.asl:52` constructs `rd/sexpr-atom` directly. A read-time flat piece list cannot
serve subtree renders, and a tree traversal needs "while stack non-empty", which no builtin
expresses (`fold` at `prelude/prelude.json:754` walks a fixed list; lowering is
`backend/runtime.py:189` — a plain Python `for`).

But rendering is purely bottom-up and local: a node's text is `open + join(child texts) + close`.
So the cache can be computed **during construction**, which the iterative reader's fold already
drives bottom-up. `sexpr-list`/`sexpr-vect` gain a `text String` field computed by
`make-list`/`make-vect` from their children's cached text (children's text is a field read —
no recursion, no "while"). `render-sexpr` becomes a field read. `sexpr-atom` is unchanged (its
render *is* its `val`). There is no raise/error builtin in `prelude.json` (grep: no
error/raise/panic/fail/abort/assert), so option (b)'s clean diagnostic would have to thread an
`Option String` through `render-sexpr`'s exported `String` contract and every caller listed
above — that is the rejection reason for (b), not taste.

Byte-identity is pinned by existing hand-written expectations:
`test_reader.py` `EXPECT_RENDER` (incl. nested `(match sh ...)`), `test_nano_verbose_roundtrip`
over three sources, and `native_render` stability tests.

## Work items (ordered)

### 1. `;` line comments in the native lexer — `packages/asl-parser/src/lexer.asl`

**What.** Add `(:c run-comment [])` to the `RunMode` enum (`lexer.asl:88`). In
`run-continues?` (`lexer.asl:94`) add `((run-comment) (not (= ch "\n")))` — needed for match
totality even though `step` short-circuits comment mode first. In `open-char`
(`lexer.asl:153`) add a `((= ch ";") ...)` branch **before** the `:else` symbol branch that
opens `run-comment` with empty raw text at the current line/col, emitting nothing. In `step`
(`lexer.asl:199`) special-case comment mode before the existing string-close check: when the
open run is `run-comment` and `ch` is `"\n"`, return the state with unchanged toks, line + 1,
col 1, run `(none)` (handing the newline to the whitespace path's accounting); otherwise return
the state **unchanged** (the char is consumed silently, nothing emitted). In `flush`
(`lexer.asl:210`) skip an open `run-comment` run instead of emitting it — the generic open-run
emit calls `run-token` (`lexer.asl:101`), whose `mt` has no comment case, so a trailing comment
without a newline would be a runtime match failure, not just a wrong token.

**Why.** The Lark grammar declares `COMMENT: /;[^\n]*/` + `%ignore COMMENT`
(`grammar/agentscript.lark:199,203`); the native lexer treats `;` as a symbol char
(`is-symbol-char`, `lexer.asl:72`), so `; hello world` lexes into garbage symbol tokens that
`decl-form`'s fallback holds as retained defuns (`ast.asl:201,209`).

**Preserved behavior.** `;` inside a string literal is ordinary text: `open-char` only sees `;`
outside any run, and the string run's continuation accepts everything but `"`
(`lexer.asl:94-99`). `run-token` and `token-type-name` need no new cases (comments emit no
token). Exported surface (`:x` at `lexer.asl:3-5`) unchanged.

**Gate** (fails now, green when done):

```
.venv/bin/python -c "
from tools.native_parser import native_render
c = '(module m)\n; hello world\n(defun f [] -> Int64 1)\n'
free = '(module m)\n(defun f [] -> Int64 1)\n'
assert native_render(c) == native_render(free)
print('OK')
"
```

Current verbatim output (measured; probe source slightly shorter than the gate's):

```
'(module :doc "x")\n(defun  [] ->  ;)\n(defun  [] ->  hello)\n(defun  [] ->  world)\n(defun f [] -> Int64 1)'
```

**Expected result when green:** the gate prints `OK` — the commented module renders exactly as
its comment-free twin.

**What breaks if it runs first:** nothing — Item 2 is independent of the lexer.

### 2. Iterative reader — `packages/asl-parser/src/ast.asl`

**What.** Replace `read-forms`/`read-one`/`read-seq-items` (`ast.asl:70-104`) and `tail-toks`
(`ast.asl:106`) with a single shift-reduce `fold` over the token list — the same pattern the
lexer already proves (`ScanState` accumulator, `fold step ... (string-chars s)`,
`lexer.asl:116-131,222`). New state types in `ast.asl`:

- `dfs RFrame` — `:f is-paren Bool`, `:f items (List rd/SExpr)` (kept reversed, appends are cons).
- `dfs RState` — `:f stack (List RFrame)` (top = head), `:f out (List rd/SExpr)` (reversed),
  `:f stopped Bool`.

`reader-step` dispatches on the token's raw text exactly as the current code does
(`read-forms` stops at raw `""`, `read-one` dispatches on `"("`/`"["`, `ast.asl:70-91`):

- stopped → return state unchanged (EOF is the last token `flush` emits, `lexer.asl:210-220`;
  the flag is defensive).
- raw `(` → push `(RFrame :is-paren true :items (list))`; raw `[` → push with `is-paren false`.
- raw `)` / `]`:
  - stack empty → append `(rd/make-atom (norm-atom raw))` to `out` (current: `read-one`'s
    `:else` branch, `ast.asl:89`);
  - top frame matches the closer → pop, build `(rd/make-list (list-reverse items))` or
    `(rd/make-vect ...)`, then: stack now empty → cons to `out`; else cons into the new top
    frame's `items` (current: `ast.asl:96-101`);
  - top frame is the *other* kind → append the closer as an atom `(rd/make-atom (norm-atom raw))`
    into the top frame's items (current: `read-seq-items` only stops on its own close and reads
    everything else through `read-one`, `ast.asl:92-104`).
- raw `""` (EOF token):
  - stack empty → set `stopped`, return (current: `read-forms` stops at raw `""`, `ast.asl:74`);
  - stack non-empty → clear the stack, append `(rd/make-atom "")` to `out`, set `stopped`
    (current: an unterminated seq discards its accumulated items and yields atom `""` with all
    remaining tokens consumed — traced through `ast.asl:92-104`: each `read-seq-items` level's
    `none` branch returns `(pair (rd/make-atom "") (list))`, dropping `acc`).
- any other raw → append `(rd/make-atom (norm-atom raw))` to the top frame's items, or to `out`
  when the stack is empty.

`read-all` finalizes with `(list-reverse (.-out state))`; `parse` (`ast.asl:65-68`) calls
`(read-all (lx/tokenize src))`. Delete `read-forms`, `read-one`, `read-seq-items`, `tail-toks`
(grep: no references outside `ast.asl:65-109`; `tail-exprs` at `ast.asl:112` stays — it is used
throughout). None of these four are in `:x` (`ast.asl:3`).

**Declared expected results** (the shunting-yard and the recursion must agree on these; they
become characterization assertions in Item 5):

| Input | Expected |
|---|---|
| `(a)` / `[a]` | list / vect containing atom `a` |
| `()` / `[]` | empty list / empty vect |
| stray `)` or `]` at top level | its own atom top form, raw text kept, `norm-atom` applied |
| `)` inside `[...]` (and vice versa) | atom `)` appended as an item |
| `( x` unterminated | single top form `(sexpr-atom "")`, everything after consumed |

**Gate** (fails now, green when done):

```
.venv/bin/python -c "
import sys; sys.path.insert(0, 'packages/asl-parser/tests')
from harness import run_asl
ns = run_asl('packages/asl-parser/tests/reader_test.asl')
out = ns['proj_parse']('('*3000 + ')'*3000)
assert out == 'module||0|0|1', out
print('OK')
"
```

Current verbatim output:

```
RAISED: RecursionError maximum recursion depth exceeded
```

**Expected result when green:** `OK`. Hand-derived: the deep form becomes the module header
(`build-module`, `ast.asl:154-162`), mined for `:doc`/`:export`/`:import` (all absent), so
`proj-module` prints `module||0|0|1` (`reader_test.asl:41-45`) and no body is rendered — this
gate isolates the reader from the renderer.

**What breaks if it runs before Item 1:** nothing, but the Item 1 gate's garbage-render
symptom is partly a reader artifact; running 1 first keeps the comment fix observable
independently. If Item 3 ran before this, its gate stays red — the reader overflows first.

### 3. Non-recursive renderer — `packages/asl-parser/src/reader.asl`

**What.** Give `sexpr-list` and `sexpr-vect` a second field `(:f text String)` — the canonical
render, computed at construction (`reader.asl:7-9`). `make-list`/`make-vect`
(`reader.asl:15-21`) build it as `(str open (string-join (map sexpr-text items) " ") close)`;
new helper `sexpr-text` returns `val` for atoms and the `text` field for lists/vects (forward
reference within the module is established practice: `token-kind` calls `delim-kind` defined
below it, `lexer.asl:39,80`). `render-sexpr` (`reader.asl:67-72`) returns the atom's `val` or
the cached `text`; `render-compound` (`reader.asl:60-65`) keeps its exported
`(is-paren Bool) (items (List SExpr))` signature and reads children's cached text. Update every
pattern match on the two changed cases to bind the new field: `is-atom?` (`reader.asl:26-28`),
`is-list?` (`reader.asl:33-35`), `sexpr-head` (`reader.asl:40-49`), `sexpr-items`
(`ast.asl:118-123`). `ast_driver.asl:52` constructs only `rd/sexpr-atom` — unaffected.

**Why.** Item 2 makes the reader survive 3000+ nesting; `render-defun` then overflows in
`rd/render-sexpr` (`ast.asl:379`). See the design decision above for why (a) and not (b).

**Gate** (fails now, green when done):

```
.venv/bin/python -c "
from tools.native_parser import native_render
deep = '('*3000 + ')'*3000
out = native_render('(defun f [] -> Int64 ' + deep + ')')
assert out == '(defun f [] -> Int64 ' + deep + ')', out[:80]
print('OK')
"
```

Current verbatim output:

```
RAISED: NativeParserError maximum recursion depth exceeded
```

**Expected result when green:** `OK`; byte-exact render derived from `render-defun`
(`ast.asl:368-383`): `(defun ` + empty mark/type-vars + `f` + ` [] -> Int64` + one joined body
item + `)`. The deep form must sit in a *defun body* — as a bare module header it is mined for
`:doc` and never rendered (see Item 2's expected result).

**What breaks if it runs before Item 2:** the gate stays red — the reader, not the renderer,
overflows first on this input. Byte-identity is guarded throughout by `test_reader.py`
`EXPECT_RENDER` / `test_nano_verbose_roundtrip` and `test_native_parser.py` stability tests.

### 4. Iterative top-form conversion — `decl-forms` in `packages/asl-parser/src/ast.asl`

**What.** `decl-forms` (`ast.asl:192-199`) recurses once per top-level form. Once Item 1 lands,
every comment line becomes a retained defun (`ast.asl:201,209`), so a 2,000-line comment-heavy
file means 2,000-deep recursion. Rebuild it as
`(list-reverse (fold decl-step (list) sexprs))` where `decl-step` conses `(decl-form s exported)`
— the existing left-fold shape. `build-module` (`ast.asl:154-162`), `find-opt`
(`ast.asl:139-146`) and `collect-vars` (`ast.asl:224-232`) recurse per *item of one form*
(width), which stays bounded for realistic forms; leave them.

**Gate** (fails now, green when done — green only after Item 2, whose recursion fires first on
this input):

```
.venv/bin/python -c "
from tools.native_parser import native_render
out = native_render('(a)\n' * 2000)
lines = out.split('\n')
assert lines[0] == '(module :doc )' and len(lines) == 2000, (lines[0], len(lines))
print('OK')
"
```

Current verbatim output:

```
RAISED: NativeParserError maximum recursion depth exceeded
```

**Expected result when green:** `OK`; 1 module line + 1,999 retained-defun renders
`(defun  [] ->  a)` (hand-derived from `render-defun`, `ast.asl:368-383`, with empty
name/type-vars/ret on `retained-defun`, `ast.asl:209-212`).

**What breaks if it runs before Item 2:** the gate stays red (read-forms recursion fires first
at the same depth), so the item would look unfinished even when correct.

### 5. Tests, one amended premise, and the full phase gate

**What.**

- `tools/tests/test_native_parser.py`: add
  `test_comment_roundtrip` — `native_render` of a module with `;` comments equals the
  comment-free twin, and a `;` inside a string docstring survives (assert the docstring text in
  the render);
  `test_deep_nesting_renders` — the Item 3 gate's defun-body case at depth 3000, exact-string
  asserted;
  `test_reader_malformed_characterization` — the five declared rows of Item 2's table, driven
  through `native_render` where observable (stray closer lines, unterminated tail atom `""`)
  or through `proj_parse` where not.
- **Amend** `test_cli_parse_parse_error_reports_diagnostic` (`test_native_parser.py:58-66`):
  its docstring asserts the reader "still recurses per nesting level" — the exact limitation
  this phase removes. Flip it to assert the 3000-deep file now parses: returncode 0 and
  non-empty stdout. **Flagged to the orchestrator:** this is a deliberate premise amendment,
  not a weakened gate; the CLI's error path stays covered by
  `test_cli_parse_bad_file_nonzero` (`test_native_parser.py:51-56`). The phase cannot both make
  deep nesting parse and keep a test asserting it fails.
- Final re-run, phase gate plus the packages regression suites (they pin byte-identical renders
  via hand-written expectations and keep all four touched files checker-clean via
  `resolve.check_file` — `test_lexer.py::test_lexer_files_check_clean`,
  `test_reader.py::test_reader_files_check_clean`):

```
.venv/bin/python -m pytest tools/tests/test_native_parser.py tools/tests/test_native_parse_all.py packages/asl-parser/tests -q
```

Current verbatim output of the phase-gate portion:

```
44 passed in 7.72s
```

**Expected when green:** all pass — prior 44, plus the new tests, plus the amended CLI test in
its flipped form.

**Why last:** every new test asserts behavior delivered by Items 1–4; the amendment in
particular fails until Item 3 lands.

## Risks / unverified

- **Cached-text cost is O(depth²)** in both time and retained memory (each level stores its
  full subtree text): ~9M chars at depth 3000, ~25M at 5000. Unmeasured beyond the probes
  above — the implementer should time the Item 3 gate before fixing the test depth at 5000
  rather than 3000.
- **Fold with a list-of-frames accumulator** — proven one level shallower by the lexer
  (`ScanState` holding `(List Token)`, `lexer.asl:116-131`); `RState` holding `(List RFrame)`
  where `RFrame` itself holds a list is one nesting deeper and unverified until transpiled. The
  Item 2 gate plus `py_compile` inside `harness.run_asl` catches this immediately.
- **Malformed-input semantics** (unterminated seq, mismatched closer) are traced from
  `ast.asl:70-104`, not executed against the current build — if a trace is wrong, the Item 5
  characterization test and the byte-identity suites catch it.
- **Match totality** — adding `run-comment` may make the checker demand a `run-token` case;
  if so, add an unreachable `((run-comment) ...)` arm rather than weakening any check, and say
  so in the commit.
- **`packages/asl-parser/tests` is not part of the AGENTS.md default gate list** — it runs here
  as an explicit regression step; nothing else in CI guards the checker-clean property of these
  four files.

## Out of scope

- `grammar/agentscript.lark`, `grammar/tree-sitter-agentscript/`, `prelude/prelude.json`,
  `backend/` — the Lark grammar already ignores comments (`agentscript.lark:199,203`); no
  builtin or lowering changes are needed (`fold`'s lowering at `backend/runtime.py:189` already
  suffices), so no `--check`/coverage ratchet is touched.
- The Lark-grammar-vs-native differential (`backend/differential.py`) — the native parser is a
  separate pipeline (`packages/asl-parser/tests/harness.py`); wiring it into differential mode
  is a different phase.
- `read-type-vars`/`collect-vars`/`find-opt` width recursions and `proj-rest` in the test driver
  (`reader_test.asl:20-31`) — width-bounded, not nesting-bounded; revisiting them is YAGNI
  until a real input overflows.
- The `web/` showcase and the token-coverage ratchet (`prelude/coverage.lock`) — no vocabulary
  change.
