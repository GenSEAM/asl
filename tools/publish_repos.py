"""Creates and pushes standalone repositories for all ecosystem packages to GenSEAM org."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES_DIR = ROOT / "packages"

PACKAGES = [
    ("asl-web-search", "search", "Decentralized SearXNG metasearch aggregator and proxy pool rotator for AI agents"),
    ("asl-mem", "mem", "Zero-server in-memory vector database and cosine similarity search in 64KB WebAssembly"),
    ("asl-agent-core", "agent-core", "Unified Agent Core: composable onion middleware, capability negotiator, FSM, and tool calling"),
    ("asl-vdom", "vdom", "Declarative S-Expression Virtual DOM renderer bridging React 19, Vue 3, and Svelte 5"),
    ("asl-harness", "harness", "Universal multi-modal agent harness with Code, Browser, Computer-Use, and Chat adapters"),
    ("asl-browser-plugin", "browser-plugin", "Cross-browser extension (Manifest V3) with in-memory WASI runner & DOM compressor"),
    ("asl-agent-bus", "agent-bus", "High-performance Inter-Agent Swarm Bus with MCP, SSE, and Socket streaming for warm subagents"),
    ("asl-eddie", "eddie", "EDDIE: Adaptive Swarm Orchestrator, Intent Classifier & Speculative Task Pool for AgentScript"),
    ("asl-voice", "voice", "Real-time Voice Stream Assistant, 16kHz PCM Audio Bridge & Sub-Millisecond Voice Router for AgentScript"),
    ("skills", "skills", "Universal Agent Skills Hub: Official AgentScript skills for Claude Code, Cursor, Antigravity, Windsurf & OpenDevin"),
]


def publish_package(pkg_dir_name: str, repo_name: str, description: str):
    pkg_dir = ROOT / "skills" if pkg_dir_name == "skills" else ROOT / "packages" / pkg_dir_name
    if not pkg_dir.exists():
        print(f"✗ Skipping {pkg_dir_name}: directory not found")
        return

    print(f"\n🚀 Publishing GenSEAM/{repo_name}...")

    # Check if repo exists on GitHub
    check = subprocess.run(["gh", "repo", "view", f"GenSEAM/{repo_name}"], capture_output=True, text=True)
    if check.returncode != 0:
        create = subprocess.run(
            ["gh", "repo", "create", f"GenSEAM/{repo_name}", "--public", "--description", description],
            capture_output=True,
            text=True
        )
        if create.returncode == 0:
            print(f"✓ Created GitHub repo: GenSEAM/{repo_name}")
        else:
            print(f"✗ Failed to create repo GenSEAM/{repo_name}: {create.stderr.strip()}")
            return
    else:
        print(f"ℹ Repository GenSEAM/{repo_name} already exists on GitHub.")

    # Export to a temporary clean git repository and push
    with tempfile.TemporaryDirectory() as tmpdir:
        dest = Path(tmpdir) / repo_name
        shutil.copytree(pkg_dir, dest)

        # Ensure .gitignore
        (dest / ".gitignore").write_text("dist/\nnode_modules/\n.DS_Store\n*.log\n")

        subprocess.run(["git", "init"], cwd=dest, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.name", "GenSEAM Core Team"], cwd=dest, capture_output=True)
        subprocess.run(["git", "config", "user.email", "dev@aslang.dev"], cwd=dest, capture_output=True)
        subprocess.run(["git", "checkout", "-b", "main"], cwd=dest, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=dest, capture_output=True, check=True)
        subprocess.run(["git", "commit", "-m", f"feat: release initial {repo_name} package"], cwd=dest, capture_output=True, check=True)
        
        remote_url = f"git@github.com:GenSEAM/{repo_name}.git"
        subprocess.run(["git", "remote", "add", "origin", remote_url], cwd=dest, capture_output=True)
        push = subprocess.run(["git", "push", "-u", "origin", "main", "--force"], cwd=dest, capture_output=True, text=True)
        if push.returncode == 0:
            print(f"✓ Successfully pushed main to https://github.com/GenSEAM/{repo_name}")
        else:
            print(f"✗ Push failed for {repo_name}: {push.stderr.strip()}")


def main():
    for pkg_folder, repo_name, desc in PACKAGES:
        publish_package(pkg_folder, repo_name, desc)
    print("\n🎉 All ecosystem tool repositories created and published successfully!")


if __name__ == "__main__":
    main()
