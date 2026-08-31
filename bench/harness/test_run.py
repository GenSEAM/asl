import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "bench" / "harness"))
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from run import (
    Budget,
    Sample,
    extract,
    evaluate,
    run_target,
    STAGES,
    SYNTHETIC_DRY_RUN_TASK,
    DEFAULT_ROOTS,
)


def test_budget_accounting():
    budget = Budget(cap=1.0, per_in=0.15, per_out=0.60)
    assert budget.spent == 0.0
    assert not budget.exhausted

    # 1000 in, 2000 out: (1000*0.15 + 2000*0.60) / 1,000,000 = 0.00135
    budget.add(1000, 2000)
    assert round(budget.spent, 6) == 0.00135
    assert not budget.exhausted

    # Exceed cap
    budget.add(10_000_000, 10_000_000)
    assert budget.spent > 1.0
    assert budget.exhausted


def test_spend_cap_abort():
    budget = Budget(cap=0.001, per_in=100.0, per_out=100.0)
    samples = []
    aborted = False
    for i in range(5):
        if budget.exhausted:
            aborted = True
            break
        budget.add(100, 100)
        samples.append(Sample(task="task", index=i))

    assert aborted is True
    assert len(samples) < 5


def test_extract_fenced_and_bare():
    # Markdown lisp fence
    assert extract("```lisp\n(module m)\n```") == "(module m)"
    # Markdown generic fence
    assert extract("```\n(module m)\n```") == "(module m)"
    # Prose before/after fence
    fenced_prose = "Here is the code:\n```lisp\n(module m :export [])\n```\nHope this helps!"
    assert extract(fenced_prose) == "(module m :export [])"
    # Bare expression starting with paren
    assert extract("(module bare :doc \"\" :export [])") == "(module bare :doc \"\" :export [])"
    # Prose rejection
    assert extract("This is purely prose without code.") is None
    assert extract("") is None


IO_DEMO_CODE = """(module io-demo
  :doc "Copies a file and echoes it back."
  :export [main])

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Entry point."
  (match args
    ((cons src rest)
      (match rest
        ((cons dst more)
          (try (file-write dst (match (file-read src) ((ok t) t) ((err e) "missing"))))
          (println (try (file-read dst))))
        ((list)
          (println (match (file-read src) ((ok t) t) ((err e) "missing"))))))
    ((list) (eprintln "usage: io-demo SRC [DST]"))))
"""


def test_evaluate_whole_program_python():
    task_path = ROOT / "bench" / "tasks" / "io_demo.json"
    task = json.loads(task_path.read_text())

    s = Sample(task="io_demo", index=0)
    evaluate(IO_DEMO_CODE, task, s, target="python")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True

    # Test permission mode handling (0o000 file)
    perm_task = {
        "id": "perm_demo",
        "cases": [
            {
                "argv": ["noperm.txt"],
                "stdin": "",
                "files": {"noperm.txt": ["secret content\n", 0o000]},
                "stdout": "missing\n",
                "stderr": "",
                "exit": 0,
            }
        ],
    }
    s_perm = Sample(task="perm_demo", index=0)
    evaluate(IO_DEMO_CODE, perm_task, s_perm, target="python")
    assert s_perm.stage_reached == "correct"
    assert s_perm.passed is True


def test_evaluate_whole_program_interp():
    task_path = ROOT / "bench" / "tasks" / "io_demo.json"
    task = json.loads(task_path.read_text())

    s = Sample(task="io_demo", index=0)
    evaluate(IO_DEMO_CODE, task, s, target="interp")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True


has_rustc = shutil.which("rustc") is not None
has_go = shutil.which("go") is not None
has_node = shutil.which("node") is not None


@pytest.mark.skipif(not has_rustc, reason="rustc not found")
def test_evaluate_whole_program_rust():
    task_path = ROOT / "bench" / "tasks" / "io_demo.json"
    task = json.loads(task_path.read_text())

    s = Sample(task="io_demo", index=0)
    evaluate(IO_DEMO_CODE, task, s, target="rust")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True


@pytest.mark.skipif(not has_go, reason="go not found")
def test_evaluate_whole_program_go():
    task_path = ROOT / "bench" / "tasks" / "io_demo.json"
    task = json.loads(task_path.read_text())

    s = Sample(task="io_demo", index=0)
    evaluate(IO_DEMO_CODE, task, s, target="go")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True


