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
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from lark import Token
from lark.exceptions import LarkError

from parse import parse_file, parse_text

ROOT = Path(__file__).parent
TS_DIR = ROOT / "tree-sitter-agents"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"


def lark_accepts(path: Path) -> tuple[bool, str]:
    try:
        parse_file(path)
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


# Both grammars accept every fixture while disagreeing about the shape around a
# qualified type, and this gate compares verdicts rather than trees (PCP c-40b5):
# `(s/concat x)` silently became a call to `s` once. Each probe pins one position
# where the new terminal has to be a single token in both parsers, on the same
# span, and pins that a bare `/` is still division.
PROBES = [
    ("param type", '(defun f [(x s/Shape)] -> Int64 1)',
     "QUALIFIED_TYPE", "qualified_type", 1),
    ("type application", '(defun f [(x (List s/Shape))] -> Int64 1)',
     "QUALIFIED_TYPE", "qualified_type", 1),
    ("return type", '(defun f [(x Int64)] -> s/Shape (s/circle 1.0))',
     "QUALIFIED_TYPE", "qualified_type", 1),
    ("ctor head", '(defun f [(x Int64)] -> s/Point (s/Point :x 1))',
     "QUALIFIED_TYPE", "qualified_type", 2),
    ("export entry", '(module m :doc "d" :export [Shape f])',
     "TYPE_NAME", "type_name", 1),
    ("enum pattern head", '(defun f [(x s/Shape)] -> Int64 (match x ((s/circle r) 1)))',
     "QUALIFIED", "qualified", 1),
    ("division", '(defun f [(a Int64) (b Int64)] -> Int64 (/ a b))',
     "OPERATOR", "operator", 1),
]


def lark_spans(src: str, terminal: str) -> list[tuple[int, int, int]]:
    tree = parse_text(src)
    return sorted((t.line - 1, t.column - 1, t.end_column - 1)
                  for t in tree.scan_values(
                      lambda t: isinstance(t, Token) and t.type == terminal))


def ts_spans(src: str, node: str) -> list[tuple[int, int, int]]:
    with tempfile.TemporaryDirectory() as d:
        probe = Path(d) / "probe.agents"
        probe.write_text(src + "\n")
        proc = subprocess.run([str(TS_BIN), "parse", str(probe)],
                              cwd=TS_DIR, capture_output=True, text=True)
        if proc.returncode != 0 or "ERROR" in proc.stdout:
            return []
        return sorted((int(a), int(b), int(d2)) for a, b, _c, d2 in re.findall(
            rf"\({node} \[(\d+), (\d+)\] - \[(\d+), (\d+)\]\)", proc.stdout))


def token_identity() -> list[str]:
    problems = []
    print(f"\n{'probe':<20} {'terminal':<16} {'lark':<8} {'tree-sitter':<12} verdict")
    print("-" * 66)
    for name, src, terminal, node, want in PROBES:
        lk, ts = lark_spans(src, terminal), ts_spans(src, node)
        stray = [] if terminal.startswith("QUALIFIED") else lark_spans(src, "QUALIFIED_TYPE")
        bad = []
        if len(lk) != want:
            bad.append(f"lark saw {len(lk)} {terminal}, wanted {want}")
        if lk != ts:
            bad.append(f"spans differ: lark {lk} vs tree-sitter {ts}")
        if stray:
            bad.append(f"stray QUALIFIED_TYPE at {stray}")
        print(f"{name:<20} {terminal:<16} {len(lk):<8} {len(ts):<12} "
              f"{'ok' if not bad else 'FAIL'}")
        for b in bad:
            problems.append(f"token identity/{name}: {b}")
            print(f"{'':<20} -> {b}")
    return problems


def main() -> int:
    if not TS_BIN.exists():
        print(f"tree-sitter CLI not found at {TS_BIN}", file=sys.stderr)
        return 1

    failures: list[str] = []

    cases = [(p, True) for p in sorted((ROOT / "corpus" / "valid").glob("*.agents"))]
    cases += [(p, False) for p in sorted((ROOT / "corpus" / "invalid").glob("*.agents"))]
    # corpus/semantic holds programs that are well-formed to any context-free
    # grammar but violate a rule only a checker can enforce (reserved prefixes,
    # exhaustiveness, arity, types). They MUST parse; rejecting them here would
    # mean the grammar is over-tight. checker/gate.py owns the other half of the
    # verdict: each must be rejected there, under the rule it names.
    # rglob, not glob: a rule that needs two files to violate it (an import
    # cycle) lives in a subdirectory, and a flat glob would let it skip this gate
    # while looking covered.
    semantic = sorted((ROOT / "corpus" / "semantic").rglob("*.agents"))
    cases += [(p, True) for p in semantic]
    # corpus/modules holds the search-path companions the module fixtures import.
    # Most of the forms this grammar gained for them live nowhere else, and no
    # gate parsed these files at all.
    cases += [(p, True) for p in sorted((ROOT / "corpus" / "modules").rglob("*.agents"))]

    print(f"{'fixture':<30} {'lark':<8} {'tree-sitter':<12} verdict")
    print("-" * 66)

    for path, should_parse in cases:
        label = str(path.relative_to(ROOT / "corpus"))
        lark_ok, lark_why = lark_accepts(path)
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
            failures.append(label)
        print(
            f"{label:<30} {('parse' if lark_ok else 'reject'):<8} "
            f"{('parse' if ts_ok else 'reject'):<12} {verdict}"
        )
        for p in problems:
            print(f"{'':<30} -> {p}")

    failures += token_identity()

    if semantic:
        print(f"\nsemantic-only fixtures (parse by design, rejected by checker/gate.py): "
              f"{', '.join(str(p.relative_to(ROOT / 'corpus' / 'semantic')) for p in semantic)}")
    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
