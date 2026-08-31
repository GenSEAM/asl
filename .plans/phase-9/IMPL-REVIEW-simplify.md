# Lens: SIMPLIFY / OVER-ENGINEERING
Verdict: reject

## Blockers

1. **Massive Code Duplication (`build_*` functions)**
   - **Evidence:** `bench/harness/run.py` re-implements `build_python`, `build_rust`, `build_interpreter`, `build_typescript`, and `build_go` identically (over 60 lines), perfectly mirroring `backend/differential.py:372-458`. The only functional difference is the passing of a `roots` argument and a `shutil.which` check for Rust.
   - **Correction:** Delete the duplicate builders from `bench/harness/run.py`. Update `backend/differential.py`'s builders to accept a `roots` argument (e.g., `roots: list[Path] = ROOTS`), and import them in `run.py`.

2. **Convoluted JSON serialization in function-mode runner**
   - **Evidence:** In `run.py:315`, the function-mode backward compatibility path writes a test driver (`check.py`) using `f"cases = json.loads({json.dumps(json.dumps(cases))})\n"`. Double JSON dumping to inject a string literal that gets `json.loads`'d at runtime is absurdly convoluted.
   - **Correction:** Simplify the injected string to `f"cases = {json.dumps(cases)}\n"` and eliminate the unnecessary `json.loads` call at runtime.

3. **Bloated `is_whole_program_task` abstraction**
   - **Evidence:** `run.py:247` defines an `is_whole_program_task(task)` helper that reaches into the `cases` list and checks if `stdout` and `exit` are keys on the first dictionary.
   - **Correction:** Task definitions perfectly demarcate whole-program versus function mode based on the presence of the `entry` key. Delete the helper or simplify it to exactly one line: `return "entry" not in task`.

## Non-blocking

- **Dead Imports:** `field` is imported from `dataclasses` at `run.py:16` but is never used.
- **`shutil` Dependency:** Once `build_rust` is deduped to use `differential.py`'s version, the `import shutil` in `run.py` will also become a dead import and should be removed.

## Verified

- The execution driver uses standard library constructs adequately beyond the noted bloat.
