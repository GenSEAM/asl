"""Parity gate: the self-hosted parser against the reference grammar.

The syntax has four encodings — `grammar/tree-sitter-agentscript/grammar.js`,
`grammar/agentscript.lark`, `packages/asl-parser` and `tools/transcoder.py` —
and until this file existed only the first two were held against each other.
Every defect Phase 6 fixed (split floats, signs read as symbols, strings cut at
an escape, a dropped module path, aliases rewritten in record keys, a parser
that could not fail) survived because nothing compared the self-hosted parser to
a grammar on real sources.

**tree-sitter is the reference here.** Lark was retired from this suite in
Phase 7; the self-hosted parser is the sole check against the reference grammar
and every test here is written against tree-sitter.

Four claims are enforced:

1. The reference grammar accepts a source  =>  the native parser accepts it.
2. The native parser's verbose rendering re-parses under the reference grammar.
   A render that loses a form is caught here even when the parse was accepted.
3. The native parser rejects everything in `corpus/invalid`, so "it accepts
   everything" cannot pass claim 1 vacuously.
4. The alias tables duplicated into `src/ast.asl` — a parser written in
   AgentScript cannot read `prelude/prelude.json` — equal `prelude/vocab.py`'s.

Where the language is in flux, the assertion is *derived* from the reference
grammar rather than written down here, so this file never has to be edited to
follow a language change. `test_lexer_comment_handling_tracks_the_reference` is
the worked example: it asks tree-sitter what `;` means and holds the lexer to
that answer, whichever way it goes.
"""

import functools
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))

from tools.native_parser import NativeParserError, native_render  # noqa: E402

AST_SRC = ROOT / "packages" / "asl-parser" / "src" / "ast.asl"
TS_DIR = ROOT / "grammar" / "tree-sitter-agentscript"
TS_BIN = ROOT / "node_modules" / ".bin" / "tree-sitter"


@functools.lru_cache(maxsize=None)
def reference_accepts(src: str) -> bool:
    """Whether the tree-sitter grammar accepts this source.

    Driven the way `grammar/validate.py` drives it: a non-zero exit, or an ERROR
    or MISSING node in the printed tree, is a rejection. The CLI warns about
    parser directories on stderr regardless; that is not a verdict.
    """
    fd, name = tempfile.mkstemp(suffix=".agentscript")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(src)
        proc = subprocess.run([str(TS_BIN), "parse", name],
                              cwd=TS_DIR, capture_output=True, text=True)
    finally:
        os.unlink(name)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0 and "ERROR" not in out and "MISSING" not in out


def _accepted_sources() -> list[Path]:
    """Every source the project requires the reference grammar to accept.

    `corpus/semantic` is included on purpose: those fixtures violate rules only
    the checker can enforce, so the grammar must still parse them, and so must
    the native parser.
    """
    files = sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.agentscript"))
    files += sorted((ROOT / "grammar" / "corpus" / "semantic").rglob("*.agentscript"))
    files += sorted((ROOT / "grammar" / "corpus" / "modules").rglob("*.agentscript"))
    files += sorted((ROOT / "packages").rglob("*.asl"))
    return files


ACCEPTED = _accepted_sources()
REJECTED = sorted((ROOT / "grammar" / "corpus" / "invalid").glob("*.agentscript"))


def test_corpus_walk_finds_sources():
    """Guards the parametrize: a broken glob must fail loudly, not report green."""
    assert (ROOT / "packages").is_dir(), f"ROOT resolved to {ROOT}, no packages/ there"
    assert TS_BIN.is_file(), f"tree-sitter CLI missing at {TS_BIN}; run `npm install`"
    assert len(ACCEPTED) > 0, "no accepted sources found"
    assert len(REJECTED) > 0, "no corpus/invalid fixtures found"


@pytest.mark.parametrize(
    "path", [pytest.param(p, id=str(p.relative_to(ROOT))) for p in ACCEPTED])
def test_native_accepts_what_the_reference_accepts(path):
    src = path.read_text()
    rel = path.relative_to(ROOT)
    assert reference_accepts(src), f"the reference grammar rejects {rel}"
    try:
        out = native_render(src)
    except NativeParserError as exc:
        pytest.fail(f"native parser rejects {rel}: {exc}")
    assert out.strip(), f"empty render for {rel}"


@pytest.mark.parametrize(
    "path", [pytest.param(p, id=str(p.relative_to(ROOT))) for p in ACCEPTED])
def test_native_render_reparses_under_the_reference(path):
    out = native_render(path.read_text())
    assert reference_accepts(out), (
        f"render of {path.relative_to(ROOT)} does not re-parse:\n{out[:400]}")


