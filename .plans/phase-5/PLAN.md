# Phase 5 — Reference interpreter

Baseline: all gates green at `d38e236` per `.plans/ORCHESTRATOR-LOG.md` (Phase 4 closed: seven gates, 161 tests, differential 120 function + 15 program cases, 0 disagreements). Item I0 re-verifies every count before any change and records the per-fixture oracle outputs the later gates compare against.

## 1. Scope

A Rust **tree-walking reference interpreter** for AgentScript: parse with the project's own tree-sitter grammar (`grammar/tree-sitter-agentscript/`), evaluate the AST directly with a dynamic value model, run a module as a program (`main` + argv + exit status). It attaches to `backend/differential.py` as a fourth **program-mode** arm over `program_cases()`. Function mode is out of scope this phase (the acceptance names program mode; §5 risk 10).

**Out of scope:** performance (no bytecode/VM), type checking (the checker gate remains the type authority; the corpus is checker-clean before the interpreter ever sees it), `; run:` header execution for non-program modules (that surface belongs to `check_corpus.py`/Python only), and field `:default` application at construction — the Python backend's `defschema` lowering emits no defaults either (`backend/to_python.py` `defschema`), and `29-literals.agentscript` records the omission as a known ROADMAP §6 gap. The interpreter matches the backends: omitting a defaulted field is a runtime failure.

**Acceptance (from `.plans/PHASES.md` Phase 5):** every `grammar/corpus/valid/*.agentscript` program executes under the interpreter and agrees with python/rust/wasm on stdout, stderr and exit status via `differential.py`.

## 2. Inventory

### 2.1 New files

| Path | Content |
|---|---|
| `Cargo.toml` (root) | Workspace `[workspace] members = ["crates/*"]`; `target/` is already gitignored (`.gitignore:4`). |
| `crates/agentscript-ts/Cargo.toml` + `build.rs` | Static-lib crate wrapping the generated parser. `build.rs` copies `grammar/tree-sitter-agentscript/src/` into `OUT_DIR` and compiles `parser.c` with `cc`. If `src/parser.c` is missing or older than `grammar.js`, it regenerates via `node_modules/.bin/tree-sitter generate` (node + CLI are already repo dev-deps, `package.json`; `validate.py` shells to the same CLI). Fail loudly if node is absent. |
| `crates/agentscript-interp/` (`Cargo.toml`, `src/main.rs`, `src/ast.rs`, `src/value.rs`, `src/num.rs`, `src/eval.rs`, `src/modules.rs`, `src/builtins.rs`, `src/io.rs`, `src/fmt.rs`, `tests/`) | The interpreter binary. Dependencies: `agentscript-ts` (path), `tree-sitter` crate pinned to a release that accepts `LANGUAGE_VERSION 14` (`grammar/tree-sitter-agentscript/src/parser.c:9`) — the exact pin is verified on crates.io during I1 (§5 risk 1). |

### 2.2 Modified files

- `backend/differential.py` — I8 only: add `build_interpreter(src, d)` beside `build_python`/`build_rust`/`build_rust_wasm` (`differential.py:282-318`); add `"interp"` to the `runners` dict (`differential.py:347-348`); extend the agreement expression (`differential.py:361`), the table header and per-case row (`differential.py:327-330,366-371`), and the summary line (`differential.py:455-456`). **No change** to `program_cases()`, the declared `want` values, `build_*` for existing arms, or `exec_coverage.py` (which imports `differential` and iterates `differential.program_cases()`, `backend/exec_coverage.py:48,219`).
- `.gitignore` — add nothing needed (`target/` present); verify `Cargo.lock` stays tracked.
- `.plans/phase-5/BASELINE.md` (+ optional `ORACLES.md`) — I0 records.

### 2.3 AST node types the evaluator dispatches on (from `grammar/tree-sitter-agentscript/grammar.js`)

`source_file`; `module_decl` (fields `path`, opts: `:doc`/`:export`/`:import`), `import_spec`, `type_params`; `defschema`/`field`/`field_opt`; `defenum`/`enum_case`; `defun` (optional `effect` `!`, `name`, `params`, `return_type`, `body`+); `let_form`/`binding`; `if_form`; `cond_form`/`cond_clause`/`else_clause`; `match_form`/`match_arm`; `try_form`; `fn_form`/`fn_params`/`fn_param`; `constructor_call` (the six heads `ok err some none pair list`); `ctor`/`ctor_arg`; `field_access` (`field_ref` is `.-name`); `call` (fields `callee`, `argument`); patterns: `ok_pattern err_pattern some_pattern none_pattern list_pattern cons_pattern pair_pattern enum_pattern` (enum_pattern also covers qualified heads and prelude cases like `(not-found)`), plus literal/ident/wildcard leaves; terminals `int float string bool unit`, `operator`, `ident`, `qualified`, `type_name`, `qualified_type`, `mod_path`, `keyword`.

