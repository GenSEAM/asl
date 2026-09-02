"""CLI tests for the self-hosted (pure-ASL) parser and `asl parse` (Phase 3).

Covers, in order: the Python ``str`` -> ASL ``String`` export boundary, the
``native_render`` entry point's stability, the ``asl parse`` subcommand's
success and bad-input paths, and the native-vs-Lark benchmark report.
"""

import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
HARNESS_DIR = ROOT / "packages" / "asl-parser" / "tests"

# Comment-free module + defun the self-hosted parser handles (it has no
# `;`-comment support and recurses out on longer inputs, so corpus fixtures
# with comments are not usable success inputs).
SAMPLE = '(module m :doc "d" :export [inc])\n(defun inc [(x Int64)] -> Int64 :doc "inc" (add1 x))\n'


@pytest.fixture(scope="module")
def ns():
    sys.path.insert(0, str(HARNESS_DIR))
    from harness import run_asl
    return run_asl(HARNESS_DIR / "reader_test.asl")


def _run_cli(*argv):
    return subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), *argv],
        capture_output=True, text=True, cwd=ROOT)


def test_render_all_accepts_string_arg(ns):
    out = ns["render_all"]("(module m)")
    assert isinstance(out, str)
    assert out
    assert "(module" in out


def test_native_render_is_stable_and_verbose():
    from tools.native_parser import native_render

    src = '(module sample/m :doc "sample")\n(defun inc [(x Int64)] -> Int64 (add1 x))'
    first = native_render(src)
    second = native_render(src)
    assert first == second
    assert "(defun inc" in first
    assert "(module :doc \"sample\")" in first


def test_cli_parse_success(tmp_path):
    f = tmp_path / "sample.asl"
    f.write_text(SAMPLE)
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0
    assert '(module :doc "d"' in proc.stdout
    assert "(defun inc" in proc.stdout


def test_cli_parse_bad_file_nonzero(tmp_path):
    proc = _run_cli("parse", str(tmp_path / "missing.asl"))
    assert proc.returncode != 0
    assert "no such file" in proc.stderr
    assert ": parse:" not in proc.stdout


def test_cli_parse_parse_error_reports_diagnostic(tmp_path):
    # The parser's own driver exceeds its current recursion budget, so this is
    # a deterministic parse failure rather than a missing-file usage error.
    f = tmp_path / "driver.asl"
    f.write_text((HARNESS_DIR / "reader_test.asl").read_text())
    proc = _run_cli("parse", str(f))
    assert proc.returncode != 0
    assert ": parse:" in proc.stdout
    assert "diagnostic(s)" in proc.stdout


def test_cli_benchmark_reports_both_backends(tmp_path):
    f = tmp_path / "sample.asl"
    f.write_text(SAMPLE)
    proc = _run_cli("parse", str(f), "--bench")
    assert proc.returncode == 0
    assert re.search(r"native\s+\(parse \+ render-node\)", proc.stdout)
    assert re.search(r"lark\s+\(parse only\)", proc.stdout)
    assert "median" in proc.stdout
    assert "mean" in proc.stdout
    assert "peak" in proc.stdout
    assert re.search(r"median \d+(\.\d+)? ms", proc.stdout)
    assert re.search(r"peak \d+(\.\d+)? MiB", proc.stdout)

