"""End-to-end: AgentScript source -> Swift -> compiled -> executed, semantics asserted.

Expected values are written from AGENT_SPEC_CORE.md, not from observing what the
transpiler produced, and they are the same values `test_smoke.py` asserts against
the Python backend. Two backends asserting the same specification is what makes
the differential gate meaningful rather than circular.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))

DRIVER = """
func show<T, E>(_ r: ASResult<T, E>) -> String {
    switch r {
    case .ok(let v): return "ok:\\(v)"
    case .err(let e): return "err:\\(e)"
    }
}
var out: [String] = []
out.append("\\(area(Shape.circle(2.0)))")
out.append("\\(area(Shape.rectangle(3.0, 4.0)))")
out.append("\\(area(Shape.point))")
out.append(classify(-5))
out.append(classify(0))
out.append(classify(5))
out.append("\\(sumList([]))")
out.append("\\(sumList([1, 2, 3, 4]))")
out.append(show(safeDiv(7, 2)))
out.append(show(safeDiv(-7, 2)))
out.append(show(safeDiv(1, 0)))
out.append(show(parseDouble("21")))
out.append(show(parseDouble("  8 ")))
out.append(show(parseDouble("nope")))
out.append(describe(ASResult.ok(7)))
out.append(describe(ASResult.err("boom")))
print(out.joined(separator: "\\n"))
"""


@pytest.fixture(scope="module")
def results():
    if shutil.which("swiftc") is None:
        pytest.skip("swiftc not installed")
    from to_swift import ToSwift
    src = (Path(__file__).parent / "smoke.as").read_text()
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "rt.swift").write_text((ROOT / "backend" / "swift" / "rt.swift").read_text())
        (p / "main.swift").write_text(ToSwift().transpile(src) + DRIVER)
        c = subprocess.run(["swiftc", "rt.swift", "main.swift", "-o", "prog"],
                           cwd=d, capture_output=True, text=True)
        assert c.returncode == 0, c.stderr
        r = subprocess.run([str(p / "prog")], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return r.stdout.splitlines()


def test_enum_dispatch(results):
    assert results[0:3] == ["12.0", "12.0", "0.0"]


def test_cond_is_total(results):
    assert results[3:6] == ["negative", "zero", "positive"]


def test_structural_recursion(results):
    assert results[6:8] == ["0", "10"]


def test_result_is_a_value_not_an_exception(results):
    assert results[8] == "ok:3"        # truncating division
    assert results[9] == "ok:-3"       # toward zero, not floor
    assert results[10] == "err:division by zero"


def test_try_propagates_failure(results):
    assert results[11:14] == ["ok:42", "ok:16", "err:not a number"]


def test_match_over_result(results):
    assert results[14:16] == ["7", "boom"]
