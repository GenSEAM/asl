"""Execution harness for the asl-checker package tests."""
import py_compile
import runpy
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))

from to_python import Transpiler  # noqa: E402

SRC_CHECKER = ROOT / "packages" / "asl-checker" / "src"
SRC_PARSER = ROOT / "packages" / "asl-parser" / "src"
RUNTIME = ROOT / "backend" / "runtime.py"


def run_asl(driver_path) -> dict:
    driver = Path(driver_path)
    emitted = Transpiler().transpile(
        driver.read_text(),
        path=driver,
        roots=[SRC_CHECKER, SRC_PARSER, driver.parent]
    )
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
