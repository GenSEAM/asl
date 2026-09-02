# Phase 9 — Harness whole-program mode

## §1 Scope and acceptance

Upgrade the benchmark measurement harness `bench/harness/run.py` from driving pure entry functions with in-memory JSON cases (`evaluate()` in `bench/harness/run.py:110-164` imports `to_python` and executes in-process) to supporting whole-program execution mode (`ROADMAP.md:138-141`, `ROADMAP.md:181-182`, `EXPERIMENT.md:140-173` amendment 2026-08-20-b).

In whole-program mode, benchmark tasks define CLI inputs (`argv`, `stdin`, input `files` with string content or integer permission modes) and expected outputs (`stdout`, `stderr`, `exit` code). The harness transpiles and executes generated AgentScript programs across all five execution targets:
1. **Python** (`backend/to_python.py` + `backend/runtime.py`)
2. **TypeScript** (`backend/to_typescript.py` + `backend/ts/rt.ts`, compiled via `_ts.compile_ts` and executed via `node`)
3. **Rust** (`backend/to_rust.py` + `backend/rust/rt.rs`, compiled via `rustc --edition 2021`)
4. **Go** (`backend/to_go.py` + `backend/golang/rt/rt.go`, compiled via `go build`)
5. **Interpreter** (`target/debug/agentscript-interp`, direct tree-sitter AST execution)

Evaluation follows a strict 6-stage pipeline (`STAGES` in `bench/harness/run.py:36`):
`extract` -> `parse` -> `check` -> `transpile` -> `execute` -> `correct`.
For direct AST interpretation on `interp`, the pipeline traverses `extract` -> `parse` -> `check` -> `execute` -> `correct` (`transpile` is omitted).

Dry-run mode (`--dry-run`) provides canned samples exercising each stage and failure mode deterministically using a dedicated synthetic whole-program task without external network or API keys. Automated test coverage in `bench/harness/test_run.py` verifies budget accounting, extraction, multi-target execution, stage progression, and timeout handling under `pytest`.

### Acceptance Criteria

1. **Whole-program task specification in `bench/tasks/`**: Tasks declare CLI test cases (`argv`, `stdin`, `files`, `stdout`, `stderr`, `exit`). Dual-mode task execution preserves backward compatibility for existing function-mode tasks (`histogram.json`) on the Python target.
2. **Multi-target execution engine**: `bench/harness/run.py` executes candidates across all five targets (`python`, `typescript`, `rust`, `go`, `interp`) via a selectable `--target` CLI option, isolating case executions in per-case temporary directories with file creation, permission management, and robust cleanup.
3. **Strict 6-stage lifecycle**: `extract` -> `parse` -> `check` -> `transpile` -> `execute` -> `correct`, recording precise stage attribution and diagnostics on failure (`Sample.stage_reached`, `Sample.detail`, `Sample.passed`).
4. **Comprehensive dry-run mode (`--dry-run`)**: `python bench/harness/run.py --dry-run` exercises all evaluation stages deterministically without network or API keys, producing `results/dry-run.json` with positive counts for each target-applicable stage in the stage distribution summary.
5. **Automated test suite**: `pytest bench/harness/test_run.py` passes all tests covering `Budget`, `extract`, target builders, dual-mode execution, stage transitions, subprocess timeouts, and CLI invocations.
6. **Budget and spend cap enforcement**: `Budget` tracking (`bench/harness/run.py:52-64`) calculates token spend accurately and aborts mid-run when the spend cap is reached (`EXPERIMENT.md:173-196` amendment 2026-08-20-c).

---

### Decisions (recorded, each the laziest correct option)

