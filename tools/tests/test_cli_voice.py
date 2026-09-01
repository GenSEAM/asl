import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_voice_session():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "voice"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "Real-Time Voice Assistant Stream Active" in proc.stdout
    assert "pcm-16k" in proc.stdout


def test_cli_voice_session_json():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "voice", "--json"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["sample_rate"] == 16000
    assert data["format"] == "pcm-16k"
    assert data["active"] is True
