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
    assert "https://aslang.dev" in proc.stdout


def test_cli_websearch_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "websearch", "test query", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "asl-internal" in proc.stdout