**D1 — Dual-mode task format & case normalization:**
A task can define whole-program execution cases or pure function cases.
Whole-program case schema:
```json
{
  "argv": ["sample.txt"],
  "stdin": "",
  "files": {
    "sample.txt": "hello from a file\n",
    "noperm.txt": ["", 0]
  },
  "stdout": "hello from a file\n\n",
  "stderr": "",
  "exit": 0
}
```
- If a case is a dictionary containing `"stdout"` and `"exit"`, it is treated as a whole-program case.
- If a case is a list `[inputs, want]`, it is treated as a function-mode case (backward compatibility for `bench/tasks/histogram.json` on the `python` target).
- `files` dictionary values can be specified as a string (file content, default mode `0o644`) or a two-element list `[content, mode]` where `mode` is an integer permission mode (e.g. `[content, 0o644]` or `["", 0o000]`).
- File permissions are restored prior to temporary directory teardown to prevent deletion/cleanup errors across environments.

**D2 — Multi-target runner architecture:**
The harness supports five execution targets selectable via `--target` (`python`, `ts`/`typescript`, `rust`, `go`, `interp`/`interpreter`), defaulting to `python`.
Target dispatch follows `backend/differential.py:370-458`:
- `python`: `to_python.py` (`Transpiler`) -> writes candidate to temp dir with `backend/runtime.py` -> runs via `sys.executable`.
- `typescript` / `ts`: `to_typescript.py` (`ToTypeScript`) -> writes candidate to temp dir with `backend/ts/rt.ts` -> compiles via `_ts.compile_ts()` -> runs via `node`.
- `rust`: `to_rust.py` (`ToRust`) -> writes candidate to temp dir with `backend/rust/rt.rs` -> compiles via `rustc --edition 2021` -> runs compiled binary.
- `go`: `to_go.py` (`ToGo`) -> writes candidate to temp dir with `backend/golang/rt/rt.go` (rewriting `package rt\n` to `package main\n`) -> compiles via `go build` -> runs compiled binary.
- `interp` / `interpreter`: locates or builds `target/debug/agentscript-interp` -> runs interpreter directly with candidate file and roots.
Each target execution runs inside an isolated per-case temporary working directory, preventing cross-case file contamination.

**D3 — Six-stage classification with explicit stage barriers:**
The evaluation sequence strictly traverses:
1. `extract`: extracts code block from LLM response (or reply text). Failure if no code block or empty code.
2. `parse`: parses AgentScript syntax via `parse_text()`. Failure if parser rejects syntax.
3. `check`: type-checks and validates semantic rules via `check_file()`. Failure if semantic diagnostics exist.
4. `transpile`: lowers AST to target code (and compiles native/tsc artifacts if target is compiled). Direct interpreter execution skips this stage. Failure if lowering raises or compiler rejects output.
5. `execute`: executes whole program (or function) in isolated workspace with `argv`, `stdin`, `files`. Process launch transitions `stage_reached = "execute"`. Failure if subprocess times out (30s limit), crashes with unexpected exit code, or outputs disagree with expected `stdout`/`stderr`/`exit`.
6. `correct`: passed all cases without discrepancy (`passed = True`).

**D4 — Comprehensive dry-run mode (`--dry-run`) with target-aware coverage:**
`--dry-run` executes against a dedicated synthetic whole-program task fixture with canned whole-program samples (with `main`), decoupled from the variable contents of `bench/tasks/`:
- Sample 0: `correct` — valid program passing all test cases.
- Sample 1: `extract` — prose reply without markdown code fence.
- Sample 2: `parse` — invalid syntax `(defun broken [ -> Int64 1)`.
- Sample 3: `check` — semantic type mismatch `(defun ! main [(args (List String))] -> (Result Unit IoError) "not-a-result")`.
- Sample 4: `transpile` — program triggering a target transpiler/compiler error (for `interp`, this sample triggers an execution failure since `interp` does not transpile).
- Sample 5: `execute` — valid program that compiles and runs, but produces wrong output (e.g. unexpected stdout or exit code).
Dry-run mode defaults to `samples_per_task: 6` so that every target-applicable stage in `STAGES` is exercised and recorded in the dry-run summary.

