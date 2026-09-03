"""Universal Agent Skills Hub & Marketplace Manager (`asl skill`)."""
import json
import os
import shutil
import sys
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent

SKILLS = ROOT / "skills"


def _front_matter(path: Path) -> dict[str, str]:
    """The `name:` and `description:` of a SKILL.md, as a dict."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return {}
    block = text.split("---", 2)[1]
    out, key = {}, None
    for line in block.splitlines():
        if line[:1].isalpha() and ":" in line:
            key, _, value = line.partition(":")
            out[key.strip()] = value.strip()
        elif key and line.strip():
            out[key] += " " + line.strip()
    return out


def registry() -> list[dict]:
    """Every skill this repository actually ships, read off the directory.

    It was a hand-written catalogue of five entries, four of which had no file
    behind them and all of which carried invented download counts, while
    `install_skill` copied the language reference no matter which id was asked
    for. A skill exists when its SKILL.md does.
    """
    out = []
    for d in sorted(SKILLS.iterdir()) if SKILLS.is_dir() else []:
        card = d / "SKILL.md"
        if not card.is_file():
            continue
        fm = _front_matter(card)
        out.append({
            "id": fm.get("name", d.name),
            "path": str(card.relative_to(ROOT)),
            "description": fm.get("description", ""),
            "chars": card.stat().st_size,
        })
    return out


def list_skills(category: str = "", json_mode: bool = False) -> int:
    """Lists the agent skills this repository ships."""
    items = registry()
    if category:
        q = category.lower()
        items = [s for s in items if q in s["id"].lower() or q in s["description"].lower()]

    if json_mode:
        print(json.dumps(items, indent=2))
        return 0

    if not items:
        print("No skills found under skills/.")
        return 1
    print(f"Agent skills ({len(items)}):\n")
    for s in items:
        print(f"  • {s['id']} — {s['path']} ({s['chars']}B)")
        print(f"    {s['description']}")
        print(f"    Install: asl skill install {s['id']}\n")
    return 0


def install_skill(skill_id: str, platform: str = "global", target_dir: Optional[Path] = None) -> int:
    """Installs one agent skill into a target harness configuration."""
    entry = next((s for s in registry() if s["id"] == skill_id), None)
    if entry is None:
        known = ", ".join(s["id"] for s in registry()) or "none"
        print(f"✗ Unknown skill: {skill_id}. Available: {known}.", file=sys.stderr)
        return 1

    src_skill = ROOT / entry["path"]
    dest_dir = target_dir or (Path.cwd() / ".skills" / skill_id)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_file = dest_dir / "SKILL.md"
    shutil.copy(src_skill, dest_file)

    print(f"✓ Installed skill [{skill_id}] to {dest_file}")
    return 0
