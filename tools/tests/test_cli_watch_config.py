import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from tools.scaffold import scaffold_project
from tools.project import build_project, load_project_config


def test_project_multi_target_build():
    with tempfile.TemporaryDirectory() as tmpdir:
        target_dir = Path(tmpdir) / "demo-build"
        scaffold_project(target_dir, template="wasm", embed_skill=False)

        # Write rich asl.json configuration
        asl_config = {
            "name": "demo-build",
            "version": "0.1.0",
            "entry": "src/main.agentscript",
            "targets": {
                "ts": {"output": "dist/index.ts"},
                "py": {"output": "dist/index.py"}
            }
        }
        (target_dir / "asl.json").write_text(json.dumps(asl_config, indent=2))

        # Test build_project
        code, results = build_project(target_dir)
        assert code == 0
        assert len(results) == 2
        assert all(r["ok"] for r in results)
        assert (target_dir / "dist" / "index.ts").exists()
        assert (target_dir / "dist" / "index.py").exists()


def test_cli_build_no_args():
    with tempfile.TemporaryDirectory() as tmpdir:
        target_dir = Path(tmpdir) / "demo-cli"
        scaffold_project(target_dir, template="wasm", embed_skill=False)

        # Write rich asl.json
        asl_config = {
            "name": "demo-cli",
            "entry": "src/main.agentscript",
            "targets": {
                "ts": {"output": "dist/bundle.ts"}
            }
        }
        (target_dir / "asl.json").write_text(json.dumps(asl_config, indent=2))

        # Run `asl build` in target_dir
        proc = subprocess.run(
            [sys.executable, str(ROOT / "agentscript"), "build"],
            cwd=target_dir,
            capture_output=True,
            text=True
        )
        assert proc.returncode == 0
        assert "[ts] ->" in proc.stdout
        assert (target_dir / "dist" / "bundle.ts").exists()
