# Phase 3 — REVIEW (lens: backend feasibility + gate integrity)

Lens: backend feasibility + gate integrity.
Iteration: `asl-selfhosted-runtime-v1`.
Plan: `/Users/purplelephant/projects/asex/.plans/phase-3/PLAN.md` (5 items).

## Verdict

**approve-with-amendments** — three required amendments listed below. None of them
block the headline goal (`asl parse` + native-vs-Lark benchmark); they sharpen
gate integrity and the str→String interface contract.

## Gate integrity

| Item | Gate | Current verbatim output | Pass-when-done? |
|---|---|---|---|
| 1 | `pytest tools/tests/test_native_parser.py::test_render_all_accepts_string_arg -q` | `ERROR: file or directory not found: tools/tests/test_native_parser.py` (re-run this session) | yes, but see amendment A1 |
| 2 | `pytest tools/tests/test_native_parser.py::test_native_render_is_stable_and_verbose -q` | same "no tests ran" | yes |
| 3 | `python agentscript parse <file>` | `argument command: invalid choice: 'parse' (...)` (re-run this session, exit 0 from wrapper stderr) | yes |
| 4 | `agentscript parse <file> --bench` | same `invalid choice: 'parse'` | yes |
| 5 | `pytest tools/tests/test_native_parser.py -q` | `no tests ran in 0.01s` + `ERROR: file or directory not found: tools/tests/test_native_parser.py` | yes (acceptance command, matches `.plans/PHASES.md:16` verbatim) |

None of the gates can be passed by mirroring or by weakening: each one names a
node id or a CLI invocation that does not exist in the tree today, and the
file-creation/commit cycle is what materialises them.

Item 4's gate is the weakest on its own (only checks that the flag is accepted
by argparse, which argparse provides by default), so the test
`test_cli_benchmark_reports_both_backends` is the actual gate that proves
the benchmark ran both arms — and the plan's declared expected result
("both backend labels present, numbers printed") is the right bar.

## Builtin surface — str→String interface (the highest-value check)

**Verdict: no wrapper needed. The transpiled export is callable from Python
with a `str` argument and returns a `str`.**

I verified the lowering end-to-end (read-only):

1. `packages/asl-parser/tests/harness.py:46-59` `run_asl` returns the
   `runpy.run_path` namespace.
2. `packages/asl-parser/tests/reader_test.asl:120-126` exports
   `(df render-all [(src String)] -> String ...)`.
3. `backend/to_python.py:209-218` `defun` lowers `defun name(params)`
   directly. The transpiled body for `render-all` is (lines 825-826 of the
   lowered output):
   ```
   def render_all(src):
       return "\n".join([(lambda t: ast__render_node(t))(_x) for _x in ast__parse(src)])
   ```
   `src` is a Python parameter, no wrapper. `ast__parse` is `ast.parse`
   (`packages/asl-parser/src/ast.asl:65`) lowered by the same defun rule,
   and `ast__parse` operates on Python `str` (its body is the lexer/tokenizer
   pipeline that uses `str` indexing throughout). `String` is `str` in
   the Python backend — there is no String→str shim because there is no
   separate String representation to convert from.
