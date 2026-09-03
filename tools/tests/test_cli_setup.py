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
    # Every skill the repository ships is named, and nothing else is. The old
    # assertion looked for a marketplace banner over four entries with no files.
    assert "Agent skills" in proc.stdout
    for d in sorted((ROOT / "skills").iterdir()):
        if (d / "SKILL.md").is_file():
            assert d.name in proc.stdout


def test_cli_setup_alias():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "setup"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL AI Agent Setup" in proc.stdout
    assert "mcpServers" in proc.stdout
