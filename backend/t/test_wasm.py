"""The browser target, held to what it can actually do.

`.as` reaches WebAssembly through the Rust backend and `wasm32-unknown-unknown`;
there is no separate wasm code generator. The risk is not that pure code fails to
build — it does build — but that an I/O module builds too and then fails at run
time, because `rustc` is happy to link `std::fs` for a target with no filesystem.
Declared effects make that decidable before the build, and this is where that is
checked.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))

PURE = ROOT / "examples" / "port" / "cron" / "cron.as"
EFFECTFUL = ROOT / "examples" / "io" / "env-report.as"
CHECK = ROOT / "checker" / "check.py"


def wasm_target_installed() -> bool:
    if shutil.which("rustup") is None:
        return False
    r = subprocess.run(["rustup", "target", "list", "--installed"],
                       capture_output=True, text=True)
    return "wasm32-unknown-unknown" in r.stdout


def check(target: str, path: Path) -> list[dict]:
    r = subprocess.run([sys.executable, str(CHECK), "--json", "--target", target, str(path)],
                       capture_output=True, text=True)
    return json.loads(r.stdout)


def test_a_pure_module_is_allowed_for_the_browser():
    assert check("wasm", PURE) == []


def test_an_effectful_module_is_refused_for_the_browser():
    diags = check("wasm", EFFECTFUL)
    assert diags, "a module reading files was allowed to target the browser"
    joined = " ".join(d["message"] for d in diags)
    for capability in ("fs", "env", "proc"):
        assert f"`{capability}`" in joined
    # console is the one thing a browser does have, so it must not be refused.
    assert "needs `console`" not in joined


def test_the_same_module_is_allowed_for_a_native_target():
    assert check("rs", EFFECTFUL) == []


@pytest.mark.skipif(not wasm_target_installed(), reason="wasm32 target not installed")
def test_a_pure_module_actually_compiles_to_wasm():
    from to_rust import ToRust
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
        (p / "lib.rs").write_text(ToRust().transpile(PURE.read_text()))
        c = subprocess.run(["rustup", "run", "stable", "rustc",
                            "--target", "wasm32-unknown-unknown", "--edition", "2021",
                            "--crate-type=cdylib", "-O", "-o", "out.wasm", "lib.rs"],
                           cwd=d, capture_output=True, text=True)
        assert c.returncode == 0, c.stderr[-600:]
        out = p / "out.wasm"
        assert out.exists() and out.stat().st_size > 0
        assert out.read_bytes()[:4] == b"\0asm", "not a WebAssembly module"
