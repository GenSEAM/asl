#!/usr/bin/env python3
"""Phase 5 derived oracle: predict a driver-wrapped corpus fixture's stdout.

The interpreter (crates/agentscript-interp) is compared against three witnesses
across phase 5. This is one of them: for a fixture that does not itself declare
`main` (I3/I4/I5/I6 map), the only way to observe its behaviour is to wrap it in
a synthesised `main` that calls the fixture's exported entries and prints the
results its `; run:` header asserts. The wrap body is a checked-in artifact
under .plans/phase-5/drivers/<fixture>.main, so the oracle's prediction and the
interpreter's input are the same text, not two conventions that can drift.

The oracle composes fixture + wrap body, transpiles the result with the project's
own to_python.py, runs it under backend/runtime.py, and prints the resulting
stdout. It never consults the interpreter: prediction and implementation are
independent by construction.

CLI: oracle.py [--root DIR]... [--emit] FIXTURE
  default  prints the expected stdout of the driver-wrapped program
  --emit   prints the driver-wrapped AgentScript source to stdout, so a gate can
           materialise exactly the program whose output the oracle predicts
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES = ROOT / "grammar" / "corpus" / "valid"
DRIVERS = Path(__file__).resolve().parent / "drivers"
RUNTIME = ROOT / "backend" / "runtime.py"

# A defun whose name is main (optionally marked `!`), anywhere in a fixture.
RE_MAIN = re.compile(r"\(defun\s*!?\s*main[ \t\n\[>]")

sys.path.insert(0, str(ROOT / "backend"))


def wrapped_source(fixture: str, roots: list[Path]) -> str:
    fixture_path = FIXTURES / f"{fixture}.agentscript"
    if not fixture_path.exists():
        raise SystemExit(f"no such fixture: {fixture}")
    src = fixture_path.read_text()
    # A fixture that already declares main is itself a program: running the bare
    # fixture produces its output, and appending another main would define it
    # twice. Only non-main fixtures go through the driver wrap.
    if "main" in RE_MAIN.findall(src):
        return src
    driver = DRIVERS / f"{fixture}.main"
    wrap = driver.read_text() if driver.exists() else ""
    return src.rstrip("\n") + "\n" + wrap + "\n" if wrap else src


def expected_stdout(fixture: str, roots: list[Path]) -> str:
    from to_python import Transpiler
    wrapped = wrapped_source(fixture, roots)
    fixture_path = FIXTURES / f"{fixture}.agentscript"
    py = Transpiler().transpile(wrapped, path=fixture_path, roots=roots)
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "runtime.py").write_text(RUNTIME.read_text())
        (d / "cand.py").write_text(py)
        r = subprocess.run([sys.executable, str(d / "cand.py")],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(f"oracle {fixture}: python exited {r.returncode}:\n{r.stderr}")
        return r.stdout


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--root", action="append", default=[],
                    help="source root for module resolution; repeatable")
    ap.add_argument("--emit", action="store_true",
                    help="print the driver-wrapped AgentScript source instead of stdout")
    args = ap.parse_args()
    roots = [Path(r) for r in args.root]
    if args.emit:
        sys.stdout.write(wrapped_source(args.fixture, roots))
    else:
        sys.stdout.write(expected_stdout(args.fixture, roots))
    return 0


if __name__ == "__main__":
    sys.exit(main())
