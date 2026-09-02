# REVIEW — lens: backend feasibility

## Verdict
**approve-with-amendments** — the execution path is real, but four claims in the
plan cite wrong line numbers or skip verifications that must be done before item 1
closes. None of the amendments changes the architecture; all are pre-implementation
sharpening so the smoke driver doesn't fail at item 1 with an opaque traceback.

## Findings (numbered)

1. **Verified-builtin table — every entry present and matches the lowering.**
   Read `prelude/prelude.json` directly:
   - `string-length` → `len({0})` (Python `len`): present.
   - `string-slice` → `_agentscript.str_slice({0},{1},{2})`: present.
   - `string-index-of` → `_agentscript.str_index_of({0},{1})`: present.
   - `string-contains?` → `({1} in {0})`: present.
   - `string-starts-with?` → `{0}.startswith({1})`: present.
   - `string-split` → `{0}.split({1})`: present.
   - `string-join` → `{1}.join({0})`: present (arg order is `(List String) String`).
   - `string-chars` → `list({0})`: present.
   - `string-to-int64` → `_agentscript.to_int({0})`: present.
   - `string-from-int64` → `str({0})`: present.
   - `str` → `"".join([{*}])`: present.
   - `list-cons` → `([{0}] + {1})`: present.
   - `list-append` → `({0} + {1})`: present.
   - `list-head` → `_agentscript.at({0},0)`: present.
   - `list-tail` → `_agentscript.tail({0})`: present.
   - `list-empty?` → `(len({0}) == 0)`: present.
   - `list-reverse` → `{0}[::-1]`: present.
   - `map` → `[{0}(_x) for _x in {1}]`: present.
   - `pair` → `_agentscript.pair({0},{1})`: present.
   No entry is missing or lowering-absent. Smoke driver can exercise the table as
   described. **Not a blocker.**

2. **`str_slice` is half-open, end-exclusive — `backend/runtime.py:196-200`.**
   ```
   def str_slice(s, a, b):
       if 0 <= a <= b <= len(s):
           return some(s[a:b])
       return NONE
   ```
   Python slice `s[a:b]` is half-open, and the guard enforces `a <= b`. The plan
   admits this was unverified; it now resolves the gap. The plan's "Implementer
   verifies before writing the scanner loop" risk should be closed by reading
   these four lines. **Not a blocker** — but the implementer must not skip the
   read; the scanner's slice indices are correct only against this convention.

3. **Harness model: the plan's `runpy` approach matches `backend/check_corpus.py`
   line-for-line, but the cited range is wrong.**
   - Plan cites `backend/check_corpus.py:57-76` for the harness approach. The
     actual `execute()` body is at **lines 50-60** (a 19-line block, not 20),
     and the next 16 lines (61-76) are `main()`. The behaviour the plan
     describes — copy `runtime.py` next to the candidate, `runpy.run_path`,
     `eval` the result in the namespace — is exactly what `execute()` does
     (`check_corpus.py:50-60`). The plan's outline is correct; the citation is
     off by seven lines.
   - The emitted Python really opens with `import runtime as _agentscript`
     (`backend/to_python.py:104`), confirmed. `runpy.run_path` resolves the
     `runtime` import against the directory of the candidate file, and the
     harness copies `runtime.py` into that directory, so `import runtime`
     works as long as `cwd=d` and the driver is also in `d`. The plan's
     approach is faithful.
   - **Root/path-handling risk for item 1 is real and the plan does not name
     it.** `runpy.run_path` does not set `sys.path[0]` to the run file's
     directory; for a script with no further imports this is fine, but the
     plan's smoke driver does `:import (asl-parser/lexer ...)`. Resolution
     goes through `Transpiler.link(roots=[...])`, which writes transitive
     deps into the same single output file prefixed by module path
     (`to_python.py:113-126`). Imports between transpiled units therefore
     become `asl_parser/lexer__xxx` references inside one Python file — they
     never trigger a fresh `import`. So the only `import` the harness has to
     resolve at run time is `runtime as _agentscript`, which is satisfied by
     the harness's `runtime.py` copy. **The harness works as drawn — but the
     implementer should still resolve imports with `roots=[<src dir>, <driver
     dir>]` as the plan specifies, not just `roots=[<src dir>]`, because
     `asl-parser/lexer` ↔ `asl-parser/reader` cross-imports won't link
     otherwise.** Not a blocker — amendment only.
   - The `asl-parser/lexer` → `asl-parser/reader` import path is genuinely
     `asl-parser/lexer.asl` / `asl-parser/reader.asl` on disk
     (`packages/asl-parser/src/`); both exist. Item 4's `parse` will need
     `roots` containing **both** `src/` and the test/fixture directory, and
     the harness should pass `roots=[<src dir>, <driver dir>]` as the plan
     says. **Amendment: make this explicit in the harness docstring**, so the
     implementer doesn't trim it.

