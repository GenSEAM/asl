#!/usr/bin/env python3
"""Differential gate: one AgentS source, every backend, identical results.

Portability across targets is a claim, not a property. Runtimes disagree by
default — measured on this machine, Python and JavaScript already differ on
2**53+1 and on rounding a .5 — so equivalence only exists where it is enforced.
This is the enforcement.

What it does not enforce: the benchmark's cases never overflow, and the three
backends do not agree there. Swift traps, Rust traps in debug, Python has
arbitrary-precision integers. See EXPERIMENT.md amendment 2026-08-21-b.

Exit code is the number of disagreements.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent


def run_python(src: Path, task: dict) -> list:
    sys.path.insert(0, str(ROOT / "backend"))
    from to_python import Transpiler
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "cand.py").write_text(Transpiler().transpile(src.read_text()))
        drv = Path(d) / "drv.py"
        drv.write_text(
            f"import sys, json\nsys.path[:0]=[{str(ROOT/'backend')!r},{d!r}]\nimport cand\n"
            f"fn=getattr(cand,{task['entry'].replace('-','_')!r})\n"
            f"print(json.dumps([fn(i) for i,_ in json.loads({json.dumps(json.dumps(task['cases']))})]))\n")
        r = subprocess.run([sys.executable, str(drv)], capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError(r.stderr.strip().splitlines()[-1][:120])
        return json.loads(r.stdout)


def run_rust(src: Path, task: dict) -> list:
    from to_rust import ToRust
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
        body = ToRust().transpile(src.read_text())
        inputs = ", ".join(f'{json.dumps(i)}.to_string()' for i, _ in task["cases"])
        fn = task["entry"].replace("-", "_")
        body += (
            "\nfn main() {\n"
            f"    let ins: Vec<String> = vec![{inputs}];\n"
            "    let mut out: Vec<String> = Vec::new();\n"
            f"    for i in ins {{ let g = {fn}(i);\n"
            "        let mut kv: Vec<String> = Vec::new();\n"
            "        for (k, v) in g.iter() { kv.push(format!(\"{:?}:{}\", k, v)); }\n"
            "        out.push(format!(\"{{{}}}\", kv.join(\",\"))); }\n"
            "    println!(\"[{}]\", out.join(\",\"));\n}\n")
        (Path(d) / "main.rs").write_text(body)
        c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                            "main.rs", "-o", "prog"], cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("rustc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
        r = subprocess.run([str(Path(d) / "prog")], capture_output=True, text=True)
        return json.loads(r.stdout.strip())


def run_swift(src: Path, task: dict) -> list:
    from to_swift import ToSwift, mangle
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "rt.swift").write_text((ROOT / "backend" / "swift" / "rt.swift").read_text())
        body = ToSwift().transpile(src.read_text())
        inputs = ", ".join(json.dumps(i) for i, _ in task["cases"])
        fn = mangle(task["entry"])
        # Keys are emitted in sorted order, which is the order the language
        # specifies for map iteration and the order BTreeMap gives Rust for free.
        body += (
            "\nlet ins: [String] = [" + inputs + "]\n"
            "var out: [String] = []\n"
            "for i in ins {\n"
            f"    let g = {fn}(i)\n"
            "    var kv: [String] = []\n"
            "    for k in g.keys.sorted() { kv.append(\"\\\"\\(k)\\\":\\(g[k]!)\") }\n"
            "    out.append(\"{\" + kv.joined(separator: \",\") + \"}\")\n"
            "}\n"
            "print(\"[\" + out.joined(separator: \",\") + \"]\")\n")
        (Path(d) / "main.swift").write_text(body)
        c = subprocess.run(["swiftc", "-O", "rt.swift", "main.swift", "-o", "prog"],
                           cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("swiftc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
        r = subprocess.run([str(Path(d) / "prog")], capture_output=True, text=True)
        return json.loads(r.stdout.strip())


BACKENDS = {"python": run_python, "rust": run_rust, "swift": run_swift}


def main() -> int:
    sys.path.insert(0, str(ROOT / "backend"))
    task = json.loads((ROOT / "bench" / "tasks" / "histogram.json").read_text())
    src = ROOT / "bench" / "algo" / "variants" / "tight.agents"

    got = {name: run(src, task) for name, run in BACKENDS.items()}

    bad = 0
    head = f"{'input':<12} {'expected':<22}" + "".join(f"{n:<22}" for n in got)
    print(head)
    print("-" * len(head))
    for k, (inp, want) in enumerate(task["cases"]):
        row = {n: v[k] for n, v in got.items()}
        agree = all(v == want for v in row.values())
        bad += 0 if agree else 1
        print(f"{inp!r:<12} {json.dumps(want):<22}"
              + "".join(f"{json.dumps(row[n]):<22}" for n in got)
              + ("" if agree else "  <-- DISAGREE"))
    print(f"\n{bad} disagreement(s) across {len(task['cases'])} cases x {len(got)} backends")
    return bad


if __name__ == "__main__":
    sys.exit(main())
