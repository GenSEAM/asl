#!/usr/bin/env python3
"""Conformance gate for the AgentScript grammars.

Checks BOTH parsers against the same corpus:
  - tree-sitter-agentscript/      (the reference tooling grammar)
  - packages/asl-parser           (the self-hosted parser, via tools.native_parser)

Every file in corpus/valid must parse under both; every file in corpus/invalid
must be rejected by both. Accepting an invalid fixture is as much a failure as
rejecting a valid one.

Checking both together is the point: the two parsers are separate artifacts that
can silently drift, and a drift would mean the self-hosted engine is enforcing a
different language than the tooling parses.

Exit code is the failure count, so CI can gate on it.
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tools.native_parser import NativeParserError, native_render  # noqa: E402

ROOT = Path(__file__).parent
TS_DIR = ROOT / "tree-sitter-agentscript"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"


def native_accepts(path: Path) -> tuple[bool, str]:
    try:
        native_render(path.read_text())
        return True, ""
    except NativeParserError as exc:
        return False, f"line {exc.line}:{exc.col}: {exc.message}"


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

    failures: list[str] = []

    cases = [(p, True) for p in sorted((ROOT / "corpus" / "valid").glob("*.agentscript"))]
    cases += [(p, False) for p in sorted((ROOT / "corpus" / "invalid").glob("*.agentscript"))]
    # corpus/semantic holds programs that are well-formed to any context-free
    # grammar but violate a rule only a checker can enforce (reserved prefixes,
    # exhaustiveness, arity, types). They MUST parse; rejecting them here would
    # mean the grammar is over-tight. checker/gate.py owns the other half of the
    # verdict: each must be rejected there, under the rule it names.
    # rglob, not glob: a rule that needs two files to violate it (an import
    # cycle) lives in a subdirectory, and a flat glob would let it skip this gate
    # while looking covered.
    semantic = sorted((ROOT / "corpus" / "semantic").rglob("*.agentscript"))
    cases += [(p, True) for p in semantic]
    # corpus/modules holds the search-path companions the module fixtures import.
    # Most of the forms this grammar gained for them live nowhere else, and no
    # gate parsed these files at all.
    cases += [(p, True) for p in sorted((ROOT / "corpus" / "modules").rglob("*.agentscript"))]

    print(f"{'fixture':<30} {'native':<8} {'tree-sitter':<12} verdict")
    print("-" * 66)

    for path, should_parse in cases:
        label = str(path.relative_to(ROOT / "corpus"))
        native_ok, native_why = native_accepts(path)
        ts_ok, ts_why = treesitter_accepts(path)

        problems = []
        if native_ok != should_parse:
            problems.append(f"native: {'accepted invalid' if native_ok else native_why}")
        if ts_ok != should_parse:
            problems.append(f"tree-sitter: {'accepted invalid' if ts_ok else ts_why}")
        if native_ok != ts_ok:
            problems.append("GRAMMARS DISAGREE")

        verdict = "ok" if not problems else "FAIL"
        if problems:
            failures.append(label)
        print(
            f"{label:<30} {('parse' if native_ok else 'reject'):<8} "
            f"{('parse' if ts_ok else 'reject'):<12} {verdict}"
        )
        for p in problems:
            print(f"{'':<30} -> {p}")

    if semantic:
        print(f"\nsemantic-only fixtures (parse by design, rejected by checker/gate.py): "
              f"{', '.join(str(p.relative_to(ROOT / 'corpus' / 'semantic')) for p in semantic)}")
    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
