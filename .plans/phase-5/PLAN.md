# Phase 5 — Reference interpreter

Baseline: all gates green at `d38e236` per `.plans/ORCHESTRATOR-LOG.md` (Phase 4 closed: seven gates, 161 tests, differential 120 function + 15 program cases, 0 disagreements). Item I0 re-runs every gate, records the literal HEAD SHA and the per-fixture oracle outputs the later gates compare against, and authors the oracle tooling the later gates execute.

## 1. Scope

A Rust **tree-walking reference interpreter** for AgentScript: parse with the project's own tree-sitter grammar (`grammar/tree-sitter-agentscript/`), evaluate the AST directly with a dynamic value model, run a module as a program (`main` + argv + exit status). It attaches to `backend/differential.py` as a fourth **program-mode** arm over `program_cases()`. Function mode is out of scope this phase: the acceptance text (`.plans/PHASES.md` Phase 5, "`corpus/valid` programs execute under the interpreter and agree with the compiled arms via `differential.py`") is read as **program mode** — the verb is "execute a program", and `differential.py`'s program mode is the only surface that compares stdout/stderr/exit. Agreement on the 120 function-mode entry returns is a follow-up (an entry-invocation protocol like `backend/rust/harness.rs`, Phase-5 follow-up or Phase-9; §5 risk 10). The wording gap in PHASES.md itself is flagged for the orchestrator, not resolved here.

**Out of scope:** performance (no bytecode/VM), type checking (the checker gate remains the type authority; the corpus is checker-clean before the interpreter ever sees it), `; run:` header execution for non-program modules (that surface belongs to `check_corpus.py`/Python only), and field `:default` application at construction — the Python backend's `defschema` lowering emits no defaults either (`backend/to_python.py` `defschema`), and `29-literals.agentscript` records the omission as a known ROADMAP §6 gap. The interpreter matches the backends: omitting a defaulted field is a runtime failure.

**Acceptance:** every `grammar/corpus/valid/*.agentscript` program executes under the interpreter and agrees with python/rust/wasm on stdout, stderr and exit status via `differential.py` — where "executes" means the fixture's entry points are actually evaluated (through the driver mechanism of §3 I0 for fixtures without `main`), not merely that the process exits.

## 2. Inventory

### 2.1 New files

