"""End-to-end: the I/O surface transpiled to Python and executed.

The property under test is totality, not plumbing: every operation that touches
the outside yields a value, so a missing file, a non-zero exit status and a
program that will not start are all ordinary results. A test that only checked
the happy path would pass against a runtime that raised on failure, which is the
behaviour the boundary exists to remove.

Expected values come from AGENT_SPEC_CORE.md §10, not from observing the runtime.
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))


@pytest.fixture(scope="module")
def mod():
    from to_python import Transpiler
    src = (Path(__file__).parent / "io.as").read_text()
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "io_mod.py"
        path.write_text(Transpiler().transpile(src))
        spec = importlib.util.spec_from_file_location("io_mod", path)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        yield m


def test_reading_a_missing_file_is_a_value(mod):
    assert mod.missing_is_a_value("/nonexistent/path/xyz") is True
    assert mod.read_or_message("/nonexistent/path/xyz").startswith("failed: ")


def test_reading_an_existing_file_returns_its_contents(mod, tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("hello\n")
    assert mod.read_or_message(str(f)) == "hello\n"


def test_write_then_read_round_trips(mod, tmp_path):
    f = tmp_path / "b.txt"
    assert mod.roundtrip(str(f), "written body") == ("ok", "written body")
    assert f.read_text() == "written body"


def test_writing_to_an_unwritable_path_fails_as_a_value(mod):
    got = mod.roundtrip("/nonexistent/dir/c.txt", "x")
    assert got[0] == "err"


def test_process_output_is_captured(mod):
    assert mod.run_echo("hi") == ("ok", "hi")


def test_a_non_zero_exit_status_is_success_of_the_call(mod):
    # The call succeeded; the program failed. Conflating the two would make a
    # failing subprocess indistinguishable from an unrunnable one.
    assert mod.exit_code_of("test", "") == ("ok", 1)


def test_a_program_that_cannot_start_is_an_err(mod):
    got = mod.exit_code_of("no-such-program-xyz", "")
    assert got[0] == "err"
