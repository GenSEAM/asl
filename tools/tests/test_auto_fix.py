import pytest
import subprocess
import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from heal import heal_file, heal_paths
from linter import AslLinter


def test_auto_fix_unused_binding(tmp_path):
    f = tmp_path / "test_unused.asl"
    f.write_text("""(module test/unused
  :doc "Unused binding before repair"
  :export [run])

(defun run [(a Int64)] -> Int64
  :doc "Function with unused binding"
  (let [(dead-val 42)
        (live-val 10)]
    (+ a live-val)))
""")

    # Verify that linter detects warning before fix
    linter = AslLinter()
    report_before = linter.lint_file(f)
    assert report_before.warning_count >= 1
    assert any(s.code == "unused-binding" for s in report_before.smells)

    # Apply auto-fix
    patches = heal_file(f, apply_fix=True)
    assert len(patches) >= 1
    assert any(p.rule == "unused-binding" for p in patches)

    # Verify content was updated
    content_after = f.read_text()
    assert "(unused-dead-val " in content_after

    # Verify linter now scores 100/100 cleanly
    report_after = linter.lint_file(f)
    assert report_after.score == 100
    assert report_after.warning_count == 0
    assert report_after.error_count == 0


def test_auto_fix_rule13_export(tmp_path):
    f = tmp_path / "test_schema.asl"
    f.write_text("""(module test/schema
  :doc "Schema with unexported referenced type"
  :export [Config])

(defenum Mode
  (:case fast [] "Fast mode")
  (:case slow [] "Slow mode"))

(defschema Config
  (:field mode Mode "Run mode"))
""")

    patches = heal_file(f, apply_fix=True)
    assert any(p.rule == "rule-13" for p in patches)

    content_after = f.read_text()
    assert ":export [Config Mode]" in content_after


def test_cli_fix_command(tmp_path):
    f = tmp_path / "cli_test.asl"
    f.write_text("""(module test/cli
  :doc "CLI fix test"
  :export [compute])

(defun compute [(n Int64)] -> Int64
  :doc "Function"
  (let [(unused-num 99)]
    (+ n 1)))
""")

    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "fix",
            str(f),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 1
