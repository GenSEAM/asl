#!/usr/bin/env python3
"""Closure gate: every call head must be a defined builtin or a local definition.

AGENT_SPEC_CORE.md's central claim is that it is closed — a model can only be
judged on forms the document actually gave it. Closure degrades silently, because
a helper invented to illustrate one construct reads as if it must be defined
elsewhere. So it is checked, not asserted (PCP c-ca5c).

Call heads are extracted with the project's own self-hosted native AST rather
than regexes: only a real parse distinguishes a call head from a binder position
such as a parameter or a let binding. The walker lives in the parser driver
(`packages/asl-parser/tests/reader_test.asl`) and is grade-checked against a
live tree-sitter baseline by `tools/tests/test_closure_native_equivalence.py`,
so a port that moves these counts silently fails that suite.

Exit code is the number of undefined heads.
"""
import functools
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent
HARNESS_DIR = ROOT.parent / "packages" / "asl-parser" / "tests"
sys.path.insert(0, str(HARNESS_DIR))
sys.path.insert(0, str(ROOT.parent / "prelude"))
sys.path.insert(0, str(ROOT.parent / "backend"))

from harness import run_asl  # noqa: E402
import exec_coverage  # noqa: E402
from vocab import builtins as defined_builtins, special_forms  # noqa: E402
SPEC = ROOT.parent / "AGENT_SPEC_CORE.md"


@functools.lru_cache(maxsize=None)
def _driver() -> dict:
    """The transpiled parser driver, loaded once per process."""
    return run_asl(HARNESS_DIR / "reader_test.asl")


def _native_buckets(src: str) -> tuple[set, set, set]:
    """The native walker's calls, definitions and qualified heads for one source.

    A parse error surfaces as an exception rather than as empty buckets: no
    output means no undefined head, which this gate would print as closure.
    """
    res = _driver()["closure_heads"](src)
    if res[0] == "err":
        e = res[1]
        raise RuntimeError(f"{e['line']}:{e['col']}: {e['msg']}")
    if res[0] != "ok":
        raise RuntimeError(f"unexpected result tag: {res[0]}")
    b = res[1]
    return set(b["calls"]), set(b["defs"]), set(b["qualified"])


def collect_sources() -> list[Path]:
    """The corpus fixtures and spec examples the gate audits.

    Spec examples become real files so the real parser sees them; a block
    marked `not-agentscript` is deliberately not a program and is skipped.
    """
    sources = sorted((ROOT / "corpus" / "valid").glob("*.agentscript"))
    tmp = Path(tempfile.mkdtemp())
    text = SPEC.read_text()
    for i, m in enumerate(re.finditer(r"```lisp\n(.*?)```", text, re.S)):
        block = m.group(1)
        if "(defun" not in block and "(defschema" not in block:
            continue  # fragment, not a compilable unit
        if re.search(r"<!-- not-agentscript:.*?-->\s*$", text[:m.start()], re.S):
            continue
        p = tmp / f"spec_{i:02d}.agentscript"
        p.write_text(block)
        sources.append(p)
    return sources


def main() -> int:
    sources = collect_sources()
    calls, local, qualified = set(), set(), set()
    for p in sources:
        c, d, q = _native_buckets(p.read_text())
        calls |= c
        local |= d
        qualified |= q
    if not calls or not local:
        raise RuntimeError(
            f"{len(sources)} source(s) yielded {len(calls)} call head(s) and "
            f"{len(local)} definition(s); the walker matched nothing, so "
            "closure is unmeasured")
    builtins = defined_builtins()
    known = builtins | local | special_forms()
    undefined = sorted(calls - known)

    # A qualified head resolves in another module, which this gate cannot see;
    # the checker's rule 9 owns that. Counted so the number is not silently zero.
    print(f"qualified heads (checker owns)  : {len(qualified)}")
    print(f"builtins defined in section 6 : {len(builtins)}")
    print(f"definitions found in sources  : {len(local)}")
    print(f"distinct call heads           : {len(calls)}")
    # Not "how many builtins are mentioned": that number was wrong in both
    # directions, and a call head in a branch no case takes still counts toward
    # it. The figure comes from the tracer, which counts evaluation.
    coverage, stats = exec_coverage.check()
    print(f"executed builtins             : {len(stats['executed'])}/{stats['declared']}"
          f"  ({stats['pct']}%)")
    print()
    for c in coverage:
        print("  " + c)
    if undefined:
        print("UNDEFINED CALL HEADS:")
        for u in undefined:
            print(f"   {u}")
    elif not coverage and not stats["unreached"]:
        print("OK: spec and corpus are closed, and every builtin is executed")
    return len(undefined) + len(coverage)


if __name__ == "__main__":
    sys.exit(main())
