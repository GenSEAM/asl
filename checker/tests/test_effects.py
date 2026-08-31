"""The effect rule and the prelude union, at unit speed.

The corpus gate proves the verdict on whole files; these cover the cases a
fixture would only duplicate, and the boundary case the rule exists for — an
effectful lambda handed to a pure combinator.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "prelude"))

from resolve import check_file  # noqa: E402
from vocab import effectful, unions  # noqa: E402


def check(tmp_path, src: str) -> list[str]:
    f = tmp_path / "case.agentscript"
    f.write_text(src)
    return [d.code for d in check_file(f, [])]


def test_io_builtins_are_marked_effectful_in_the_vocabulary():
    assert {"file-read", "file-write", "println", "read-all"} <= effectful()
    assert "string-length" not in effectful()


def test_prelude_declares_the_io_union():
    assert "not-found" in unions()["IoError"]


def test_effectful_call_needs_the_marker(tmp_path):
    src = '(defun read-it [(p String)] -> (Result String IoError)\n  (file-read p))\n'
    assert "rule-12" in check(tmp_path, src)


def test_marked_declaration_may_call_out(tmp_path):
    src = '(defun ! read-it [(p String)] -> (Result String IoError)\n  (file-read p))\n'
    assert check(tmp_path, src) == []


def test_marker_without_any_effect_is_not_an_error(tmp_path):
    """The marker is a contract, and tightening one later must not break a caller."""
    src = '(defun ! plain [(n Int64)] -> Int64\n  (+ n 1))\n'
    assert check(tmp_path, src) == []


def test_unmarked_lambda_may_not_do_io(tmp_path):
    src = ('(defun ! each [(ps (List String))] -> (List (Result String IoError))\n'
           '  (map (fn [p] (file-read p)) ps))\n')
    assert "rule-12" in check(tmp_path, src)


def test_marked_lambda_colours_the_call_that_takes_it(tmp_path):
    """One `map` serves both kinds; passing the effectful one colours the caller."""
    pure_caller = ('(defun each [(ps (List String))] -> (List (Result String IoError))\n'
                   '  (map (fn ! [p] (file-read p)) ps))\n')
    assert "rule-12" in check(tmp_path, pure_caller)

    marked_caller = pure_caller.replace("(defun each", "(defun ! each")
    assert check(tmp_path, marked_caller) == []


def test_io_error_cases_are_patterns(tmp_path):
    src = ('(defun ! describe [(p String)] -> String\n'
           '  (match (file-read p)\n'
           '    ((ok text)         text)\n'
           '    ((err (not-found)) "missing")\n'
           '    ((err e)           "other")))\n')
    assert check(tmp_path, src) == []


def test_io_error_pattern_against_the_wrong_union_is_a_type_error(tmp_path):
    src = ('(defun classify [(o (Option Int64))] -> String\n'
           '  (match o\n'
           '    ((not-found) "missing")\n'
           '    ((some n)    "here")\n'
           '    ((none)      "absent")))\n')
    assert "type" in check(tmp_path, src)


def test_main_is_ordinary_until_a_backend_reads_it(tmp_path):
    src = ('(defun ! main [(args (List String))] -> (Result Unit IoError)\n'
           '  (println "hi"))\n')
    assert check(tmp_path, src) == []
