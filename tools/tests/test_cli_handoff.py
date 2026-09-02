import subprocess
import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

def test_cli_loom_handoff_json():
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "handoff",
            "--to",
            "agent-coder",
            "--task",
            "build_rate_limiter",
            "--cwd",
            "packages/asl-rate",
            "--owns",
            "src/limiter.asl,tests/limiter_test.asl",
            "--frozen",
            "src/core.asl",
            "--gate",
            "asl check src/limiter.asl",
            "--budget",
            "4500",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "DELIVERED"
    assert data["type"] == "HANDOFF"
    assert data["dialect"] == "asl/coord"
    assert data["payload"]["task"] == "build_rate_limiter"
    assert data["payload"]["cwd"] == "packages/asl-rate"
    assert "src/limiter.asl" in data["payload"]["owns"]
    assert "src/core.asl" in data["payload"]["frozen"]
    assert data["payload"]["budget"] == 4500
    assert "(loom:handoff" in data["wireFrame"]


def test_cli_loom_yield_json():
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "yield",
            "--to",
            "agent-orchestrator",
            "--reply-to",
            "handoff-1234",
            "--status",
            "ok",
            "--verdict",
            "PASS (0 diagnostics, 12 tests green)",
            "--artifacts",
            "src/limiter.asl,dist/limiter.wasm",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "DELIVERED"
    assert data["type"] == "YIELD"
    assert data["dialect"] == "asl/coord"
    assert data["replyTo"] == "handoff-1234"
    assert data["payload"]["status"] == "ok"
    assert "src/limiter.asl" in data["payload"]["artifacts"]
    assert "(loom:yield" in data["wireFrame"]


def test_cli_loom_spawn_json(tmp_path):
    sub_dir = tmp_path / "worker_cwd"
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "spawn",
            "--to",
            "agent-subworker-1",
            "--cwd",
            str(sub_dir),
            "--cmd",
            "asl check src/main.asl",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "SPAWNED"
    assert data["agent"] == "agent-subworker-1"
    assert str(sub_dir) in data["cwd"]
    assert any(str(sub_dir) in s for s in data["scopes"])


def test_cli_loom_handoff_human():
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "handoff",
            "--to",
            "agent-qa",
            "--task",
            "run_integration_suite",
            "--cwd",
            "packages/asl-rate",
            "--gate",
            "asl test",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    assert "Context-Isolated Agent Handoff" in proc.stdout
    assert "(loom:handoff" in proc.stdout


def test_cli_loom_transcode_bidirectional():
    raw_nano = 'SK1|1|msg-transcode-01|alice|bob|DATA|tasks/compile|1788350000000||{"action":"build"}'
    
    # Nano -> Verbose
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "transcode",
            "--frame",
            raw_nano,
            "--to-dialect",
            "verbose",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["status"] == "OK"
    assert data["target"] == "asl/v1"
    verbose_wire = data["wireFrame"]
    assert "(loom:frame" in verbose_wire
    assert ':type "DATA"' in verbose_wire

    # Verbose -> Nano
    proc_rev = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "loom",
            "transcode",
            "--frame",
            verbose_wire,
            "--to-dialect",
            "nano",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc_rev.returncode == 0
    data_rev = json.loads(proc_rev.stdout)
    assert data_rev["status"] == "OK"
    assert data_rev["target"] == "compact/v1"
    assert data_rev["wireFrame"].startswith("SK1|1|msg-transcode-01|alice|bob|DATA|tasks/compile")
