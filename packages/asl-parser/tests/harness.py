"""Execution harness for the asl-parser package tests.

`run_asl` transpiles an AgentScript driver to Python with the project's own
backend, compiles the output, copies the runtime beside it and executes it with
`runpy.run_path`, returning the namespace the driver populated. A test asserts
against values the DRIVER computes — never against a Python mirror of the
parser's logic.

Both roots are passed to the transpiler on purpose. The `src/` root is what a
driver's `:import [(lexer :as lex)]` resolves against: `modules.find` maps a
module path to `root/<path>.asl`, and the library modules live under `src/`. The
fixture root is the second search location, so a fixture-local module a driver
imports can also resolve. `Transpiler.link` resolves every transitive dependency
against the same roots; trimming either root breaks the cross-module link
(`ast` imports `lexer` and `reader`), which would surface as a linker error
rather than a wrong value.
"""
import py_compile
import runpy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))

from to_python import Transpiler  # noqa: E402

SRC = ROOT / "packages" / "asl-parser" / "src"
RUNTIME = ROOT / "backend" / "runtime.py"


def run_asl(driver_path) -> dict:
    driver = Path(driver_path)
    emitted = Transpiler().transpile(driver.read_text(), path=driver,
                                     roots=[SRC, driver.parent])
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        tmp = Path(d)
        (tmp / "runtime.py").write_text(RUNTIME.read_text())
        out = tmp / "cand.py"
        out.write_text(emitted)
        py_compile.compile(str(out), doraise=True)
        sys.path.insert(0, str(tmp))
        try:
            return runpy.run_path(str(out))
        finally:
            sys.path.remove(str(tmp))
