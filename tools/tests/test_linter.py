import pytest
import subprocess
import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from linter import AslLinter, calculate_quality_score


def test_calculate_quality_score():
    assert calculate_quality_score(0, 0) == 100
    assert calculate_quality_score(0, 1) == 95
    assert calculate_quality_score(1, 0) == 75
    assert calculate_quality_score(2, 2) == 40
    assert calculate_quality_score(5, 0) == 0


def test_lint_clean_asl():
    linter = AslLinter()
    src = """(module test/clean
  :doc "Clean module test"
  :export [add])

(defun add [(a Int64) (b Int64)] -> Int64
  :doc "Adds two integers"
  (+ a b))
"""
    report = linter.lint_source(src)
    assert report.score == 100
    assert report.error_count == 0
    assert report.warning_count == 0
    assert len(report.smells) == 0
    assert not report.should_block


def test_lint_duplicate_match_arm():
    linter = AslLinter()
    src = """(module test/dup
  :doc "Duplicate match arm test"
  :export [handle])

(defun handle [(n Int64)] -> Int64
  :doc "Test handler"
  (match n
    (1 (+ n 42))
    (2 (+ n 42))
    (_ 0)))
"""
    report = linter.lint_source(src)
    assert report.warning_count >= 1
    codes = [s.code for s in report.smells]
    assert "duplicate-match-arm" in codes
    dup_smell = next(s for s in report.smells if s.code == "duplicate-match-arm")
    assert dup_smell.can_autofix is True


def test_lint_dead_branch():
    linter = AslLinter()
    src = """(module test/dead
  :doc "Dead branch test"
  :export [evaluate])

(defun evaluate [(n Int64)] -> String
  :doc "Unreachable arm test"
  (match n
    (1 "one")
    (_ "wildcard")
    (2 "unreachable")))
"""
    report = linter.lint_source(src)
    assert report.error_count >= 1
    codes = [s.code for s in report.smells]
    assert "dead-branch" in codes
    dead_smell = next(s for s in report.smells if s.code == "dead-branch")
    assert dead_smell.severity == "error"
    assert report.should_block is True


def test_lint_unused_binding():
    linter = AslLinter()
    src = """(module test/unused
  :doc "Unused binding test"
  :export [calc])

(defun calc [(a Int64)] -> Int64
  :doc "Calculates result with unused intermediate"
  (let [(dead-var 42)
        (used-var 10)]
    (+ a used-var)))
"""
    report = linter.lint_source(src)
    assert report.warning_count >= 1
    codes = [s.code for s in report.smells]
    assert "unused-binding" in codes
    unused_smell = next(s for s in report.smells if s.code == "unused-binding")
    assert "dead-var" in unused_smell.message
    assert unused_smell.can_autofix is True


def test_lint_excessive_nesting():
    linter = AslLinter(max_allowed_nesting=3)
    src = """(module test/nesting
  :doc "Excessive nesting test"
  :export [deep])

(defun deep [(a Int64) (b Int64) (c Int64) (d Int64)] -> Int64
  :doc "Deeply nested logic"
  (if (> a 0)
    (if (> b 0)
      (if (> c 0)
        (if (> d 0)
          1
          0)
        0)
      0)
    0))
"""
    report = linter.lint_source(src)
    codes = [s.code for s in report.smells]
    assert "excessive-nesting" in codes


def test_cli_lint_command():
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "lint",
            "packages/asl-skyloom/src/core/skyloom.asl",
            "packages/asl-lint/src/core/lint.asl",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) == 2
    assert all(d["score"] == 100 for d in data)
    assert all(d["errorCount"] == 0 for d in data)
