#!/usr/bin/env python3
"""Closure gate: every call head must be a defined builtin or a local definition.

AGENT_SPEC_CORE.md's central claim is that it is closed — a model can only be
judged on forms the document actually gave it. Closure degrades silently, because
a helper invented to illustrate one construct reads as if it must be defined
elsewhere. So it is checked, not asserted (PCP c-ca5c).

Call heads are extracted with the project's own tree-sitter grammar rather than
regexes: only a real parse distinguishes a call head from a binder position such
as a parameter or a let binding.

Exit code is the number of undefined heads.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT.parent / "prelude"))
sys.path.insert(0, str(ROOT.parent / "backend"))

import exec_coverage  # noqa: E402
from vocab import builtins as defined_builtins, special_forms  # noqa: E402
TS_DIR = ROOT / "tree-sitter-agentscript"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"
SPEC = ROOT.parent / "AGENT_SPEC_CORE.md"

# Every head shape the `call` rule admits, not only identifiers: `callee` is
# any expression, so operator heads (+, <=) and qualified heads (s/upper) were
# invisible to this gate and the closure it reported excluded them.
#
# A `defenum` case is a definition too — it is a constructor within its own
# module (§4.4). Only `defun` was collected, so the first corpus fixture to
# construct a user union case reported every one of its cases as an undefined
# call head. Nothing had, which is why the hole survived.
QUERY = """
(call callee: (ident) @callee)
(call callee: (operator) @callee)
(call callee: (qualified) @qualified)
(defun name: (ident) @definition)
(enum_case name: (ident) @definition)
"""

def run_query(paths: list[Path]) -> tuple[set[str], set[str], set[str]]:
    """The call heads, definitions and qualified heads tree-sitter finds.

    The runner's exit status is checked because the failure mode is silent in the
    dangerous direction: a missing binary, an unbuilt grammar or a query the
    grammar no longer admits all yield no output, and no output means no
    undefined head, which this gate prints as closure.
    """
    if not paths:
        raise RuntimeError("closure over no sources is not closure")
    with tempfile.TemporaryDirectory() as d:
        qfile = Path(d) / "closure.scm"
        qfile.write_text(QUERY)
        proc = subprocess.run(
            [str(TS_BIN), "query", str(qfile), *[str(p.resolve()) for p in paths]],
            cwd=TS_DIR, capture_output=True, text=True,
        )
    if proc.returncode != 0:
        raise RuntimeError(
            f"tree-sitter query failed (exit {proc.returncode}): "
            + (proc.stderr.strip().splitlines() or ["no stderr"])[-1][:160])
    calls, defs, qualified = set(), set(), set()
    bucket = {"callee": calls, "definition": defs, "qualified": qualified}
    for line in proc.stdout.splitlines():
        m = re.search(r"capture: \d+ - (callee|definition|qualified), .*text: `([^`]*)`", line)
        if m:
            bucket[m.group(1)].add(m.group(2))
    if not calls or not defs:
        raise RuntimeError(
            f"{len(paths)} source(s) yielded {len(calls)} call head(s) and {len(defs)} "
            "definition(s); the query matched nothing, so closure is unmeasured")
    return calls, defs, qualified


def main() -> int:
    sources = sorted((ROOT / "corpus" / "valid").glob("*.agentscript"))

    # Spec examples become real files so the real parser sees them.
    tmp = Path(tempfile.mkdtemp())
    for i, block in enumerate(re.findall(r"```lisp\n(.*?)```", SPEC.read_text(), re.S)):
        if "(defun" not in block and "(defschema" not in block:
            continue  # fragment, not a compilable unit
        p = tmp / f"spec_{i:02d}.agentscript"
        p.write_text(block)
        sources.append(p)

    calls, local, qualified = run_query(sources)
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