**D5 — Spend cap and budget tracking guarantees:**
`Budget` tracks exact input and output token consumption based on pricing per 1M tokens (`bench/harness/run.py:52-64`).
Before launching each sample, `budget.exhausted` is evaluated against `spend_cap_usd`.
If `budget.spent >= budget.cap`, execution terminates immediately (`aborted = True`), outputting the partial results JSON and tagging `[ABORTED ON CAP]`.
Dry-run synthetic token charges are calibrated to remain well below the default $0.20 cap during standard runs, leaving cap tripwire and abortion behavior to dedicated unit tests in `bench/harness/test_run.py`.

**D6 — Automated test harness in `bench/harness/test_run.py`:**
Pytest-compatible test suite covering:
- `Budget` accounting, spend calculation, and cap enforcement.
- `extract()` with various markdown fence variations, bare expressions, and prose rejection.
- Whole-program task execution across targets (`python`, `interp`, `rust`, `go`, `ts`) with string content and `[content, mode]` permission tuples.
- Function-mode backward compatibility on `python`.
- Stage progression & failure classification at every stage (`extract`, `parse`, `check`, `transpile`, `execute`, `correct`).
- Subprocess timeout handling (`subprocess.TimeoutExpired`).
- CLI flags: `--dry-run`, `--target`, `--roots`, `--config`, `--tasks`.

---

### Anti-stub measures (what stops a wired-but-fake harness)

1. **Per-case isolated execution**: Each case runs in a fresh temporary directory where declared input files are created and permissions set. A stub cannot reuse outputs across test cases.
2. **Byte-level stdout/stderr and exit code verification**: Whole-program cases verify `stdout`, `stderr`, and `returncode` against declared values. An arm that fails to capture stderr or returns wrong exit codes is flagged as a failure.
3. **Stage barrier enforcement**: Each stage must succeed before the next stage executes. A failure at `check` never enters `transpile`; a failure at `transpile` never enters `execute`.
4. **Target-aware dry-run verification**: The dry-run gate requires all target-applicable stages to have non-zero counts in `results/dry-run.json`.

---

## §2 Inventory

**Modified:**
- `bench/harness/run.py`: Upgraded to support whole-program execution, multi-target dispatch (`python`, `ts`, `rust`, `go`, `interp`), 6-stage error handling, `--target` and `--roots` CLI options, timeout handling, and target-aware canned dry-run responses.

**New:**
- `bench/tasks/io_demo.json`: Whole-program benchmark task fixture defining CLI inputs (`argv`, `stdin`, `files`) and outputs (`stdout`, `stderr`, `exit`).
- `bench/harness/test_run.py`: Automated pytest test suite for the harness covering budget, extract, evaluation, multi-target runners, timeout classification, and dry-run CLI.

**Unchanged, verified:**
- `backend/to_python.py`, `backend/to_typescript.py`, `backend/to_rust.py`, `backend/to_go.py`: Existing transpilers used for target code generation.
- `crates/agentscript-interp/`: Reference interpreter used for direct AST execution.
- `backend/differential.py`: Existing differential gate with 120 function cases and 15 whole-program cases.
- `checker/resolve.py`, `grammar/parse.py`, `prelude/HANDBOOK.md`: Core language tools.

---

## §3 Work items

### W1 — Whole-program benchmark task definition (`bench/tasks/io_demo.json`)

**What changes:**
Create `bench/tasks/io_demo.json`, declaring a whole-program benchmark task with prompt, entry specification, and test cases with `argv`, `stdin`, `files` (including permission modes), `stdout`, `stderr`, and `exit` status based on `grammar/corpus/valid/08-io.agentscript`.

**Why:**
Acceptance criterion 1 (`EXPERIMENT.md:140-173` amendment 2026-08-20-b). The harness cannot evaluate whole-program mode without task fixtures that define CLI inputs and outputs.

**Gate (fails now):**
```bash
.venv/bin/python -c "
import json
from pathlib import Path
p = Path('bench/tasks/io_demo.json')
assert p.exists(), f'missing {p}'
task = json.loads(p.read_text())
assert 'cases' in task and len(task['cases']) > 0
c = task['cases'][0]
assert all(k in c for k in ('argv', 'stdin', 'files', 'stdout', 'stderr', 'exit')), f'invalid case keys: {list(c.keys())}'
"
```
Current verbatim output (measured this session):
```
Traceback (most recent call last):
  File "<string>", line 5, in <module>
    assert p.exists(), f'missing {p}'
           ~~~~~~~~^^
AssertionError: missing bench/tasks/io_demo.json
```

