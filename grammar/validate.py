#!/usr/bin/env python3
"""Conformance gate for the AgentScript Core grammars.

Checks BOTH grammars against the same corpus:
  - as-lang.lark              (Earley; the constrained-decoding path)
  - tree-sitter-as-lang/      (the tooling path: AST, queries, editor support)

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

from lark import Lark
from lark.exceptions import LarkError

ROOT = Path(__file__).parent
TS_DIR = ROOT / "tree-sitter-as-lang"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"
HANDBOOK = ROOT.parent / "prelude" / "HANDBOOK.md"


def lark_parser() -> Lark:
    return Lark(
        (ROOT / "as-lang.lark").read_text(),
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


def qualified_names(path: Path, parser: Lark) -> tuple[set, set]:
    """The qualified names each grammar finds in one file.

    Agreeing on accept/reject is weaker than agreeing on the language, and the
    difference was not hypothetical: `(s/concat a b)` parsed as a four-argument
    call to `s` under Lark and as a call to `s/concat` under tree-sitter, so both
    grammars accepted the file while reading it differently. Comparing the
    verdict could never see that. This compares one piece of shape, chosen
    because it is exactly where the two lexers can disagree.
    """
    try:
        tree = parser.parse(path.read_text())
    except LarkError:
        return set(), set()
    lark_names = {str(t) for t in tree.scan_values(
        lambda v: getattr(v, "type", None) == "QUALIFIED")}

    proc = subprocess.run([str(TS_BIN), "parse", str(path.resolve())],
                          cwd=TS_DIR, capture_output=True, text=True)
    src = path.read_text().splitlines()
    ts_names = set()
    for m in re.finditer(r"\(qualified \[(\d+), (\d+)\] - \[(\d+), (\d+)\]", proc.stdout):
        r0, c0, r1, c1 = (int(x) for x in m.groups())
        if r0 == r1 and r0 < len(src):
            ts_names.add(src[r0][c0:c1])
    return lark_names, ts_names


def handbook_blocks() -> list[tuple[str, str]]:
    """Every fenced lisp block in the agent handbook, as (label, source).

    The handbook is the artifact that goes into a prompt, and nothing used to
    parse it: its foreign-call example wrote `pl/read_csv`, which the identifier
    rule cannot lex. A wrong example in the one document an agent actually reads
    is worse than no example, so the blocks are now held to the same grammar as
    the corpus.
    """
    if not HANDBOOK.exists():
        return []
    text = HANDBOOK.read_text()
    out = []
    section = "(top)"
    for chunk in re.split(r"(^## .*$)", text, flags=re.M):
        if chunk.startswith("## "):
            section = chunk[3:].strip()
            continue
        for i, block in enumerate(re.findall(r"```lisp\n(.*?)```", chunk, re.S)):
            out.append((f"HANDBOOK: {section}" + (f" [{i}]" if i else ""), block))
    return out


def main() -> int:
    if not TS_BIN.exists():
        print(f"tree-sitter CLI not found at {TS_BIN}", file=sys.stderr)
        return 1

    parser = lark_parser()
    failures: list[str] = []

    cases = [(p, True) for p in sorted((ROOT / "corpus" / "valid").glob("*.as"))]
    cases += [(p, False) for p in sorted((ROOT / "corpus" / "invalid").glob("*.as"))]
    # corpus/semantic holds programs that are well-formed to any context-free
    # grammar but violate a rule only a checker can enforce (reserved prefixes,
    # exhaustiveness, arity, types). They MUST parse; rejecting them here would
    # mean the grammar is over-tight. They are listed so the untested surface
    # stays visible instead of looking covered.
    semantic = sorted((ROOT / "corpus" / "semantic").glob("*.as"))
    cases += [(p, True) for p in semantic]

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

    if semantic:
        print(f"\nsemantic-only fixtures (parse by design, need a checker): "
              f"{', '.join(p.name for p in semantic)}")

    print()
    for path, should_parse in cases:
        if not should_parse:
            continue
        lark_names, ts_names = qualified_names(path, parser)
        if lark_names != ts_names:
            failures.append(path.name)
            only_lark = ", ".join(sorted(lark_names - ts_names)) or "-"
            only_ts = ", ".join(sorted(ts_names - lark_names)) or "-"
            print(f"{path.name:<30} SHAPE DISAGREEMENT on qualified names")
            print(f"{'':<30} -> lark only: {only_lark}")
            print(f"{'':<30} -> tree-sitter only: {only_ts}")
    print(f"qualified-name shape: {len([c for c in cases if c[1]])} file(s) compared "
          f"across both grammars")

    blocks = handbook_blocks()
    if blocks:
        print()
        with tempfile.TemporaryDirectory() as d:
            for label, src in blocks:
                f = Path(d) / (re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-") + ".as")
                f.write_text(src)
                lark_ok, lark_why = lark_accepts(parser, f)
                ts_ok, ts_why = treesitter_accepts(f)
                problems = []
                if not lark_ok:
                    problems.append(f"lark: {lark_why}")
                if not ts_ok:
                    problems.append(f"tree-sitter: {ts_why}")
                if problems:
                    failures.append(label)
                print(f"{label:<30} {('parse' if lark_ok else 'reject'):<8} "
                      f"{('parse' if ts_ok else 'reject'):<12} "
                      f"{'ok' if not problems else 'FAIL'}")
                for pr in problems:
                    print(f"{'':<30} -> {pr}")

    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
