"""Pytest integration suite for AgentScript WebAssembly compiler and WASI runner.

Verifies:
1. `agentscript build <file> --target wasm [-o <out.wasm>]` emits valid WebAssembly binaries.
2. In-memory WASI preview1 host shim (`backend/ts/wasm_runner.js`) executes compiled Wasm
   programs producing matching stdout, stderr, and exit codes.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent


def compile_agentscript_wasm(src_path: Path, out_wasm: Path) -> subprocess.CompletedProcess:
    """Invokes `agentscript build <file> --target wasm -o <out_wasm>`."""
    return subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "build", str(src_path),
         "--target", "wasm", "-o", str(out_wasm)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )


def run_wasm_with_runner(wasm_path: Path, args: list[str] | None = None, env: dict[str, str] | None = None) -> dict:
    """Executes a .wasm binary using `backend/ts/wasm_runner.js` via node and returns result dict."""
    runner_script = ROOT / "backend" / "ts" / "wasm_runner.js"
    args_json = json.dumps(args or ["main"])
    env_json = json.dumps(env or {})
    node_code = f"""
import {{ runWasm }} from '{runner_script.as_posix()}';
import {{ readFileSync }} from 'fs';

const wasmBytes = readFileSync('{wasm_path.as_posix()}');
const options = {{
    args: {args_json},
    env: {env_json}
}};

runWasm(wasmBytes, options).then(res => {{
    console.log(JSON.stringify(res));
}}).catch(err => {{
    console.error(err);
    process.exit(1);
}});
"""
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", node_code],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"node runner failed: {proc.stderr}")
    return json.loads(proc.stdout)


def test_cli_build_wasm_with_output_flag():
    src = ROOT / "grammar" / "corpus" / "valid" / "01-basics.agentscript"
    with tempfile.TemporaryDirectory() as td:
        out_wasm = Path(td) / "basics.wasm"
        res = compile_agentscript_wasm(src, out_wasm)
        assert res.returncode == 0, f"build failed: {res.stderr}"
        assert out_wasm.exists()
        header = out_wasm.read_bytes()[:8]
        assert header == b"\x00asm\x01\x00\x00\x00", "Must have WebAssembly magic and version header"


def test_cli_build_wasm_stdout_stream():
    src = ROOT / "grammar" / "corpus" / "valid" / "01-basics.agentscript"
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "build", str(src), "--target", "wasm"],
        cwd=ROOT,
        capture_output=True,
    )
    assert proc.returncode == 0, f"build failed: {proc.stderr.decode()}"
    assert proc.stdout.startswith(b"\x00asm\x01\x00\x00\x00")


def test_cli_build_wasm_missing_file():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "build", "nonexistent.agentscript", "--target", "wasm"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0
    assert "no such file" in proc.stdout.lower() or "no such file" in proc.stderr.lower()


def test_wasm_runner_executes_module_program():
    src = ROOT / "grammar" / "corpus" / "valid" / "13-module-program.agentscript"
    with tempfile.TemporaryDirectory() as td:
        wasm_file = Path(td) / "program.wasm"
        res = compile_agentscript_wasm(src, wasm_file)
        assert res.returncode == 0, f"Compilation failed: {res.stderr}"

        run_res = run_wasm_with_runner(wasm_file)
        assert run_res["exitCode"] == 0
        assert "rectangle\n6.0\n" == run_res["stdout"]
        assert run_res["stderr"] == ""


def test_wasm_runner_executes_sequenced_bodies():
    src = ROOT / "grammar" / "corpus" / "valid" / "14-sequenced-bodies.agentscript"
    with tempfile.TemporaryDirectory() as td:
        wasm_file = Path(td) / "sequenced.wasm"
        res = compile_agentscript_wasm(src, wasm_file)
        assert res.returncode == 0, f"Compilation failed: {res.stderr}"

        run_res = run_wasm_with_runner(wasm_file)
        assert run_res["exitCode"] == 0
        expected_lines = [
            "function-1",
            "let-1",
            "cond-1",
            "else-1",
            "match-ok-1",
            "match-err-1",
            "lambda-1",
            "lambda-1",
            "cond-bare",
            "else-bare",
            "15",
            "13",
            "30",
            "",
        ]
        assert run_res["stdout"] == "\n".join(expected_lines)
        assert run_res["stderr"] == ""


def test_wasm_runner_executes_shadowed_binders():
    src = ROOT / "grammar" / "corpus" / "valid" / "15-shadowed-binders.agentscript"
    with tempfile.TemporaryDirectory() as td:
        wasm_file = Path(td) / "shadowed.wasm"
        res = compile_agentscript_wasm(src, wasm_file)
        assert res.returncode == 0, f"Compilation failed: {res.stderr}"

        run_res = run_wasm_with_runner(wasm_file)
        assert run_res["exitCode"] == 0
        assert run_res["stdout"] == "7 6 101 102\n"
        assert run_res["stderr"] == ""


def test_wasm_runner_io_usage_output():
    src = ROOT / "grammar" / "corpus" / "valid" / "08-io.agentscript"
    with tempfile.TemporaryDirectory() as td:
        wasm_file = Path(td) / "io.wasm"
        res = compile_agentscript_wasm(src, wasm_file)
        assert res.returncode == 0, f"Compilation failed: {res.stderr}"

        # Running without args prints usage on stderr
        run_res = run_wasm_with_runner(wasm_file, args=["main"])
        assert run_res["exitCode"] == 0
        assert run_res["stdout"] == ""
        assert run_res["stderr"] == "usage: io-demo SRC [DST]\n"