**Order justification:**
`run.py` multi-target execution and evaluation in W2–W4 cannot be gated on whole-program tasks if no whole-program task fixture exists in `bench/tasks/`.

---

### W2 — Multi-target execution runner engine in `bench/harness/run.py`

**What changes:**
In `bench/harness/run.py`:
- Add target builders (`build_python`, `build_typescript`, `build_rust`, `build_go`, `build_interpreter`), mirroring `backend/differential.py:370-458`.
- Implement isolated per-case temporary directory execution helper `run_target(cmd, cwd, stdin, files)` setting up input files with permissions (`chmod`), piping `stdin`, passing `argv`, executing with 30-second timeout, catching `subprocess.TimeoutExpired`, restoring permissions for safe cleanup, and capturing `(returncode, stdout, stderr)`.

**Why:**
Acceptance criterion 2. The harness must support building and executing whole programs across all five language targets.

**Gate (fails now):**
```bash
.venv/bin/python -c "
import sys; sys.path.insert(0, 'bench/harness')
import run
for name in ('build_python', 'build_typescript', 'build_rust', 'build_go', 'build_interpreter', 'run_target'):
    assert hasattr(run, name), f'missing runner/builder {name}'
"
```
Current verbatim output (measured this session):
```
Traceback (most recent call last):
  File "<string>", line 5, in <module>
    assert hasattr(run, name), f'missing runner/builder {name}'
           ~~~~~~~^^^^^^^^^^^
AssertionError: missing runner/builder build_python
```

**Order justification:**
W3 (stage pipeline refactoring) and W4 (CLI / dry-run) rely on the target runner engine to build and execute programs.

---

### W3 — Upgrade `evaluate()` stage pipeline and dual-mode execution

**What changes:**
In `bench/harness/run.py`:
- Refactor `evaluate(code, task, s, target="python", roots=None)` to enforce strict stage barriers:
  `parse` -> `check` -> `transpile` -> `execute` -> `correct`.
- For `target="interp"`, direct AST execution is evaluated without transpilation (`extract` -> `parse` -> `check` -> `execute` -> `correct`).
- Support both whole-program tasks (`argv`/`stdin`/`files`/`stdout`/`stderr`/`exit` across all five targets) and function-mode tasks (`cases: [[inputs, want]]` on `python`).
- For compiled targets, capture compilation errors at the `transpile` stage.
- For execution failures (process timeout, non-zero return code mismatch, or stdout/stderr discrepancies), record diagnostics under the `execute` stage and set `s.passed = False`.
- When all cases match, set `s.stage_reached = "correct"` and `s.passed = True`.

**Why:**
Acceptance criterion 3. Prevents stage collapse and ensures failure modes are accurately attributed to the stage at which they occurred.

**Gate (fails now):**
```bash
.venv/bin/python -c "
import sys; sys.path.insert(0, 'bench/harness')
from run import evaluate, Sample
wp_task = {'id': 'io_demo', 'cases': [{'argv': ['sample.txt'], 'stdin': '', 'files': {'sample.txt': 'hello\n'}, 'stdout': 'hello\n\n', 'stderr': '', 'exit': 0}]}
wp_wrong = '''(module io-demo :doc \"test\" :export [main])
(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc \"Entry point.\"
  (println \"wrong\"))'''
s1 = Sample(task='io_demo', index=0)
evaluate(wp_wrong, wp_task, s1, target='python')
assert s1.stage_reached == 'execute' and not s1.passed, f'expected execute failure: {s1.stage_reached}'
fn_task = {'id': 'fn_test', 'entry': 'add', 'cases': [[[1, 2], 3]]}
fn_code = '''(module fn-test :doc \"test\" :export [add])
(defun add [(a Int64) (b Int64)] -> Int64
  :doc \"Add.\"
  (+ a b))'''
s2 = Sample(task='fn_test', index=0)
evaluate(fn_code, fn_task, s2, target='python')
assert s2.stage_reached == 'correct' and s2.passed, f'expected function mode pass: {s2.stage_reached}'
"
```
Current verbatim output (measured this session):
```
Traceback (most recent call last):
  File "<string>", line 10, in <module>
    evaluate(wp_wrong, wp_task, s1, target='python')
    ~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: evaluate() got an unexpected keyword argument 'target'
```

