import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))


def test_cli_machine_diagnostics_clean():
    clean_file = ROOT / "grammar" / "corpus" / "valid" / "01-basics.agentscript"
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "check", str(clean_file), "--machine"],
        capture_output=True,
        text=True,
        cwd=ROOT
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["valid"] is True
    assert data["diagnostics_count"] == 0


def test_cli_heal_rule13_auto_export():
    with tempfile.TemporaryDirectory() as tmpdir:
        broken_src = """(module test/demo
  :doc "Test unexported schema type"
  :export [MyConfig])

(defenum Mode
  (:case fast [] "Fast mode")
  (:case slow [] "Slow mode"))

(defschema MyConfig
  (:field mode Mode "Operating mode"))
"""
        target_file = Path(tmpdir) / "test.agentscript"
        target_file.write_text(broken_src)

        # First check fails rule-13
        proc_check = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "check", str(target_file), "--machine"],
            capture_output=True,
            text=True,
            cwd=ROOT
        )
        assert proc_check.returncode == 1
        data = json.loads(proc_check.stdout)
        assert data["valid"] is False
        assert any(d["code"] == "rule-13" for d in data["diagnostics"])

        # Run heal to fix rule-13
        proc_heal = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "heal", str(target_file)],
            capture_output=True,
            text=True,
            cwd=ROOT
        )
        assert proc_heal.returncode == 0
        assert "Repaired [rule-13]" in proc_heal.stdout

        # Re-check is now 100% clean
        proc_check2 = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "check", str(target_file), "--machine"],
            capture_output=True,
            text=True,
            cwd=ROOT
        )
        assert proc_check2.returncode == 0
        data2 = json.loads(proc_check2.stdout)
        assert data2["valid"] is True