Dispatch rule: every `_expr` alternative has a branch; an unrecognized node is an error naming the node type and position, never silent (the `c-2d38` lesson — a skipped branch is a silent language change).

### 2.4 CLI contract

`agentscript-interp [--root DIR]... SOURCE [args...]` — repeatable `--root` after the file's own directory, same search order as `to_python.py --root` and `modules.py` (`file's parent first`); everything after `SOURCE` is program argv (`main` receives `(List String)` like `to_rust.py` `host_entry`: `std::env::args().skip(1)`); stdin/stdout/stderr inherited; file I/O cwd-relative. File without a `main`: exit 0, no output (mirrors `to_python.py host_entry`, which emits a host entry only when the root module declares `main`). Parse error / missing module / evaluator internal error: diagnostic on stderr, exit 2 (distinct from program failure exit 1, which `main_exit` owns).

### 2.5 Runtime semantics the interpreter must reproduce (cited, not re-derived)

- **Numeric widths & traps** — `backend/runtime.py` `INT64_MIN/MAX`, `_int`, `_trunc_div`, `mod` (MIN mod −1 = 0 via `a - q*b`), `checked_div`; `AGENT_SPEC_CORE.md` §3.1. Literals: sign belongs to the digits (`AGENT_SPEC_CORE.md` §2; both grammars already agree on the span, `grammar/validate.py` probes); unsuffixed int is Int64 unless the called function's declared signature says Int32, and an out-of-width literal is an error (§3: "static error").
- **NaN total order** — `runtime.py order_key` / `rt.rs nan_last`: NaN-holding values last, tie with each other, stable; `min`/`max`/`list-min`/`list-max` select by that order (`rt.rs sorts_before`).
- **Equality** — structural, NaN ≠ NaN including inside containers (`runtime.py eq`, spec §3.2).
- **Formatting** — `string-from-float64` must equal Python `repr(float(x))`; port `rt.rs fmt_f64` verbatim (NaN case, signed exponent, ≥2 exponent digits). `string-from-int64` is plain decimal.
- **Conversions** — `string-to-int64`/`string-to-float64`: strip, then reject non-ASCII and `_` before parsing (`runtime.py _parsable` — Rust's bare `parse()` accepts unicode digits Python's gate rejects); `float64-to-int64`: range before truncation (`runtime.py f_to_i`, `rt.rs f_to_i`); `int64-to-int32` range check.
- **Maps** — immutable copy-on-write; iteration sorted by key (`runtime.py m_pairs`, `rt.rs` BTreeMap); `Float64` not a legal key (checker `map-key-order` owns it).
- **Strings** — indices in characters, never bytes (spec §3); escapes `\" \\ \n \t \r \0` (§2) — the tree-sitter `string` node carries the raw quoted text, the interpreter unescapes.
- **I/O + IoError** — map from `std::io::ErrorKind`, folding `NotADirectory | IsADirectory` into `invalid-path` (`rt.rs io_err`); `read-line` returns `(some line)` without the trailing `\n`, `(none)` at EOF (`rt.rs read_line` == `runtime.py read_line`); writes flush.
- **Exit glue** — mirror `rt.rs main_exit` and `runtime.py main_exit`: `ok` → 0; `err case` → write case name + `\n` to stderr, exit 1; reject any other shape (internal error).
- **Modules** — port `grammar/modules.py`: `find` (root/`path + ".agentscript"`), `closure` (dependencies first, root excluded, `seen` seeded with the root's declared path so cycles break instead of recursing — the checker's rule 11 owns the verdict), root last. Top-level identities are keyed by the **defining module path** (mangled per `to_python.py module_prefix` logic), never by the importing alias (`to_python.py`/`to_rust.py` both state this); one module reached through two aliases is one definition (`13-module-program`, `11-name-coexistence`). Enum/runtime tags stay **bare case names** across boundaries (`to_python.py pattern`: "The runtime tag stays the bare case name").
- **Scope & sequencing** — lexical frames, binders shadow top-levels (`15-shadowed-binders` + `core/shadow`); `let*` sequential, a binding's initialiser is outside its own scope; bodies are strict left-to-right, every non-final expression evaluated for effect (`14-sequenced-bodies`); `try` evaluates to the `ok` payload or returns the `err` value from the **enclosing defun** (spec §5.5) — a lambda is not a return target, so `try` unwinds through lambda application to the nearest defun invocation frame; `and`/`or` short-circuit, nothing else does (§5.6). Recursion is plain evaluator recursion (corpus depth is small).

