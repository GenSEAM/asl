"""The host entry glue, which is where the two backends' `main` types meet.

rt::main_exit takes a Result<(), IoError> and rejects anything else at compile
time. A Python host that indexed whatever it was handed made the backends
disagree about which programs are valid: a `main` returning Int64 died with an
unrelated TypeError, and one failing with a String printed the error's first
character to stderr as though it were a case name.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

import runtime as _agentscript  # noqa: E402


def test_a_result_becomes_an_exit_status():
    assert _agentscript.main_exit(_agentscript.ok(None)) == 0
    assert _agentscript.main_exit(_agentscript.err(("not-found",))) == 1


def test_the_failing_case_name_reaches_stderr(capsys):
    _agentscript.main_exit(_agentscript.err(("permission-denied",)))
    assert capsys.readouterr().err == "permission-denied\n"


@pytest.mark.parametrize("value", [42, "boom", None, ("ok",), ("maybe", 1)])
def test_a_main_that_is_not_a_result_is_rejected(value):
    with pytest.raises(TypeError, match="must return a Result"):
        _agentscript.main_exit(value)


@pytest.mark.parametrize("failure", ["boom", ("no-such-case",), 7, ()])
def test_a_failure_that_is_not_an_io_error_is_rejected(failure):
    with pytest.raises(TypeError, match="must fail with an IoError"):
        _agentscript.main_exit(_agentscript.err(failure))
