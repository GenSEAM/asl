# Phase 3 — CLI integration: `asl parse` + native-vs-Lark benchmark

Iteration: `asl-selfhosted-runtime-v1`. Acceptance criterion (fixed by the roadmap):

```
.venv/bin/python -m pytest tools/tests/test_native_parser.py -q
```

## Verified interface facts (all re-checked this session)

- CLI pattern: `p = sub.add_parser(...)`, `p.add_argument(...)`, `p.set_defaults(fn=cmd_x)` — e.g.
  the `view` subcommand at `agentscript:712-722`. `--json` flags use
  `action="store_true", default=argparse.SUPPRESS` (`agentscript:709,717`), so `getattr(args,"json",False)`
  is the safe read. `main()` dispatches `args.fn(args)` at `agentscript:923`; `BadInput` → exit 1 at
  `agentscript:926-928`. Diagnostic shape: `diag(file, code, message) -> Diagnostic` and
  `report(diags, as_json, subject) -> int` at `agentscript:59-77` (`report` returns the diag count, so
  `return report(...)` gives nonzero on failure). `cmd_check` is the model for a file-path command
  (`agentscript:87-116`).
- Harness: `packages/asl-parser/tests/harness.py:46-59` `run_asl(driver_path) -> dict` — transpiles a
  driver via `backend.to_python.Transpiler` with `roots=[SRC, driver.parent]`, py_compiles, copies
  `backend/runtime.py`, `runpy.run_path`s it. One-time cost; must be excluded from benchmark timing.
- Driver: `packages/asl-parser/tests/reader_test.asl:120-126` exports
  `render-all [(src String)] -> String` = `(string-join (map render-node (a/parse src)) "\n")`.
  Backing builtins: `parse` at `packages/asl-parser/src/ast.asl:65`,
  `render-node` at `packages/asl-parser/src/ast.asl:331`.
- Lark reference: `grammar/agentscript.lark:15` `start: toplevel*`; in-repo reference parse
  `tools/tests/test_ultra_nano.py:8-11` — `Lark.open(str(ROOT/"grammar"/"agentscript.lark"), parser="earley")`.
  `lark 1.3.1` importable from `.venv/bin/python` (verified).
- Timing precedent: `bench/harness/benchmark_suite.py:62-63` `time.perf_counter()`. No `tracemalloc`
  anywhere in the repo — memory measurement is new here (stdlib, no dependency).
- CLI test convention: `tools/tests/test_cli_grammar.py:1-14` — subprocess
  `[sys.executable, str(ROOT/"agentscript"), ...]`, `capture_output=True, text=True, cwd=ROOT`,
  assert `returncode` + stdout substring. Never import `main()`.