## 3. Ordered work items

Every expected output below is either written down in `backend/differential.py` `program_cases()` or derived in I0 from the Python lowering (the checked-in oracle: transpile with `to_python.py`, run under `backend/runtime.py`). An item whose fixture outputs are not yet written down records them in `.plans/phase-5/ORACLES.md` in I0 — a gate comparing two implementations that share a defect is blind; the written value is the third witness.

**I0 — Baseline + oracle capture.** Run the full battery verbatim into `.plans/phase-5/BASELINE.md`; record counts (validate 98 `ok`; checker gate 79 `ok`; check_corpus 31; differential "0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm)"; pytest 161). Then derive per-fixture expected stdout for the single-module non-program fixtures by executing their Python lowering. Gate:
```
test -s .plans/phase-5/BASELINE.md && test -s .plans/phase-5/ORACLES.md
```

**I1 — Workspace + parser crate + CLI skeleton.** Root workspace, `crates/agentscript-ts` (build.rs per §2.2), `crates/agentscript-interp` binary that parses `SOURCE` with tree-sitter and reports: no ERROR/MISSING nodes → continues; any ERROR/MISSING node or load failure → stderr `SOURCE:line: syntax error`, exit 2. The tree-sitter crate pin is verified against ABI 14 here (§5 risk 1). Gate (fails now: no workspace):
```
rustup run stable cargo build --manifest-path Cargo.toml
B=crates/target/debug/agentscript-interp
printf '(defun f [] -> Int64 1)\n' > /tmp/p5-ok.agentscript && $B /tmp/p5-ok.agentscript; test $? -eq 0
printf '(defun f [] -> Int64 1\n' > /tmp/p5-bad.agentscript && $B /tmp/p5-bad.agentscript; test $? -eq 2
```

**I2 — Value model, literals, arithmetic, core forms.** `Value` enum (Bool; Int32/Int64 width-tagged ints; Float64; String; Unit; List; Pair; Map = BTreeMap keyed with the language order; Option/Result tagged; enum values tagged by bare case name; records = ordered field map). Width-tagged trapping arithmetic (§2.5), literal parsing incl. sign-as-literal and Int32-literal check against the called function's declared signature, string unescaping, `let`/`if`/`cond`/`defun`/call/recursion/`fn` closures with shadowing. Gate (each line fails until implemented; heredoc sources are single-module, no imports):
```
B=crates/target/debug/agentscript-interp
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (str "a" (string-from-int64 (+ -1 2)) "b")))\n' > /tmp/p5-i2.agentscript
test "$($B /tmp/p5-i2.agentscript)" = "ab"
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (string-from-float64 (/ -3.0 2.0))) (println (str "x\\ny")))\n' > /tmp/p5-i2b.agentscript
test "$($B /tmp/p5-i2b.agentscript)" = "$(printf -- '-1.5\nx\ny')"
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (string-from-int64 (+ 9223372036854775807 1))))\n' > /tmp/p5-i2c.agentscript
$B /tmp/p5-i2c.agentscript; test $? -ne 0
```

**I3 — Forms over the corpus (no match, no modules, no I/O).** Single-module fixtures `01,03,04,05,07` run against ORACLES.md entries (their exported entries wrapped in a generated `main` driver checked into `.plans/phase-5/`, never the corpus). Gate:
```
B=crates/target/debug/agentscript-interp; O=.plans/phase-5/ORACLES.md
for f in 01-basics 03-strings 04-longest-run 05-constructors 07-lambda-elision; do
  $B grammar/corpus/valid/$f.agentscript >/tmp/out.$$ || true
  diff -u <(grep -A1 "^$f:" $O | tail -1) /tmp/out.$$ || exit 1
done
```

