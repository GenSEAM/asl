#!/usr/bin/env python3
"""
Deployment Pre-Flight Validator for Cloudflare Pages / Static Hosting.
Verifies TypeScript compilation, production build, bundle integrity, and wrangler configuration.
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def check_deployment() -> bool:
    errors = []
    print("--- Running Deployment Pre-Flight Checks ---")

    # 1. Check pnpm lockfile integrity (frozen-lockfile for Cloudflare Pages)
    print("--> Checking pnpm frozen-lockfile integrity...")
    env = os.environ.copy()
    env["PATH"] = f"/usr/local/bin:{env.get('PATH', '')}"
    pnpm_bin = "pnpm"
    r = subprocess.run(
        [pnpm_bin, "install", "--frozen-lockfile"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        env=env
    )
    if r.returncode != 0:
        errors.append(f"pnpm lockfile is outdated (Cloudflare Pages CI will fail):\n{r.stderr or r.stdout}")

    # 2. Run TypeScript typecheck on web
    print("--> Typechecking web app (tsc -p web/tsconfig.json)...")
    node_bin = "/usr/local/bin/node" if Path("/usr/local/bin/node").exists() else "node"
    tsc_script = ROOT / "web" / "node_modules" / "typescript" / "bin" / "tsc"
    vite_script = ROOT / "web" / "node_modules" / "vite" / "bin" / "vite"

    if tsc_script.exists():
        r = subprocess.run(
            [node_bin, str(tsc_script), "-p", str(ROOT / "web" / "tsconfig.json")],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=env
        )
        if r.returncode != 0:
            errors.append(f"TypeScript compilation failed in web/:\n{r.stdout}\n{r.stderr}")

    # 2. Build web app bundle
    if not errors and vite_script.exists():
        print("--> Building web production bundle (vite build web)...")
        r = subprocess.run(
            [node_bin, str(vite_script), "build", "web"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=env
        )
        if r.returncode != 0:
            errors.append(f"Vite production build failed:\n{r.stdout}\n{r.stderr}")

    # 3. Check wrangler.toml
    wrangler_file = ROOT / "wrangler.toml"
    if not wrangler_file.exists():
        errors.append("Missing wrangler.toml configuration file.")
    else:
        content = wrangler_file.read_text()
        if "pages_build_output_dir" not in content:
            errors.append("wrangler.toml must declare pages_build_output_dir.")

    # 4. Check web/dist build output
    dist_dir = ROOT / "web" / "dist"
    if not dist_dir.exists():
        errors.append("web/dist directory does not exist after build.")
    else:
        index_html = dist_dir / "index.html"
        if not index_html.exists():
            errors.append("Missing web/dist/index.html entrypoint.")
        else:
            html_content = index_html.read_text()
            if "<div id=\"root\">" not in html_content:
                errors.append("web/dist/index.html is missing root mounting div.")

        assets_dir = dist_dir / "assets"
        if not assets_dir.exists() or not list(assets_dir.glob("*.js")):
            errors.append("Missing compiled javascript chunks in web/dist/assets/.")

    # 5. Check release notes
    release_notes = ROOT / "docs" / "RELEASE_NOTES_v0.1.0.md"
    if not release_notes.exists():
        errors.append("Missing docs/RELEASE_NOTES_v0.1.0.md documentation.")

    if errors:
        print(f"FAILED: {len(errors)} deployment pre-flight error(s):")
        for err in errors:
            print(f"  - {err}")
        return False

    print("OK: Deployment pre-flight & TypeScript checks passed (Cloudflare Pages ready).")
    return True


if __name__ == "__main__":
    if not check_deployment():
        sys.exit(1)
