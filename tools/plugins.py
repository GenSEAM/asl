"""Community-extensible Agent Plugin System for ASL."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from dataclasses import dataclass

ROOT = Path(__file__).resolve().parent.parent

COMMUNITY_REGISTRY = [
    {
        "name": "asl-github",
        "repo": "github.com/GenSEAM/plugin-github",
        "capability": "vcs",
        "description": "Inspect repositories, read pull requests, and review diffs via GitHub API",
        "author": "GenSEAM Core",
        "stars": 142
    },
    {
        "name": "asl-slack",
        "repo": "github.com/GenSEAM/plugin-slack",
        "capability": "chat",
        "description": "Autonomous message dispatch, channel listener, and thread summarization",
        "author": "community/alex",
        "stars": 98
    },
    {
        "name": "asl-postgres",
        "repo": "github.com/GenSEAM/plugin-postgres",
        "capability": "database",
        "description": "Type-safe SQL query generation, schema inspection, and migration runner",
        "author": "community/database-dao",
        "stars": 215
    },
    {
        "name": "asl-linear",
        "repo": "github.com/GenSEAM/plugin-linear",
        "capability": "pm",
        "description": "Issue tracking, sprint planning, and automated roadmap synchronization",
        "author": "community/pm-tools",
        "stars": 86
    }
]


def search_plugins(query: str = "", json_mode: bool = False) -> int:
    """Searches the community plugin registry."""
    q = query.lower()
    matches = [p for p in COMMUNITY_REGISTRY if q in p["name"].lower() or q in p["description"].lower() or q in p["capability"].lower()]

    if json_mode:
        print(json.dumps(matches, indent=2))
    else:
        print(f"🌟 Community Agent Plugins ({len(matches)} found):\n")
        for p in matches:
            print(f"  • {p['name']} [{p['capability']}] ⭐ {p['stars']}")
            print(f"    Repo: {p['repo']}")
            print(f"    {p['description']}\n")
    return 0


def create_plugin_scaffold(name: str, target_dir: Path | None = None) -> int:
    """Scaffolds a clean, community-extensible agent plugin."""
    clean_name = name.replace("_", "-").lower()
    dest = (target_dir or Path.cwd()) / f"asl-plugin-{clean_name}"
    dest.mkdir(parents=True, exist_ok=True)

    (dest / "src").mkdir(exist_ok=True)

    manifest = {
        "name": f"@genseam/asl-plugin-{clean_name}",
        "version": "0.1.0",
        "type": "agent-plugin",
        "capability": clean_name,
        "entry": "src/plugin.agentscript",
        "targets": {
            "wasm": {"output": "dist/plugin.wasm"},
            "ts": {"output": "dist/plugin.ts"}
        }
    }
    (dest / "asl.json").write_text(json.dumps(manifest, indent=2) + "\n")

    code = f"""(module asl-plugin-{clean_name}/core
  :doc "Community agent plugin for {clean_name}"
  :export [PluginManifest execute]
  :import [(core/strings :as s)])

(defschema PluginManifest
  (:field name String "asl-plugin-{clean_name}")
  (:field capability String "{clean_name}")
  (:field version String "0.1.0"))

(defun execute [(payload String)] -> String
  :doc "Executes community tool action"
  (s/concat "Executed {clean_name}: " payload))
"""
    (dest / "src" / "plugin.agentscript").write_text(code)

    readme = f"""# asl-plugin-{clean_name}

Community extensible AgentScript plugin for `{clean_name}`.

## Installation
```bash
asl plugin add github.com/your-username/asl-plugin-{clean_name}
```

## Contributing
Submit PRs to expand capabilities!
"""
    (dest / "README.md").write_text(readme)
    print(f"✓ Created community plugin scaffold in {dest}")
    return 0
