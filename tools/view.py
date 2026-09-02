#!/usr/bin/env python3
"""Virtual non-mutating projection viewer for ASL and SQL ASTs (@pcp:r-8d8e)."""

import sys
from pathlib import Path
from tools.sql_cli import parse_sql_sexpr, AslSqlRenderer


def view_file_cli(path: Path, verbose: bool = True, dialect: str = "postgres") -> int:
    """Renders virtual projection of a file without disk mutations."""
    if not path.exists():
        print(f"Error: file '{path}' not found", file=sys.stderr)
        return 1

    content = path.read_text(encoding="utf-8")

    # If file represents or contains a SQL S-expression query
    if any(k in content for k in ("(select", "(q/select", "(insert", "(q/insert", "(create-table")):
        print(f"==========================================================================")
        print(f"           Virtual SQL Projection: {path.name} [{dialect.upper()}]        ")
        print(f"==========================================================================")
        try:
            tree = parse_sql_sexpr(content)
            renderer = AslSqlRenderer(dialect=dialect)
            sql, params = renderer.render_query_tree(tree)
            print(f"\n[Live Parameterized SQL ({dialect.upper()})]:")
            print(f"  {sql}")
            print(f"\n[Extracted Parameters]:")
            print(f"  {params}\n")
            return 0
        except Exception as e:
            # Fall back to standard ASL projection if not pure query tree
            pass

    # Standard ASL module virtual projection
    mode = "VERBOSE" if verbose else "NANO"
    print(f"==========================================================================")
    print(f"           Virtual ASL Projection: {path.name} ({mode})                  ")
    print(f"==========================================================================")
    print(content)
    return 0
