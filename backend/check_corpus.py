#!/usr/bin/env python3
"""Every corpus program must transpile AND the output must be accepted by the target.

Transpiling without crashing is not evidence the output is valid: the Rust
backend silently emitted a wildcard for list destructuring and every file
"passed" while producing code rustc rejects. A backend gate that does not invoke
the target compiler measures the transpiler's exit code, nothing more.

The same reasoning applies to Python, where the gate was still doing exactly
that: the module fixture transpiled to `s/concat(...)` and passed. py_compile
exits 0 on that output — it is a division expression — so a fixture may also
declare, in a `; run:` header, one expression over its own emitted names that has
to evaluate true. Compiling proves the shape; only running proves the meaning.

There is no skip list, and there is not going to be one: a `skipped` column still
exits 0, and that is how the module fixture's broken lowering stayed invisible.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
# Every source any gate counts is compile-gated: the differential harness and
# the coverage tracer both execute the bench sources, and a source that runs
# without compiling here is one whose backend coverage nothing checks.
CORPUS = (sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.agents"))
          + sorted((ROOT / "bench").rglob("*.agents")))
MODULES = ROOT / "grammar" / "corpus" / "modules"


def transpile(backend: str, f: Path) -> tuple[bool, str, str]:
    r = subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(f),
                        "--root", str(MODULES)], capture_output=True, text=True)
    return r.returncode == 0, r.stdout, (r.stderr.strip().splitlines() or [""])[-1][:70]


def declared_run(f: Path) -> str | None:
    """The expression a fixture declares in its leading comments, or None."""
    for line in f.read_text().splitlines():
        if not line.startswith(";"):
            return None
        if "; run:" in line:
            return line.split("; run:", 1)[1].strip()
    return None


def execute(py_src: str, expr: str) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        (Path(d) / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
        mod = Path(d) / "cand.py"
        mod.write_text(py_src)
        drv = Path(d) / "drv.py"
        drv.write_text(f"import runpy, sys\n"
                       f"ns = runpy.run_path({str(mod)!r})\n"
                       f"sys.exit(0 if eval({expr!r}, ns) else 1)\n")
        r = subprocess.run([sys.executable, str(drv)], cwd=d, capture_output=True, text=True)
        return r.returncode == 0, (r.stderr.strip().splitlines() or [""])[-1][:70]


def main() -> int:
    fails = []
    if not CORPUS:
        print("no corpus sources were found; the gate would pass by having nothing to do")
        return 1
    print(f"{'fixture':<26} {'python':<12} {'compile':<10} {'run':<10} "
          f"{'rust':<12} {'rustc':<10}")
    print("-" * 84)
    for f in CORPUS:
        py_ok, py_src, py_err = transpile("to_python.py", f)
        rs_ok, rs_src, rs_err = transpile("to_rust.py", f)
        pyc = "-"
        if py_ok:
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                mod = Path(d) / "cand.py"
                mod.write_text(py_src)
                c = subprocess.run([sys.executable, "-m", "py_compile", str(mod)],
                                   capture_output=True, text=True)
                pyc = "ok" if c.returncode == 0 else "FAIL"
                if c.returncode:
                    fails.append(f"{f.name}: python rejected the output: "
                                 f"{c.stderr.strip().splitlines()[-1][:60]}")
        ran = "-"
        expr = declared_run(f)
        if expr is not None:
            if "==" not in expr:
                ran = "FAIL"
                fails.append(f"{f.name}: `; run:` header has no `==` assertion: `{expr}`")
            elif not py_ok:
                ran = "FAIL"
            else:
                ok, why = execute(py_src, expr)
                ran = "ok" if ok else "FAIL"
                if not ok:
                    fails.append(f"{f.name}: `{expr}` did not hold: {why}")
        rustc = "-"
        if rs_ok:
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                (Path(d) / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
                (Path(d) / "lib.rs").write_text(rs_src)
                c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                                    "--crate-type=lib", "lib.rs"], cwd=d,
                                   capture_output=True, text=True)
                rustc = "ok" if c.returncode == 0 else "FAIL"
                if c.returncode:
                    fails.append(f"{f.name}: rustc rejected the output")
        if not py_ok:
            fails.append(f"{f.name}: python backend: {py_err}")
        if not rs_ok:
            fails.append(f"{f.name}: rust backend: {rs_err}")
        print(f"{f.name:<26} {'ok' if py_ok else 'FAIL':<12} {pyc:<10} {ran:<10} "
              f"{'ok' if rs_ok else 'FAIL':<12} {rustc:<10}")
    print()
    for x in fails:
        print("  " + x)
    print(f"\n{len(fails)} failure(s)")
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