4. **`defenum` lowers to a tagged tuple, `defschema` to a Python function returning a
   dict. Confirmed at `backend/to_python.py:206-216` and `:194-201`.**
   - `defenum` cases are emitted as `def <prefix><case>(args...): return ("<case>"
     [, payload, ...],)` — a one-tuple `(case,)` when zero-field, with the
     explicit trailing-comma comment at `to_python.py:214-216` explaining why.
   - `defschema` is emitted as `def <prefix><Name>(args...): return {"field":
     field, ...}` — a `dict`, **not a `dataclass`**. So the plan's advice to
     access via `(.-field tok)` is correct, and the lower produces
     `tok["field"]` (see `to_python.py:348-352`): for the runtime this is a
     `dict["field"]` lookup, which is fast. The plan's `defschema` typed-node
     design (item 3) is sound — `(.-field tok)` lowers cleanly.
   - **Enum equality for `match`: pattern lowering is at
     `to_python.py:432-487`.** Enum case patterns lower to a tag-string
     compare (`{subj}[0] == "<case>"`). `(match ... ((tok-lparen) ...))`
     becomes `if s[0] == "tok-lparen": ...`, which is **not** the same as
     Python-tagged-tuple identity but is exactly the runtime equality the
     `defenum` emit produces (tag string + payload). The plan's claim
     "transpiled enum is a tagged tuple" is accurate, and the test advice
     ("assert kinds via `token-type-name` String, not tuple shape") is the
     right move — it asserts on the lexer's *rendered* name, not on the
     tagged-tuple layout that the lowering happens to use. **Not a blocker.**
   - **One real risk the plan names but doesn't address.** `to_python.py:212-216`
     emits the case name verbatim — `(tok-lparen,)` — but `pattern()` at
     `:447-451` strips any qualified prefix from the pattern head (`head =
     head.partition("/")[2]`). When item 4's reader constructs `DefunNode`
     with **verbose** heads only, the pattern comparator will read the verbose
     string `"tok-lparen"` and match it against `s[0]`, which is also
     `"tok-lparen"` (the emit uses the case name as-is, no prefix). Good.
     The plan says "Unclassified forms stay as generic `SExpr` inside the
     node's body field rather than being dropped" — but the `match` patterns
     in the test driver file `packages/asl-parser/src/lexer.asl:53-65`
     match on the **enum cases of `TokenType`**, not on `SExpr`. Those will
     work. **Amendment: item 3's test for `DefunNode` should *also* drive
     through a fixture that does `(match tok ((tok-lparen) ...))` — a
     micro-smoke that exercises the tag comparison. Without it, item 1's
     driver could pass on uses that don't `match`, and item 4's first `match`
     test would still be the canary, which the plan accepts.**

