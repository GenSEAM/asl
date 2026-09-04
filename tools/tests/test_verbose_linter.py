import sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from verbose_linter import check_file_for_verbose


def test_clean_standard_asl_passes(tmp_path):
    f = tmp_path / "clean.asl"
    f.write_text("""(module test/clean
  :d "Clean standard module"
  :x [add])

(df add [(a I64) (b I64)] -> I64
  :d "Adds two numbers"
  (+ a b))
""")
    violations = check_file_for_verbose(f, check_types=True)
    assert len(violations) == 0


def test_verbose_head_and_options_flagged_as_errors(tmp_path):
    f = tmp_path / "verbose.asl"
    f.write_text("""(module test/verbose
  :doc "Verbose module"
  :export [calc])

(defun calc [(n I64)] -> I64
  :doc "Calculates"
  (match n
    (1 10)
    (_ 0)))
""")
    violations = check_file_for_verbose(f, check_types=False)
    assert len(violations) >= 4
    errors = [v for v in violations if v[4] == "error"]
    origs = {v[2] for v in errors}
    assert ":doc" in origs
    assert ":export" in origs
    assert "defun" in origs
    assert "match" in origs


def test_verbose_types_flagged(tmp_path):
    f = tmp_path / "types.asl"
    f.write_text("""(module test/types
  :d "Types"
  :x [f])

(df f [(s String) (n Int64)] -> Float64
  :d "Type signature with verbose aliases"
  42.0)
""")
    violations = check_file_for_verbose(f, check_types=True)
    warnings = [v for v in violations if v[4] == "warning"]
    origs = {v[2] for v in warnings}
    assert "String" in origs
    assert "Int64" in origs
    assert "Float64" in origs
