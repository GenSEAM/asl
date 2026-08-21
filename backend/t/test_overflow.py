"""§3 says wrapping is an error, not a behavior. Held to that on every backend.

This was a documented divergence rather than a bug nobody knew about
(`EXPERIMENT.md` amendment `2026-08-21-b`): Swift trapped, Rust trapped only in
debug and wrapped under `-O`, and Python's arbitrary-precision integers could not
overflow at all. The differential gate could not see it because no benchmark case
overflows, so the disagreement was latent rather than absent.

Rust is compiled with `-O` here on purpose: that is the profile where it used to
disagree, and a debug-only test would pass against the defect.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
SRC = Path(__file__).parent / "overflow.as"


def test_python_traps_on_int64_overflow():
    from to_python import Transpiler
    import runtime
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "m.py").write_text(Transpiler().transpile(SRC.read_text()))
        sys.path.insert(0, d)
        try:
            import importlib
            m = importlib.import_module("m")
            with pytest.raises(runtime.Trap):
                m.blow_up(1)
            assert m.safe_sum(2, 3) == 5          # ordinary arithmetic is untouched
        finally:
            sys.path.remove(d)
            sys.modules.pop("m", None)


def test_rust_traps_on_int64_overflow_under_optimisation():
    if shutil.which("rustup") is None:
        pytest.skip("rustup not installed")
    from to_rust import ToRust
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
        (p / "prog.rs").write_text(ToRust().transpile(SRC.read_text())
                                   + 'fn main() { println!("{}", blow_up(1)); }\n')
        c = subprocess.run(["rustup", "run", "stable", "rustc", "-O", "--edition", "2021",
                            "-o", "prog", "prog.rs"], cwd=d, capture_output=True, text=True)
        assert c.returncode == 0, c.stderr
        r = subprocess.run([str(p / "prog")], capture_output=True, text=True)
        assert r.returncode != 0, "release-mode Rust wrapped instead of trapping"


def test_swift_traps_on_int64_overflow_under_optimisation():
    if shutil.which("swiftc") is None:
        pytest.skip("swiftc not installed")
    from to_swift import ToSwift
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "rt.swift").write_text((ROOT / "backend" / "swift" / "rt.swift").read_text())
        (p / "lib.swift").write_text(ToSwift().transpile(SRC.read_text()))
        (p / "main.swift").write_text("print(blowUp(1))\n")
        c = subprocess.run(["swiftc", "-O", "-o", "prog", "rt.swift", "lib.swift", "main.swift"],
                           cwd=d, capture_output=True, text=True)
        assert c.returncode == 0, c.stderr
        r = subprocess.run([str(p / "prog")], capture_output=True, text=True)
        assert r.returncode != 0, "Swift did not trap on overflow"
