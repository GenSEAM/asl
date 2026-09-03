#!/usr/bin/env python3
"""Module interface compressor for AgentScript.

Keeps the part of a module a caller has to read — the header, every `defschema`
and `defenum`, and each `defun`'s signature and docstring — and drops the bodies.

It works from the parse, not from the text. Matching `(defun` as a literal missed
every module written in the Nano projection, which is the storage default, so the
storage default compressed to nothing; and the elided body it wrote was
`(panic "interface")`, a call to a name the vocabulary does not define, so the
output was not AgentScript. The stub is a call to the declaration itself: it is
the one expression that has the declaration's own return type whatever that type
is, and the vocabulary has no bottom to spell instead.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from lark import Token, Tree  # noqa: E402
from lark.exceptions import LarkError  # noqa: E402

from parse import parse_text  # noqa: E402


class CompressError(Exception):
    """The source could not be parsed, so there is no interface to extract."""


def compress_module(source: str) -> str:
    """Compress full AgentScript module text into an interface signature."""
    try:
        tree = parse_text(source)
    except LarkError as exc:
        first = str(exc).splitlines()[0] if str(exc) else exc.__class__.__name__
        raise CompressError(f"does not parse: {first}") from None

    out = []
    for top in tree.children:
        node = _unwrap(top)
        if not isinstance(node, Tree):
            continue
        out.append(_signature(source, node) if node.data == "defun"
                   else _span(source, node))
    return "\n\n".join(out) + ("\n" if out else "")


def _unwrap(n):
    while isinstance(n, Tree) and n.data == "toplevel" and len(n.children) == 1:
        n = n.children[0]
    return n


def _span(source: str, n) -> str:
    """`n` exactly as it was written, delimiters included."""
    return source[_start(n):_end(n)]


def _start(n) -> int:
    return n.start_pos if isinstance(n, Token) else n.meta.start_pos


def _end(n) -> int:
    return n.end_pos if isinstance(n, Token) else n.meta.end_pos


def _signature(source: str, n: Tree) -> str:
    """A `defun`'s header exactly as written, then a body that stands in for its own."""
    kids = list(n.children)
    ret = next(i for i, c in enumerate(kids) if isinstance(c, Tree) and c.data == "type")
    doc = next((c for c in kids[ret + 1:]
                if isinstance(c, Tree) and c.data == "doc_opt"), None)
    header = source[_start(n):_end(doc if doc is not None else kids[ret])]
    return f"{header}\n  {_stub(kids)})"


def _stub(kids: list) -> str:
    """A call to the declaration being stubbed, with its own parameters as arguments."""
    name = next(c for c in kids if isinstance(c, Token) and c.type == "IDENT")
    params = next(c for c in kids if isinstance(c, Tree) and c.data == "params")
    args = [str(p.children[0]) for p in params.children
            if isinstance(p, Tree) and p.data == "param"]
    return "(" + " ".join([str(name), *args]) + ")"
