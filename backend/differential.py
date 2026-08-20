#!/usr/bin/env python3
"""Differential gate: one AgentS source, every backend, identical results.

Portability across targets is a claim, not a property. Runtimes disagree by
default — measured on this machine, Python and JavaScript already differ on
2**53+1 and on rounding a .5 — so equivalence only exists where it is enforced.
This is the enforcement.

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
        raw = r.stdout.strip()
        # Rust prints {"a":1,...}; normalise to the same shape Python returns.
        return json.loads(raw.replace("{", "{").replace("}", "}")) if raw.startswith("[{") else raw


def main() -> int:
    sys.path.insert(0, str(ROOT / "backend"))
    task = json.loads((ROOT / "bench" / "tasks" / "histogram.json").read_text())
    src = ROOT / "bench" / "algo" / "variants" / "tight.agents"
    expected = [w for _, w in task["cases"]]

    py = run_python(src, task)
    rs = run_rust(src, task)

    bad = 0
    print(f"{'input':<12} {'expected':<22} {'python':<22} {'rust':<22}")
    print("-" * 82)
    for k, ((inp, want), p) in enumerate(zip(task["cases"], py)):
        r = rs[k] if isinstance(rs, list) else "?"
        agree = (p == want) and (r == want)
        bad += 0 if agree else 1
        print(f"{inp!r:<12} {json.dumps(want):<22} {json.dumps(p):<22} {json.dumps(r):<22}"
              + ("" if agree else "  <-- DISAGREE"))
    print(f"\n{bad} disagreement(s) across {len(py)} cases x 2 backends")
    return bad


if __name__ == "__main__":
    sys.exit(main())
