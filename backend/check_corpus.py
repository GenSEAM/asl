#!/usr/bin/env python3
"""Every corpus program must transpile. Exit code is the failure count.

Parsing proves a program is well-formed; transpiling proves the backend actually
covers the forms the grammar admits. The two drift apart silently — a form can
be added to the grammar and accepted by the gate while no backend can lower it.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
fails = []
for f in sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.agents")):
    r = subprocess.run([sys.executable, str(ROOT / "backend" / "to_python.py"), str(f)],
                       capture_output=True, text=True)
    ok = r.returncode == 0
    print(f"  {'ok  ' if ok else 'FAIL'}  {f.name}"
          + ("" if ok else f"  {r.stderr.strip().splitlines()[-1][:70]}"))
    if not ok:
        fails.append(f.name)
print(f"\n{len(fails)} failure(s)")
sys.exit(len(fails))
