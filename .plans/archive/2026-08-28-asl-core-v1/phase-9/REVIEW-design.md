# Lens: DESIGN / ARCHITECTURAL
Verdict: reject

## Blockers

1. **Dry-run Sample 0 (`correct`) will fail on `io_demo.json` and compiled targets**
   - **Evidence:** `run.py:204` hardcodes `tight.agentscript` as the `correct` sample, but `run.py:193` iterates over all real tasks in `bench/tasks/`. When W1 introduces `io_demo.json` (a whole-program task expecting specific `stdout`), feeding it `tight.agentscript` (a pure function with no output) will fail the `execute` stage instead of registering as `correct`. Furthermore, on compiled targets (`rust`, `go`), `tight.agentscript` will fail `transpile` because it lacks a `main` function.
   - **Correction:** Decouple `dry-run` from the real `bench/tasks/` folder. Use a synthetic, hardcoded whole-program task and a matching canned whole-program S-expression that contains a valid `main`, ensuring it compiles and executes correctly across all targets.

2. **The `interp` target lacks a `transpile` stage, breaking the dry-run gate**
   - **Evidence:** W4 and its gate require all 6 stages (`extract`, `parse`, `check`, `transpile`, `execute`, `correct`) to have non-zero counts in dry-run. However, D2 mirrors `differential.py:417` (`build_interpreter`), which simply returns a command string `['agentscript-interp', ...]`. The interpreter target does not transpile. Therefore, Sample 4 (the mock transpile failure) will silently succeed at `transpile` and fail at `execute`. The gate will crash on `--target interp` because `transpile` will have a count of 0.
   - **Correction:** Make the dry-run assertions and summary target-aware. If the target is `interp`, expect 0 `transpile` failures, or map the mock failure to something that structurally aborts before execution.

3. **Function-mode multi-target execution requires massive test-driver duplication**
   - **Evidence:** W3 mandates supporting function-mode tasks, and W2 specifies mirroring the target builders from `differential.py:370-458`. However, those builders only compile whole programs (they assume a `main` function). Executing function-mode tasks on Rust/Go/TS requires generating target-specific test drivers with complex AST-to-literal serialization (as seen in `differential.py:run_rust`, etc.). Re-implementing this in `run.py` violates the architectural requirement to be minimal and free of unnecessary abstractions.
   - **Correction:** Explicitly restrict function-mode execution in `run.py` to the `python` target (for backward compatibility), and require that all other targets (`rust`, `go`, `ts`, `interp`) only execute whole-program tasks.

## Non-blocking

- **Temporary Directory Cleanup:** D1 specifies setting permissions to `0o000`. Python 3.13 handles this cleanly in `tempfile.TemporaryDirectory()`, but ensure any `chmod` modifications do not inadvertently break sandbox cleanup on other platforms if `run.py` is executed elsewhere.

## Verified

- `backend/differential.py:370-458` accurately maps to the whole-program `build_*` functions.
- The 6-stage pipeline correctly aligns with `EXPERIMENT.md` amendment `2026-08-29-a`.
- The current implementation of `evaluate` in `run.py` correctly establishes the baseline behaviors described in D3.

## Unverified

- The runtime behavior of `io_demo.json` whole-program execution (since it is created in W1 and cannot be tested yet).