**I4 — Pattern matching.** All pattern forms (§2.3): bare ident = binder vs parenthesised = case (`18-pattern-binders`); negative literal pattern; qualified enum heads resolve to the defining module's bare tag; cons spines; wildcard. Gate: `02-match` driver output equals its `; run:` values, plus:
```
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (match -1 (-1 "hit") (_ "miss"))))\n' > /tmp/p5-i4.agentscript
test "$($B /tmp/p5-i4.agentscript)" = "hit"
```

**I5 — Builtin vocabulary.** All 107 builtins from `prelude/prelude.json` with the semantics of §2.5 (sorted map iteration, NaN-last stable sort, `fmt_f64`, `_parsable` parsing guards, `f_to_i` range-before-truncation, char-indexed string ops, `list-sum` through trapping add). Cargo unit tests for the traps and formatting (`fmt_f64(1e16)`, `fmt_f64(-0.0)`, `MIN/-1`, `MIN mod -1 == 0`, NaN order, sort stability on NaN keys per `backend/cases/25-list-nan-keys.json`). Gate — the single-module vocabulary fixtures agree with ORACLES:
```
for f in 16-recursive-schema 17-nested-cons 20-option-result-ctors 21-option-result-combinators 22-boolean-algebra 23-numeric 24-list-reshaping 25-list-aggregation 26-map-lifecycle 27-string-query 28-string-transforms 29-literals; do
  $B grammar/corpus/valid/$f.agentscript >/tmp/out.$$ || true
  diff -u <(.venv/bin/python .plans/phase-5/oracle.py $f) /tmp/out.$$ || exit 1
done
rustup run stable cargo test --manifest-path Cargo.toml -q
```

**I6 — Module system.** Port `modules.py` resolution into `src/modules.rs` (§2.5): search path = file's parent + `--root`s; dependencies-first evaluation order; alias tables per unit; global table keyed by defining module path; qualified name/type resolution; bare enum tags across boundaries. Gate:
```
R=--root grammar/corpus/modules
for f in 06-module 09-imported-types 10-imported-generic-types 11-name-coexistence 12-transitive-use 15-shadowed-binders; do
  $B $R grammar/corpus/valid/$f.agentscript >/tmp/out.$$ || true
  diff -u <(.venv/bin/python .plans/phase-5/oracle.py $f) /tmp/out.$$ || exit 1
done
```

**I7 — I/O + program entry.** IoError mapping from `ErrorKind` (§2.5), the nine I/O builtins, `main` glue: argv as `(List String)`, `main_exit` semantics, exit 0/1, stderr case name. Gate — replay every case of `08-io` and `19-io-errors` exactly as declared in `differential.py program_cases()` (files seeded per case in a fresh dir, stdin piped, stdout/stderr/exit each asserted).

**I8 — Differential integration.** Add `build_interpreter` and the fourth arm per §2.2; the agree expression gains `== seen["interp"]`, the declared-value check stays `seen["python"] == want` (unchanged); summary line names four arms. Gate — the acceptance battery below.

## 4. Acceptance gate

```
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py          # now python/rust/wasm/interp; "0 disagreement(s)"
.venv/bin/python backend/exec_coverage.py         # untouched, must stay green (imports differential)
.venv/bin/python -m pytest backend/t bench/algo checker/t -q
rustup run stable cargo test --manifest-path Cargo.toml -q
.venv/bin/python backend/differential.py 2>&1 | grep -q 'interp'
git diff <I0 baseline> HEAD -- backend/differential.py | grep '^[+-]' | grep -E '"stdout"|"stderr"|"exit"'   # empty: declared values untouched
git diff <I0 baseline> HEAD -- prelude/coverage.lock backend/cases                                            # empty
```

## 5. Risks

