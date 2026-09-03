#!/usr/bin/env python3
"""Bidirectional projection transcoder: Nano <-> Verbose (@pcp:d-1eed, @pcp:r-8d8e).

The projection covers three kinds of name — declaration heads, option keywords and
type aliases (AGENT_SPEC_CORE.md §2.1) — and each is significant only where the
grammar admits it. Text substitution cannot tell those positions apart: it rewrote
the record key of `(P :x 1)` into `:export`, and it would rewrite an expression
that happens to be spelled like a type. The parse has already drawn every one of
those lines, so each rewrite here is the span of a token the grammar classified.

Nothing is reprinted. The output is the input with those spans replaced, so
comments, blank lines and indentation survive byte for byte; a formatter is what
reflows a file, and a transcoder that also reflowed would not be reversible. A
source that does not parse is refused rather than rewritten blind.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))

from lark import Token, Tree  # noqa: E402
from lark.exceptions import LarkError  # noqa: E402

from parse import FORM_KW, parse_text  # noqa: E402
from vocab import (head_aliases, nano_head, nano_option,  # noqa: E402
                   nano_type, option_aliases, reserved_widths, resolve_type)

NANO = "nano"
VERBOSE = "verbose"

_NANO_NAMES = {NANO, "ultra-nano", "compact", "agent"}
_VERBOSE_NAMES = {VERBOSE, "human", "full"}


class TranscodeError(Exception):
    """The source could not be parsed, so no rewrite is safe."""


def normalize_target(name: str) -> str:
    if name in _NANO_NAMES:
        return NANO
    if name in _VERBOSE_NAMES:
        return VERBOSE
    raise TranscodeError(f"unknown projection `{name}`; want nano or verbose")


def _rewrites(target: str) -> dict[str, str]:
    """Every spelling of an aliased form, mapped to its spelling in `target`."""
    table = {}
    for spelling, verbose in head_aliases().items():
        table[spelling] = verbose if target == VERBOSE else nano_head(verbose)
    for spelling, verbose in option_aliases().items():
        table[spelling] = verbose if target == VERBOSE else nano_option(verbose)
    return table


def _type_projector(target: str):
    """A type name in the `target` projection: `I64` <-> `Int64`, `Num` -> `F64`.

    A reserved width is left exactly as written in both directions. `F32` names a
    width Core has no type for; resolving it to `Float64` would erase the only
    record of what the author asked for, and it has to survive a round trip.
    """
    reserved = set(reserved_widths())

    def project(name: str) -> str:
        if name in reserved:
            return name
        core = resolve_type(name)
        return core if target == VERBOSE else nano_type(core)

    return project


def _bound_type_params(node: Tree) -> frozenset[str]:
    """Type variables this declaration binds, which no table may rewrite.

    A name is a type variable because it was declared one, so `{Str} f [(x Str)]`
    is a function over a variable and not over `String` — expanding it there would
    turn a polymorphic signature into a concrete one.
    """
    for child in node.children:
        if isinstance(child, Tree) and child.data == "type_params":
            return frozenset(str(t) for t in child.children if isinstance(t, Token))
    return frozenset()


def _collect(node: Tree, bound: frozenset[str], keywords: dict, project, edits: list) -> None:
    """Every token the projection renames, as (start, end, replacement).

    `FORM_KW` is the set of terminals the grammar gives a form keyword its own name
    for, and a `type` node is the only place a `TYPE_NAME` names a type rather than
    a declaration, a constructor or an export. A record key is a `KEYWORD` and an
    identifier an `IDENT`, so neither can reach a table however it is spelled.
    """
    bound = bound | _bound_type_params(node)
    in_type = node.data == "type"
    for child in node.children:
        if isinstance(child, Tree):
            _collect(child, bound, keywords, project, edits)
        elif child.type in FORM_KW:
            _record(edits, child, keywords.get(str(child)))
        elif in_type and child.type == "TYPE_NAME" and str(child) not in bound:
            _record(edits, child, project(str(child)))


def _record(edits: list, tok: Token, want: str | None) -> None:
    if want is not None and want != str(tok) and tok.start_pos is not None:
        edits.append((tok.start_pos, tok.end_pos, want))


def transcode_text(src: str, target: str = NANO, path: str = "<stdin>") -> str:
    """`src` in the `target` projection, byte-identical everywhere else."""
    target = normalize_target(target)
    try:
        tree = parse_text(src)
    except LarkError as exc:
        first = str(exc).splitlines()[0] if str(exc) else exc.__class__.__name__
        raise TranscodeError(f"{path}: does not parse: {first}") from None

    edits: list[tuple[int, int, str]] = []
    _collect(tree, frozenset(), _rewrites(target), _type_projector(target), edits)
    edits.sort()

    out, cut = [], 0
    for start, end, want in edits:
        out.append(src[cut:start])
        out.append(want)
        cut = end
    out.append(src[cut:])
    return "".join(out)


def to_ultra_nano(text: str) -> str:
    """Compacts ASL source into the Nano projection, the on-disk default."""
    return transcode_text(text, NANO)


def to_verbose(text: str) -> str:
    """Expands ASL source into the self-describing Verbose projection for humans."""
    return transcode_text(text, VERBOSE)


def transcode_file(path: Path, target_dialect: str = NANO, in_place: bool = False) -> str:
    """Transcodes a file between the nano and verbose projections."""
    content = Path(path).read_text(encoding="utf-8")
    out = transcode_text(content, target_dialect, str(path))
    if in_place and out != content:
        Path(path).write_text(out, encoding="utf-8")
    return out


def run_transcode_cli(args) -> int:
    path = Path(args.file)
    if not path.exists():
        print(f"Error: file {path} not found", file=sys.stderr)
        return 1

    target = VERBOSE if getattr(args, "verbose", False) else NANO
    in_place = getattr(args, "in_place", False)
    try:
        result = transcode_file(path, target_dialect=target, in_place=in_place)
    except TranscodeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if not in_place:
        print(result, end="" if result.endswith("\n") else "\n")
    else:
        print(f"Transcoded {path.name} to {target.upper()} in-place.")
    return 0


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="ASL Dual-Projection Transcoder")
    parser.add_argument("file", help="path to ASL file")
    parser.add_argument("--to", dest="target", choices=[NANO, VERBOSE], default=NANO)
    parser.add_argument("-i", "--in-place", action="store_true", help="modify file in place")
    args = parser.parse_args()
    args.verbose = (args.target == VERBOSE)
    sys.exit(run_transcode_cli(args))
