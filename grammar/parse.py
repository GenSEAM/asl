#!/usr/bin/env python3
"""One parser for every tool that reads AgentScript source.

Three copies of this construction had drifted apart on their arguments, and a
checker that disagreed with a backend about what a program is would report
diagnostics against a tree the backend never sees.

Positions are propagated because a diagnostic without a line number is not
actionable; Lark only fills tree-level positions when asked.
"""
from pathlib import Path

from lark import Lark, Token, Tree

GRAMMAR = Path(__file__).parent / "agentscript.lark"

# Form heads are named terminals, so Lark keeps them as children. Filtering them
# centrally beats per-handler index arithmetic, which breaks the moment an
# optional child is added to a rule.
FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", "MODULE", "IF", "COND", "MATCH",
           "TRY", "LET", "FN", "ARROW", "ELSE_KW", "CASE_KW", "FIELD_KW",
           "DOC_KW", "EXPORT_KW", "IMPORT_KW", "AS_KW", "DEFAULT_KW", "JSON_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR", "BANG", "TAG_HEAD"}

_parser: Lark | None = None


def parser() -> Lark:
    global _parser
    if _parser is None:
        _parser = Lark(GRAMMAR.read_text(), start="start", parser="earley",
                       ambiguity="resolve", propagate_positions=True)
    return _parser


def parse_text(src: str) -> Tree:
    return parser().parse(src)


def parse_file(path: Path) -> Tree:
    return parse_text(Path(path).read_text())


def kids(node) -> list:
    return [k for k in node.children if not (isinstance(k, Token) and k.type in FORM_KW)]


def tok(node) -> str:
    return str(node) if isinstance(node, Token) else str(node.children[0])


def position(node) -> tuple[int, int]:
    """Line and column of a token or tree, 1-based; (0, 0) when Lark has none."""
    if isinstance(node, Token):
        return node.line or 0, node.column or 0
    meta = getattr(node, "meta", None)
    if meta is not None and not getattr(meta, "empty", True):
        return meta.line, meta.column
    for child in node.children:
        line, col = position(child)
        if line:
            return line, col
    return 0, 0
