"""Unit tests for AgentScript In-Memory Jailed Sandbox Runner (@pcp:r-8d8e)."""

import pytest
from pathlib import Path
from tools.sandbox_runner import AslSandboxRunner, JailedEnvironment

ROOT = Path(__file__).resolve().parent.parent.parent


def test_sandbox_normal_execution():
    target = ROOT / "packages" / "asl-sql" / "src" / "core" / "sql.asl"
    runner = AslSandboxRunner(jail_root=target.parent, timeout_ms=3000, memory_limit_mb=16)
    telemetry = runner.execute_file(target)
    assert telemetry.status == "OK"
    assert telemetry.exit_code == 0
    assert telemetry.memory_allocated_kb > 0
    assert "(ok" in telemetry.result


def test_sandbox_jail_enforcement():
    target = ROOT / "packages" / "asl-sql" / "src" / "core" / "sql.asl"
    # Set jail to a directory that does NOT contain target
    runner = AslSandboxRunner(jail_root=ROOT / "bench", timeout_ms=1000)
    telemetry = runner.execute_file(target, enforce_jail=True)
    assert telemetry.status == "PERMISSION_DENIED"
    assert telemetry.exit_code == 126
    assert "Security breach" in telemetry.stderr


def test_sandbox_missing_file():
    missing = ROOT / "non_existent_file.asl"
    runner = AslSandboxRunner(jail_root=ROOT)
    telemetry = runner.execute_file(missing, enforce_jail=True)
    assert telemetry.status == "ERROR"
    assert telemetry.exit_code == 1
    assert "not found" in telemetry.stderr
