"""Decentralized, Go-style package manager and registry client for ASL."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = Path.home() / ".asl" / "pkg" / "mod"


def get_project_root(start_dir: Path | None = None) -> tuple[Path, dict]:
    cur = (start_dir or Path.cwd()).resolve()
    while True:
        cand = cur / "asl.json"
        if cand.is_file():
            try:
                return cur, json.loads(cand.read_text())
            except Exception as exc:
                raise ValueError(f"Invalid asl.json in {cur}: {exc}")
        if cur.parent == cur:
            break
        cur = cur.parent
    return Path.cwd().resolve(), {}


def normalize_pkg_url(url: str) -> tuple[str, str]:
    """Extracts (repo_url, import_path) from package identifier."""
    cleaned = url.strip()
    if cleaned.startswith("https://"):
        cleaned = cleaned[8:]
    elif cleaned.startswith("http://"):
        cleaned = cleaned[7:]
    
    parts = cleaned.split("@", 1)
    pkg_path = parts[0].rstrip("/")
    version = parts[1] if len(parts) > 1 else "main"
    return pkg_path, version


def add_package(pkg_identifier: str, local: bool = True) -> int:
    """Installs a remote package from GitHub/Git and records it in asl.json."""
    pkg_path, version = normalize_pkg_url(pkg_identifier)
    project_root, manifest = get_project_root()

    print(f"⚡ Fetching package {pkg_path}@{version}...")

    # Target directory in local .asl_modules or global cache
    if local:
        target_dir = project_root / ".asl_modules" / pkg_path
    else:
        target_dir = CACHE_DIR / pkg_path

    target_dir.parent.mkdir(parents=True, exist_ok=True)

    git_url = f"https://{pkg_path}.git"
    t0 = time.perf_counter()

    if (target_dir / ".git").exists():
        res = subprocess.run(["git", "fetch", "--all"], cwd=target_dir, capture_output=True, text=True)
        checkout = subprocess.run(["git", "checkout", version], cwd=target_dir, capture_output=True, text=True)
        if checkout.returncode != 0:
            print(f"✗ Failed to checkout {version}: {checkout.stderr.strip()}")
            return 1
    else:
        res = subprocess.run(["git", "clone", "--depth", "1", "--branch", version, git_url, str(target_dir)],
                             capture_output=True, text=True)
        if res.returncode != 0:
            # Fallback without branch flag
            res = subprocess.run(["git", "clone", "--depth", "1", git_url, str(target_dir)],
                                 capture_output=True, text=True)
            if res.returncode != 0:
                print(f"✗ Git clone failed for {git_url}: {res.stderr.strip()}")
                return 1

    dt = (time.perf_counter() - t0) * 1000.0
    print(f"✓ Installed {pkg_path} in {dt:.1f}ms -> {target_dir}")

    # Update asl.json
    manifest_file = project_root / "asl.json"
    if manifest_file.exists():
        deps = manifest.get("dependencies", {})
        deps[pkg_path] = version
        manifest["dependencies"] = deps
        manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"✓ Recorded dependency in {manifest_file}")

    # Write lockfile
    lock_file = project_root / "asl.lock"
    lock_data = {}
    if lock_file.exists():
        try:
            lock_data = json.loads(lock_file.read_text())
        except Exception:
            pass
    lock_data[pkg_path] = {"version": version, "path": str(target_dir)}
    lock_file.write_text(json.dumps(lock_data, indent=2) + "\n")

    return 0


def install_all_packages() -> int:
    """Restores all dependencies listed in asl.json."""
    project_root, manifest = get_project_root()
    deps = manifest.get("dependencies", {})
    if not deps:
        print("No dependencies defined in asl.json.")
        return 0

    print(f"⚡ Restoring {len(deps)} package(s) for '{manifest.get('name', 'project')}'...")
    has_err = False
    for pkg_path, ver in deps.items():
        code = add_package(f"{pkg_path}@{ver}", local=True)
        if code != 0:
            has_err = True

    return 1 if has_err else 0