@pytest.mark.parametrize(
    "path", [pytest.param(p, id=str(p.relative_to(ROOT))) for p in REJECTED])
def test_native_rejects_invalid_corpus(path):
    src = path.read_text()
    assert not reference_accepts(src), (
        f"{path.relative_to(ROOT)} is in corpus/invalid but the grammar accepts it")
    with pytest.raises(NativeParserError) as caught:
        native_render(src)
    exc = caught.value
    assert exc.line >= 1 and exc.col >= 1, f"diagnostic has no position: {exc!r}"
    assert exc.message, "diagnostic has no message"


def test_lexer_comment_handling_tracks_the_reference():
    """`;` means to the lexer whatever it means to the reference grammar.

    `;` line comments are retired in favour of free-standing string literals,
    so the reference grammar now rejects `;` and this test holds the lexer to
    that. It asks tree-sitter rather than writing the answer down, so if the
    grammar ever admits `;` again the lexer is the only thing that must follow.
    """
    src = '; a comment\n(defun f [] -> Int64 :doc "d" 1)'
    rendered = '(defun f [] -> Int64 :doc "d" 1)'
    if reference_accepts(src):
        assert native_render(src) == rendered
    else:
        with pytest.raises(NativeParserError):
            native_render(src)


def test_top_level_note_handling_tracks_the_reference():
    """A bare string bound to nothing, the mechanism replacing `;` comments.

    Derived the same way. Where the grammar admits a note, the parser accepts it
    and erases it, which is what all four backends do with one.
    """
    src = '"a file banner"\n(defun f [] -> Int64 :doc "d" 1)\n"a trailing note"'
    rendered = '(defun f [] -> Int64 :doc "d" 1)'
    if reference_accepts(src):
        assert native_render(src) == rendered
    else:
        with pytest.raises(NativeParserError):
            native_render(src)


def _asl_string_list(name: str) -> list[str]:
    """The `(list "a" "b" ...)` body of a nullary `(df <name> [] -> (List String))`."""
    src = AST_SRC.read_text()
    start = src.index(f"(df {name} [] -> (List String)")
    body = src.index("(list ", start)
    depth, i = 0, body
    while True:
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return re.findall(r'"([^"]*)"', src[body:i])


def _ast_table(spellings: str, verbose: str) -> dict[str, str]:
    keys = _asl_string_list(spellings)
    values = _asl_string_list(verbose)
    assert len(keys) == len(values), (
        f"{spellings} has {len(keys)} entries, {verbose} has {len(values)}")
    return dict(zip(keys, values))


# `where` values that put an option keyword in head position rather than an
# option slot: `(:field ...)` and `(:case ...)` lead their own form.
HEAD_POSITION_WHERE = {"field-head", "enum-case-head"}


def _vocab_tables() -> tuple[dict[str, str], dict[str, str]]:
    from vocab import head_aliases, option_aliases, projection
    heads = dict(head_aliases())
    options = {}
    by_verbose = {o["verbose"]: o for o in projection()["options"]}
    for spelling, verbose in option_aliases().items():
        where = by_verbose[verbose]["where"]
        target = heads if where in HEAD_POSITION_WHERE else options
        target[spelling] = verbose
    return heads, options


def test_ast_alias_tables_match_prelude():
    """`src/ast.asl`'s duplicated projection table equals `prelude/vocab.py`'s."""
    vocab_heads, vocab_options = _vocab_tables()
    assert _ast_table("head-spellings", "head-verbose-names") == vocab_heads
    assert _ast_table("option-spellings", "option-verbose-names") == vocab_options


def test_ast_type_table_matches_prelude():
    """The type spellings too: Nano abbreviates `Int64` to `I64`.

    Types are a third alias axis, added to the projection after heads and
    options. It reached the transcoder before it reached this parser, and the
    table check above did not cover it, so the Nano twin of a source rendered
    `I64` where its verbose twin rendered `Int64`. Pinned here so the next axis
    cannot arrive silently either.
    """
    from vocab import type_aliases
    assert _ast_table("type-spellings", "type-verbose-names") == dict(type_aliases())


def test_nano_type_spellings_resolve_to_core():
    """Every Nano type spelling renders back as the Core name it abbreviates."""
    from vocab import nano_type, resolve_type
    for core in ("Int64", "Int32", "Float64", "String", "Bool", "Unit"):
        nano = nano_type(core)
        src = f'(defun f [(x {nano})] -> {nano} :doc "d" x)'
        expected = f'(defun f [(x {resolve_type(nano)})] -> {resolve_type(nano)} :doc "d" x)'
        assert native_render(src) == expected
