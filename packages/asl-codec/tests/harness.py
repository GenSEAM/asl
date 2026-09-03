"""Execution harness for the asl-codec package tests.

`run_asl` transpiles an AgentScript driver to Python with the project's own
backend, compiles the output, copies the runtime beside it and executes it with
`runpy.run_path`, returning the namespace the driver populated. A test asserts
against values the DRIVER computes — never against a Python mirror of the
reader's logic, which would only prove the mirror agrees with itself.

Three roots are passed, and each is load-bearing. `CORE` is where the driver's
`:import [(asn :as a)]` and `(asn-check :as c)` resolve. `PARSER_SRC` is where
`asn.asl`'s own `(lexer :as lx)` resolves: ASN reuses packages/asl-parser's
scanner rather than forking a second one, so the link crosses packages. The
driver's own directory comes first, as it does for the checker CLI.
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

CORE = ROOT / "packages" / "asl-codec" / "src" / "core"
PARSER_SRC = ROOT / "packages" / "asl-parser" / "src"
RUNTIME = ROOT / "backend" / "runtime.py"
CORPUS = ROOT / "grammar" / "corpus" / "asn"


def run_asl(driver_path) -> dict:
    driver = Path(driver_path)
    emitted = Transpiler().transpile(driver.read_text(), path=driver,
                                     roots=[CORE, PARSER_SRC, driver.parent])
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
