import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_bus_list():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "bus"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "agent-planner" in proc.stdout
    assert "agent-coder" in proc.stdout


def test_cli_bus_list_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "bus", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 4
    assert any(p["id"] == "agent-coder" for p in data)


def test_cli_bus_send():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "bus", "--send", "agent-coder", "--msg", "(eval/wasm :fast)"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "Dispatched task to [agent-coder]" in proc.stdout
