import json
import tempfile
from pathlib import Path
from tools.scaffold import scaffold_project


def test_scaffold_project():
    with tempfile.TemporaryDirectory() as tmpdir:
        target = Path(tmpdir) / "demo-agent-service"
        res = scaffold_project(target, template="wasm", embed_skill=True)
        assert res["status"] == "success"
        assert res["project"] == "demo-agent-service"

        # Verify asex.json
        manifest = json.loads((target / "asex.json").read_text())
        assert manifest["name"] == "demo-agent-service"
        assert "wasm" in manifest["targets"]

        # Verify AGENTS.md, CLAUDE.md, and skill
        assert (target / "AGENTS.md").exists()
        assert (target / "CLAUDE.md").exists()
        assert (target / ".skills" / "agentscript" / "SKILL.md").exists()
        assert (target / "src" / "main.agentscript").exists()
        assert (target / "tests" / "test_main.agentscript").exists()
