#!/usr/bin/env python3
"""
Deployment Pre-Flight Validator for Cloudflare Pages / Static Hosting.
Verifies production bundle integrity, assets, and wrangler configuration.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def check_deployment() -> bool:
    errors = []
    print("--- Running Deployment Pre-Flight Checks ---")

    # 1. Check wrangler.toml
    wrangler_file = ROOT / "wrangler.toml"
    if not wrangler_file.exists():
        errors.append("Missing wrangler.toml configuration file.")
    else:
        content = wrangler_file.read_text()
        if "pages_build_output_dir" not in content:
            errors.append("wrangler.toml must declare pages_build_output_dir.")

    # 2. Check web/dist build output
    dist_dir = ROOT / "web" / "dist"
    if not dist_dir.exists():
        errors.append("web/dist directory does not exist. Run 'npm run build:web' first.")
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

    # 3. Check release notes
    release_notes = ROOT / "docs" / "RELEASE_NOTES_v0.1.0.md"
    if not release_notes.exists():
        errors.append("Missing docs/RELEASE_NOTES_v0.1.0.md documentation.")

    if errors:
        print(f"FAILED: {len(errors)} deployment pre-flight error(s):")
        for err in errors:
            print(f"  - {err}")
        return False

    print("OK: Deployment pre-flight checks passed (Cloudflare Pages ready).")
    return True


if __name__ == "__main__":
    if not check_deployment():
        sys.exit(1)
