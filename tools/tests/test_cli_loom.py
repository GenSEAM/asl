import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_loom_peers():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "loom", "peers"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "agent-orchestrator" in proc.stdout
    assert "agent-planner" in proc.stdout
    assert "agent-vanilla-llm" in proc.stdout


def test_cli_loom_peers_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "loom", "peers", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert len(data) >= 5
    assert any(p["id"] == "agent-orchestrator" for p in data)
    assert any(p["id"] == "agent-vanilla-llm" for p in data)


def test_cli_loom_send_aware():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "loom", "send", "--to", "agent-planner", "--msg", "test_task", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "DELIVERED"
    assert data["dialect"] == "asl/v1"
    assert "loom:frame" in data["wireFormat"]


def test_cli_loom_send_lonely():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "loom", "send", "--to", "agent-lonely-sub", "--msg", "queued_task", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "QUEUED"
    assert data["code"] == 1002


def test_cli_loom_demo():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "loom", "demo"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "Live Autonomous Swarm Demonstration" in proc.stdout
    assert "ALL SKYLOOM CAPABILITIES VERIFIED" in proc.stdout
