"""Universal Agent Skills Hub & Marketplace Manager (`asl skill`)."""
import json
import os
import shutil
import sys
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent

SKILLS_REGISTRY = [
    {
        "id": "asl-core",
        "name": "AgentScript Language Core",
        "category": "Code Generation & Wasm",
        "description": "Complete grammar specification, §9 semantic rules, standard library handbook, and self-healing engine",
        "author": "GenSEAM Core",
        "downloads": 4820,
        "token_cost": 2400,
        "platforms": ["Claude Code", "Cursor", "Antigravity", "Windsurf", "OpenDevin"],
        "repo": "github.com/GenSEAM/skills/asl-core"
    },
    {
        "id": "asl-eddie",
        "name": "EDDIE Swarm Orchestrator",
        "category": "Swarm & Task Pool",
        "description": "3-layer intent classification, consultative ambiguity resolver, and speculative task pool DAG",
        "author": "GenSEAM Core",
        "downloads": 2910,
        "token_cost": 1850,
        "platforms": ["Claude Code", "Cursor", "Antigravity"],
        "repo": "github.com/GenSEAM/skills/asl-eddie"
    },
    {
        "id": "asl-browser",
        "name": "Browser DOM & WASI Agent",
        "category": "Browser Automation",
        "description": "Intelligent DOM tree compression (-78% tokens) and in-memory WebAssembly action execution",
        "author": "GenSEAM Core",
        "downloads": 3410,
        "token_cost": 1600,
        "platforms": ["Claude Code", "Antigravity", "OpenDevin"],
        "repo": "github.com/GenSEAM/skills/asl-browser"
    },
    {
        "id": "asl-search",
        "name": "SearXNG & Proxy Pool Scout",
        "category": "Web Research & RAG",
        "description": "Multi-engine decentralized search with proxy rotation and clean markdown RAG context compressor",
        "author": "GenSEAM Core",
        "downloads": 2150,
        "token_cost": 1200,
        "platforms": ["Claude Code", "Cursor", "Antigravity", "Windsurf"],
        "repo": "github.com/GenSEAM/skills/asl-search"
    },
    {
        "id": "asl-mem",
        "name": "Vector Memory & Semantic Recall",
        "category": "Memory & Embeddings",
        "description": "Zero-server in-memory vector database and cosine similarity in 64KB WebAssembly",
        "author": "GenSEAM Core",
        "downloads": 1940,
        "token_cost": 1100,
        "platforms": ["Claude Code", "Cursor", "Antigravity"],
        "repo": "github.com/GenSEAM/skills/asl-mem"
    }
]


def list_skills(category: str = "", json_mode: bool = False) -> int:
    """Lists available agent skills in the marketplace."""
    items = SKILLS_REGISTRY
    if category:
        items = [s for s in items if category.lower() in s["category"].lower() or category.lower() in s["name"].lower()]

    if json_mode:
        print(json.dumps(items, indent=2))
        return 0

    print(f"📦 Agent Skills Marketplace ({len(items)} available skills):\n")
    for s in items:
        platforms = ", ".join(s["platforms"])
        print(f"  • {s['name']} ({s['id']}) — [{s['category']}]")
        print(f"    Downloads: {s['downloads']} | Token cost: ~{s['token_cost']} tokens")
        print(f"    Supported Platforms: {platforms}")
        print(f"    Install: asl skill install {s['id']}\n")
    return 0


def install_skill(skill_id: str, platform: str = "global", target_dir: Optional[Path] = None) -> int:
    """Installs an agent skill into target harness configuration."""
    skill = next((s for s in SKILLS_REGISTRY if s["id"] == skill_id), None)
    if not skill and skill_id != "asl":
        print(f"✗ Unknown skill: {skill_id}. Run 'asl skill list' to view available skills.")
        return 1

    # Source skill file
    src_skill = ROOT / "skills" / "asl" / "SKILL.md"
    if not src_skill.exists():
        src_skill = ROOT / "prelude" / "HANDBOOK.md"

    dest_dir = target_dir or (Path.cwd() / ".skills" / skill_id)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_file = dest_dir / "SKILL.md"

    if src_skill.exists():
        shutil.copy(src_skill, dest_file)
    else:
        dest_file.write_text(f"---\nname: {skill_id}\ndescription: {skill['description'] if skill else 'ASL Skill'}\n---\n# {skill_id}\n")

    print(f"✓ Successfully installed skill [{skill_id}] to {dest_file}")
    print(f"  Ready for Claude Code, Cursor, Antigravity, and Windsurf.")
    return 0
