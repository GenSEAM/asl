import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
CORPUS = ROOT / "grammar" / "corpus" / "valid"
MODULES = ROOT / "grammar" / "corpus" / "modules"


def test_cli_build_wasm():
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        out_wasm = Path(d) / "basics.wasm"
        r = subprocess.run([
            sys.executable, str(ROOT / "agentscript"), "build",
            str(CORPUS / "01-basics.agentscript"), "--target", "wasm", "-o", str(out_wasm)
        ], capture_output=True, text=True, cwd=ROOT)
        assert r.returncode == 0, f"agentscript build wasm failed: {r.stderr}"
        assert out_wasm.exists() and out_wasm.stat().st_size > 0
        magic = out_wasm.read_bytes()[:4]
        assert magic == b"\x00asm"


def test_wasm_runner_node_suite():
    r = subprocess.run(["node", str(ROOT / "backend" / "ts" / "test_wasm_runner.js")],
                       capture_output=True, text=True, cwd=ROOT)
    assert r.returncode == 0, f"node test_wasm_runner.js failed:\nstdout: {r.stdout}\nstderr: {r.stderr}"
    assert "All tests passed!" in r.stdout