1. **tree-sitter crate/ABI pin** — `parser.c` is `LANGUAGE_VERSION 14` (`src/parser.c:9`); which crates.io releases accept 14 is undecidable from the repo. I1 verifies the pin before any evaluation work; a wrong pin fails the scaffold gate loudly.
2. **`build.rs` regeneration dependency** — `src/` is gitignored; the parser crate depends on `parser.c` existing (regenerate via the node CLI, which `validate.py` already requires). If node is absent in some future environment, build fails loudly rather than silently using a stale parser — a gate-environment decision for the orchestrator.
3. **Float formatting** — Rust `{:?}` ≠ Python `repr` at NaN case, unsigned/short exponents; `fmt_f64` is ported verbatim from `rt.rs` and pinned by the 29-literals/23-numeric oracles and cargo tests.
4. **Numeric parse guards** — Rust's `parse()` accepts more than the language (unicode digits); `_parsable` must be ported or `string-to-int64` disagrees on hostile input; pinned by 23-numeric `from-float` cases.
5. **NaN order & stability** — sort must be stable with NaN-last ties or `25-list-nan-keys` disagrees; cargo test pins `-nan` before `nan` (input order) exactly as the case file declares.
6. **`MIN / -1` family** — `/`, `neg`, `abs`, `+`, `-`, `*`, `list-sum` trap; `mod MIN -1 == 0`; `checked-div` → none. Pinned by 23-numeric oracles and cargo tests.
7. **Map key order** — language order = Python `sorted()` = BTreeMap `Ord` = codepoint order for String; the interpreter's key comparator must be codepoint order, not locale/case-insensitive. Pinned by 26-map-lifecycle and `map-pairs` oracles.
8. **Module identity** — keying globals on the import alias instead of the defining module path breaks `13-module-program` (one module, two aliases) with duplicate or missing definitions; `11-name-coexistence` additionally pins local-vs-imported nominal identity.
9. **`try` across lambdas** — `try` returns from the enclosing defun, not the lambda (spec §5.5); an unwind that stops at the lambda frame is silently wrong. Pinned by an I2/I3 heredoc with `try` inside a lambda passed to a Result-returning defun.
10. **Function mode not covered** — the acceptance is program mode; the interpreter's agreement on pure entry returns (the 120 function cases) is proven only indirectly via program outputs. Extending function mode to the interpreter needs an entry-invocation protocol (JSON in/out like `harness.rs`) — flagged as a Phase-5 follow-up or Phase-9 item, decision for the orchestrator.
11. **String escapes untested by the corpus** — no corpus fixture contains a `\"`/`\\`/`\n` escape; I2's heredoc gate pins `\n` and `\\` unescaping explicitly, else the defect ships invisible.
12. **Grammar nodes the interpreter could skip** — `field_opt` `:json`, `type_app` in type position, `constructor_call` heads used where `call` would also parse: dispatch is exhaustive with a named-error default (§2.3); a skipped branch is the `c-2d38` failure shape.
13. **Exit-code collisions** — program failure (1) vs internal error (2) vs usage: pinned distinct in I1/I7, because `differential.py` compares exit status byte-for-byte and a trap that exits 1 would masquerade as an `IoError` failure.

## Invariants (each tied to an item)

| Invariant | Citation | Item |
|---|---|---|
| Agreement compares stdout+stderr+exit across ALL arms AND against the declared value | `backend/differential.py:361-363` | I8 |
| Declared case values (`"stdout"/"stderr"/"exit"`) and existing `build_*` arms unchanged | `differential.py:336-348` | I8 |
| Resolution = dependencies first, root last, cycle broken not diagnosed | `grammar/modules.py:44-71` | I6 |
| Top-level identity keyed by defining module path, never alias | `backend/to_python.py` `module_prefix` + `to_rust.py` `rust_mod` docstrings | I6 |
| Enum/runtime tags are bare case names across boundaries | `backend/to_python.py` `pattern` comment | I4/I6 |
| Exit glue: ok→0; err→case name on stderr, exit 1; other shapes rejected | `backend/rust/rt.rs` `main_exit`, `backend/runtime.py` `main_exit` | I7 |
| IoError mapping from `ErrorKind`, `NotADirectory\|IsADirectory`→invalid-path | `backend/rust/rt.rs` `io_err` | I7 |
| NaN-last total order, stable; selection follows sort | `backend/runtime.py` `order_key`, `backend/rust/rt.rs` `nan_last` | I5 |
| Map iteration sorted by key | `backend/runtime.py` `m_pairs`, `rt.rs` BTreeMap note | I5 |
| `fmt_f64` == Python `repr` | `backend/rust/rt.rs` `fmt_f64` | I5 |
| Host entry only when the root module declares `main` | `backend/to_python.py` `host_entry` | I7 |
| `exec_coverage.py` consumes `differential.program_cases()` and must stay green untouched | `backend/exec_coverage.py:48,219` | I8 |
| `target/` ignored; `grammar/tree-sitter-agentscript/src/` generated | `.gitignore:4,5` | I1 |
