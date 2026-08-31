import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_skill_subcommand():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "skill"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL AI Agent Setup" in proc.stdout
    assert "mcpServers" in proc.stdout


def test_cli_setup_alias():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "setup"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL AI Agent Setup" in proc.stdout
