"""End-to-end: AgentScript source -> Python -> executed, semantics asserted.

Expected values are written from AGENT_SPEC_CORE.md, not from observing what the
transpiler produced. A test that records current behaviour proves the pipeline
runs; it does not prove the pipeline is right.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import smoke as s
import runtime as _as


def test_enum_dispatch():
    assert s.area(s.circle(2.0)) == 12.0
    assert s.area(s.rectangle(3.0, 4.0)) == 12.0
    assert s.area(s.point()) == 0.0


def test_cond_is_total():
    assert [s.classify(n) for n in (-5, 0, 5)] == ["negative", "zero", "positive"]


def test_structural_recursion():
    assert s.sum_list([]) == 0
    assert s.sum_list([1, 2, 3, 4]) == 10


def test_result_is_a_value_not_an_exception():
    assert s.safe_div(7, 2) == ("ok", 3)          # truncating division
    assert s.safe_div(-7, 2) == ("ok", -3)        # toward zero, not floor
    assert s.safe_div(1, 0) == ("err", "division by zero")


def test_try_propagates_failure():
    assert s.parse_double("21") == ("ok", 42)
    assert s.parse_double("  8 ") == ("ok", 16)
    assert s.parse_double("nope") == ("err", "not a number")


def test_match_over_result():
    assert s.describe(_as.ok(7)) == "7"
    assert s.describe(_as.err("boom")) == "boom"
