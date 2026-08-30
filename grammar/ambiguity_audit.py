#!/usr/bin/env python3
"""Earley ambiguity audit for the AgentScript grammar.

Counts `_ambig` nodes over every parseable corpus fixture (valid + semantic +
modules) under an `ambiguity="explicit"` Earley parse, ratcheted in
`grammar/ambiguity.lock`.

Precedence over the cached parser in `parse.py`: this audit builds its own Lark
with `ambiguity="explicit"` so ambiguous branches surface as `_ambig` trees, and
leaves `parse.py`'s `resolve`-ambig cached parser untouched — no consumer sees
`_ambig` trees from the ordinary parse path.

The lock is exact-match (D7): `--check` fails on ANY difference from the recorded
figure, up or down, and `--write` records a new figure deliberately, in the
commit that earns it. Directional intent ("ambiguity must not regress") is
carried by the work items, not by this check.
"""
import sys
from pathlib import Path

from lark import Lark, Tree
from lark.exceptions import LarkError

from parse import GRAMMAR

ROOT = Path(__file__).parent
LOCK = ROOT / "ambiguity.lock"


def _ambig_count(tree) -> int:
    """Count `_ambig` nodes recursively; an `_ambig` subtree's children are
    re-scanned because ambiguity is transitive."""
    total = 0
    for child in tree.children:
        if isinstance(child, Tree) and child.data == "_ambig":
            total += 1 + _ambig_count(child)
        elif isinstance(child, Tree):
            total += _ambig_count(child)
    return total


def parseable_fixtures() -> list[Path]:
    """Parseable corpus fixtures: valid (flat), semantic and modules (recursive).

    Invalid fixtures are excluded by construction — they must not parse at all.
    """
    root = ROOT / "corpus"
    paths = sorted((root / "valid").glob("*.agentscript"))
    paths += sorted((root / "semantic").rglob("*.agentscript"))
    paths += sorted((root / "modules").rglob("*.agentscript"))
    return paths


def measure() -> tuple[int, dict[str, int]]:
    parser = Lark(GRAMMAR.read_text(), start="start", parser="earley",
                  ambiguity="explicit")
    per_file: dict[str, int] = {}
    total = 0
    for path in parseable_fixtures():
        try:
            tree = parser.parse(path.read_text())
        except LarkError:
            # A parseable corpus fixture that fails to parse here is a grammar
            # regression, but not an ambiguity number; surface it loudly.
            sys.stderr.write(f"ambiguity_audit: unparseable fixture {path}\n")
            continue
        n = _ambig_count(tree)
        per_file[str(path.relative_to(ROOT / "corpus"))] = n
        total += n
    return total, per_file


def print_report(total: int, per_file: dict[str, int]) -> None:
    for path, n in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
        if n:
            print(f"{n:>4}   {path}")
    print(f"\n{total} ambiguity node(s) over {len(per_file)} parseable fixture(s)")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv[1:]
    if write and args:
        sys.stderr.write("ambiguity_audit: --write takes no path argument\n")
        return 2

    total, per_file = measure()
    if write:
        LOCK.write_text(f"{total}\n")
        print_report(total, per_file)
        print(f"wrote {LOCK} = {total}")
        return 0

    if not LOCK.exists():
        sys.stderr.write(
            f"ambiguity_audit: {LOCK} missing; run with --write to record\n")
        return 2

    recorded = int(LOCK.read_text().strip())
    if total != recorded:
        print_report(total, per_file)
        sys.stderr.write(
            f"ambiguity_audit: measured {total} but lock records {recorded} "
            f"({LOCK}); exact-match (D7) — --write only in the commit that "
            f"earns the figure\n")
        return 1
    print_report(total, per_file)
    return 0


if __name__ == "__main__":
    sys.exit(main())
