#!/usr/bin/env python3
"""Every corpus program must transpile AND the output must be accepted by the target.

Transpiling without crashing is not evidence the output is valid: the Rust
backend silently emitted a wildcard for list destructuring and every file
"passed" while producing code rustc rejects. A backend gate that does not invoke
the target compiler measures the transpiler's exit code, nothing more.

The Python column had exactly that hole for longer, because Python was the one
backend with no compiler to invoke: it emitted `s(/, concat, ...)` for every
qualified name — not valid Python — and the gate reported `ok`. `compile()` is
Python's accept/reject oracle and is now called like rustc and swiftc.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
# The conformance corpus AND the example tree: an example that does not compile
# teaches an agent a call shape the target rejects, which is worse than no
# example at all.
CORPUS = (sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.as"))
          + sorted((ROOT / "examples").rglob("*.as")))

# Cross-module resolution does not exist: `s/concat` flattens to a name that no
# file in the fixture defines, so the target compiler is right to reject it.
# Skipped whole — reporting a transpile as `ok` whose output is never compiled is
# the failure mode this gate exists to prevent.
SKIP = {"python": {"06-module.as"},
        "rust": {"06-module.as"},
        "swift": {"06-module.as"}}

# A module carrying a foreign declaration belongs to one ecosystem, and a
# transpiler for another target must refuse it BY NAME. Asserted rather than
# skipped: a refusal that silently stopped happening would look like coverage.
REFUSE = {"rust": {"08-ffi.as"}, "swift": {"08-ffi.as"}}


def transpile(backend: str, f: Path) -> tuple[bool, str, str]:
    r = subprocess.run([sys.executable, str(ROOT / "backend" / backend), str(f)],
                       capture_output=True, text=True)
    return r.returncode == 0, r.stdout, (r.stderr.strip().splitlines() or [""])[-1][:70]


class Accepted:
    """Stands in for a CompletedProcess when the check is in-process."""
    def __init__(self, ok: bool, err: str = ""):
        self.returncode = 0 if ok else 1
        self.stderr = err


def compile_python(src: str, d: Path) -> Accepted:
    try:
        compile(src, "lib.py", "exec")
        return Accepted(True)
    except SyntaxError as exc:
        return Accepted(False, f"{exc.msg} (line {exc.lineno})")


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


BACKENDS = [("python", "to_python.py", compile_python, "compile"),
            ("rust", "to_rust.py", compile_rust, "rustc"),
            ("swift", "to_swift.py", compile_swift, "swiftc")]


def main() -> int:
    fails = []
    cols = [n for b in BACKENDS for n in (b[0], b[3]) if n]
    print(f"{'fixture':<26}" + "".join(f"{c:<10}" for c in cols))
    print("-" * (26 + 10 * len(cols)))
    for f in CORPUS:
        label = str(f.relative_to(ROOT / "examples")) if "examples" in f.parts else f.name
        row = []
        for name, script, compiler, cname in BACKENDS:
            if label in SKIP.get(name, ()) or f.name in SKIP.get(name, ()):
                row += ["skipped"] + (["skipped"] if cname else [])
                continue
            ok, src, err = transpile(script, f)
            if label in REFUSE.get(name, ()) or f.name in REFUSE.get(name, ()):
                # The refusal IS the expected result here, so the verdicts invert.
                row += ["refused" if not ok else "ACCEPTED", "n/a"]
                if ok:
                    fails.append(f"{label}: {name} backend accepted a module "
                                 f"declared for another target")
                continue
            row.append("ok" if ok else "FAIL")
            if not ok:
                fails.append(f"{label}: {name} backend: {err}")
            if not cname:
                continue
            if not ok:
                row.append("-")
                continue
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                c = compiler(src, Path(d))
            row.append("ok" if c.returncode == 0 else "FAIL")
            if c.returncode:
                fails.append(f"{label}: {cname} rejected the output: "
                             + (c.stderr.strip().splitlines() or ["?"])[0][:70])
        print(f"{label:<26}" + "".join(f"{x:<10}" for x in row))
    print()
    for x in fails:
        print("  " + x)
    print(f"\n{len(fails)} failure(s)")
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
