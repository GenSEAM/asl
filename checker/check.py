#!/usr/bin/env python3
"""Semantic checker CLI: AgentScript source in, diagnostics out.

Exit code is the diagnostic count, matching the other gates so CI can gate on it.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from resolve import check_file  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--root", action="append", default=[],
                    help="source root for module resolution; repeatable. "
                         "A file's own directory is always searched.")
    args = ap.parse_args()

    total = 0
    for f in args.files:
        for d in check_file(Path(f), [Path(r) for r in args.root]):
            print(d)
            total += 1
    return total


if __name__ == "__main__":
    sys.exit(main())
