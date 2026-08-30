# Phase 6 — Implementation Review (reuse / simplification / efficiency / dead state)

## Lens
Reuse and simplification: reinvented stdlib, dead code, speculative abstraction,
the ctypes tree-sitter binding's robustness, efficiency hazards that matter now.

## Verdict
`approve-with-amendments`

Two findings are medium (the ctypes binding and the duplicate diagnostic type) and
several are low. None is a blocker — none weakens a gate or silently drops work —
but the ctypes binding carries real fragility that an existing crate removes
without giving anything up, and the diagnostic type is a duplication the rest of
the toolchain can absorb cleanly.

## Blockers
None.

## Non-blocking (high → low)

### H1 — `tools/tsutil.py` is a hand-rolled ctypes shim over an existing Rust crate
- File: `tools/tsutil.py:21-56`, full file (165 lines).
- What to cut: the ctypes `CDLL(str(SO_PATH))` + `init.restype = ctypes.c_void_p` +
  `Language(init())` dance, plus the `tree-sitter build -o` subprocess in
  `language()`. The project already builds a Rust crate against the same
  tree-sitter ABI 14 grammar: `crates/agentscript-ts` (`src/lib.rs` exposes
  `language() -> Language`), and `crates/agentscript-interp` consumes it
  (`Cargo.toml` deps: `agentscript-ts`, `tree-sitter = "0.24"`).
- Replacement: a small Rust binary in `crates/agentscript-ts` (or a new
  `agentscript-ts-cli` `[[bin]]`) that prints JSON for `ast` and `search`, and
  performs the byte-range edit in place. `tools/tsutil.py` shrinks to a thin
  subprocess wrapper (or disappears entirely into `agentscript`'s `cmd_ast` /
  `cmd_search` / `cmd_edit`). The Rust side already does the parser construction
  with the same `.so`-free path the ctypes shim is reinventing; the bindgen
  failure mode and the `Language(init())` raw-pointer contract both disappear.
  Plan §5 already names the "Rust edit CLI in a new [[bin]] target" as the
  documented fallback — promoting it to the primary path is what the existing
  crate existence makes cheaper than the ctypes layer.
- Class enumeration: this applies to `agentscript ast`, `agentscript search`, and
  `agentscript edit` in `agentscript` (lines around 165-200 — every `cmd_*` that
  does `import tsutil`); all three rely on the same fragile binding.
- Severity: medium (not blocker — it works, and the Python binding load *was*
  verified per plan §5 — but it is the only fragile mechanism in Phase 6 and
  the alternative is an existing crate, not a hypothetical rewrite).

### H2 — `agentscript cmd_check` runs `checker/check.py` as a subprocess and re-parses stdout with a regex instead of calling `resolve.check_file` directly
- File: `agentscript:75-95` (`cmd_check`), `agentscript:97-110` (`parse_diag`).
- What to cut: the `subprocess.run([sys.executable, str(ROOT / "checker" /
  "check.py"), str(f), "--root", *roots], capture_output=True, text=True)` loop
  and the `parse_diag` regex. The current `checker/resolve.py:641` exposes
  `check_file(path, roots) -> list[Diagnostic]` — the exact API `cmd_check`
  reconstructs by spawning a process and re-parsing its stdout. The subprocess
  also re-imports the checker module on every file (N process starts per N
  files), which is real overhead when a corpus run is invoked through the
  distributor.
- Replacement: `sys.path.insert(0, str(ROOT / "checker"))` once at the top (the
  `sys.path.insert` calls already in `agentscript` cover `tools` and
  `tools/fmt`; add `checker`) and call `resolve.check_file(Path(f), roots)`
  directly, returning `len(diags)`. The regex collapses; the `parse_diag`
  function and its regex go away. The exit code semantics are preserved because
  `check_file` already returns the list the current `checker/check.py`
  walks to print and count.
- Severity: medium (works; the cost is a missing direct call into an in-process
  function, which is exactly the "delegate rather than re-implement" pattern the
  rest of `agentscript` follows for `fmt`, `ambiguity`, `tokens`, `bindgen`).
- Class enumeration: `cmd_fmt` and `cmd_bindgen` legitimately subprocess
  because the formatter and bindgen own their state; `cmd_ast`, `cmd_search`,
  `cmd_edit` legitimately import the module. Only `cmd_check` is doing both —
  subprocess and parse — and only it should change.