- Corrections to the task digest (do not cite the digest's numbers): `cmd_grammar` is at
  `agentscript:517` (not 249); `render-all` is at `reader_test.asl:120-126` (not 133-137); and
  `test_lexer.py:38` does pass one argument (`ns["len_list"]([1,2,3,4])`) — what is **unverified** is
  specifically a **String** (Python `str`) argument through `run_asl`, which is why item 1 exists.

## Work items

### Item 1 — Prove the one-String-arg export through `run_asl`

**What:** Create `tools/tests/test_native_parser.py` with a module-scoped fixture that calls
`run_asl(ROOT/"packages/asl-parser/tests/reader_test.asl")` once, and a first test
`test_render_all_accepts_string_arg` that calls `ns["render_all"]("(module m)")` and asserts the
result is a non-empty `str` containing `"module"` (render-node of a top-module emits its header).
No CLI, no benchmark — this item only certifies the Python→ASL String boundary.

**Why:** Everything downstream (CLI correctness output and both benchmark arms) calls
`render_all(src)`. The parent flagged this boundary as the highest-risk unverified interface; if
String lowering or the runtime's foreign-call convention mangles a `str`, every later item fails on
it, so it is isolated as the first gate.

**Gate (fails now, verbatim):**
```
$ .venv/bin/python -m pytest tools/tests/test_native_parser.py::test_render_all_accepts_string_arg -q
ERROR: file or directory not found: tools/tests/test_native_parser.py
```
Green when: this exact node id passes. **Breaks if run before nothing** — it is the first item.

### Item 2 — `tools/native_parser.py`: cached driver + `native_render(src)`

**What:** Create `tools/native_parser.py` exposing:
- a module-level lazy singleton that runs `run_asl` on `reader_test.asl` exactly once per process
  and keeps the namespace (so benchmark timing can exclude setup),
- `native_render(src: str) -> str` (calls `ns["render_all"]`),
- a `NativeParserError` for parse failures surfaced by the runtime, to be mapped to diagnostics in
  item 3.
Test `test_native_render_is_stable_and_verbose`: rendering a hand-written multi-form sample
(module + a def) twice yields identical strings, and the output contains the def's name in verbose
form. Parsing-and-rendering is the observable contract of the self-hosted parser; if `render-all`
is not deterministic on the same input, the benchmark in item 4 would compare noise.

**Why:** Gives the CLI and benchmark a single entry point and pins the one-time-setup exclusion the
benchmark contract requires (parent decision: setup excluded from measurement).

**Gate (fails now, verbatim):**
```
$ .venv/bin/python -m pytest tools/tests/test_native_parser.py::test_native_render_is_stable_and_verbose -q
ERROR: file or directory not found: tools/tests/test_native_parser.py
```
(Collection succeeds after item 1 but this node id does not exist → `no tests ran` for the id.)
**Breaks if run before item 1:** if the String boundary is broken, this test's failure would look
like a `native_parser.py` bug instead of a harness-interface bug.

### Item 3 — `asl parse <file>` subcommand

**What:** In `agentscript`, register `p = sub.add_parser("parse", ...)` with a positional
`file: Path`, `--json` (`action="store_true", default=argparse.SUPPRESS`), and
`p.set_defaults(fn=cmd_parse)`. `cmd_parse(args)` reads the file, calls `native_render(src)`:
- success → print the rendered verbose forms, `return 0`;
- parse/runtime failure → `return report([diag(args.file, "parse", message)], args.json, "diagnostic(s)")`,
  nonzero via `report`'s diag count;
- missing file → raise `BadInput` (handled to exit 1 at `agentscript:926-928`, matching `sources()` at
  `agentscript:46-56`).
Tests `test_cli_parse_success` and `test_cli_parse_bad_file_nonzero` following the subprocess
convention (`test_cli_grammar.py:1-14`): success asserts `returncode == 0` and a rendered form in
stdout; bad-path asserts `returncode != 0`. Use an existing corpus file (e.g. a
`grammar/corpus/valid/*.agentscript` fixture) as the success input.

**Why:** This is the phase's headline deliverable — the self-hosted parser wired into the CLI as
`asl parse`, reporting through the toolchain diagnostic shape per the parent's contract decision.

**Gate (fails now, verbatim):**
```
$ .venv/bin/python agentscript parse <file>
agentscript: error: argument command: invalid choice: 'parse' (choose from 'version', ..., 'bindgen')
```
(recorded this session; `asl parse` is not a registered subcommand today). The pytest node
`test_cli_parse_success` likewise does not exist.
**Breaks if run before item 2:** `cmd_parse` would import a module that does not exist.

### Item 4 — `--benchmark` / `--bench` on `asl parse`

**What:** Add `p.add_argument("--benchmark", "--bench", action="store_true", default=argparse.SUPPRESS)`
to the parse subparser. When set, `cmd_parse` runs, on the same file's text:
- **native arm:** N iterations of the parse call itself via the cached driver (item 2's singleton —
  `run_asl` transpile/py_compile/runpy setup must happen before the timer starts), timing each with
  `time.perf_counter()` (precedent `bench/harness/benchmark_suite.py:62-63`) and measuring peak
  allocated bytes with `tracemalloc.start()` / `get_traced_memory()[1]` / `stop()` around the
  iteration loop;
- **Lark arm:** `Lark.open(str(ROOT/"grammar"/"agentscript.lark"), parser="earley")` built once
  outside the timer (matching the precedent at `tools/tests/test_ultra_nano.py:8-11`), then N
  `parser.parse(src)` iterations under the same `perf_counter` + `tracemalloc` protocol;
- report median/mean latency and peak memory for both arms to stdout (or a JSON object under `--json`).
N defaults to a small fixed number (e.g. 20) with a `--iterations` override; document in `--help`
that the comparison is parse-call-only.
Test `test_cli_benchmark_reports_both_backends`: subprocess `parse <corpus file> --bench`, assert
`returncode == 0` and that stdout contains both backend labels and numeric timing output.

**Why:** The parent's second deliverable: a high-speed parsing benchmark comparing memory/latency
against Lark over the same file, measured on the parse call itself.

**Gate (fails now, verbatim):** `--benchmark` is not an accepted argument of `parse` (which does not
exist yet), so `agentscript parse <file> --bench` fails with the same `invalid choice: 'parse'`
argument error recorded under item 3; the node `test_cli_benchmark_reports_both_backends` does not exist.
**Breaks if run before items 2-3:** no cached driver to time, no subcommand to hang the flag on.
Also note: an item-4 test that only checks "exit 0" would pass against a benchmark that measures
setup — the test must assert both backend labels present, per the declared expected result.

### Item 5 — Phase acceptance gate

**What:** Run the full new test file:
```
.venv/bin/python -m pytest tools/tests/test_native_parser.py -q
```
Green when: every node from items 1-4 passes and the summary is not `no tests ran`. If `asl` is on
PATH anywhere in the docs, also confirm the help text lists `parse` (the subparser's `help` string),
but the acceptance criterion itself is only the pytest command above.

**Gate:** the acceptance command; its current verbatim output (recorded this session):
```
$ .venv/bin/python -m pytest tools/tests/test_native_parser.py -q
no tests ran in 0.00s
ERROR: file or directory not found: tools/tests/test_native_parser.py
```

## Risks / unverified

1. **String-arg foreign call (item 1 exists to retire this):** no in-repo test calls an ASL export
   with a Python `str`; `test_lexer.py:38` passes a `list`, not a `str`. If the runtime's
   String representation is not a plain `str`, item 1 fails and the interface needs a shim the
   plan does not currently budget for.
2. **Error channel for native parse failures unverified:** how a runtime error inside `render_all`
   surfaces through `runpy` (exception type, traceback) has no existing test. `cmd_parse`'s
   failure path maps `NativeParserError`/`Exception` to `diag(..., "parse", ...)`, but the exact
   exception type is confirmed only when item 1/3 run against a deliberately bad input; the
   bad-input test under item 3 covers the nonzero-exit contract regardless of type.
3. **Benchmark comparability:** the native arm renders (`parse` + `render-node`) while the Lark arm
   only builds a tree — render cost is native-side overhead unless the plan's implementation times
   the parse portion. Declared expected result for the test: both labels present and numbers
   printed; whether "native render-all" vs "lark parse" is the right comparison is the roadmap's
   framing (render-node is the parser's only observable output), flagged here rather than decided.
4. **tracemalloc noise:** peak-memory numbers under `tracemalloc` include interpreter allocation
   churn and can be dominated by the Lark tree objects; figures are comparative on the same
   protocol, not absolute. No repo precedent exists (verified: no `tracemalloc` usage).
5. **Unverified:** whether `reader_test.asl`'s `render-all` validates rather than rejects
   ill-formed input (the Lark arm raises on syntax errors, the native arm's behavior on
   `corpus/invalid`-style text is unknown). The CLI's bad-input path is exercised with a missing
   file, not invalid syntax; syntax-error behavior is deferred until observed.

## Out of scope

- **Wiring the native parser into `check`/`build`/other subcommands** — the roadmap names only
  `asl parse` for this phase; replacing Lark elsewhere is a later decision with its own gates.
- **Schema/checker integration** — `render-all` proves parsing only; semantic checking of the
  native parse tree is not part of the acceptance criterion.
- **Publishing benchmark numbers on the website** — DESIGN.md §5 requires every number on the page
  to trace to a roadmap gate; marketing figures need their own item in a later phase.
- **stdin input** — explicitly decided against by the orchestrator (file path only, matching
  `check`/`build`/`fmt`).
- **`prelude/coverage.lock` updates** — `run_asl` already executes the parser builtins through the
  existing gates; no new lowering is introduced by this phase, so no ratchet change is expected.
  If item 1 disproves this (a new builtin needed for the String boundary), that is a flagged
  decision for the orchestrator, not a quiet lock edit.
