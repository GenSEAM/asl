"""A module boundary, lowered and executed.

The source is transpiled inside the test rather than read from a checked-in
`.py`, because the defect this covers — a qualified name lowered with its slash
intact — produced output that still compiled. Expected values come from
AGENT_SPEC_CORE.md 4.0 and 4.4, not from what the emitter happened to print.
"""
import runpy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))

from to_python import Transpiler  # noqa: E402

CORPUS = ROOT / "grammar" / "corpus"

SHAPES = """(module geo/shapes
  :doc "A union and a measurement over it."
  :export [Shape area])

(defenum Shape
  (:case circle    [(radius Float64)]                 "A circle")
  (:case rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))

(defun area [(sh Shape)] -> Float64
  :doc "Area of a shape."
  (match sh
    ((circle r)      (* 3.0 (* r r)))
    ((rectangle w h) (* w h))))
"""

CONSUMER = """(module geo/report
  :doc "Naming and measuring shapes declared elsewhere."
  :export [name-of measure square]
  :import [(geo/shapes :as g)
           (geo/shapes :as shapes)])

(defun name-of [(sh g/Shape)] -> String
  :doc "The case an imported shape belongs to."
  (match sh
    ((g/circle r)      "circle")
    ((g/rectangle w h) "rectangle")))

(defun measure [(sh shapes/Shape)] -> Float64
  :doc "Area, through a second alias for the same module."
  (shapes/area sh))

(defun square [(side Float64)] -> g/Shape
  :doc "A square of the given side."
  (g/rectangle side side))
"""


def build(tmp: Path):
    """Both modules on disk, the consumer transpiled with the tree as its root."""
    (tmp / "geo").mkdir()
    (tmp / "geo" / "shapes.agents").write_text(SHAPES)
    source = tmp / "geo" / "report.agents"
    source.write_text(CONSUMER)
    (tmp / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
    out = tmp / "cand.py"
    out.write_text(Transpiler().transpile(source.read_text(), path=source, roots=[tmp]))
    sys.path.insert(0, str(tmp))
    try:
        return runpy.run_path(str(out))
    finally:
        sys.path.remove(str(tmp))


def test_an_imported_constructor_builds_a_value_of_its_union():
    with tempfile.TemporaryDirectory() as d:
        ns = build(Path(d))
        assert ns["geo_shapes__circle"](2.0) == ("circle", 2.0)
        assert ns["square"](3.0) == ("rectangle", 3.0, 3.0)


def test_a_match_over_an_imported_union_dispatches_on_the_case():
    with tempfile.TemporaryDirectory() as d:
        ns = build(Path(d))
        circle = ns["geo_shapes__circle"](2.0)
        assert ns["name_of"](circle) == "circle"
        assert ns["name_of"](ns["square"](1.0)) == "rectangle"


def test_two_aliases_for_one_module_reach_one_definition():
    """The prefix comes from the defining module path, never from the alias, so
    `g/area` and `shapes/area` are one emitted function (AGENT_SPEC_CORE 8)."""
    with tempfile.TemporaryDirectory() as d:
        ns = build(Path(d))
        emitted = [k for k in ns if k.endswith("__area")]
        assert emitted == ["geo_shapes__area"]
        assert ns["measure"](ns["geo_shapes__circle"](2.0)) == 12.0


def test_the_corpus_module_fixture_calls_across_the_boundary():
    """`shout` is an imported *function* call — the exact form the backend gate's
    skip list was hiding, and the one an imported-union case does not cover."""
    source = CORPUS / "valid" / "06-module.agents"
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        (tmp / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
        out = tmp / "cand.py"
        out.write_text(Transpiler().transpile(
            source.read_text(), path=source, roots=[CORPUS / "modules"]))
        sys.path.insert(0, str(tmp))
        try:
            ns = runpy.run_path(str(out))
        finally:
            sys.path.remove(str(tmp))
        assert ns["shout"]("hi") == "HI!"
        assert ns["area"](ns["circle"](2.0)) == 3.14159 * 4.0