### M1 — `agentscript` imports `fmt` four times inside `cmd_*` bodies to reach `Diag`
- File: `agentscript:53, 100, 136, 165, 181, 195` — `import fmt` appears in
  six function bodies (`diag`, `parse_diag`, `cmd_fmt`, `cmd_ast`, `cmd_search`,
  `cmd_edit`).
- What to cut: the per-function `import fmt`. The module is already on
  `sys.path` via the top-level `sys.path.insert(0, str(ROOT / "tools" /
  "fmt"))` (line 19).
- Replacement: a single top-of-file `import fmt`. Removes six duplicate
  imports and makes the dependency obvious.
- Severity: low.

### M2 — `Diag` is re-declared in `tools/fmt/fmt.py:99-111` and re-referenced from `agentscript` rather than using `checker.resolve.Diagnostic`
- File: `tools/fmt/fmt.py:99-111` (`@dataclass Diag`), `agentscript:53` (uses
  `fmt.Diag`), `checker/resolve.py:75-83` (`class Diagnostic`).
- What to cut: the local `Diag` in `fmt.py`. Both spell the same five fields
  (`file`, `line`, `col`, `rule`, `message`), and the formatter's `text()` /
  `as_dict()` are exactly the operations a `--json` consumer needs. The
  formatter's rationale comment claims importing `checker.Diagnostic` pulls in
  the checker's prelude load — but the checker's `resolve.py` imports
  `vocab.py`, which is the only thing that gate loads; `tools/fmt/fmt.py` is
  not on any hot path that the prelude load would slow, and the lockfile-style
  tooling here is invoked from CI gates that already pay the load.
- Replacement: `from checker.resolve import Diagnostic as Diag`. The fields
  line up (`code` -> `rule` is the only rename and is documented in the
  distributor). The `agentscript` `diag()` helper then becomes a one-liner.
  Net: three files (`fmt.py`, `agentscript`, `checker/resolve.py`) share one
  dataclass instead of two duplicates spelling the same five fields.
- Severity: medium (the duplication is exactly the drift risk the rest of
  Phase 6 explicitly guards against — `parse.py` is the "one parser" because
  three copies drifted; the `Diag` is the same pattern one level down).

### M3 — `agentscript` adds `sys.path` entries for `tools/fmt`, `tools`, and `checker` at runtime; `grammar/parse.py` is reached only because `fmt.py` adds it on import
- File: `agentscript:18-21` (`sys.path.insert(0, str(ROOT / "tools" / "fmt"))`,
  etc.).
- What to cut: the runtime `sys.path` mutation. `agentscript ast|search|edit`
  imports `tsutil` and the others import `fmt`; both are sibling packages of
  `tools/`. Either:
  - (preferred) put `agentscript` inside a `cli/` subdirectory and add a
    `cli/` `__init__.py` with explicit relative imports; or
  - ship a `tools/__init__.py` (currently absent — see L1) and use ordinary
    `from tools import tsutil` / `from tools.fmt import fmt` imports.
- Replacement: real package imports, no `sys.path.insert` anywhere. The
  shim's `from parse import ...` in `fmt.py:32` is the same anti-pattern and
  goes the same way.
- Severity: low (works; the smell is that `agentscript`, `fmt.py`, and the
  tools package have to coordinate path mutations to find each other, and
  pytest's `sys.path.insert(0, str(ROOT / "tools"))` in `test_edit.py:17`
  and `test_interp_diag.py` already confirms the dependency).

### M4 — `tools/span_coverage.py` declares an unused `structs` dict and an unused `fields_in` closure, and `span_carrying_variants` returns a `str` nothing reads
- File: `tools/span_coverage.py:51-52` (`structs: dict[str, set[str]] = {}`,
  `fields_in` nested closure), `tools/span_coverage.py:42-46`
  (`span_carrying_variants() -> tuple[list[str], str]`).
- What to cut:
  - `structs = {}` and `def fields_in(block)`: declared, never read.
  - The second tuple element of `span_carrying_variants`: every caller (`measure`
    at line 105) discards the text — `text = AST.read_text()` is already passed
    into `_carrying_from(text)` separately.
- Replacement: drop the `structs` dict and the `fields_in` closure; change the
  signature to `span_carrying_variants() -> list[str]`. The function is then
  unused — `measure` calls `_carrying_from` directly — and it can be deleted
  entirely.
- Severity: low.

