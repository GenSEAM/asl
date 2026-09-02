# Lens: EXECUTABILITY / GATE COVERAGE
# Verdict: reject

## Blockers

1. **W1 Gate Misses File Inputs:** W1 requires the task fixture to include `stdin` and `files` (with permission modes), but the gate only verifies `argv`, `stdout`, `stderr`, and `exit`. A conformant-but-wrong implementation could omit `stdin` and `files`, entirely missing the file I/O capabilities, and the gate would still pass.
   *Evidence:* W1 gate: `assert all(k in c for k in ('argv', 'stdout', 'stderr', 'exit'))`
   *Fix:* Add `'stdin'` and `'files'` to the tuple of required keys in the W1 gate assertion.

2. **W2 / W3 Boundary Violation:** W2's gate explicitly calls `evaluate(...)` with a whole-program task fixture (missing the `'entry'` key). However, updating `evaluate` to support whole-program tasks (rather than function-mode tasks) is explicitly assigned to W3. A conformant implementation of W2 will fail its own gate with a `KeyError: 'entry'` (or similar) because it hasn't upgraded `evaluate` yet.
   *Evidence:* W2 gate runs `evaluate(code, task, s, target='python')` on a task without `'entry'`. W3 instructions: "Support both whole-program tasks ... and function-mode tasks".
   *Fix:* Either merge W2 and W3 so `evaluate()` is fully upgraded before it is tested with whole-program cases, or have W2's gate test the new runner functions (e.g. `build_python`, `run_python`) directly instead of calling `evaluate()`.

3. **W3 Gate Ignores Function-Mode Backward Compatibility:** W3's instruction explicitly requires supporting "both whole-program tasks ... and function-mode tasks". The gate only tests a whole-program failure path. A conformant-but-wrong implementation could drop function-mode support (breaking existing tasks like `histogram.json`) and the gate would still pass.
   *Evidence:* W3 gate tests only `task='io_demo'` and asserts failure on `'execute'`. It does not evaluate a function-mode task.
   *Fix:* Add a quick evaluation of a function-mode task in W3's gate to prove backward compatibility is maintained.

4. **W4 Gate Missing CLI Flags:** W4 adds `--target` and `--roots` CLI arguments, but the gate only runs `bench/harness/run.py --dry-run`. A conformant-but-wrong implementation could fail to register the `--target` and `--roots` argparse options, and the gate would still pass.
   *Evidence:* W4 gate: `.venv/bin/python bench/harness/run.py --dry-run`
   *Fix:* Include an invocation with the new arguments in the gate, e.g., `bench/harness/run.py --dry-run --target interp --roots grammar/corpus/modules`.

5. **W6 Gate Fails to Run Project Gates:** W6's description states "verify that all 8 repository project gates remain clean: validate.py, closure_audit.py, generate.py --check, checker/gate.py, check_corpus.py, monomorphism.py, differential.py, and pytest." However, the gate command only runs the harness tests and two dry-runs. A conformant-but-wrong implementation could break other components (like `differential.py`) and the W6 gate would pass.
   *Evidence:* W6 gate: `.venv/bin/pytest bench/harness/test_run.py && .venv/bin/python bench/harness/run.py --dry-run --target python && .venv/bin/python bench/harness/run.py --dry-run --target interp`
   *Fix:* Add all the project check scripts (e.g. `backend/differential.py`, `validate.py`, etc.) to the W6 gate command.

## Non-blocking

- The dummy test case in the gates uses a `files` schema `{'sample.txt': 'hello\n'}` but the instructions mention that `files` can be a list with permission modes `['content', 0o644]`. It's fine for the basic gate check to just test the string shortcut, but ensuring test coverage handles both formats in W5 would be beneficial.

## Verified

- The Python gate script fragments correctly catch the intended failure conditions for the specific assertions they make.
- W1 gate fails correctly on current main (`AssertionError: missing bench/tasks/io_demo.json`).
- W2 gate fails correctly on current main (`TypeError: evaluate() got an unexpected keyword argument 'target'`).
- W3 gate fails correctly on current main (same `TypeError` due to missing `target`).
- W4 gate fails correctly on current main (missing stages in output).
- W5 and W6 gates fail correctly on current main (missing `test_run.py`).
- Evaluation on `08-io.agentscript` accurately produces `hello\n\n` because `println` appends a newline to the read file content.

## Unverified

- Toolchains (Rust, Go, Node) are assumed to be available or correctly skipped in the environment.
