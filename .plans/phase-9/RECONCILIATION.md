# Phase 9 Reconciliation

## Review Findings & Dispositions

| # | Review Lens | Finding ID | Finding Description | Disposition | Where / How Addressed & Justification |
|---|---|---|---|---|---|
| 1 | Design | D-B1 | Dry-run Sample 0 (`correct`) will fail on `io_demo.json` and compiled targets because `run.py` iterates `bench/tasks/` using function-mode sample. | `accept-modified` | Folded into §1 (D4), §3 (W4), and §3 (W5). Rather than coupling `--dry-run` to the runtime contents of `bench/tasks/`, `--dry-run` uses a fixed synthetic whole-program task fixture and whole-program canned AgentScript samples (with `main`) tailored to that task. This guarantees deterministic dry-run execution across all targets. |
| 2 | Design | D-B2 | The `interp` target lacks a `transpile` stage, which would cause Sample 4 in dry-run to succeed transpilation and break the dry-run 6-stage gate. | `accept` | Folded into §1 (D3, D4), §3 (W4), and W4 gate. Interpreter directly executes AST and skips `transpile`. Stage reporting and dry-run gate assertions are made target-aware (5 stages for `interp`: `extract`, `parse`, `check`, `execute`, `correct`; 6 stages for transpiled/compiled targets). |
| 3 | Design | D-B3 | Function-mode multi-target execution requires massive test-driver duplication across Rust/Go/TS. | `accept` | Folded into §1 (D1, D2) and §3 (W3). Function-mode execution backward compatibility is scoped strictly to the `python` target (for existing tasks like `histogram.json`). All five targets (`python`, `ts`, `rust`, `go`, `interp`) support whole-program execution mode (`main` entry point with CLI inputs/outputs). |
| 4 | Design | D-NB1 | `0o000` permission files in temporary directories may cause sandbox cleanup errors on some platforms. | `accept` | Folded into §1 (D1) and §3 (W2). In the isolated runner execution helper, file permissions are safely restored (e.g. `chmod 0o700`) before temporary directory exit/cleanup. |
| 5 | Executability | E-B1 | W1 gate checks `argv`, `stdout`, `stderr`, `exit` but omits checking `stdin` and `files`. | `accept` | Folded into §3 (W1 gate). Updated W1 gate assertion to verify all 6 required keys: `('argv', 'stdin', 'files', 'stdout', 'stderr', 'exit')`. |
| 6 | Executability | E-B2 | W2 gate calls `evaluate(...)` with a whole-program task fixture before W3 upgrades `evaluate()` to support whole-program mode. | `accept-modified` | Folded into §3 (W2) and §3 (W3). Separated boundaries cleanly: W2 implements and gates the target builders (`build_python`, `build_typescript`, `build_rust`, `build_go`, `build_interpreter`) and the isolated runner helper directly; W3 integrates them into `evaluate()` and gates end-to-end stage evaluation. |
| 7 | Executability | E-B3 | W3 gate only tests whole-program execution failure and omits function-mode backward compatibility. | `accept` | Folded into §3 (W3 gate). Added evaluation of a function-mode task on `python` target to W3's gate assertion alongside whole-program execution failure. |
| 8 | Executability | E-B4 | W4 gate only tests `--dry-run` without exercising the new `--target` and `--roots` CLI options. | `accept` | Folded into §3 (W4 gate). Updated W4 gate command to invoke `run.py` with `--target interp --roots grammar/corpus/modules` and `--target python`. |
| 9 | Executability | E-B5 | W6 gate command omitted repository project validation check scripts mentioned in its description. | `accept` | Folded into §3 (W6 gate). Added `grammar/validate.py`, `grammar/closure_audit.py`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py`, and `backend/differential.py` directly to the W6 gate. |
| 10 | Executability | E-NB1 | Gate tests use string format for `files`; test suite must cover both string content and `[content, mode]` tuple format. | `accept` | Folded into §3 (W5). Explicitly included tests for both raw string content and `[content, mode]` permission tuples in `bench/harness/test_run.py`. |
| 11 | Coverage | C-B1 | W2 gate only tests `python` and `interp`, missing gate coverage for compiled targets (`rust`, `go`, `ts`). | `accept` | Folded into §3 (W2 gate). Updated W2 gate to verify builder registration and command emission for all 5 targets (`build_python`, `build_typescript`, `build_rust`, `build_go`, `build_interpreter`). |
| 12 | Coverage | C-B2 | `subprocess.TimeoutExpired` unhandled in execution pipeline; missing timeout failure classification. | `accept` | Folded into §3 (W2, W3) and §3 (W5). Specified that `subprocess.TimeoutExpired` must be caught and recorded as an `execute` stage failure (`s.stage_reached = "execute"`, `s.passed = False`, `s.detail = "timeout after 30s"`), and added unit test in W5. |
| 13 | Coverage | C-B3 | W3 missing backward compatibility gate (duplicate of E-B3). | `accept` | Folded into §3 (W3 gate). Verified function-mode evaluation alongside whole-program mode in W3 gate. |
| 14 | Coverage | C-B4 | W1 missing `stdin` and `files` in task fixture gate (duplicate of E-B1). | `accept` | Folded into §3 (W1 gate). Added `'stdin'` and `'files'` to required keys assertion. |
| 15 | Coverage | C-B5 | Dry-run synthetic charges could conflict with spend cap if set too high. | `accept` | Folded into §1 (D5) and §3 (W4). Clarified that dry-run synthetic charges are calibrated to stay well below the cap ($0.20) during standard dry runs, while spend cap abortion is tested in W5 unit tests (`test_spend_cap_abort`). |
| 16 | Coverage | C-NB1 | Non-zero returncode on candidate crash should be attributed to `execute` stage, not left as `transpile`. | `accept` | Folded into §1 (D3) and §3 (W3). Refactored `evaluate()` so that process launch sets `stage_reached = "execute"` before inspecting returncode or outputs. |

## Reconciliation Summary

- **Total Findings in Reviews:** 16 (Design: 4, Executability: 6, Coverage: 6)
- **Dispositions:**
  - `accept`: 14
  - `accept-modified`: 2 (D-B1, E-B2)
  - `reject`: 0
- **Total Rows Reconciled:** 16
- **Item Ordering:** Unchanged (W1 through W6 remain strictly sequentially ordered, with tightened gate boundaries).