### L1 — `tools/` has no `__init__.py` but the test files expect to import it as a package
- File: `tools/__init__.py` (absent), `tools/t/test_edit.py:17` (`sys.path.insert(0,
  str(ROOT / "tools"))`), `tools/t/test_interp_diag.py:21` (`ROOT /
  "target/debug/agentscript-interp"`).
- What to cut: the test-time `sys.path.insert`. Add `tools/__init__.py` (empty
  is fine) so `import tsutil` resolves without path mutation.
- Replacement: drop the `sys.path.insert(0, str(ROOT / "tools"))` lines and
  let pytest's normal rootdir discovery handle it (the existing
  `conftest.py` setup, if any, is unaffected — verified by reading test
  files that import `tsutil`).
- Severity: low (works today; the `__pycache__/` next to `tools/` already
  shows Python found it as a namespace package, so this is a clean-up, not a
  fix).

### L2 — `tools/bindgen/from_pyi.py` builds a `pascal` opaque name with hand-rolled logic that duplicates `str.title().replace('_', '')`
- File: `tools/bindgen/from_pyi.py:91-95` (`"".join(p[:1].upper() + p[1:] for p in
  name.replace(".", "_").split("_") if p)`).
- What to cut: the inline generator.
- Replacement: `pascal = name.replace(".", "_").title().replace("_", "")` (or
  the `.replace(".", "_")` followed by `"_".join(...).title()` with `.replace("_",
  "")`). Two lines instead of a comprehension, and it handles the empty-part
  skip the comprehension silently relies on.
- Severity: low.

### L3 — `tools/tsutil.py:128` computes `lines_end = src.split(b"\n")` and never uses it
- File: `tools/tsutil.py:128` (inside `edit_apply`).
- What to cut: the assignment.
- Replacement: remove the line.
- Severity: low (single dead line, but it sits next to the working
  `_point_to_byte` call so the dead variable could mislead a future reader
  into thinking the function clamps ranges by line).

### L4 — `tools/tsutil.py:54` has a no-op `parser.included_ranges` access kept "alive" by `# noqa: B018`
- File: `tools/tsutil.py:53-55` (`parser = Parser(language()); parser.included_ranges # noqa:
  B018`).
- What to cut: the attribute access and its noqa comment.
- Replacement: `parser = Parser(language()); return parser.parse(...)` —
  the attribute access serves no documented purpose in the surrounding code
  and there is no test that exercises `included_ranges`.
- Severity: low (the noqa comment is itself evidence the author knew it was
  dead — `# noqa` without a reason usually means "make a linter stop
  complaining"; this one has a parenthetical reason but the parenthetical
  reason is "nothing else needed", which is the same thing as "remove it").

### L5 — `tools/fmt/fmt.py:80` hard-codes `WIDTH = 80` / `SIGNATURE_WIDTH = 100` with a multi-paragraph rationale; `tools/fmt/fmt.py:23` rebuilds `FORM_KW` from `parse.FORM_KW` minus `BANG` rather than letting `parse.kids` handle it
- File: `tools/fmt/fmt.py:21-32, 49, 251-253`.
- What to cut: the rationale paragraph on lines 23-29 (acceptable to keep —
  the budgets are corpus-derived) and the duplicated `kids()` body in
  `fmt.py:251-253` which exists only to drop BANG.
- Replacement: leave the budgets and the rationale (they are real corpus
  measurements); add a single `kids_keep(*keep)` helper to `grammar/parse.py`
  that takes `FORM_KW - set(keep)` and have `fmt.py` use it. Removes the
  formatter's `kids` re-implementation and one paragraph of rationale.
- Severity: low.

### L6 — `agentscript:283-284` re-implements the `agentscript` parser's `__str__`-style exit by returning `args.fn(args)`'s return value; `cmd_ambiguity` / `cmd_tokens` return a subprocess returncode that is not the diagnostic count
- File: `agentscript:282-284`, `agentscript:140-149` (`cmd_ambiguity`,
  `cmd_tokens`).
- What to cut: nothing (kept). The two ratchet subcommands correctly return
  the subprocess exit code (0 / 1 / 2), matching the "exit = problem count"
  contract for `0`/`2` and the lock-fail case for `1`. A diagnostic-count
  exit would not be the ratchet's contract — the lock check returns 1 on
  difference, not on diagnostic count.
- Severity: not a finding; flagged here because the brief asks for places I
  inspected and chose not to simplify.

