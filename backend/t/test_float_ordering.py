"""The Rust derive, at a declaration that holds a Float64.

`PartialOrd` was bundled with `Eq, Ord` in one derive, so a record or a union
holding a `Float64` derived none of the three — and `f64` is `PartialOrd`. The
language specifies an order for exactly those values (AGENT_SPEC_CORE.md 3.2,
NaN last, ties stable) and `rt::sort` is written against `PartialOrd` so it can
express that order, so the bundle removed an order the runtime already had.

Rust only, deliberately. The Python lowering represents a record as a dict,
which no `sorted` can order, so this shape has no agreeing pair to compare — see
ROADMAP.md section 6. Asserting it on the one backend that can answer beats
asserting nothing until the other can.
"""
import sys
from pathlib import Path

import pytest

BACKEND = Path(__file__).parent.parent
ROOT = BACKEND.parent
sys.path.insert(0, str(BACKEND))
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "grammar"))

import differential as d  # noqa: E402

RECORD = """\
; Fields in the order the derived comparison uses them: the measurement decides,
; and `seq` is only there to make a kept order visible.
(defschema Reading
  (:field v Float64 "The measurement.")
  (:field seq Int64 "Arrival order."))

(defun ordered [(vs (List Float64))] -> (List Float64)
  :doc "Sort readings holding those values, and report the values back."
  (map (fn [r] (.-v r))
       (list-sort (map (fn [p] (Reading :v (.-second p) :seq (.-first p)))
                       (zip (range 0 (list-length vs)) vs)))))

(defun seqs [(vs (List Float64))] -> (List Int64)
  :doc "The same sort, reporting arrival order instead: a stable sort leaves
        values that tie in the order they arrived."
  (map (fn [r] (.-seq r))
       (list-sort (map (fn [p] (Reading :v (.-second p) :seq (.-first p)))
                       (zip (range 0 (list-length vs)) vs)))))
"""

UNION = """\
(defenum Sample
  (:case reading [(v Float64)] "A measured value.")
  (:case missing [] "No measurement."))

(defun ordered [(vs (List Float64))] -> (List Float64)
  :doc "Sort samples holding those values, and report the values back."
  (map (fn [s] (match s ((reading v) v) ((missing) 0.0)))
       (list-sort (map (fn [v] (reading v)) vs))))
"""


def _rust(tmp_path, text: str, entry: str, args: list):
    path = tmp_path / "probe.agents"
    path.write_text(text)
    return d.run_rust(path, {"id": entry, "entry": entry, "cases": [[args, None]]})[0]


def test_a_record_holding_a_float_can_be_sorted(tmp_path):
    assert _rust(tmp_path, RECORD, "ordered", [[3.0, 0.5, 2.0]]) == [0.5, 2.0, 3.0]


def test_a_nan_inside_a_record_sorts_last(tmp_path):
    """Section 3.2: a value *holding* a NaN sorts after every value that does
    not. Derived PartialOrd answers None for such a record, which is what
    rt::nan_last reads."""
    assert _rust(tmp_path, RECORD, "ordered", [[3.0, "nan", 0.5]]) == [0.5, 3.0, "nan"]


def test_records_holding_a_nan_tie_and_keep_their_order(tmp_path):
    """They tie with one another and the sort is stable, so arrival order 1 and
    3 come back in that order behind the two that are ordered."""
    assert _rust(tmp_path, RECORD, "seqs", [[3.0, "nan", 0.5, "nan"]]) == [2, 0, 1, 3]


def test_a_union_holding_a_float_can_be_sorted(tmp_path):
    assert _rust(tmp_path, UNION, "ordered", [[3.0, 0.5, 2.0]]) == [0.5, 2.0, 3.0]


def test_a_nan_inside_a_union_case_sorts_last(tmp_path):
    assert _rust(tmp_path, UNION, "ordered", [[3.0, "nan", 0.5]]) == [0.5, 3.0, "nan"]


def test_an_ioerror_bearing_record_still_derives_no_order(tmp_path):
    """The other half of the split: IoError implements none of the four order
    traits, so a declaration reaching it must keep deriving neither. A fix that
    made everything PartialOrd would pass the tests above and break this."""
    src = ('(defschema Failure (:field cause IoError "Why it failed."))\n'
           '(defun ordered [(n Int64)] -> Int64 :doc "Unused." n)\n')
    from to_rust import ToRust
    path = tmp_path / "probe.agents"
    path.write_text(src)
    out = ToRust().transpile(src, path=path)
    assert "#[derive(Debug, Clone, PartialEq)]\npub struct Failure" in out
