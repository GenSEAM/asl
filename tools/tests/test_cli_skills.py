import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_skill_list():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "skill", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 5
    ids = [s["id"] for s in data]
    assert "asl-core" in ids
    assert "asl-eddie" in ids


def test_cli_skill_search():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "skill", "Browser", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 1
    assert data[0]["id"] == "asl-browser"
