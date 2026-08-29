"""The differential harness's own encoding, which no gate would otherwise check.

The harness sits between the two backends, so a defect in it reports agreement
or disagreement about itself. The shapes compose — `(Option (List T))`,
`(List (Pair K V))`, `(Result (Option Int64) IoError)` — and the flat serializer
it replaced could not spell any of them.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

import differential as d  # noqa: E402

SOURCE = """\
(defun opt-list [(n Int64)] -> (Option (List Int64))
  (if (< n 0) (none) (some (range 0 n))))

(defun tagged [(n Int64)] -> (List (Pair Int64 String))
  (zip (range 0 n) (list "a" "b")))

(defun outcome [(n Int64)] -> (Result (Option Int64) IoError)
  (if (< n 0) (err (not-found)) (ok (some n))))
"""

SHAPES = [
    ("opt-list", [[[2], ["some", [0, 1]]], [[-1], ["none"]], [[0], ["some", []]]]),
    ("tagged", [[[2], [["pair", 0, "a"], ["pair", 1, "b"]]], [[0], []]]),
    ("outcome", [[[1], ["ok", ["some", 1]]], [[-1], ["err", ["not-found"]]]]),
]


@pytest.fixture(scope="module")
def source(tmp_path_factory) -> Path:
    path = tmp_path_factory.mktemp("shapes") / "shapes.agents"
    path.write_text(SOURCE)
    return path


@pytest.mark.parametrize("entry,cases", SHAPES)
def test_composed_shapes_encode_identically_on_both_backends(source, entry, cases):
    task = {"id": entry, "entry": entry, "cases": cases}
    want = [expected for _, expected in cases]
    assert d.run_python(source, task) == want
    assert d.run_rust(source, task) == want


def test_argument_types_come_from_the_declaration(source):
    specs = d.entry_types(source, "opt-list")
    assert [d.con(s) for s in specs] == ["Int64"]


def test_a_list_input_keeps_its_element_type():
    spec = {"con": "List", "args": [{"con": "Float64", "args": []}]}
    assert d.rust_literal(spec, [1, 2]) == "vec![1.0f64, 2.0f64]"
    assert d.rust_literal(spec, []) == "Vec::<f64>::new()"
    assert d.py_literal(spec, [1, 2]) == "[1.0, 2.0]"


def test_a_non_finite_float_has_a_spelling_on_both_sides():
    spec = {"con": "Float64", "args": []}
    assert d.rust_literal(spec, "nan") == "f64::NAN"
    assert d.py_literal(spec, "-inf") == "float('-inf')"


@pytest.mark.parametrize("spec", [{"var": "T"}, {"con": "Unit", "args": []}])
def test_an_input_type_the_harness_cannot_spell_fails_loudly(spec):
    with pytest.raises(RuntimeError):
        d.rust_literal(spec, None)


def test_successful_file_write_case_pins_content_and_declares_stderr():
    cases = next(cases for src, cases in d.program_cases()
                 if src.name == "08-io.agents")
    case = next((c for c in cases if c.get("argv") == ["sample.txt", "out.txt"]),
                None)
    assert case is not None
    assert (case["stdout"], case["stderr"], case["exit"]) == \
        ("hello from a file\n\n", "", 0)
