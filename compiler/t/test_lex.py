"""The self-hosting probe: a lexer written in AgentScript, run over AgentScript.

ROADMAP §7 registered this probe as the cheap place to find out whether the
language can host its own compiler. It can, for small inputs, and the ceiling it
hits is the finding — see `.pcp/lang/host.md` `c-1d90`.

The round-trip assertion needs no oracle: concatenating every token's text must
reproduce the source with whitespace removed, which catches a dropped or
duplicated character anywhere in the scan.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
SRC = ROOT / "compiler" / "lex.as"

# Python's default recursion limit is 1000 and no backend eliminates tail calls,
# so the probe is exercised below the ceiling it documents.
SMALL = [ROOT / "grammar" / "corpus" / "valid" / f
         for f in ("01-basics.as", "02-match.as", "05-constructors.as", "09-aliases.as")]


@pytest.fixture(scope="module")
def lexer():
    from to_python import Transpiler
    d = tempfile.mkdtemp()
    p = Path(d)
    (p / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
    (p / "aslex.py").write_text(Transpiler().transpile_file(SRC))
    sys.path.insert(0, d)
    import aslex
    yield aslex
    sys.path.remove(d)


def lex_ok(lexer, text):
    r = lexer.lex(text)
    assert r[0] == "ok", f"lexer refused: {r[1]}"
    return r[1]


@pytest.mark.parametrize("path", SMALL, ids=lambda p: p.name)
def test_round_trips_real_source(lexer, path):
    src = path.read_text()
    toks = lex_ok(lexer, src)
    joined = "".join(t["text"] for t in toks)
    assert re.sub(r"\s", "", joined) == re.sub(r"\s", "", src)


def test_classifies_the_token_kinds(lexer):
    toks = lex_ok(lexer, '(defun f [(x Int64)] -> Bool :doc "d" (.-y x))')
    got = [(lexer.render_kind(t["kind"]), t["text"]) for t in toks]
    assert got == [
        ("open-paren", "("), ("ident", "defun"), ("ident", "f"),
        ("open-square", "["), ("open-paren", "("), ("ident", "x"),
        ("type-name", "Int64"), ("close-paren", ")"), ("close-square", "]"),
        ("arrow", "->"), ("type-name", "Bool"), ("keyword", ":doc"),
        ("string", '"d"'), ("open-paren", "("), ("field-ref", ".-y"),
        ("ident", "x"), ("close-paren", ")"), ("close-paren", ")"),
    ]


@pytest.mark.parametrize("text,kind", [
    ("42", "int"), ("-42", "int"), ("3.5", "float"), ("-3.5", "float"),
    ("true", "bool"), ("false", "bool"), ("_", "wildcard"),
    ("s/concat", "qualified"), (":target", "keyword"), (".-first", "field-ref"),
    ("->", "arrow"), ("<=", "operator"), ("!=", "operator"), ("+", "operator"),
    ("empty?", "ident"), ("Int64", "type-name"), ('"hi"', "string"),
    ("; a comment", "comment"),
])
def test_single_tokens(lexer, text, kind):
    toks = lex_ok(lexer, text)
    assert len(toks) == 1, [t["text"] for t in toks]
    assert lexer.render_kind(toks[0]["kind"]) == kind


def test_an_escaped_quote_does_not_end_the_string(lexer):
    toks = lex_ok(lexer, r'"a\"b"')
    assert len(toks) == 1 and toks[0]["text"] == r'"a\"b"'


def test_an_unterminated_string_is_a_value_not_a_crash(lexer):
    r = lexer.lex('"never closed')
    assert r[0] == "err" and "unterminated" in r[1]


def test_a_lone_dot_is_refused(lexer):
    assert lexer.lex("(. x)")[0] == "err"


def test_the_recursion_ceiling_is_real_and_is_the_probe_s_finding(lexer):
    """The language has no loop, and no backend eliminates tail calls.

    `lex-from` recurses once per token, so the Python backend runs out of stack
    at roughly its recursion limit. This is asserted rather than worked around
    because it is the probe's result: the compiler cannot yet be written in the
    language it compiles, and this is the reason.
    """
    assert lex_ok(lexer, "(a) " * 300)          # comfortably under
    with pytest.raises(RecursionError):
        lexer.lex("(a) " * 1000)


def test_the_lexer_cannot_yet_lex_itself(lexer):
    # The sharpest statement of the ceiling: compiler/lex.as is about 1,400
    # atoms, and lexing it needs more stack than the Python backend has.
    with pytest.raises(RecursionError):
        lexer.lex(SRC.read_text())


def test_it_transpiles_to_every_backend():
    for backend in ("to_python.py", "to_rust.py", "to_swift.py"):
        r = subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(SRC)],
                           capture_output=True, text=True)
        assert r.returncode == 0, f"{backend}: {r.stderr[-400:]}"
        assert r.stdout.strip()
