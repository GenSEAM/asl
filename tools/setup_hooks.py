#!/usr/bin/env python3
"""
Install git pre-commit hooks for AgentScript (ASL).
"""
import os
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK_SRC = ROOT / "tools" / "hooks" / "pre-commit"
HOOK_DST = ROOT / ".git" / "hooks" / "pre-commit"


def install_hook():
    if not (ROOT / ".git").exists():
        print("Not a git repository root. Skipping hook installation.")
        return

    (ROOT / ".git" / "hooks").mkdir(parents=True, exist_ok=True)
    HOOK_DST.write_bytes(HOOK_SRC.read_bytes())
    # Make executable
    st = os.stat(HOOK_DST)
    os.chmod(HOOK_DST, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    print(f"OK: Pre-commit hook installed to {HOOK_DST}")


if __name__ == "__main__":
    install_hook()
