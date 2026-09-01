import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_eddie_classify_search():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "eddie", "Search for papers", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["layer2_intent"] == "web-search"
    assert data["layer1_triage"] == "instant"
    assert data["layer3_tier"] == "tier-1"


def test_cli_eddie_classify_code():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "eddie", "Refactor compiler", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["layer2_intent"] == "code-gen"
    assert data["layer3_tier"] == "tier-2"
    assert data["speculative_branches"] == 2
