#!/usr/bin/env python3
"""Conformance check for the AgentS-Core Lark grammar.

Every file in corpus/valid must parse; every file in corpus/invalid must be
rejected. A grammar that accepts an invalid fixture is as broken as one that
rejects a valid program, so both directions are failures.

Exit code is the number of failures, so CI can gate on it.
"""
import sys
from pathlib import Path

from lark import Lark
from lark.exceptions import LarkError

ROOT = Path(__file__).parent


def load_parser() -> Lark:
    return Lark(
        (ROOT / "agents.lark").read_text(),
        start="start",
        parser="earley",
        ambiguity="resolve",
    )


def main() -> int:
    parser = load_parser()
    failures = []

    for path in sorted((ROOT / "corpus" / "valid").glob("*.agents")):
        try:
            parser.parse(path.read_text())
            print(f"  ok    {path.name}")
        except LarkError as exc:
            failures.append(path.name)
            print(f"  FAIL  {path.name}: should parse but did not")
            print(f"        {str(exc).splitlines()[0]}")

    for path in sorted((ROOT / "corpus" / "invalid").glob("*.agents")):
        try:
            parser.parse(path.read_text())
            failures.append(path.name)
            print(f"  FAIL  {path.name}: should be rejected but parsed")
        except LarkError:
            print(f"  ok    {path.name} (rejected)")

    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
