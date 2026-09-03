"""CLI tests for the self-hosted (pure-ASL) parser and `asl parse` (Phase 3/6).

Covers, in order: the driver's ``(Result String ParseError)`` export boundary,
the ``native_render`` entry point's stability, the ``asl parse`` subcommand's
success, bad-input and parse-failure paths, and the native-vs-Lark benchmark
report.
"""

import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
HARNESS_DIR = ROOT / "packages" / "asl-parser" / "tests"

SAMPLE = ('(module m :doc "d" :export [inc])\n'
          '(defun inc [(x Int64)] -> Int64 :doc "inc" (add1 x))\n')


@pytest.fixture(scope="module")
def ns():
    sys.path.insert(0, str(HARNESS_DIR))
    from harness import run_asl
    return run_asl(HARNESS_DIR / "reader_test.asl")


def _run_cli(*argv):
    return subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), *argv],
        capture_output=True, text=True, cwd=ROOT)


def test_render_all_returns_a_result(ns):
    out = ns["render_all"]("(module m/n)")
    assert out[0] == "ok", out
    assert isinstance(out[1], str)
    assert "(module m/n)" in out[1]


def test_native_render_is_stable_and_verbose():
    from tools.native_parser import native_render

    src = '(module sample/m :doc "sample")\n(defun inc [(x Int64)] -> Int64 (add1 x))'
    first = native_render(src)
    second = native_render(src)
    assert first == second
    assert "(defun inc" in first
    # The module's own path is part of the header: dropping it made the render
    # unparseable by the reference grammar, and the old assertion pinned the loss.
    assert '(module sample/m :doc "sample")' in first


def test_native_render_keeps_record_keys_that_look_like_options():
    """A Nano alias is significant in head or option position and nowhere else."""
    from tools.native_parser import native_render

    src = '(defun mk [] -> P :doc "d" (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6))'
    assert native_render(src) == src


def test_cli_parse_success(tmp_path):
    f = tmp_path / "sample.asl"
    f.write_text(SAMPLE)
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0
    assert '(module m :doc "d"' in proc.stdout
    assert "(defun inc" in proc.stdout


def test_cli_parse_bad_file_nonzero(tmp_path):
    proc = _run_cli("parse", str(tmp_path / "missing.asl"))
    assert proc.returncode != 0
    assert "no such file" in proc.stderr
    assert ": parse:" not in proc.stdout


def test_cli_parse_error_reports_located_diagnostic(tmp_path):
    """An unbalanced source is a diagnostic at the delimiter that opened it.

    This used to be asserted through a `RecursionError` from 3000-deep nesting,
    which was the parser having no failure path rather than having one. Deep
    nesting now parses (see below); a real syntax error is what fails.
    """
    f = tmp_path / "broken.asl"
    f.write_text('(module t/x :doc "d")\n(defun broken [] -> Int64 :doc "b" (+ 1 2)\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode != 0
    assert f"{f}:2:1: parse: unclosed delimiter" in proc.stdout
    assert "1 diagnostic(s)" in proc.stdout


def test_cli_parse_error_json_carries_position(tmp_path):
    import json
    f = tmp_path / "broken.asl"
    f.write_text('(defun f [] -> Int64 :doc "d" 1))\n')
    proc = _run_cli("parse", str(f), "--json")
    assert proc.returncode != 0
    payload = json.loads(proc.stdout)
    assert payload[0]["code"] == "parse"
    assert payload[0]["line"] == 1
    assert payload[0]["col"] == 33
    assert "unexpected closing delimiter" in payload[0]["message"]


def test_cli_parse_deep_nesting_succeeds(tmp_path):
    """3000 levels of nesting parse and render; nothing recurses per level."""
    depth = 3000
    body = "(id " * depth + "1" + ")" * depth
    f = tmp_path / "deep.asl"
    f.write_text(f'(defun deep [] -> Int64 :doc "d" {body})\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert proc.stdout.strip() == f'(defun deep [] -> Int64 :doc "d" {body})'


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


# -- bare string top-level comments ------------------------------------------

def test_cli_parse_bare_string_comment_succeeds(tmp_path):
    f = tmp_path / "with_comment.asl"
    f.write_text('"this is a comment"\n(defun f [] -> Int64 :doc "d" 1)\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "this is a comment" not in proc.stdout  # comment is discarded
    assert "(defun f [] -> Int64 :doc \"d\" 1)" in proc.stdout


def test_cli_parse_multiple_bare_string_comments(tmp_path):
    f = tmp_path / "multi_comment.asl"
    f.write_text(
        '"first comment"\n'
        '"second comment"\n'
        '(defun f [] -> Int64 :doc "d" 1)\n'
    )
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "(defun f [] -> Int64 :doc \"d\" 1)" in proc.stdout


def test_cli_parse_multiline_bare_string_comment(tmp_path):
    f = tmp_path / "ml_comment.asl"
    f.write_text(
        '"this comment spans\n'
        'two lines in the source"\n'
        '(defun f [] -> Int64 :doc "d" 1)\n'
    )
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "(defun f [] -> Int64 :doc \"d\" 1)" in proc.stdout


def test_cli_parse_top_level_note_is_accepted_and_erased(tmp_path):
    """A bare string at top level is a note bound to nothing (`toplevel: ... | note`).

    Every backend erases it, so the render drops it too — and still re-parses.
    """
    f = tmp_path / "note.asl"
    f.write_text('"a file banner"\n(defun f [] -> Int64 :doc "d" 1)\n"a trailing note"\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert proc.stdout.strip() == '(defun f [] -> Int64 :doc "d" 1)'


def test_cli_parse_string_in_body_remains_value(tmp_path):
    """A bare string inside a defun body is a value, not a comment."""
    f = tmp_path / "body_string.asl"
    f.write_text('(defun f [] -> String :doc "d" "hello")\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert '"hello"' in proc.stdout  # string remains in the output


def test_cli_parse_semicolons_inside_strings_are_fine(tmp_path):
    """A semicolon inside a string literal is just text."""
    f = tmp_path / "semi_in_string.asl"
    f.write_text('"a string with ; semicolons inside"\n(defun f [] -> Int64 :doc "d" 1)\n')
    proc = _run_cli("parse", str(f))
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "(defun f [] -> Int64 :doc \"d\" 1)" in proc.stdout
