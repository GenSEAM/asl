"""One test suite, both implementations. Cases are HumanEval/111's.

The AgentS result is a Python dict because Map lowers to dict, so the two are
directly comparable without adaptation.
"""
import sys, pathlib
import pytest

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "backend"))

import histogram_agents
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


@pytest.mark.parametrize("impl", [histogram_agents.histogram, histogram_python.histogram],
                         ids=["agents", "python"])
@pytest.mark.parametrize("text,expected", CASES)
def test_histogram(impl, text, expected):
    assert impl(text) == expected


def test_both_agree_everywhere():
    for text, _ in CASES:
        assert histogram_agents.histogram(text) == histogram_python.histogram(text)
