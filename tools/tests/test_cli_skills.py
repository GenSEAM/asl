"""`asl skill` reports the skills this repository actually ships.

These tests asserted a hand-written catalogue of five entries with invented
download counts, four of which had no file behind them, while `install_skill`
copied the language reference no matter which id was asked for. They passed
throughout. The assertions below are tied to the directory instead, so a skill
exists exactly when its SKILL.md does.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SKILLS = ROOT / "skills"


def _run(*argv):
    return subprocess.run([sys.executable, str(ROOT / "agentscript"), *argv],
                          capture_output=True, text=True, cwd=ROOT)


def on_disk() -> set[str]:
    return {d.name for d in SKILLS.iterdir() if (d / "SKILL.md").is_file()}


def test_listing_matches_the_directory():
    proc = _run("skill", "list", "--json")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert {s["id"] for s in data} == on_disk()
    assert data, "the repository ships at least one skill"
    for entry in data:
        assert (ROOT / entry["path"]).is_file()
        assert entry["description"], f"{entry['id']} has no description in its front matter"


def test_filter_narrows_the_listing():
    proc = _run("skill", "list", "asl", "--json")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert [s["id"] for s in data] == ["asl"]


def test_install_rejects_an_id_with_no_file():
    """The old installer answered success for any id and copied the wrong skill."""
    proc = _run("skill", "install", "asl-mem")
    assert proc.returncode == 1
    assert "Unknown skill" in proc.stderr


def test_install_copies_the_skill_asked_for(tmp_path):
    target = tmp_path / "dest"
    proc = subprocess.run(
        [sys.executable, "-c",
         "import sys; sys.path.insert(0, %r); "
         "from tools.skills_manager import install_skill; "
         "from pathlib import Path; "
         "sys.exit(install_skill('skyloom', target_dir=Path(%r)))" % (str(ROOT), str(target))],
        capture_output=True, text=True, cwd=ROOT)
    assert proc.returncode == 0, proc.stderr
    written = (target / "SKILL.md").read_text()
    assert written == (SKILLS / "skyloom" / "SKILL.md").read_text()