**Order justification:**
Dry-run mode (W4) and test suite (W5) depend on `evaluate()` producing accurate stage classifications and detail messages.

---

### W4 — Multi-stage canned dry-run suite and CLI options in `bench/harness/run.py`

**What changes:**
In `bench/harness/run.py`:
- Add CLI arguments:
  - `--target`: choices `["python", "ts", "typescript", "rust", "go", "interp", "interpreter"]`, default `"python"`.
  - `--roots`: search paths for module resolution (default `[ROOT / "grammar" / "corpus" / "modules"]`).
- Decouple `--dry-run` from `bench/tasks/` by using a dedicated synthetic whole-program task fixture and canned whole-program S-expressions (with `main`):
  - Sample 0: `correct` (valid whole-program passing test cases)
  - Sample 1: `extract` (prose response without markdown code block)
  - Sample 2: `parse` (syntax error)
  - Sample 3: `check` (type/semantic checker diagnostic)
  - Sample 4: `transpile` (untranspilable or build-failing code; executes and fails under `interp`)
  - Sample 5: `execute` (wrong stdout/exit code)
- Set default `samples_per_task: 6` in dry-run mode so all applicable stages are evaluated.
- Ensure summary output and `results/dry-run.json` record the full stage distribution.

**Why:**
Acceptance criterion 4. `--dry-run` verifies the complete harness pipeline offline without API keys or spend.

**Gate (fails now):**
```bash
.venv/bin/python bench/harness/run.py --dry-run --target python
```
Current verbatim output (measured this session):
```
usage: run.py [-h] [--config CONFIG] [--dry-run] [--tasks TASKS]
run.py: error: unrecognized arguments: --target python
```

**Order justification:**
W5 tests the complete dry-run CLI behaviour, which requires W4's CLI flags and canned responses to be in place.

---

### W5 — Harness unit and integration test suite (`bench/harness/test_run.py`)

**What changes:**
Create `bench/harness/test_run.py` tested via `pytest`:
- `test_budget_accounting()` & `test_spend_cap_abort()`: Verifies token calculation and `budget.exhausted` mid-run abortion.
- `test_extract_fenced_and_bare()`: Tests markdown code block extraction, bare expressions, and prose rejection.
- `test_evaluate_whole_program_python()`: Tests whole-program execution on Python target with string content and `[content, mode]` permission tuples.
- `test_evaluate_whole_program_interp()`: Tests whole-program execution on Interpreter target.
- `test_evaluate_whole_program_compiled_targets()`: Tests Rust, Go, TypeScript targets with `pytest.mark.skipif` toolchain guards.
- `test_function_mode_backward_compatibility()`: Tests function tasks on `python` target (`histogram.json`).
- `test_stage_failure_classification()`: Verifies explicit failure classification at each stage (`extract`, `parse`, `check`, `transpile`, `execute`).
- `test_subprocess_timeout_classification()`: Verifies infinite loop / timeout handling classifies as `execute` failure.
- `test_dry_run_cli_all_stages()`: Tests CLI execution of `run.py --dry-run` and verifies target-aware stage distribution in output.

**Why:**
Acceptance criterion 5. Automated regression testing for the harness under pytest.

**Gate (fails now):**
```bash
.venv/bin/pytest bench/harness/test_run.py
```
Current verbatim output (measured this session):
```
ERROR: file or directory not found: bench/harness/test_run.py

============================= test session starts ==============================
platform darwin -- Python 3.13.0, pytest-9.1.1, pluggy-1.6.0
rootdir: /Users/purplelephant/projects/asex
collected 0 items

============================ no tests ran in 0.00s =============================
```

