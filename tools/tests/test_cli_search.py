import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_websearch():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "websearch", "test query"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "Search Results for:" in proc.stdout
    assert any(proto in proc.stdout for proto in ["https://", "http://"])


def test_cli_websearch_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "websearch", "test query", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert isinstance(data, list)
    assert len(data) > 0
    assert "title" in data[0]
    assert "url" in data[0]
    assert "engine" in data[0]
