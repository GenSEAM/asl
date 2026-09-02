# Lens
COVERAGE / GAP ANALYSIS

# Verdict
reject

# Blockers

1. **W2: Missing gate coverage for compiled execution targets.**
   - **What is wrong:** W2 requires multi-target execution across 5 targets (`python`, `typescript`, `rust`, `go`, `interp`). However, the W2 gate only tests `python` and `interp`. A conformant-but-wrong implementation could completely stub or break the `rust`, `go`, and `ts` runners and still pass the gate, violating Acceptance Criterion 2.
   - **Evidence:** `.plans/phase-9/PLAN.md:173-184` shows the W2 gate code only asserting `target='python'` and `target='interp'`.
   - **What would make it right:** Add `evaluate(..., target='rust')`, `go`, and `ts` to the W2 gate. If host toolchains are a concern, either rely on the fact that this is a development machine with the toolchains installed (which they are), or at least assert that the 5 target builder functions are present and dispatchable.

2. **W2/W3: Unhandled timeout in execution pipeline.**
   - **What is wrong:** Risk 3 mentions a 30-second subprocess timeout to prevent hangs. However, neither W2 nor W3's instructions require catching `subprocess.TimeoutExpired`, and neither gate tests a hanging program. An implementation could omit the timeout entirely or fail to catch the exception, crashing the harness rather than classifying the failure as an `execute` stage failure.
   - **Evidence:** W2 only lists capturing stdout/stderr/returncode, W3 only lists mismatch diagnostics, and neither gate includes a timeout test.
   - **What would make it right:** Specify that `subprocess.TimeoutExpired` must be caught and classified as an `execute` stage failure in W3, and add an explicit test for it in W5.

3. **W3: Missing backward compatibility gate.**
   - **What is wrong:** W3 requires dual-mode support for both whole-program and function-mode tasks. However, the W3 gate only tests a whole-program failure and completely omits function-mode execution. An implementation could break or remove function-mode compatibility and still pass the gate.
   - **Evidence:** `.plans/phase-9/PLAN.md:215-229` shows the W3 gate only executing against a whole-program fixture (`io_demo`).
   - **What would make it right:** Add an assertion in W3's gate using a synthetic function-mode case (e.g., `{'cases': [[['args'], 'want']]}`) to verify it evaluates successfully.

4. **W1: Missing `stdin` and `files` check in task fixture gate.**
   - **What is wrong:** W1 requires the `io_demo.json` task to define `argv`, `stdin`, and `files` (with permission modes) to exercise whole-program I/O. However, the W1 gate only asserts the presence of `'argv', 'stdout', 'stderr', 'exit'`. A conformant implementation could omit `stdin` and `files` completely, passing the gate but leaving the multi-target runner's file-handling untested.
   - **Evidence:** `.plans/phase-9/PLAN.md:135-146` shows the gate does not check for `stdin` or `files`.
   - **What would make it right:** Add `'stdin'` and `'files'` to the required keys check in W1's gate (`assert all(k in c for k in ('argv', 'stdin', 'files', 'stdout', 'stderr', 'exit'))`).

5. **W4: Dry-run cap exhaustion conflict.**
   - **What is wrong:** Decision D5 states that dry-run mode "charges synthetic token counts to verify the budget accounting and cap tripwire without actual spend." However, W4's gate requires `--dry-run` to output all 6 stages. If the synthetic charges trip the default $0.20 cap mid-run, execution will abort early and fail to produce all 6 stages, breaking the W4 gate.
   - **Evidence:** `.plans/phase-9/PLAN.md:267-275` (W4 gate expects 6 stages) and `.plans/phase-9/PLAN.md:85` (D5 states dry-run verifies cap tripwire).
   - **What would make it right:** Clarify that dry-run's synthetic charges must be tuned to *not* exhaust the default cap so all 6 samples complete successfully, and rely solely on W5 (`test_budget_accounting`) to verify the tripwire, OR provide a specific CLI flag in dry-run to test the tripwire separately.

# Non-blocking

- **W3 stage check logic:** The current codebase in `run.py` only changes `s.stage_reached` to `"execute"` if the subprocess exits with `returncode == 0`. The plan states "For execution failures (mismatch in stdout, stderr, or exit code), record mismatch diagnostics under execute stage". It should be explicitly noted that this requires refactoring the current `returncode != 0` early return to ensure crashes are properly attributed to the `execute` stage instead of remaining as `transpile`.

# Verified

- `ROADMAP.md §4 item 4` requirement is met by the plan's shift to whole-program tasks and multi-target CLI options.
- The 5 target backend builders (`backend/to_python.py`, `backend/to_typescript.py`, `backend/to_rust.py`, `backend/to_go.py`) and their compilation functions (e.g. `compile_ts`) exist and are available in the repository.
- The 6-stage lifecycle logic is fully described and assigned to appropriate samples in `--dry-run`.
- The current gate output in the plan matches actual verbatim execution on the machine.

# Unverified

- Toolchain functionality across all 5 targets for the specific multi-target benchmarks was not deeply run since `io_demo.json` does not exist yet.
