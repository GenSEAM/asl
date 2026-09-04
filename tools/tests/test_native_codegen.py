"""Tests for native Rust code generator bridge (tools/native_codegen.py)."""
import subprocess
import sys
import tempfile
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from tools.native_codegen import native_emit_rust

RT_RS = ROOT / "backend" / "rust" / "rt.rs"
CORPUS = ROOT / "grammar" / "corpus" / "valid"
MODULES = ROOT / "grammar" / "corpus" / "modules"


def _compile_with_rustc(rs_src: str) -> None:
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        (Path(d) / "rt.rs").write_text(RT_RS.read_text())
        (Path(d) / "lib.rs").write_text(rs_src)
        cmd = ["rustup", "run", "stable", "rustc", "--edition", "2021", "--crate-type=lib", "lib.rs"]
        res = subprocess.run(cmd, cwd=d, capture_output=True, text=True)
        msg = f"rustc failed with code {res.returncode}:\n{res.stderr}\n{res.stdout}\n{rs_src}"
        assert res.returncode == 0, msg


@pytest.mark.parametrize("fixture_name", [
    "01-basics.agentscript",
    "02-match.agentscript",
    "03-strings.agentscript",
    "05-constructors.agentscript",
    "07-lambda-elision.agentscript",
    "12-transitive-use.agentscript",
    "14-sequenced-bodies.agentscript",
])
def test_native_codegen_fixtures(fixture_name: str) -> None:
    path = CORPUS / fixture_name
    src = path.read_text()
    rs_code = native_emit_rust(src, path=str(path), roots=[str(MODULES)])
    assert "mod rt;" in rs_code
    _compile_with_rustc(rs_code)


def test_native_codegen_standalone_main() -> None:
    src = """(df main [(args (List String))] -> (Result Unit IoError)
  (let [(x 10)
        (y 20)]
    (println "hello from native codegen")
    (ok ())))"""
    rs_code = native_emit_rust(src)
    assert "pub fn main_(args: Vec<String>) -> Result<(), rt::IoError>" in rs_code
    assert "fn main() {" in rs_code
    _compile_with_rustc(rs_code)
