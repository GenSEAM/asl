"""A raw control character in a string literal must not reach the target's quotes.

The grammar admits a raw newline between the quotes, and a comment is now spelled
as a free-standing string, so a note running to a second line is ordinary source.
Every backend used to pass the token through verbatim: Rust accepts a multi-line
literal and Python, TypeScript and Go do not, so three of four emitted source
their own compiler refused while every gate stayed green.

The corpus fixture covers the newline and the tab. The carriage return lives here
instead, because a file carrying a bare CR does not survive being edited.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
for sub in ("grammar", "backend", "prelude"):
    sys.path.insert(0, str(ROOT / sub))

from _literals import string_literal  # noqa: E402
from to_python import Transpiler as ToPython  # noqa: E402
from to_rust import ToRust  # noqa: E402
from to_typescript import ToTypeScript  # noqa: E402

BACKENDS = {"python": ToPython, "rust": ToRust, "typescript": ToTypeScript}
MODULES = ROOT / "grammar" / "corpus" / "modules"

TEMPLATE = """(module t/raw
  :doc "One string literal carrying a raw control character."
  :export [f])

(defun f [] -> String
  :doc "Return it."
  "{body}")
"""

# Named rather than inlined: a failure report that prints a bare "\r" is unreadable.
RAW = [("newline", "\n"), ("carriage return", "\r"), ("tab", "\t")]


def emit(backend: str, body: str, tmp_path: Path) -> str:
    src = TEMPLATE.format(body=body)
    path = tmp_path / "raw.agentscript"
    path.write_text(src)
    return BACKENDS[backend]().transpile(src, path=path, roots=[MODULES])


def test_the_helper_rewrites_only_the_raw_characters():
    assert string_literal('"a\nb\rc\td"') == r'"a\nb\rc\td"'


def test_an_escape_already_in_the_source_is_left_alone():
    """`\\n` in the source is already the target's own spelling; rewriting the
    backslash would double it and turn the newline back into two characters."""
    assert string_literal(r'"a\nb"') == r'"a\nb"'
    assert string_literal(r'"a\\b"') == r'"a\\b"'


def test_an_escaped_backslash_before_a_raw_newline_stays_escaped():
    """The pair is a literal backslash followed by a newline, not a continuation."""
    assert string_literal('"a\\\\\nb"') == r'"a\\\nb"'


@pytest.mark.parametrize("backend", sorted(BACKENDS))
@pytest.mark.parametrize("name,ch", RAW, ids=[n for n, _ in RAW])
def test_no_backend_emits_a_raw_control_character(backend, name, ch, tmp_path):
    out = emit(backend, f"one{ch}two", tmp_path)
    assert f"one{ch}two" not in out, f"{backend} passed a raw {name} through"
    assert "one\\" in out and "two" in out


@pytest.mark.parametrize("name,ch", RAW, ids=[n for n, _ in RAW])
def test_the_python_literal_still_holds_the_character_it_started_with(name, ch, tmp_path):
    """Escaping is a change of spelling, not of value: the emitted literal has to
    evaluate back to the character the source carried."""
    out = emit("python", f"one{ch}two", tmp_path)
    literal = next(ln.split("return ", 1)[1] for ln in out.splitlines()
                   if ln.strip().startswith("return \""))
    assert eval(literal) == f"one{ch}two"