**Order justification:**
W5 verifies all components implemented in W1–W4.

---

### W6 — End-to-end multi-target verification and project gate clean check

**What changes:**
Verify dry-run execution across supported targets (`python`, `interp`) and verify that all repository project gates remain clean:
`grammar/validate.py`, `grammar/closure_audit.py`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py`, and `backend/differential.py`.

**Why:**
Acceptance criterion 6. Proves that the upgraded harness works across targets without regressing any existing project gates.

**Gate (fails now):**
```bash
.venv/bin/pytest bench/harness/test_run.py && .venv/bin/python bench/harness/run.py --dry-run --target python && .venv/bin/python bench/harness/run.py --dry-run --target interp && .venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/python backend/differential.py
```
Current verbatim output (measured this session):
```
ERROR: file or directory not found: bench/harness/test_run.py

============================= test session starts ==============================
platform darwin -- Python 3.13.0, pytest-9.1.1, pluggy-1.6.0
rootdir: /Users/purplelephant/projects/asex
collected 0 items

============================ no tests ran in 0.00s =============================
```

**Order justification:**
Final integration check verifying the complete phase deliverables.

---

## §4 Execution Targets & Differential Verification

The table below summarizes the target runner configuration implemented in `bench/harness/run.py`:

| Target | Transpiler / Runner | Runtime File | Build / Invocation Command |
|---|---|---|---|
| `python` | `backend/to_python.py` (`Transpiler`) | `backend/runtime.py` | `python cand.py [argv...]` |
| `interp` | `target/debug/agentscript-interp` | AST tree-sitter | `agentscript-interp [--root DIR]... cand.agentscript [argv...]` |
| `rust` | `backend/to_rust.py` (`ToRust`) | `backend/rust/rt.rs` | `rustc --edition 2021 main.rs -o rust_prog` -> `./rust_prog [argv...]` |
| `go` | `backend/to_go.py` (`ToGo`) | `backend/golang/rt/rt.go` (package main) | `go build -o go_prog main.go rt.go` -> `./go_prog [argv...]` |
| `ts` / `typescript` | `backend/to_typescript.py` (`ToTypeScript`) | `backend/ts/rt.ts` | `compile_ts([main.ts, rt.ts])` -> `node dist/main.js [argv...]` |

---

## §5 Risks

1. **Host Toolchain Dependencies**: Rust (`rustc`), Go (`go`), and TypeScript (`tsc`/`node`) depend on local toolchains. If a toolchain is absent in an environment, `test_run.py` uses pytest `skipif` guards for those target-specific integration tests while testing `python` and `interp` unconditionally.
2. **Interpreter Binary Availability**: Direct AST interpretation requires `target/debug/agentscript-interp`. If not pre-built, the runner triggers `cargo build` automatically (matching `backend/differential.py:418-420`).
3. **Subprocess Timeout and Concurrency**: Long-running or infinite-loop candidates are bounded by a 30-second subprocess timeout per case, catching `subprocess.TimeoutExpired` and classifying it as an `execute` stage failure.

---

## §6 Out of scope

1. **Live LLM measurement execution**: Running live API benchmarks against frontier models requires external gateway endpoints and credentials (`PHASES.md:85`, `ROADMAP.md:183`), which are separate from harness implementation.
2. **SWE-bench / FFI Interoperability**: SWE-bench repo editing requiring external Python library subclassing is out of scope per `EXPERIMENT.md:151-155`.
3. **Multi-file candidate generation**: The model generation contract (`bench/harness/run.py:71-72`) emits a single complete module per response; multi-file candidate generation is not evaluated.
4. **Function-mode execution across non-Python targets**: Executing pure function-mode tasks across compiled targets (Rust/Go/TypeScript) requires complex type serialization drivers and is reserved for `backend/differential.py`; benchmark tasks in Phase 9 use whole-program mode.