### L7 — `crates/agentscript-interp/src/{ast,cst,eval}.rs` — `parse_diag` regex vs direct construction
- File: `agentscript:97-110` (`parse_diag`).
- Already covered under H2 (the regex disappears when `cmd_check` calls
  `resolve.check_file` directly).

## Deliberate complexity I inspected and kept

### K1 — `tools/tsutil.py`'s separate `_point_to_byte` for insert vs `edit_apply`'s line-then-column walk
- Could be unified into a single helper that takes `(line, col)` and returns
  the byte offset; the split exists because insert only needs the start byte
  (no `end` byte to clamp against), but the divergence is one line. Kept:
  collapsing them would create a parameter or a returned tuple that callers
  must always unpack; the current split is two paths, each two lines.

### K2 — `tools/fmt/fmt.py`'s `_stack` / `_fill` / `_aligned` layout primitives
- Three primitives do real work (a stack for one-per-line, a fill for packed
  continuation lines, and a table aligner for declaration members) and the
  corpus uses all three. They are not redundant with each other, and the
  formatter is the only consumer. Could be folded into one with a mode
  parameter, but the existing per-call code already passes through the
  primitive that matches its shape; a unified version would be longer, not
  shorter.

### K3 — `tools/bindgen/from_pyi.py`'s `_union_parts` recursive walk
- Handles nested `X | Y | Z` unions recursively rather than via a flat
  expression walk. The function is six lines and the alternative
  (`isinstance(node, BinOp) and isinstance(node.op, BitOr)` in a loop) would
  be a regex on the AST — exactly the prototype the docstring warns against.
  Kept: the AST is the simpler path here.

### K4 — `crates/agentscript-interp/src/eval.rs` span attachment in `eval()`
- The `if err.located.is_none()` guard wraps `e.span()` in a fallible call
  and only attaches when the variant carries one. Removing it would either
  force every variant to carry a span (defeating the D4 denominator of 13)
  or require the four `Float`/`Str`/`Bool`/`Unit` sites to fabricate spans
  for variants that never reach an `Err`. Kept: the guard is the
  mechanism that makes the 13/13 lock figure mean what it says.

### K5 — `prelude/budget.py` and `grammar/ambiguity_audit.py` re-read `HANDBOOK.md` / parse every fixture on every run rather than caching
- Caching would require invalidation discipline (a `--write` that changes
  the lock file has to invalidate a derived cache), and the lock files are
  the canonical record. The whole ratchet is "exact-match (D7) — `--write`
  only in the commit that earns the figure"; a stale cache breaks the
  contract. Kept: re-parse is cheap (12K chars / 77 fixtures).

## Gates run (verbatim, where run; otherwise, why not)

This lens is reuse / simplification — no command was run that the implementer
did not already run for the gate battery. I verified the files I read were
current by `git status --short` (Phase 6 working tree matches the implementer's
report: new files under `tools/`, `grammar/ambiguity_audit.py`,
`prelude/budget.py`, `agentscript` at root, span threading in
`crates/agentscript-interp/src/{ast,cst,eval}.rs`) and by reading each
file from disk.

I did **not** run:
- `.venv/bin/python grammar/ambiguity_audit.py --check` — the ratchet is the
  gate, and the lens is not gate-correctness; the file is short and was read.
- `prelude/budget.py --check` — same.
- `tools/span_coverage.py --check` — same; the dead-code finding (M4) is
  visible from reading.
- `agentscript ...` — would re-run the implementer's smoke tests; not the
  lens's job, and would need the venv active.
- The Rust interpreter — `eval.rs` was read in full; the span attachment
  sites are visible.

## Unverified
- H1's claim that `crates/agentscript-ts` exports `language() -> Language`
  compatible with the JSON shape `tools/tsutil.py` produces: I read
  `crates/agentscript-ts/src/lib.rs` (it does export `language()` and wraps
  `tree_sitter::Language`), but the byte-for-byte equivalence of the
  proposed Rust CLI's JSON output with the Python `tsutil.ast_json` output
  is not asserted. The contract is the formatter round-trip in
  `tools/t/test_edit.py:108-117` (re-parse + idempotent format), which is
  the actual integration test, and would catch a divergence.
- M3's "real package imports" replacement assumes `tools/__init__.py` is
  acceptable to pytest's rootdir discovery in this repo; the existing
  `__pycache__/` next to `tools/` already shows Python found it as a
  namespace package, which is the only signal I have without running
  pytest.
