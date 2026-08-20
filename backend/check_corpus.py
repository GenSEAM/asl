#!/usr/bin/env python3
"""Every corpus program must transpile AND the output must be accepted by the target.

Transpiling without crashing is not evidence the output is valid: the Rust
backend silently emitted a wildcard for list destructuring and every file
"passed" while producing code rustc rejects. A backend gate that does not invoke
the target compiler measures the transpiler's exit code, nothing more.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
CORPUS = sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.agents"))
# Qualified names and module headers are parsed but not yet lowered; see ROADMAP.
SKIP_RUST = {"06-module.agents"}


def transpile(backend: str, f: Path) -> tuple[bool, str, str]:
    r = subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(f)],
                       capture_output=True, text=True)
    return r.returncode == 0, r.stdout, (r.stderr.strip().splitlines() or [""])[-1][:70]


def main() -> int:
    fails = []
    print(f"{'fixture':<26} {'python':<12} {'rust':<12} {'rustc':<10}")
    print("-" * 62)
    for f in CORPUS:
        py_ok, _, py_err = transpile("to_python.py", f)
        rs_ok, rs_src, rs_err = transpile("to_rust.py", f)
        rustc = "-"
        if rs_ok and f.name not in SKIP_RUST:
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                (Path(d) / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
                (Path(d) / "lib.rs").write_text(rs_src)
                c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                                    "--crate-type=lib", "lib.rs"], cwd=d,
                                   capture_output=True, text=True)
                rustc = "ok" if c.returncode == 0 else "FAIL"
                if c.returncode:
                    fails.append(f"{f.name}: rustc rejected the output")
        elif f.name in SKIP_RUST:
            rustc = "skipped"
        if not py_ok:
            fails.append(f"{f.name}: python backend: {py_err}")
        if not rs_ok:
            fails.append(f"{f.name}: rust backend: {rs_err}")
        print(f"{f.name:<26} {'ok' if py_ok else 'FAIL':<12} {'ok' if rs_ok else 'FAIL':<12} {rustc:<10}")
    print()
    for x in fails:
        print("  " + x)
    print(f"\n{len(fails)} failure(s)")
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
