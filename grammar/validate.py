#!/usr/bin/env python3
"""Conformance gate for the AgentS-Core grammars.

Checks BOTH grammars against the same corpus:
  - agents.lark              (Earley; the constrained-decoding path)
  - tree-sitter-agents/      (the tooling path: AST, queries, editor support)

Every file in corpus/valid must parse under both; every file in corpus/invalid
must be rejected by both. Accepting an invalid fixture is as much a failure as
rejecting a valid one.

Checking both together is the point: the two grammars are separate artifacts that
can silently drift, and a drift would mean the constrained-decoding arm of
EXPERIMENT.md is enforcing a different language than the tooling parses.

Exit code is the failure count, so CI can gate on it.
"""
import subprocess
import sys
from pathlib import Path

from lark import Lark
from lark.exceptions import LarkError

ROOT = Path(__file__).parent
TS_DIR = ROOT / "tree-sitter-agents"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"


def lark_parser() -> Lark:
    return Lark(
        (ROOT / "agents.lark").read_text(),
        start="start",
        parser="earley",
        ambiguity="resolve",
    )


def lark_accepts(parser: Lark, path: Path) -> tuple[bool, str]:
    try:
        parser.parse(path.read_text())
        return True, ""
    except LarkError as exc:
        return False, str(exc).splitlines()[0]


def treesitter_accepts(path: Path) -> tuple[bool, str]:
    """tree-sitter exits non-zero and prints ERROR/MISSING nodes on failure."""
    proc = subprocess.run(
        [str(TS_BIN), "parse", str(path.resolve())],
        cwd=TS_DIR,
        capture_output=True,
        text=True,
    )
    out = proc.stdout + proc.stderr
    ok = proc.returncode == 0 and "ERROR" not in out and "MISSING" not in out
    detail = "" if ok else next(
        (ln.strip() for ln in out.splitlines() if "ERROR" in ln or "MISSING" in ln),
        out.strip().splitlines()[0] if out.strip() else "unknown",
    )
    return ok, detail


def main() -> int:
    if not TS_BIN.exists():
        print(f"tree-sitter CLI not found at {TS_BIN}", file=sys.stderr)
        return 1

    parser = lark_parser()
    failures: list[str] = []

    cases = [(p, True) for p in sorted((ROOT / "corpus" / "valid").glob("*.agents"))]
    cases += [(p, False) for p in sorted((ROOT / "corpus" / "invalid").glob("*.agents"))]

    print(f"{'fixture':<30} {'lark':<8} {'tree-sitter':<12} verdict")
    print("-" * 66)

    for path, should_parse in cases:
        lark_ok, lark_why = lark_accepts(parser, path)
        ts_ok, ts_why = treesitter_accepts(path)

        problems = []
        if lark_ok != should_parse:
            problems.append(f"lark: {'accepted invalid' if lark_ok else lark_why}")
        if ts_ok != should_parse:
            problems.append(f"tree-sitter: {'accepted invalid' if ts_ok else ts_why}")
        if lark_ok != ts_ok:
            problems.append("GRAMMARS DISAGREE")

        verdict = "ok" if not problems else "FAIL"
        if problems:
            failures.append(path.name)
        print(
            f"{path.name:<30} {('parse' if lark_ok else 'reject'):<8} "
            f"{('parse' if ts_ok else 'reject'):<12} {verdict}"
        )
        for p in problems:
            print(f"{'':<30} -> {p}")

    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
