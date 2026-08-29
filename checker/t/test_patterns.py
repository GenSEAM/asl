"""Which pattern shapes bind and which test, at unit speed.

AGENT_SPEC_CORE 5.4's table gives `<ident>` and `(<case> <p>*)` different
meanings — bare binds anything, parenthesised tests a case — and the prelude
seeds `IoError`, so `not-found`, `interrupted` and `other` are live names on both
sides of that line. A backend that read a bare one as a nullary case test agreed
with the checker on every program where the two readings coincide, which is why
this is pinned by the cases where they do not.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "prelude"))

from resolve import check_file  # noqa: E402


def check(tmp_path, src: str) -> list[str]:
    f = tmp_path / "case.agents"
    f.write_text(src)
    return [d.code for d in check_file(f, [])]


def test_bare_case_name_binds_and_so_catches_all(tmp_path):
    """`other` names an IoError case and still matches anything: the arm closes a
    union four cases short of covered, and rule 4 stays silent."""
    src = ('(defun code [(e IoError)] -> Int64\n'
           '  (match e\n'
           '    ((not-found) 1)\n'
           '    (other       0)))\n')
    assert check(tmp_path, src) == []


def test_bare_case_name_shadows_an_outer_binding(tmp_path):
    """The reading that decides it: bound, the arm's `other` is the IoError
    scrutinee and shadows the String parameter. Read as a nullary case test
    instead, the body would see the parameter and this would check clean."""
    src = ('(defun code [(other String) (e IoError)] -> Int64\n'
           '  (match e\n'
           '    ((not-found) 1)\n'
           '    (other       (string-length other))))\n')
    assert "type" in check(tmp_path, src)


def test_parenthesised_case_tests_and_so_leaves_the_union_open(tmp_path):
    src = ('(defun code [(e IoError)] -> Int64\n'
           '  (match e\n'
           '    ((not-found)   1)\n'
           '    ((interrupted) 2)))\n')
    assert "rule-4" in check(tmp_path, src)


def test_wildcard_binds_nothing_but_still_catches_all(tmp_path):
    src = ('(defun code [(e IoError)] -> Int64\n'
           '  (match e\n'
           '    ((not-found) 1)\n'
           '    (_           0)))\n')
    assert check(tmp_path, src) == []
