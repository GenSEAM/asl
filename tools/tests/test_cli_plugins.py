import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_plugin_search():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "plugin", "github"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "asl-github" in proc.stdout


def test_cli_plugin_search_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "plugin", "--search", "slack", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 1
    assert data[0]["name"] == "asl-slack"


def test_cli_plugin_create_scaffold():
    with tempfile.TemporaryDirectory() as tmpdir:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "plugin", "--create", "weather-tool"],
            capture_output=True,
            text=True,
            cwd=tmpdir
        )
        assert proc.returncode == 0
        plugin_dir = Path(tmpdir) / "asl-plugin-weather-tool"
        assert (plugin_dir / "asl.json").exists()
        assert (plugin_dir / "src" / "plugin.agentscript").exists()
        assert (plugin_dir / "README.md").exists()
