"""Decentralized, Go-style package manager and dependency management engine for ASL."""
import json
import os
import shutil
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


def remove_package(pkg_path: str) -> int:
    """Removes a package from asl.json, .asl_modules, and asl.lock."""
    project_root, manifest = get_project_root()
    pkg_clean, _ = normalize_pkg_url(pkg_path)

    manifest_file = project_root / "asl.json"
    deps = manifest.get("dependencies", {})
    if pkg_clean in deps:
        del deps[pkg_clean]
        manifest["dependencies"] = deps
        manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"✓ Removed {pkg_clean} from asl.json")

    # Remove from .asl_modules
    target_dir = project_root / ".asl_modules" / pkg_clean
    if target_dir.exists():
        if target_dir.is_symlink():
            target_dir.unlink()
        else:
            shutil.rmtree(target_dir, ignore_errors=True)
        print(f"✓ Deleted local module directory {target_dir}")

    # Update lockfile
    lock_file = project_root / "asl.lock"
    if lock_file.exists():
        try:
            lock_data = json.loads(lock_file.read_text())
            if pkg_clean in lock_data:
                del lock_data[pkg_clean]
                lock_file.write_text(json.dumps(lock_data, indent=2) + "\n")
        except Exception:
            pass
    return 0


def list_packages(json_mode: bool = False) -> int:
    """Lists all direct dependencies and their installation status."""
    project_root, manifest = get_project_root()
    deps = manifest.get("dependencies", {})

    out_list = []
    for pkg, ver in deps.items():
        installed = (project_root / ".asl_modules" / pkg).exists()
        out_list.append({
            "package": pkg,
            "required_version": ver,
            "installed": installed,
            "path": str(project_root / ".asl_modules" / pkg)
        })

    if json_mode:
        print(json.dumps(out_list, indent=2))
    else:
        print(f"📦 Dependencies for '{manifest.get('name', 'project')}' ({len(deps)} total):")
        if not deps:
            print("  (no dependencies declared in asl.json)")
            return 0
        for item in out_list:
            status = "✓ installed" if item["installed"] else "✗ missing (run 'asl install')"
            print(f"  • {item['package']} @ {item['required_version']} [{status}]")
    return 0


def link_package(pkg_identifier: str, local_path: str) -> int:
    """Links a local path as an alias for a package (monorepo/local dev workflow)."""
    project_root, manifest = get_project_root()
    pkg_clean, _ = normalize_pkg_url(pkg_identifier)
    target_link = project_root / ".asl_modules" / pkg_clean
    src_path = Path(local_path).resolve()

    if not src_path.exists():
        print(f"✗ Source path does not exist: {src_path}")
        return 1

    target_link.parent.mkdir(parents=True, exist_ok=True)
    if target_link.is_symlink():
        target_link.unlink()
    elif target_link.is_dir():
        shutil.rmtree(target_link)

    target_link.symlink_to(src_path)
    print(f"✓ Linked {pkg_clean} -> {src_path}")
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
