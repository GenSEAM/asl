#!/usr/bin/env python3
"""Coverage gate: every declared builtin must appear in at least one example.

The closure gate (grammar/closure_audit.py) checks one direction — no example
calls an undefined name. This checks the converse, which PCP l-3434 recorded and
which is the direction that degrades generation quality: an example is what an
agent learns a call shape from, so a builtin declared in a table and never shown
in use is close to an absent one.

Extraction uses the project's own tree-sitter grammar, not regexes, because only
a real parse tells a call head from a binder. Three capture kinds are needed:
ordinary builtins are `ident` heads, arithmetic and comparison are `operator`
heads, and ok/err/some/none/list/pair have their own grammar rule because their
heads double as pattern heads.

Exit code is the number of unexercised builtins.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
TS_DIR = ROOT / "grammar" / "tree-sitter-as-lang"
TS_BIN = ROOT / "node_modules" / ".bin" / "tree-sitter"
PRELUDE = ROOT / "prelude" / "prelude.json"

# Every tree of hand-written AgentScript. Adding a source here is how a new
# example starts counting toward coverage.
SOURCE_DIRS = [ROOT / "grammar" / "corpus" / "valid",
               ROOT / "examples",
               ROOT / "bench",
               ROOT / "backend" / "t"]

QUERY = """
(call callee: (ident) @ident_head)
(call callee: (operator) @operator_head)
(constructor_call) @ctor_form
"""


def sources() -> list[Path]:
    out: list[Path] = []
    for d in SOURCE_DIRS:
        if d.exists():
            out += sorted(d.rglob("*.as"))
    return out


def exercised(paths: list[Path]) -> set[str]:
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as fh:
        fh.write(QUERY)
        qfile = fh.name
    proc = subprocess.run(
        [str(TS_BIN), "query", qfile, *[str(p.resolve()) for p in paths]],
        cwd=TS_DIR, capture_output=True, text=True)
    names: set[str] = set()
    for line in proc.stdout.splitlines():
        m = re.search(r"capture: \d+ - (\w+), .*text: `(.*)`", line)
        if not m:
            continue
        kind, text = m.group(1), m.group(2)
        if kind == "ctor_form":
            # The head is an anonymous token, so it is read off the form's text.
            head = re.match(r"\(\s*([a-z]+)", text)
            if head:
                names.add(head.group(1))
        else:
            names.add(text)
    return names


def main() -> int:
    if not TS_BIN.exists():
        print(f"tree-sitter CLI not found at {TS_BIN}", file=sys.stderr)
        return 1
    prelude = json.loads(PRELUDE.read_text())
    declared = [b["name"] for b in prelude["builtins"]]
    used = exercised(sources())
    missing = [n for n in declared if n not in used]

    print(f"sources scanned      : {len(sources())}")
    print(f"builtins declared    : {len(declared)}")
    print(f"builtins exercised   : {len(declared) - len(missing)}/{len(declared)}"
          f"  ({100 * (len(declared) - len(missing)) // max(len(declared), 1)}%)")
    print()
    if missing:
        by_sec: dict[str, list[str]] = {}
        for b in prelude["builtins"]:
            if b["name"] in missing:
                by_sec.setdefault(b["sec"], []).append(b["name"])
        print("NEVER SHOWN IN AN EXAMPLE:")
        for sec, names in by_sec.items():
            print(f"  {sec}: " + " ".join(names))
    else:
        print("OK: every declared builtin appears in an example")
    return len(missing)


if __name__ == "__main__":
    sys.exit(main())
