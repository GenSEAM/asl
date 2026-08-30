"""One test suite, both implementations. Cases are HumanEval/111's.

The AgentScript result is a Python dict because Map lowers to dict, so the two are
directly comparable without adaptation.
"""
import sys, pathlib
import pytest

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "backend"))

import histogram_agentscript
import histogram_python

CASES = [
    ("a b c",           {"a": 1, "b": 1, "c": 1}),
    ("a b b a",         {"a": 2, "b": 2}),
    ("a b c a b",       {"a": 2, "b": 2}),
    ("b b b b a",       {"b": 4}),
    ("",                {}),
    ("   ",             {}),
    ("r t g",           {"r": 1, "t": 1, "g": 1}),
    ("a",               {"a": 1}),
]


@pytest.mark.parametrize("impl", [histogram_agentscript.histogram, histogram_python.histogram],
                         ids=["agentscript", "python"])
@pytest.mark.parametrize("text,expected", CASES)
def test_histogram(impl, text, expected):
    assert impl(text) == expected


def test_both_agree_everywhere():
    for text, _ in CASES:
        assert histogram_agentscript.histogram(text) == histogram_python.histogram(text)


def test_the_checked_in_lowering_matches_its_source():
    """`histogram_agentscript.py` is committed and every case above imports it, so an
    emitter change reached the measurement in ROADMAP's size table without
    anything comparing the file to the source it came from — and one had already
    drifted by an arithmetic lowering. Regenerate with:

        .venv/bin/python backend/to_python.py bench/algo/histogram.agentscript \
            > bench/algo/histogram_agentscript.py
    """
    sys.path.insert(0, str(HERE.parent.parent / "grammar"))
    from to_python import Transpiler
    src = HERE / "histogram.agentscript"
    assert Transpiler().transpile(src.read_text(), path=src) == \
        (HERE / "histogram_agentscript.py").read_text()
