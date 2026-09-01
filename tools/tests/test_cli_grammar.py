import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def test_cli_grammar_subcommand():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "grammar"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL" in proc.stdout
    assert "LLM Reference Sheet" in proc.stdout


def test_cli_ref_alias():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "ref"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL" in proc.stdout
    assert "LLM Reference Sheet" in proc.stdout


def test_cli_top_level_ref_flag():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "--ref"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "ASL" in proc.stdout
    assert "LLM Reference Sheet" in proc.stdout


def test_cli_grammar_lark_flag():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "grammar", "--lark"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    assert "Lark grammar" in proc.stdout
