import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_version_subcommand():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "version"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "asl (AgentScript Language) v0.3.0" in proc.stdout
    assert "https://aslang.dev" in proc.stdout


def test_cli_version_flag():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "--version"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "asl (AgentScript Language) v0.3.0" in proc.stdout


def test_upgrade_helper_functions():
    sys.path.insert(0, str(ROOT))
    from tools.upgrade import get_current_version
    assert get_current_version() == "0.3.0"