4. Direct probe (this session):
   ```
   ns = run_asl('packages/asl-parser/tests/reader_test.asl')
   ns['render_all']('(module m)')   # => '(module :doc )',  type=str
   ```
   The namespace contains `render_all` (no module prefix because the root
   unit's `prefix` is empty per `backend/to_python.py:97`) alongside
   zero-arg exports like `tail_forms` and the `ast__*` / `lexer__*`
   / `reader__*` helpers, so the runpy convention puts both arities on the
   namespace as the plan assumes.

Item 1's gate as written is therefore correct.

## Roadmap conformance

- `.plans/PHASES.md:16` criterion is exactly
  `.venv/bin/python -m pytest tools/tests/test_native_parser.py -q`. Plan
  item 5 names this command verbatim. ✓
- Phase goal `.plans/PHASES.md:15` ("Wire native parser into CLI as
  `asl parse` and provide high-speed parsing benchmark comparing
  memory/latency against Lark") is covered by items 3 + 4. ✓

## Benchmark comparability

The plan's `--benchmark` design is sound:

- Setup is excluded via the module-level singleton (item 2). The Lark
  equivalent (`Lark.open(...)`) is also constructed once outside the timer,
  matching `tools/tests/test_ultra_nano.py:8-11`. ✓
- Per-iteration timing uses `time.perf_counter()` per
  `bench/harness/benchmark_suite.py:62-63`. ✓
- Memory via `tracemalloc.start()` / `get_traced_memory()[1]` / `stop()`
  is stdlib, no dependency, no repo precedent exists (verified — no
  `tracemalloc` elsewhere). ✓
- The test asserts both backend labels + numeric output, so a label-only
  benchmark would fail the test. ✓

Risk acknowledged in the plan (item 4's risk #3): the native arm measures
parse + render-node, the Lark arm measures parse only. That asymmetry is
the right comparison if the deliverable is the self-hosted parser's
observable behaviour, and the plan flags it rather than deciding — keep
it flagged.

## Blockers

None.

## Amendments (required)

**A1. Item 1 — pin the input substring assertion more tightly.**
The test asserts `ns["render_all"]("(module m)")` returns a non-empty `str`
containing `"module"`. The lowered `render-module` emits `(module :doc )`
(empirically, with empty doc/imports/export), so `"module"` is present, but
`render-all`'s contract is "join every form with newlines", not "emit a
module". Pin the assertion to:
- result is `str` (catches a foreign-call wrapper regression);
- result is non-empty;
- result contains `"(module"` (the rendered head, not just `module`),
  because `render-node` of a top-module emits `"(module :doc ...)"` per
  `packages/asl-parser/src/ast.asl:331-345`.

This guards against the failure mode where `String` lowering silently
becomes "encode then decode" and returns the input verbatim with the
substring `"module"` still matching.

**A2. Item 3 — separate `cmd_parse`'s "file missing" diagnostic from
"parse failure" diagnostic.**
The plan says missing-file raises `BadInput` (exit 1, `agentscript:923-928`)
while parse failure goes through `return report([diag(args.file, "parse",
message)], ...)`. The test `test_cli_parse_bad_file_nonzero` asserts only
`returncode != 0` and cannot distinguish the two paths. Add a second
subprocess test — `test_cli_parse_bad_file_is_usage` — that runs
`agentscript parse /nonexistent.asl` and asserts:
- exit 1;
- stdout does **not** contain `"parse"` (the diagnostic `code`);
- stderr contains the BadInput message.

This protects the BadInput contract from a refactor that quietly turns the
missing-file branch into a generic parse diagnostic, which would change the
caller's classification of the error.

**A3. Item 4 — name the asymmetric comparison in the benchmark output.**
The plan acknowledges in its risks (#3) that the native arm measures
`parse + render-node` while the Lark arm measures `parse` only. To stop a
reader of the benchmark output from drawing an unfair inference, the
benchmark must label the arms explicitly in stdout, not just emit two
backend names. Pin the output strings:
- native line: `"native (parse+render): <latency_ms> ms, peak <bytes> B"`,
  preceded by a line `native arm: parse + render-node`;
- Lark line: `"lark (parse only): <latency_ms> ms, peak <bytes> B"`,
  preceded by a line `lark arm: parse only`.

The test `test_cli_benchmark_reports_both_backends` then asserts both
header substrings are present. Without this, the benchmark could print
two identical-looking "X ms" lines and pass the "both labels present"
assertion while lying about what was measured.

## Non-blocking

- `tools/tests/test_lexer.py` does not exist (verified by `ls tools/tests`),
  so the plan's stated precedent `test_lexer.py:38` is wrong. The closest
  precedent is `test_ultra_nano.py` for `Lark.open` usage. No item
  references `test_lexer.py` directly; the plan cites it only as a
  precedent for a str-arg call and its non-existence strengthens the
  rationale for item 1.
- `cmd_grammar` is at `agentscript:517` (verified); the plan's
  self-correction note matches.
- `cmd_view` is at `agentscript:155` (verified); plan's `agentscript:712-722`
  reference is for the `add_parser`/`add_argument` pattern of the `view`
  subparser, not the function, so the citation is correct in context.
- `reader_test.asl:120-126` defines `render-all` (verified; line range
  correct).
- `packages/asl-parser/src/ast.asl:65` defines `parse`; `:331` defines
  `render-node` (verified).
- `bench/harness/benchmark_suite.py:62-63` uses `time.perf_counter()`
  (verified); no `tracemalloc` anywhere in the repo (verified — only the
  absence is the evidence).

## Unverified

- The exact exception type a runtime error inside `render_all` raises
  through `runpy` is not known until item 3 runs against a deliberately
  malformed source. The plan's risk #2 names this and item 3's
  bad-input test covers the nonzero-exit contract regardless. Acceptable.
- Whether `render-all` validates or rejects ill-formed input (plan risk #5)
  is genuinely unverified and deferred. Not part of this phase's
  acceptance criterion; flagged correctly.
