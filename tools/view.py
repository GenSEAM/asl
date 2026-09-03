#!/usr/bin/env python3
"""Virtual non-mutating projection viewer for ASL and SQL ASTs (@pcp:r-8d8e)."""

import sys
from pathlib import Path

from tools.sql_cli import parse_sql_sexpr, AslSqlRenderer
from tools.transcoder import NANO, VERBOSE, TranscodeError, transcode_text

RULE = "=" * 74


def view_file_cli(path: Path, verbose: bool = True, dialect: str = "postgres") -> int:
    """Renders virtual projection of a file without disk mutations."""
    if not path.exists():
        print(f"Error: file '{path}' not found", file=sys.stderr)
        return 1

    content = path.read_text(encoding="utf-8")

    # If file represents or contains a SQL S-expression query
    if any(k in content for k in ("(select", "(q/select", "(insert", "(q/insert", "(create-table")):
        print(RULE)
        print(f"           Virtual SQL Projection: {path.name} [{dialect.upper()}]")
        print(RULE)
        try:
            tree = parse_sql_sexpr(content)
            renderer = AslSqlRenderer(dialect=dialect)
            sql, params = renderer.render_query_tree(tree)
            print(f"\n[Live Parameterized SQL ({dialect.upper()})]:")
            print(f"  {sql}")
            print("\n[Extracted Parameters]:")
            print(f"  {params}\n")
            return 0
        except Exception:
            # Fall back to standard ASL projection if not pure query tree
            pass

    # The projection is computed, not announced: the banner used to head the
    # file's own unconverted text, so a Nano module read VERBOSE (@pcp:d-1eed).
    target = VERBOSE if verbose else NANO
    try:
        projected = transcode_text(content, target, str(path))
    except TranscodeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(RULE)
    print(f"           Virtual ASL Projection: {path.name} ({target.upper()})")
    print(RULE)
    print(projected, end="" if projected.endswith("\n") else "\n")
    return 0
