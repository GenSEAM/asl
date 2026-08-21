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
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent
TS_DIR = ROOT / "tree-sitter-as-lang"
TS_BIN = ROOT.parent / "node_modules" / ".bin" / "tree-sitter"
SPEC = ROOT.parent / "AGENT_SPEC_CORE.md"

QUERY = """
(call callee: (ident) @callee)
(defun name: (ident) @definition)
"""

def special_forms() -> set[str]:
    """Grammar productions, not calls; they never reach a `call` node."""
    sf = json.loads((ROOT.parent / "prelude" / "prelude.json").read_text())["special_forms"]
    return {n for group in sf.values() for n in group}


def defined_builtins() -> set[str]:
    """Read the vocabulary from its single source of truth.

    This previously regexed the specification's markdown tables, which made the
    gate depend on prose formatting: a reworded table silently changed what
    counted as defined.
    """
    prelude = json.loads((ROOT.parent / "prelude" / "prelude.json").read_text())
    return {b["name"] for b in prelude["builtins"]}


def run_query(paths: list[Path]) -> tuple[set[str], set[str]]:
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as fh:
        fh.write(QUERY)
        qfile = fh.name
    proc = subprocess.run(
        [str(TS_BIN), "query", qfile, *[str(p.resolve()) for p in paths]],
        cwd=TS_DIR, capture_output=True, text=True,
    )
    calls, defs = set(), set()
    for line in proc.stdout.splitlines():
        m = re.search(r"capture: \d+ - (callee|definition), .*text: `([^`]*)`", line)
        if m:
            (calls if m.group(1) == "callee" else defs).add(m.group(2))
    return calls, defs


def main() -> int:
    sources = sorted((ROOT / "corpus" / "valid").glob("*.as"))

    # Spec examples become real files so the real parser sees them.
    tmp = Path(tempfile.mkdtemp())
    for i, block in enumerate(re.findall(r"```lisp\n(.*?)```", SPEC.read_text(), re.S)):
        if "(defun" not in block and "(defschema" not in block:
            continue  # fragment, not a compilable unit
        p = tmp / f"spec_{i:02d}.as"
        p.write_text(block)
        sources.append(p)

    calls, local = run_query(sources)
    builtins = defined_builtins()
    known = builtins | local | special_forms()
    undefined = sorted(calls - known)

    print(f"builtins defined in section 6 : {len(builtins)}")
    print(f"definitions found in sources  : {len(local)}")
    print(f"distinct call heads           : {len(calls)}")
    print(f"exercised builtins            : {len(calls & builtins)}/{len(builtins)}"
          f"  ({100*len(calls & builtins)//max(len(builtins),1)}%)")
    print()
    if undefined:
        print("UNDEFINED CALL HEADS:")
        for u in undefined:
            print(f"   {u}")
    else:
        print("OK: spec and corpus are closed")
    return len(undefined)


if __name__ == "__main__":
    sys.exit(main())