5. **Recursion depth.**
   - `runpy.run_path` does not raise the recursion limit; default CPython is
     1000. The plan's `tokenize` is per-character recursive (item 2). For test
     inputs that are dozens of characters, this is well within budget. For a
     scanner that walks with `string-slice`/`string-length`/`string-chars` and
     recurses on the tail at each delimiter boundary, **a 200-character input
     already exceeds the budget** because every delimiter spawns a frame the
     tail-recursion doesn't release (Python doesn't TCO, and `string-slice`
     makes a copy each call). The plan says "Test inputs stay short"; that's
     prudent but unquantified.
   - **The fix the plan names (`sys.setrecursionlimit` in the harness) works,
     but only up to ~10⁴ frames** before CPython segfaults from C-stack
     exhaustion. A more durable fix is an explicit accumulator in the
     scanner. The plan should commit, in item 2, to **a specific maximum input
     length the harness promises** (e.g. 4 KiB) rather than leave the limit
     implicit. Without it, item 2's `test_tokenize_runs` could pick a sample
     that fails the harness for an unrelated reason. **Amendment: name a
     bound, e.g. "inputs ≤ 2 KiB; deeper input requires an accumulator-style
     rewrite, which is item-2 scope expansion and would be flagged."**

6. **`grammar/corpus/modules/core/strings.agentscript` exists.** Verified. The
   plan's "Not in the vocabulary" note about `core/strings` is therefore moot
   for any fixture that still imports it after item 6's rewrite — the import
   path is real. Not a blocker; just confirmation.

7. **Citation errors (line-number drift).**
   - `PLAN.md` cites `backend/to_python.py:413-416` for `.-field` / field
     access. Actual location is `to_python.py:345-352` (`if node.data ==
     "field_access":`).
   - `PLAN.md` cites `backend/check_corpus.py:57-76` for the harness
     approach. Actual `execute()` block is `check_corpus.py:50-60`.
   - These are not blockers — the cited *behaviour* is correct — but the
     plan asserts line numbers as evidence, and two of three are wrong. If a
     reviewer or downstream agent reads the plan and jumps to those lines,
     they'll find different code. **Amendment: correct both citations, or
     drop the line numbers and cite by symbol name.**

## Blockers
None. The execution path is real and the smoke driver described in item 1
will close the unverified-lowering gap the plan identifies. The amendments
above (recursion budget, harness `roots` docstring, match micro-smoke, line
citations) should land in the plan before item 1 is implemented, but no
finding makes the plan **wrong**.

## Non-blocking
- The `(.-field tok)` access path is fast (dict lookup) but **not** a
  property-attr access, so any future item that compares performance
  against a Rust struct will see a constant-factor gap. Out of scope here.
- `Transpiler.host_entry` (`to_python.py:175-181`) only emits a host entry
  when the source has a `main`. The plan's smoke driver must **not** be
  named `main`, or `runpy.run_path` will execute it under `if __name__ ==
  "__main__":` and the test driver will print instead of returning a value.
  The plan says the driver returns `ns["run-smoke"]` — `run-smoke` is not
  `main`, so this is fine. Worth a one-line check in the implementer's
  harness.
- `Transpiler.link` mangles module paths and raises on collisions
  (`to_python.py:118-122`). `asl-parser/lexer.asl` and `asl-parser/reader.asl`
  both have one common dep prefix; if both are imported from a single
  fixture, the linker needs both files in `roots`. The plan's `roots=[<src
  dir>, <driver dir>]` covers it — confirmed.

## Unverified
- No claim about differential / Rust/JS/Go behaviour was investigated
  (out of scope per plan).
- No run of the actual `harness.run_asl` was performed — the review is
  static. The smoke driver has not been written, so I cannot confirm that
  the string it computes (e.g. `(token-type-name (token-kind "("))` →
  `"LPAREN"`) compiles and runs under `runpy`. The plan's claim is
  plausible (the expression exists in `packages/asl-parser/src/lexer.asl:54`
  and the string-literal `"LPAREN"` is the expected match arm at
  `lexer.asl:55`), but the executable form depends on the harness being
  built correctly per amendment 3.

## Summary
Verdict: **approve-with-amendments.** 7 findings, 0 blockers. Highest-value
amendment: name a recursion-input bound in item 2 (the plan's smoke driver
will work today but the lexer rewrite will silently fail on longer inputs).
Second-highest: correct the two line citations (`:413-416` → `:345-352`;
`:57-76` → `:50-60`) so the next reviewer reads what you claim.