@pytest.mark.skipif(not has_node, reason="node not found")
def test_evaluate_whole_program_typescript():
    task_path = ROOT / "bench" / "tasks" / "io_demo.json"
    task = json.loads(task_path.read_text())

    s = Sample(task="io_demo", index=0)
    evaluate(IO_DEMO_CODE, task, s, target="ts")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True


def test_function_mode_backward_compatibility():
    hist_path = ROOT / "bench" / "tasks" / "histogram.json"
    hist_task = json.loads(hist_path.read_text())
    hist_code = (ROOT / "bench" / "algo" / "variants" / "tight.agentscript").read_text()

    s = Sample(task="histogram", index=0)
    evaluate(hist_code, hist_task, s, target="python")
    assert s.stage_reached == "correct", f"Expected correct, got {s.stage_reached}: {s.detail}"
    assert s.passed is True

    # Function mode on non-python target should fail at transpile stage
    s_ts = Sample(task="histogram", index=0)
    evaluate(hist_code, hist_task, s_ts, target="ts")
    assert s_ts.stage_reached == "transpile"
    assert not s_ts.passed


def test_stage_failure_classification():
    task = SYNTHETIC_DRY_RUN_TASK

    # 1. extract failure
    s_ext = Sample(task="synthetic_dry_run", index=1)
    code = extract("Prose without code")
    if code is None:
        s_ext.detail = "no code block in reply"
    assert s_ext.stage_reached == "extract"
    assert not s_ext.passed

    # 2. parse failure
    s_parse = Sample(task="synthetic_dry_run", index=2)
    evaluate("(defun broken [ -> Int64 1)", task, s_parse, target="python")
    assert s_parse.stage_reached == "parse"
    assert not s_parse.passed

    # 3. check failure
    s_check = Sample(task="synthetic_dry_run", index=3)
    type_err = "(module synthetic :doc \"Dry run test\" :export [main])\n(defun ! main [(args (List String))] -> (Result Unit IoError)\n  :doc \"Entry point.\"\n  \"not-a-result\")"
    evaluate(type_err, task, s_check, target="python")
    assert s_check.stage_reached == "check"
    assert not s_check.passed

    # 4. transpile failure
    s_trans = Sample(task="synthetic_dry_run", index=4)
    trans_err = "(module synthetic :doc \"Dry run test\" :export [main])\n(defun ! import [(args (List String))] -> (Result Unit IoError)\n  :doc \"Entry point.\"\n  (println \"hi\"))\n(defun ! main [(args (List String))] -> (Result Unit IoError)\n  :doc \"Entry point.\"\n  (import args))"
    evaluate(trans_err, task, s_trans, target="python")
    assert s_trans.stage_reached == "transpile"
    assert not s_trans.passed

    # 5. execute failure (wrong stdout)
    s_exec = Sample(task="synthetic_dry_run", index=5)
    exec_wrong = "(module synthetic :doc \"Dry run test\" :export [main])\n(defun ! main [(args (List String))] -> (Result Unit IoError)\n  :doc \"Entry point.\"\n  (println \"wrong-dry-run-output\"))"
    evaluate(exec_wrong, task, s_exec, target="python")
    assert s_exec.stage_reached == "execute"
    assert not s_exec.passed


def test_subprocess_timeout_classification(tmp_path):
    cmd = [sys.executable, "-c", "import time; time.sleep(2)"]
    ret, stdout, stderr = run_target(cmd, cwd=tmp_path, timeout=0.1)
    assert ret == -1
    assert "timeout" in stderr


def test_dry_run_cli_all_stages():
    # Test python dry-run
    res_py = subprocess.run(
        [sys.executable, "bench/harness/run.py", "--dry-run", "--target", "python"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert res_py.returncode == 0, f"run.py dry-run failed:\n{res_py.stderr}"
    dry_out_py = json.loads((ROOT / "results" / "dry-run.json").read_text())
    assert dry_out_py["target"] == "python"
    stages_seen = {s["stage_reached"] for s in dry_out_py["samples"]}
    for expected_stage in STAGES:
        assert expected_stage in stages_seen, f"Stage {expected_stage} not found in {stages_seen}"

    # Test interp dry-run
    res_interp = subprocess.run(
        [sys.executable, "bench/harness/run.py", "--dry-run", "--target", "interp"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert res_interp.returncode == 0, f"run.py dry-run interp failed:\n{res_interp.stderr}"
    dry_out_interp = json.loads((ROOT / "results" / "dry-run.json").read_text())
    assert dry_out_interp["target"] == "interp"
