import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_test_runner_valid_fixture():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "test", "backend/tests/smoke.agentscript"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "1 passed" in proc.stdout


def test_cli_test_runner_json_output():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "test", "backend/tests/smoke.agentscript", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["total"] == 1
    assert data["passed"] == 1
    assert data["failed"] == 0
