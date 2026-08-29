"""The import closure a backend has to lower, and the order it comes in.

Whole-closure linking means one wrong order silently emits a call to a name that
does not exist yet in the target, so the order is asserted rather than observed.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from modules import find, resolve  # noqa: E402

CORPUS = ROOT / "grammar" / "corpus"


def test_closure_is_dependencies_first_and_the_file_last():
    units = resolve(CORPUS / "valid" / "06-module.agents", [CORPUS / "modules"])
    assert [name for name, _ in units] == ["core/strings", "text/casing"]


def test_a_transitive_import_precedes_the_module_that_needs_it():
    units = resolve(CORPUS / "valid" / "12-transitive-use.agents", [CORPUS / "modules"])
    assert [name for name, _ in units] == ["core/shapes", "text/report", "text/consume"]


def test_one_module_under_two_aliases_is_linked_once():
    units = resolve(CORPUS / "valid" / "11-name-coexistence.agents", [CORPUS / "modules"])
    assert [name for name, _ in units] == ["core/shapes", "text/coexist"]


def test_a_root_is_searched_in_order():
    assert find("core/strings", [CORPUS / "modules"]).name == "strings.agents"
    assert find("core/absent", [CORPUS / "modules"]) is None


def test_an_unresolvable_import_is_reported_not_swallowed():
    with pytest.raises(FileNotFoundError):
        resolve(CORPUS / "valid" / "06-module.agents", [])


CYCLE = {
    "a": """(module cyc/a
  :doc "One half of an import cycle."
  :export [f]
  :import [(cyc/b :as b)])

(defun f [(n Int64)] -> Int64
  :doc "Calls across the cycle."
  (b/g n))
""",
    "b": """(module cyc/b
  :doc "The other half of an import cycle."
  :export [g]
  :import [(cyc/a :as a)])

(defun g [(n Int64)] -> Int64
  :doc "Calls back across the cycle."
  (+ n 1))
""",
}


def test_a_cycle_leaves_the_root_out_of_its_own_closure(tmp_path):
    """Rule 11 rejects a cyclic program, but the backend path claims to break the
    cycle rather than diagnose it — and emitting the root once as a dependency
    and once bare is not breaking it."""
    (tmp_path / "cyc").mkdir()
    for name, src in CYCLE.items():
        (tmp_path / "cyc" / f"{name}.agents").write_text(src)
    units = resolve(tmp_path / "cyc" / "a.agents", [tmp_path])
    assert [name for name, _ in units] == ["cyc/b", "cyc/a"]