| Path | Content |
|---|---|
| `Cargo.toml` (root) | Workspace `[workspace] members = ["crates/*"]`; `target/` is already gitignored (`.gitignore:4`). |
| `crates/agentscript-ts/Cargo.toml` + `build.rs` | Static-lib crate wrapping the generated parser. `build.rs` copies `grammar/tree-sitter-agentscript/src/` into `OUT_DIR` and compiles `parser.c` with `cc`. If `src/parser.c` is missing or older than `grammar.js`, it regenerates via `node_modules/.bin/tree-sitter generate` (node + CLI are already repo dev-deps, `package.json`; `validate.py` shells to the same CLI). Fail loudly if node is absent. |
| `crates/agentscript-interp/` (`Cargo.toml`, `src/main.rs`, `src/ast.rs`, `src/value.rs`, `src/num.rs`, `src/eval.rs`, `src/modules.rs`, `src/builtins.rs`, `src/io.rs`, `src/fmt.rs`, `tests/`) | The interpreter binary. Dependencies: `agentscript-ts` (path), `tree-sitter` crate pinned to a release that accepts `LANGUAGE_VERSION 14` (`grammar/tree-sitter-agentscript/src/parser.c:9`) — the exact pin is verified on crates.io during I1 (§5 risk 1). |
| `.plans/phase-5/oracle.py` | **Authored in I0.** CLI: `oracle.py [--root DIR]... [--emit] FIXTURE`. Default mode prints the expected stdout of the driver-wrapped program for `FIXTURE` (expected stderr is empty and exit 0 for every fixture it serves — all are pure). `--emit` prints the wrapped AgentScript source to stdout, so a gate can materialize exactly the program whose output the oracle predicts. It composes the wrapped source as `grammar/corpus/valid/FIXTURE.agentscript` + the checked-in wrap body from `.plans/phase-5/drivers/FIXTURE.main` (an appended `(defun ! main …)` that calls the fixture's exported entries and prints the results its `; run:` headers assert), transpiles with `to_python.py`, runs under `backend/runtime.py`, and prints the resulting stdout. It never consults the interpreter. |
| `.plans/phase-5/drivers/<fixture>.main` | **Authored in I0.** One wrap body per fixture the driver mechanism serves (§3's mapping table). Checked in so the oracle's prediction and the interpreter's input are both inspectable artifacts, not implicit conventions. |
| `.plans/phase-5/probes/<name>.agentscript` + `<name>.expected` | **Authored in I0.** Hand-written probe programs and their hand-written expected stdout/stderr/exit — the third witness that never passes through the Python lowering. Required probes: `int32-trap` (the `l-4d92` witness), `user-sort` (the `l-5c47` witness), `escapes` (all six: `\" \\ \n \t \r \0`), `try-in-lambda`, `read-line-eof`, `nan-stability` (two NaNs), `parsable-guards` (`"١٢٣"`, `"1_000"`), `map-pairs-order`. |
| `.plans/phase-5/BASELINE.md`, `.plans/phase-5/ORACLES.md` | I0 records: BASELINE.md holds the literal baseline commit SHA (`baseline: <40-hex>`) and the re-run gate counts; ORACLES.md holds the per-fixture expected stdout the oracle derives (for human review of the oracle's predictions). |
| `.plans/phase-5/replay.py` | **Authored in I7, rewritten in I8.** CLI: `replay.py` (no args). I7: iterates `backend/differential.py` `program_cases()`, builds the interpreter binary, seeds each case's `files`/`stdin`/`argv` in a fresh directory and asserts the case's declared stdout/stderr/exit against the interpreter alone. I8 replaces its local build step with `differential.build_interpreter`, so the replay and the differential arm cannot drift. |

### 2.2 Modified files

- `backend/differential.py` — I8 only: add `build_interpreter(src, d)` beside `build_python`/`build_rust`/`build_rust_wasm` (`differential.py:282-322`); add `"interp"` to the `runners` dict (`differential.py:347-348`); extend the agreement expression and the declared-value check (`differential.py:361-363` — `agree` gains `== seen["interp"]`; `declared_ok = seen["python"] == want` stays a separate comparison against the python arm); extend the table header and per-case row (`differential.py:336,366-369`); and the summary line (`differential.py:455-456`) to name four arms: `(python/rust/wasm/interp)`. **No change** to `program_cases()`, the declared `want` values, `build_*` for existing arms, or `exec_coverage.py` (which imports `differential` and iterates `differential.program_cases()`, `backend/exec_coverage.py:48,219`).
- `.gitignore` — add nothing needed (`target/` present); verify `Cargo.lock` stays tracked.
- `.plans/phase-5/replay.py` — I8 rewrite per §2.1.

### 2.3 AST node types the evaluator dispatches on (from `grammar/tree-sitter-agentscript/grammar.js`)

`source_file`; `module_decl` (fields `path`, opts: `:doc`/`:export`/`:import`), `import_spec`, `type_params`; `defschema`/`field`/`field_opt`; `defenum`/`enum_case`; `defun` (optional `effect` `!`, `name`, `params`, `return_type`, `body`+); `let_form`/`binding`; `if_form`; `cond_form`/`cond_clause`/`else_clause`; `match_form`/`match_arm`; `try_form`; `fn_form`/`fn_params`/`fn_param`; `constructor_call` (the six heads `ok err some none pair list`); `ctor`/`ctor_arg`; `field_access` (`field_ref` is `.-name`); `call` (fields `callee`, `argument`); patterns: `ok_pattern err_pattern some_pattern none_pattern list_pattern cons_pattern pair_pattern enum_pattern` (enum_pattern also covers qualified heads and prelude cases like `(not-found)`), plus literal/ident/wildcard leaves; terminals `int float string bool unit`, `operator`, `ident`, `qualified`, `type_name`, `qualified_type`, `type_app`, `mod_path`, `keyword`. `type_app` appears only in type positions (`_type`); the interpreter never evaluates types, but it must **recognize** the node wherever it walks (a `defun`'s `return_type` or a parameter type may be `(List Int64)`) and treat it as erased — an unrecognized node in type position is the same named-error as anywhere else, never a silent skip.

Dispatch rule: every `_expr` alternative has a branch; an unrecognized node is an error naming the node type and position, never silent (the `c-2d38` lesson — a skipped branch is a silent language change).

### 2.4 CLI contract

`agentscript-interp [--root DIR]... SOURCE [args...]` — repeatable `--root` after the file's own directory, same search order as `to_python.py --root` and `modules.py` (`file's parent first`); everything after `SOURCE` is program argv (`main` receives `(List String)` like `to_rust.py` `host_entry`: `std::env::args().skip(1)`); stdin/stdout/stderr inherited; file I/O cwd-relative. Gate commands that pass argv containing shell-significant characters must quote them; every gate in §3 uses quoted or arg-free invocations. File without a `main`: exit 0, no output (mirrors `to_python.py host_entry`, which emits a host entry only when the root module declares `main`) — which is exactly why every gate that must observe a fixture's behaviour goes through the driver mechanism (§3 I0) instead of running the bare fixture. Parse error / missing module / evaluator internal error / **trap** (arithmetic overflow, out-of-width literal at runtime, malformed conversion): diagnostic on stderr, exit 2 (distinct from program failure exit 1, which `main_exit` owns).

### 2.5 Runtime semantics the interpreter must reproduce (cited, not re-derived)

- **Numeric widths & traps** — `backend/runtime.py` `INT64_MIN/MAX`, `_int`, `_trunc_div`, `mod` (MIN mod −1 = 0 via `a - q*b`), `checked_div`; `AGENT_SPEC_CORE.md` §3.1. Int32 and Int64 are siblings: arithmetic is trapping at the operand's own width (Int32 traps at the 2³¹ boundary), and an out-of-width literal is an error (§3: "static error"). Literals: sign belongs to the digits (`AGENT_SPEC_CORE.md` §2; both grammars already agree on the span, `grammar/validate.py` probes); unsuffixed int is Int64 unless the called function's declared signature says Int32. The Python arm is known-wrong here — its lowering ignores Int32 width (ROADMAP `l-4d92`) — so Int32 trap behaviour is pinned by the hand-written `int32-trap` probe, never by the Python-derived oracle; and because a Rust trap is not a value, `program_cases()` stays trap-free (a recorded scope decision, not an oversight).
- **Sort order** — NaN total order and stability: `runtime.py order_key` / `rt.rs nan_last`: NaN-holding values last, tie with each other, stable; `min`/`max`/`list-min`/`list-max` select by that order (`rt.rs sorts_before`). For **user types** the interpreter orders enum/union values by **declaration order** — the order ROADMAP names as the presumptive §3.2 rule (`l-5c47`/`d-6c04`: "one sort order for user types, presumably declaration order, written into §3.2"). The compiled arms disagree with each other here today, so no differential case can pin it; the hand-written `user-sort` probe is the witness, and the §3.2 specification change itself is flagged for the orchestrator.
- **Equality** — structural, NaN ≠ NaN including inside containers (`runtime.py eq`, spec §3.2).
- **Formatting** — `string-from-float64` must equal Python `repr(float(x))`; port `rt.rs fmt_f64` verbatim (NaN case, signed exponent, ≥2 exponent digits). `string-from-int64` is plain decimal.
- **Conversions** — `string-to-int64`/`string-to-float64`: strip, then reject non-ASCII and `_` before parsing (`runtime.py _parsable` — Rust's bare `parse()` accepts unicode digits Python's gate rejects); `float64-to-int64`: range before truncation (`runtime.py f_to_i`, `rt.rs f_to_i`); `int64-to-int32` range check.
- **Maps** — immutable copy-on-write; iteration sorted by key (`runtime.py m_pairs`, `rt.rs` BTreeMap); the key comparator is codepoint order, not locale or case-folding; `Float64` is not a legal key — the checker's `map-key-order` rule rejects it before any program runs, so a `Map Float64 V` reaching the interpreter at runtime is an internal error (exit 2 diagnostic), a shape no valid program can produce.
- **Strings** — indices in characters, never bytes (spec §3); escapes `\" \\ \n \t \r \0` (§2) — the tree-sitter `string` node carries the raw quoted text, the interpreter unescapes all six.
- **I/O + IoError** — map from `std::io::ErrorKind`, folding `NotADirectory | IsADirectory` into `invalid-path` (`rt.rs io_err`); `read-line` returns `(some line)` without the trailing `\n`, `(none)` at EOF (`rt.rs read_line` == `runtime.py read_line`); writes flush.
- **Exit glue** — mirror `rt.rs main_exit` and `runtime.py main_exit`: `ok` → 0; `err case` → write case name + `\n` to stderr, exit 1; reject any other shape (internal error). Traps are exit 2 with a diagnostic (§2.4); they are not comparable across the compiled arms, which is why no differential case traps.
- **Modules** — port `grammar/modules.py`: `find` (root/`path + ".agentscript"`), `closure` (dependencies first, root excluded, `seen` seeded with the root's declared path so cycles break instead of recursing — the checker's rule 11 owns the verdict), root last. Top-level identities are keyed by the **defining module path** (mangled per `to_python.py module_prefix` logic), never by the importing alias (`to_python.py`/`to_rust.py` both state this); one module reached through two aliases is one definition (`13-module-program`, `11-name-coexistence`). Enum/runtime tags stay **bare case names** across boundaries (`to_python.py pattern`: "The runtime tag stays the bare case name").
- **Scope & sequencing** — lexical frames, binders shadow top-levels (`15-shadowed-binders` + `core/shadow`); `let*` sequential, a binding's initialiser is outside its own scope; bodies are strict left-to-right, every non-final expression evaluated for effect (`14-sequenced-bodies`); `try` evaluates to the `ok` payload or returns the `err` value from the **enclosing defun** (spec §5.5) — a lambda is not a return target, so `try` unwinds through lambda application to the nearest defun invocation frame; `and`/`or` short-circuit, nothing else does (§5.6). Recursion is plain evaluator recursion (corpus depth is small).

## 3. Ordered work items

Every gate below compares against one of two witnesses. The **derived oracle** (`.plans/phase-5/oracle.py`, authored in I0) predicts a fixture's driver-wrapped stdout by executing the Python lowering — the checked-in oracle. The **hand-written probes** (`.plans/phase-5/probes/`, authored in I0) pin every behaviour where the Python lowering is a blind oracle: the defects it already has (`l-4d92` Int32 width, `l-5c47` user-type sort) and the behaviours no corpus fixture exercises (the six escapes, EOF, two-NaN stability, parse guards, `map-pairs` order, `try` unwinding). A gate comparing two implementations that share a defect is blind; the probes exist so that no gate's only witnesses are two arms of the same lowering.

**Fixture → item map (all 29 `corpus/valid` fixtures):**

| Item | Fixtures | Mechanism |
|---|---|---|
| I3 | 01, 03, 04, 05, 07 | driver-wrapped, derived oracle |
| I4 | 02, 18 | 02 driver-wrapped; 18 driver-wrapped (the only fixture pinning binder-vs-parenthesised-case) |
| I5 | 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29 | driver-wrapped, derived oracle + cargo tests |
| I6 | 06, 09, 10, 11, 12, 15 | driver-wrapped + `--root grammar/corpus/modules` (only 15 declares `main`; 06 does not) |
| I7 | 08, 19 | declared `program_cases()` replayed against the interpreter (`replay.py`) + `read-line-eof` probe |
| differential (pre-existing) | 13, 14, 15 (+ 08, 19) | declared `want` values are themselves a hand-written witness |

No fixture is unaccounted for; `13`/`14` were already Phase-4 commitments and stay in the differential battery.

**I0 — Baseline, oracle tooling, probes.** Run the full battery verbatim into `.plans/phase-5/BASELINE.md` with the literal HEAD SHA; record counts (validate 98 `ok`; checker gate 79 `ok`; check_corpus 31; differential "0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm)"; pytest 161). Author `oracle.py`, the per-fixture `drivers/*.main` wrap bodies for every fixture in the map above, `ORACLES.md` (the derived per-fixture predictions, for human review), and the probe files in `.plans/phase-5/probes/` with hand-written `.expected` files. If any re-run count differs from the recorded claim, I0 halts and reports — the expectation is never edited to match a regressed tree. Gate:
```
test -s .plans/phase-5/BASELINE.md && test -s .plans/phase-5/ORACLES.md
grep -q '^baseline: [0-9a-f]\{40\}$' .plans/phase-5/BASELINE.md
grep -q 'validate: 98 ok' .plans/phase-5/BASELINE.md
grep -q 'checker gate: 79 ok' .plans/phase-5/BASELINE.md
grep -q 'check_corpus: 31' .plans/phase-5/BASELINE.md
grep -q 'differential: 0 disagreement(s) across 120 function cases + 15 program cases' .plans/phase-5/BASELINE.md
grep -q 'pytest: 161 passed' .plans/phase-5/BASELINE.md
test -x .plans/phase-5/oracle.py
ls .plans/phase-5/probes/*.expected | wc -l   # ≥ 8, one per required probe
.venv/bin/python .plans/phase-5/oracle.py 01-basics   # exits 0, prints non-empty expected stdout
```

**I1 — Workspace + parser crate + CLI skeleton.** Root workspace, `crates/agentscript-ts` (build.rs per §2.2), `crates/agentscript-interp` binary that parses `SOURCE` with tree-sitter and reports: no ERROR/MISSING nodes → continues; any ERROR/MISSING node or load failure → stderr `SOURCE:line: syntax error`, exit 2. The tree-sitter crate pin is verified against ABI 14 here (§5 risk 1), including a cargo test that parses a source end-to-end — the scaffold exercises the parser at runtime, not merely at link time. Gate (fails now: no workspace):
```
rustup run stable cargo build --manifest-path Cargo.toml
B=crates/target/debug/agentscript-interp
printf '(defun f [] -> Int64 1)\n' > /tmp/p5-ok.agentscript
out="$($B /tmp/p5-ok.agentscript)"; test $? -eq 0 && test -z "$out"
printf '(defun f [] -> Int64 1\n' > /tmp/p5-bad.agentscript && $B /tmp/p5-bad.agentscript; test $? -eq 2
rustup run stable cargo test --manifest-path Cargo.toml -q
```

**I2 — Value model, literals, arithmetic, core forms.** `Value` enum (Bool; Int32/Int64 width-tagged ints; Float64; String; Unit; List; Pair; Map = BTreeMap keyed with the language order; Option/Result tagged; enum values tagged by bare case name; records = ordered field map). Width-tagged trapping arithmetic at **both** widths (§2.5), literal parsing incl. sign-as-literal and the Int32-literal check against the called function's declared signature, string unescaping, `let`/`if`/`cond`/`defun`/call/recursion/`fn` closures with shadowing, `try` unwinding to the enclosing defun through lambda application. Gate (each line fails until implemented; heredoc sources are single-module, no imports):
```
B=crates/target/debug/agentscript-interp
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (str "a" (string-from-int64 (+ -1 2)) "b")))\n' > /tmp/p5-i2.agentscript
test "$($B /tmp/p5-i2.agentscript)" = "ab"
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (string-from-float64 (/ -3.0 2.0))) (println (str "x\\ny")))\n' > /tmp/p5-i2b.agentscript
test "$($B /tmp/p5-i2b.agentscript)" = "$(printf -- '-1.5\nx\ny')"
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (string-from-int64 (+ 9223372036854775807 1))))\n' > /tmp/p5-i2c.agentscript
$B /tmp/p5-i2c.agentscript 2>/tmp/err.$$; test $? -eq 2 && test -s /tmp/err.$$
cat > /tmp/p5-i2d.agentscript <<'EOF'
(defun ! main [(args (List String))] -> (Result Unit IoError)
  (println (string-from-int32 (bump 2147483647))))
EOF
printf '(defun bump [(n Int32)] -> Int32 (+ n 1))\n' >> /tmp/p5-i2d.agentscript
$B /tmp/p5-i2d.agentscript 2>/tmp/err2.$$; test $? -eq 2 && test -s /tmp/err2.$$
$B .plans/phase-5/probes/try-in-lambda.agentscript; test $? -eq 0
diff -u .plans/phase-5/probes/try-in-lambda.expected <($B .plans/phase-5/probes/try-in-lambda.agentscript) || exit 1
diff -u .plans/phase-5/probes/escapes.expected <($B .plans/phase-5/probes/escapes.agentscript) || exit 1
```
The `p5-i2b` line is correct as written: `printf` emits one backslash followed by `n` into the source — which is exactly the two-character escape the lexer must unescape — while the expected side (`printf -- '-1.5\nx\ny'`) contains real newlines. The Int32 trap (`p5-i2d`) and the trap's stderr+exit-2 shape pin the `l-4d92` behaviour the Python oracle cannot see.

**I3 — Forms over the corpus (no match, no modules, no I/O).** Fixtures 01, 03, 04, 05, 07 run **driver-wrapped** (none declares `main`; the bare fixture would exit 0 with empty stdout and the comparison would be vacuous) against the derived oracle. Gate:
```
B=crates/target/debug/agentscript-interp; O=".venv/bin/python .plans/phase-5/oracle.py"
for f in 01-basics 03-strings 04-longest-run 05-constructors 07-lambda-elision; do
  $O --emit $f > /tmp/wrap.$$.agentscript
  $B /tmp/wrap.$$.agentscript > /tmp/out.$$ || exit 1
  diff -u <($O $f) /tmp/out.$$ || exit 1
done
```

**I4 — Pattern matching.** All pattern forms (§2.3): bare ident = binder vs parenthesised = case (`18-pattern-binders` — the only fixture pinning the distinction, so it is driven by name, not by prose); negative literal pattern; qualified enum heads resolve to the defining module's bare tag; cons spines; wildcard. Gate: `02-match` driver output equals the oracle's, plus:
```
B=crates/target/debug/agentscript-interp; O=".venv/bin/python .plans/phase-5/oracle.py"
for f in 02-match 18-pattern-binders; do
  $O --emit $f > /tmp/wrap.$$.agentscript
  $B /tmp/wrap.$$.agentscript > /tmp/out.$$ || exit 1
  diff -u <($O $f) /tmp/out.$$ || exit 1
done
printf '(defun ! main [(args (List String))] -> (Result Unit IoError) (println (match -1 (-1 "hit") (_ "miss"))))\n' > /tmp/p5-i4.agentscript
test "$($B /tmp/p5-i4.agentscript)" = "hit"
```

**I5 — Builtin vocabulary.** All 107 builtins from `prelude/prelude.json` with the semantics of §2.5 (sorted map iteration, NaN-last stable sort, `fmt_f64`, `_parsable` parsing guards, `f_to_i` range-before-truncation, char-indexed string ops, `list-sum` through trapping add). Cargo unit tests for the traps and formatting (`fmt_f64(1e16)`, `fmt_f64(-0.0)`, `MIN/-1`, `MIN mod -1 == 0`, NaN order, **sort stability with two NaN values** whose tie order must be input order per `backend/cases/25-list-nan-keys.json`, **multi-entry map key iteration in codepoint order** — the test that would catch a `HashMap` standing in for the BTreeMap, **`map-pairs` key/value ordering** — no corpus fixture or case file asserts it — **`_parsable` hostile input** `"١٢٣"` and `"1_000"` rejected). Gate — the driver-wrapped vocabulary fixtures agree with the derived oracle, and the hand-written probes hold:
```
B=crates/target/debug/agentscript-interp; O=".venv/bin/python .plans/phase-5/oracle.py"
for f in 16-recursive-schema 17-nested-cons 20-option-result-ctors 21-option-result-combinators 22-boolean-algebra 23-numeric 24-list-reshaping 25-list-aggregation 26-map-lifecycle 27-string-query 28-string-transforms 29-literals; do
  $O --emit $f > /tmp/wrap.$$.agentscript
  $B /tmp/wrap.$$.agentscript > /tmp/out.$$ || exit 1
  diff -u <($O $f) /tmp/out.$$ || exit 1
done
for p in int32-trap user-sort nan-stability parsable-guards map-pairs-order; do
  diff -u .plans/phase-5/probes/$p.expected <($B .plans/phase-5/probes/$p.agentscript) || exit 1
done
rustup run stable cargo test --manifest-path Cargo.toml -q
```
The `user-sort` probe compares only against its hand-written `.expected` file: the compiled arms disagree on user-type sort order today (`l-5c47`), so there is no derived oracle and no differential case — the interpreter implements the ROADMAP-presumptive rule (declaration order, §2.5) and the spec change is the orchestrator's.

**I6 — Module system.** Port `modules.py` resolution into `src/modules.rs` (§2.5): search path = file's parent + `--root`s; dependencies-first evaluation order; alias tables per unit; global table keyed by defining module path; qualified name/type resolution; bare enum tags across boundaries. Gate — all six fixtures driver-wrapped (`06` does not declare `main`; `15` does but goes through the same mechanism with `--root` for its `core/shadow` import):
```
B=crates/target/debug/agentscript-interp; O=".venv/bin/python .plans/phase-5/oracle.py"
for f in 06-module 09-imported-types 10-imported-generic-types 11-name-coexistence 12-transitive-use 15-shadowed-binders; do
  $O --emit --root grammar/corpus/modules $f > /tmp/wrap.$$.agentscript
  $B --root grammar/corpus/modules /tmp/wrap.$$.agentscript > /tmp/out.$$ || exit 1
  diff -u <($O --root grammar/corpus/modules $f) /tmp/out.$$ || exit 1
done
```

**I7 — I/O + program entry.** IoError mapping from `ErrorKind` (§2.5), the nine I/O builtins, `main` glue: argv as `(List String)`, `main_exit` semantics, exit 0/1, stderr case name. Gate — `replay.py` (§2.1) replays every case of `program_cases()` (`08-io`: 5 cases, `13`, `14`, `15`: 1 each, `19-io-errors`: 7 cases) against the interpreter alone, seeding files/stdin/argv per case and asserting declared stdout/stderr/exit; plus the EOF probe, since no declared case feeds empty stdin to `read-line`:
```
.venv/bin/python .plans/phase-5/replay.py || exit 1
diff -u .plans/phase-5/probes/read-line-eof.expected \
  <($B .plans/phase-5/probes/read-line-eof.agentscript </dev/null) || exit 1
```
`replay.py` is executable here because it needs only the built binary and `program_cases()`, not the I8 wiring.

**I8 — Differential integration.** Add `build_interpreter` and the fourth arm per §2.2; the agree expression gains `== seen["interp"]`, the declared-value check stays `seen["python"] == want` (unchanged); summary line names four arms; `replay.py` switches its build step to `differential.build_interpreter`. Sub-items, each with its own check:
1. The arm runs and agrees: the acceptance battery below is green.
2. The declared values are untouched: `git diff $(baseline) HEAD -- backend/differential.py` shows no `+`/`-` line matching `"stdout"|"stderr"|"exit"` (grep guard, §4).
3. `prelude/coverage.lock` and `backend/cases` are byte-identical to the baseline (grep-empty guard, §4) — these are enumerated here as I8 obligations, not left as belt-and-braces at acceptance.
4. `exec_coverage.py` stays green untouched: its dependency is `differential.program_cases()`, which I8 does not modify.

## 4. Acceptance gate

`<base>` is the SHA recorded in `.plans/phase-5/BASELINE.md` by I0 (a literal commit ref, not a tree hash, so intermediate commits are included):
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
.venv/bin/python backend/differential.py 2>&1 | grep -q 'cases (python/rust/wasm/interp)'
git diff $(grep '^baseline:' .plans/phase-5/BASELINE.md | awk '{print $2}') HEAD -- backend/differential.py \
  | grep '^[+-]' | grep -E '"stdout"|"stderr"|"exit"'   # empty: declared values untouched
git diff $(grep '^baseline:' .plans/phase-5/BASELINE.md | awk '{print $2}') HEAD -- prelude/coverage.lock backend/cases  # empty
```
The summary-line grep pins the four-arm literal `(python/rust/wasm/interp)`, not the bare substring `interp`, so it fails if the arm is wired but the summary line was not updated — and fails if the summary was updated but the arm never ran (`0 disagreement(s)` cannot print for a case list the interpreter never entered, because a missing `build_interpreter` output is a disagreement, not a skip).

## 5. Risks

1. **tree-sitter crate/ABI pin** — `parser.c` is `LANGUAGE_VERSION 14` (`src/parser.c:9`); which crates.io releases accept 14 is undecidable from the repo. I1 verifies the pin with an end-to-end parse test before any evaluation work; a wrong pin fails the scaffold gate loudly.
2. **`build.rs` regeneration dependency** — `src/` is gitignored; the parser crate depends on `parser.c` existing (regenerate via the node CLI, which `validate.py` already requires). If node is absent in some future environment, build fails loudly rather than silently using a stale parser — a gate-environment decision for the orchestrator.
3. **Float formatting** — Rust `{:?}` ≠ Python `repr` at NaN case, unsigned/short exponents; `fmt_f64` is ported verbatim from `rt.rs` and pinned by the 29-literals driver oracle, the cargo tests (`fmt_f64(1e16)` pins the ≥2-exponent-digit rule explicitly), and the `escapes`/`parsable-guards` probes.
4. **Numeric parse guards** — Rust's `parse()` accepts more than the language (unicode digits); `_parsable` must be ported or `string-to-int64` disagrees on hostile input; pinned by the `parsable-guards` probe and the I5 cargo test, not merely by clean corpus inputs.
5. **NaN order & stability** — sort must be stable with NaN-last ties or `25-list-nan-keys` disagrees; the I5 cargo test pins a two-NaN input preserving input order (a one-NaN list cannot distinguish a real `nan_last` comparator from a panic-prone `partial_cmp`), exactly as the case file declares.
6. **`MIN / -1` family** — `/`, `neg`, `abs`, `+`, `-`, `*`, `list-sum` trap; `mod MIN -1 == 0`; `checked-div` → none. Pinned by 23-numeric driver oracle and cargo tests.
7. **Map key order** — language order = Python `sorted()` = BTreeMap `Ord` = codepoint order for String; the interpreter's key comparator must be codepoint order, not locale/case-insensitive. Pinned by 26-map-lifecycle driver oracle, the `map-pairs-order` probe, and the multi-entry cargo test.
8. **Module identity** — keying globals on the import alias instead of the defining module path breaks `13-module-program` (one module, two aliases) with duplicate or missing definitions; `11-name-coexistence` additionally pins local-vs-imported nominal identity. The declared `want` for `13-module-program` in `program_cases()` is a hand-written witness independent of the Python lowering.
9. **`try` across lambdas** — `try` returns from the enclosing defun, not the lambda (spec §5.5); an unwind that stops at the lambda frame is silently wrong. Pinned by the `try-in-lambda` probe (I2), whose expected values are hand-written — the Python arm shares the wrong-shape risk, so the derived oracle is not trusted here.
10. **Function mode not covered** — the acceptance is program mode (§1 states the reading explicitly); the interpreter's agreement on pure entry returns (the 120 function cases) is proven only indirectly via program outputs. Extending function mode to the interpreter needs an entry-invocation protocol (JSON in/out like `harness.rs`) — flagged as a Phase-5 follow-up or Phase-9 item, decision for the orchestrator; the PHASES.md acceptance wording is part of that decision.
11. **String escapes** — no corpus fixture contains an escape; the `escapes` probe (I2) pins all six (`\" \\ \n \t \r \0`) with hand-written expectations, so the defect cannot ship one escape at a time.
12. **Grammar nodes the interpreter could skip** — `field_opt` `:json`, `type_app` in type position, `constructor_call` heads used where `call` would also parse: dispatch is exhaustive with a named-error default (§2.3); a skipped branch is the `c-2d38` failure shape.
13. **Exit-code collisions** — program failure (1) vs trap/internal error (2) vs usage: pinned distinct in I1/I2/I7, because `differential.py` compares exit status byte-for-byte and a trap that exits 1 would masquerade as an `IoError` failure. Traps are exit 2 with a diagnostic; no differential case traps (a Rust trap is not a value, ROADMAP `l-4d92` — recorded scope decision).
14. **User-type sort order** — the interpreter implements declaration order (§2.5), which the compiled arms do not agree on today; until §3.2 is written and the arms converge, `user-sort` is probe-pinned only, and any differential case sorting a user type would fail on the arms, not on the interpreter. Sorting a record or a `Map` is unpinned this phase — the same `l-5c47` gap the backends carry.

## Invariants (each tied to an item)

| Invariant | Citation | Item |
|---|---|---|
| Agreement compares stdout+stderr+exit across ALL arms (`agree`), AND the declared value is checked separately by python arm (`declared_ok = seen["python"] == want`) | `backend/differential.py:361-363` | I8 |
| Declared case values (`"stdout"/"stderr"/"exit"`) and existing `build_*` arms unchanged; additions to `program_cases()` would be a recorded decision, never a quiet edit | `differential.py:336-348,373` | I8 |
| Every non-`main` fixture is observed through a checked-in driver, never run bare | §3 fixture map; `oracle.py --emit` | I0–I6 |
| Behaviour where the Python lowering is blind (`l-4d92`, `l-5c47`, escapes, EOF, two-NaN stability, parse guards, `map-pairs`) is pinned by hand-written probes, not by the derived oracle | `.plans/phase-5/probes/` | I2/I5/I7 |
| Resolution = dependencies first, root last, cycle broken not diagnosed | `grammar/modules.py:44-71` | I6 |
| Top-level identity keyed by defining module path, never alias | `backend/to_python.py` `module_prefix` + `to_rust.py` `rust_mod` docstrings | I6 |
| Enum/runtime tags are bare case names across boundaries | `backend/to_python.py` `pattern` comment | I4/I6 |
| Exit glue: ok→0; err→case name on stderr, exit 1; traps→diagnostic on stderr, exit 2; other shapes rejected | `backend/rust/rt.rs` `main_exit`, `backend/runtime.py` `main_exit` | I7 |
| IoError mapping from `ErrorKind`, `NotADirectory\|IsADirectory`→invalid-path | `backend/rust/rt.rs` `io_err` | I7 |
| NaN-last total order, stable (two-NaN tie = input order); selection follows sort | `backend/runtime.py` `order_key`, `backend/rust/rt.rs` `nan_last` | I5 |
| Map iteration sorted by key — `map-keys`, `map-values` and `map-pairs` alike | `backend/runtime.py` `m_pairs`, `rt.rs` BTreeMap note | I5 |
| `fmt_f64` == Python `repr`, exponent ≥2 digits pinned by cargo test | `backend/rust/rt.rs` `fmt_f64` | I5 |
| User enum/union sort order = declaration order (ROADMAP-presumptive §3.2 rule); spec change flagged to orchestrator | ROADMAP `l-5c47`, `d-6c04` | I5 |
| Int32 arithmetic traps at the 32-bit boundary (the Python arm's known defect, not the interpreter's) | `AGENT_SPEC_CORE.md` §3.1; ROADMAP `l-4d92` | I2 |
| Host entry only when the root module declares `main` | `backend/to_python.py` `host_entry` | I7 |
| `exec_coverage.py` consumes `differential.program_cases()` and must stay green untouched | `backend/exec_coverage.py:48,219` | I8 |
| `target/` ignored; `grammar/tree-sitter-agentscript/src/` generated | `.gitignore:4,5` | I1 |
