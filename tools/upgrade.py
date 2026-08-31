"""Version checking and auto-upgrade mechanism for ASL CLI."""
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

VERSION = "1.0.0"
VERSION_ENDPOINT = "https://aslang.dev/version.json"


def get_current_version() -> str:
    return VERSION


def check_latest_version(timeout: float = 1.5) -> dict | None:
    """Checks latest version from aslang.dev. Returns payload or None on failure."""
    try:
        req = urllib.request.Request(
            VERSION_ENDPOINT,
            headers={"User-Agent": f"asl-cli/{VERSION}"}
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except Exception:
        # Graceful fallback (e.g. offline, firewalled)
        pass
    return None


def run_upgrade(verbose: bool = True) -> int:
    """Upgrades local ASL installation via git pull or package manager."""
    root_dir = Path(__file__).resolve().parent.parent
    if (root_dir / ".git").exists():
        if verbose:
            print(f"📦 Updating ASL repository in {root_dir}...")
        res = subprocess.run(["git", "pull", "--ff-only"], cwd=root_dir, capture_output=True, text=True)
        if res.returncode == 0:
            if verbose:
                print("✓ Successfully updated ASL to the latest release!")
                print(f"  Current version: v{VERSION}")
            return 0
        else:
            if verbose:
                print(f"✗ Git pull failed: {res.stderr.strip()}")
            return 1
    else:
        if verbose:
            print("💡 To upgrade ASL, run your package manager update command:")
            print("  • curl -fsSL https://aslang.dev/install.sh | bash")
            print("  • brew upgrade aslang")
            print("  • npm update -g aslang")
            print("  • pip install --upgrade aslang")
        return 0
