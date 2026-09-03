"""A Nano-spelled module must emit exactly what its Core-spelled twin emits.

Three of the four backends read a type token off the AST and printed it, so a
module written `I64` reached rustc, tsc and go vet as `I64` and all three
rejected it while Python -- which emits no types at all -- stayed green. The
assertion here is equality against the verbose twin rather than a table of
expected spellings: a table restated in the test is the second alias map that
caused the defect.

Parametrised over the vocabulary itself, so an alias added to prelude.json is
covered without this file being touched.
"""
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
for sub in ("grammar", "backend", "prelude"):
    sys.path.insert(0, str(ROOT / sub))

from to_go import ToGo  # noqa: E402
from to_python import Transpiler as ToPython  # noqa: E402
from to_rust import ToRust  # noqa: E402
from to_typescript import ToTypeScript  # noqa: E402
from vocab import reserved_widths, type_aliases  # noqa: E402

BACKENDS = {"rust": ToRust, "typescript": ToTypeScript, "go": ToGo, "python": ToPython}

# The identity entries say nothing about resolution; a rename is the whole test.
RENAMES = sorted((a, core) for a, core in type_aliases().items() if a != core)

MODULES = ROOT / "grammar" / "corpus" / "modules"

# Every position a backend emits a type name from: a field, a parameter, a
# return type, and a type argument inside a constructed type.
TEMPLATE = """(module t/alias-probe
  :doc "One type name in every position a backend emits one from."
  :export [Box unbox spread])

(defschema Box
  (:field v {ty} "The value."))

(defun unbox [(b Box)] -> {ty}
  :doc "Read the field back."
  (.-v b))

(defun spread [(b Box)] -> (List {ty})
  :doc "The same type inside a constructed one."
  (list (.-v b) (unbox b)))
"""


def emit(backend: str, ty: str, tmp_path: Path) -> str:
    src = TEMPLATE.format(ty=ty)
    path = tmp_path / "probe.agentscript"
    path.write_text(src)
    return BACKENDS[backend]().transpile(src, path=path, roots=[MODULES])


@pytest.mark.parametrize("backend", sorted(BACKENDS))
@pytest.mark.parametrize("alias,core", RENAMES)
def test_an_alias_emits_what_its_core_type_emits(backend, alias, core, tmp_path):
    assert emit(backend, alias, tmp_path) == emit(backend, core, tmp_path)


@pytest.mark.parametrize("backend", sorted(BACKENDS))
@pytest.mark.parametrize("alias,_core", RENAMES)
def test_the_alias_spelling_never_reaches_the_target(backend, alias, _core, tmp_path):
    out = emit(backend, alias, tmp_path)
    # Whole word: `Str` is a prefix of the `String` it correctly resolves to.
    assert not re.search(rf"\b{re.escape(alias)}\b", out), \
        f"{backend} emitted the alias {alias} verbatim"


@pytest.mark.parametrize("backend", sorted(BACKENDS))
@pytest.mark.parametrize("width,core", sorted(reserved_widths().items()))
def test_a_reserved_width_carries_no_narrower_semantics(backend, width, core, tmp_path):
    """`F32` is a width Core does not have. It is accepted and resolved to the
    type prelude.json names, and a backend that invented a narrower one for it
    would diverge from the twin here."""
    assert emit(backend, width, tmp_path) == emit(backend, core, tmp_path)
