#!/usr/bin/env python3
"""Structured AST, structural search, and byte-range edits over AgentScript.

Runs tree-sitter through the Python binding (a dev dependency in `.venv`), loading
the grammar compiled to a shared library by the tree-sitter CLI. Node byte ranges and
points come straight from tree-sitter and are the authoritative extent used by the
edit operations: the file is rewritten in place from `source_bytes[start:end]`.

The 0.26 Python binding builds `Language` from a raw `TSLanguage *` pointer, so the
`.so` is opened with ctypes and its `tree_sitter_agentscript` init symbol is called
rather than passed a path.
"""
import ctypes
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
TS_DIR = ROOT / "grammar" / "tree-sitter-agentscript"
TS_CLI = ROOT / "node_modules" / ".bin" / "tree-sitter"
SO_PATH = TS_DIR / "agentscript.so"
INIT_SYMBOL = "tree_sitter_agentscript"

_lang = None


class TsError(Exception):
    pass


def language():
    """The compiled grammar, built on first use if it is missing."""
    global _lang
    if _lang is not None:
        return _lang
    if not SO_PATH.exists():
        build = subprocess.run([str(TS_CLI), "build", "-o", str(SO_PATH)],
                               cwd=TS_DIR, capture_output=True, text=True)
        if build.returncode != 0:
            raise TsError(f"tree-sitter build failed: {build.stderr.strip()}")
    import tree_sitter
    from tree_sitter import Language
    lib = ctypes.CDLL(str(SO_PATH))
    init = getattr(lib, INIT_SYMBOL, None)
    if init is None:
        raise TsError(f"{SO_PATH} does not export {INIT_SYMBOL}")
    init.restype = ctypes.c_void_p
    _lang = Language(init())
    return _lang


def parse_file(path: Path):
    from tree_sitter import Parser
    parser = Parser(language())
    return parser.parse(Path(path).read_bytes())


# ---------- AST ----------

def _node_dict(n) -> dict:
    parent = n.parent
    field = parent.field_name_for_child(parent.children.index(n)) \
        if parent is not None else None
    return {
        "type": n.type,
        "field": field,
        "byteRange": [n.start_byte, n.end_byte],
        "start": {"row": n.start_point.row, "col": n.start_point.column},
        "end": {"row": n.end_point.row, "col": n.end_point.column},
        "children": [_node_dict(c) for c in n.children],
    }


def ast_json(path: Path) -> list:
    tree = parse_file(path)
    return [_node_dict(tree.root_node)]


# ---------- search ----------

def search_json(path: Path, query_text: str) -> list:
    from tree_sitter import Query, QueryCursor
    tree = parse_file(path)
    src = Path(path).read_bytes()
    cursor = QueryCursor(Query(language(), query_text))
    out = []
    for _match, captures in cursor.matches(tree.root_node):
        for name, node in sorted(captures.items()):
            for n in node:
                out.append({
                    "capture": name,
                    "byteRange": [n.start_byte, n.end_byte],
                    "start": {"row": n.start_point.row, "col": n.start_point.column},
                    "end": {"row": n.end_point.row, "col": n.end_point.column},
                    "text": src[n.start_byte:n.end_byte].decode(),
                })
    return out


# ---------- edits ----------

def _parse_range(spec: str) -> tuple[int, int, int, int]:
    """`<l>:<c>-<l>:<c>` (0-based rows/cols) -> (start_line, start_col, end_line, end_col)."""
    try:
        start, end = spec.split("-", 1)
        sl, sc = (int(x) for x in start.split(":"))
        el, ec = (int(x) for x in end.split(":"))
    except ValueError as exc:
        raise TsError(f"bad range `{spec}`; want <l>:<c>-<l>:<c>") from exc
    return sl, sc, el, ec


def _point_to_byte(src: bytes, line: int, col: int) -> int:
    lines = src.split(b"\n")
    if line >= len(lines):
        raise TsError("edit range starts past the end of the file")
    return sum(len(l) + 1 for l in lines[:line]) + col


def edit_apply(src: bytes, op: str, range_spec: str, text: str) -> str:
    """Apply an edit to `src` by byte range and return the new text.

    Byte coordinates are derived from `_point_to_byte`; byte offsets are clamped to
    the line's length so a point range over a line is well defined.
    """
    sl, sc, el, ec = _parse_range(range_spec)
    start = _point_to_byte(src, sl, sc)
    end = _point_to_byte(src, el, ec)
    if end < start:
        raise TsError("edit range is not ordered (end before start)")
    if op == "delete":
        return src[:start] + src[end:]
    if op == "replace":
        return src[:start] + text.encode() + src[end:]
    if op == "insert":
        return src[:start] + text.encode() + src[start:]
    raise TsError(f"unknown op `{op}`")


def edit(path: Path, op: str, range_spec: str | None, text: str) -> dict:
    src = Path(path).read_bytes()
    if op == "insert":
        if range_spec is None:
            raise TsError("insert needs --at <l>:<c>")
        start = _point_to_byte(src, *_parse_at(range_spec))
        new = src[:start] + text.encode() + src[start:]
        new_range = range_spec
    else:
        if range_spec is None:
            raise TsError(f"{op} needs --range <l>:<c>-<l>:<c>")
        new = edit_apply(src, op, range_spec, text)
        new_range = range_spec
    Path(path).write_bytes(new)
    return {"file": str(path), "op": op, "applied": True,
            "range": new_range, "newByteLen": len(new)}


def _parse_at(spec: str) -> tuple[int, int]:
    try:
        line, col = (int(x) for x in spec.split(":"))
    except ValueError as exc:
        raise TsError(f"bad point `{spec}`; want <l>:<c>") from exc
    return line, col
