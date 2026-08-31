import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from tools.pkg import normalize_pkg_url


def test_normalize_pkg_url():
    pkg, ver = normalize_pkg_url("github.com/genseam/search@v1.0.0")
    assert pkg == "github.com/genseam/search"
    assert ver == "v1.0.0"

    pkg2, ver2 = normalize_pkg_url("https://github.com/genseam/mem")
    assert pkg2 == "github.com/genseam/mem"
    assert ver2 == "main"


def test_cli_pkg_install_empty():
    with tempfile.TemporaryDirectory() as tmpdir:
        asl_json = Path(tmpdir) / "asl.json"
        asl_json.write_text(json.dumps({"name": "test-pkg", "dependencies": {}}))

        proc = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "install"],
            cwd=tmpdir,
            capture_output=True,
            text=True
        )
        assert proc.returncode == 0
        assert "No dependencies defined" in proc.stdout
