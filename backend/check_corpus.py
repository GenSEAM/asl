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
SKIP = {"rust": {"06-module.agents"}, "swift": {"06-module.agents"}}


def transpile(backend: str, f: Path) -> tuple[bool, str, str]:
    r = subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(f)],
                       capture_output=True, text=True)
    return r.returncode == 0, r.stdout, (r.stderr.strip().splitlines() or [""])[-1][:70]


def compile_rust(src: str, d: Path) -> subprocess.CompletedProcess:
    (d / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
    (d / "lib.rs").write_text(src)
    return subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                           "--crate-type=lib", "lib.rs"], cwd=d, capture_output=True, text=True)


def compile_swift(src: str, d: Path) -> subprocess.CompletedProcess:
    (d / "rt.swift").write_text((ROOT / "backend" / "swift" / "rt.swift").read_text())
    (d / "lib.swift").write_text(src)
    # -typecheck, not -c: the corpus has no entry point and the question a gate
    # asks here is whether the target compiler accepts the code, not whether it
    # links.
    return subprocess.run(["swiftc", "-typecheck", "rt.swift", "lib.swift"],
                          cwd=d, capture_output=True, text=True)


BACKENDS = [("python", "to_python.py", None, None),
            ("rust", "to_rust.py", compile_rust, "rustc"),
            ("swift", "to_swift.py", compile_swift, "swiftc")]


def main() -> int:
    fails = []
    cols = [n for b in BACKENDS for n in (b[0], b[3]) if n]
    print(f"{'fixture':<26}" + "".join(f"{c:<10}" for c in cols))
    print("-" * (26 + 10 * len(cols)))
    for f in CORPUS:
        row = []
        for name, script, compiler, cname in BACKENDS:
            # A skipped fixture is skipped whole. Reporting a transpile as `ok`
            # while its output is never compiled is the failure mode this gate
            # exists to prevent.
            if f.name in SKIP.get(name, ()):
                row += ["skipped"] + (["skipped"] if cname else [])
                continue
            ok, src, err = transpile(script, f)
            row.append("ok" if ok else "FAIL")
            if not ok:
                fails.append(f"{f.name}: {name} backend: {err}")
            if not cname:
                continue
            if not ok:
                row.append("-")
                continue
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                c = compiler(src, Path(d))
            row.append("ok" if c.returncode == 0 else "FAIL")
            if c.returncode:
                fails.append(f"{f.name}: {cname} rejected the output: "
                             + (c.stderr.strip().splitlines() or ["?"])[0][:70])
        print(f"{f.name:<26}" + "".join(f"{x:<10}" for x in row))
    print()
    for x in fails:
        print("  " + x)
    print(f"\n{len(fails)} failure(s)")
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
