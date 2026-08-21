#!/usr/bin/env python3
"""Differential gate: one AgentScript source, every backend, identical results.

Portability across targets is a claim, not a property. Runtimes disagree by
default, so equivalence exists only where it is enforced. This is the
enforcement.

The example this file used to give — Python and JavaScript differing on
2**53+1 — is no longer one, and the reason is worth keeping: `Int64` lowers to
`bigint` in the TypeScript backend rather than to `number`, so the disagreement
was designed out instead of being measured. Rounding a half still differs, and
so does ordering a tagged value (`EXPERIMENT.md` amendment 2026-08-21-d).

What it does not enforce: the benchmark's cases never overflow, and the three
backends do not agree there. Swift traps, Rust traps in debug, Python has
arbitrary-precision integers. See EXPERIMENT.md amendment 2026-08-21-b.

A task declares its `result` shape, because the driver that collects an answer
has to render it: a Map is printed key-sorted, a String verbatim. Adding a shape
is how a new class of divergence becomes gateable.

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
        # Python needs no per-shape rendering: json.dumps already agrees with the
        # expected literal for both a dict and a str.
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
        if task.get("result") == "string":
            render = f"    for i in ins {{ out.push(format!(\"{{:?}}\", {fn}(i))); }}\n"
        else:
            render = (
                f"    for i in ins {{ let g = {fn}(i);\n"
                "        let mut kv: Vec<String> = Vec::new();\n"
                "        for (k, v) in g.iter() { kv.push(format!(\"{:?}:{}\", k, v)); }\n"
                "        out.push(format!(\"{{{}}}\", kv.join(\",\"))); }\n")
        body += (
            "\nfn main() {\n"
            f"    let ins: Vec<String> = vec![{inputs}];\n"
            "    let mut out: Vec<String> = Vec::new();\n"
            + render +
            "    println!(\"[{}]\", out.join(\",\"));\n}\n")
        (Path(d) / "main.rs").write_text(body)
        c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                            "main.rs", "-o", "prog"], cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("rustc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
        r = subprocess.run([str(Path(d) / "prog")], capture_output=True, text=True)
        # A trap prints nothing on stdout, so without this the gate died inside
        # json.loads with a decode error naming neither the backend nor the
        # panic. Overflow is exactly the case this reaches.
        if r.returncode:
            raise RuntimeError("rust: " + (r.stderr.strip().splitlines() or ["?"])[-1][:140])
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
        if task.get("result") == "string":
            render = ("for i in ins {\n"
                      f"    out.append(\"\\\"\\({fn}(i))\\\"\")\n"
                      "}\n")
        else:
            render = ("for i in ins {\n"
                      f"    let g = {fn}(i)\n"
                      "    var kv: [String] = []\n"
                      "    for k in g.keys.sorted() { kv.append(\"\\\"\\(k)\\\":\\(g[k]!)\") }\n"
                      "    out.append(\"{\" + kv.joined(separator: \",\") + \"}\")\n"
                      "}\n")
        body += (
            "\nlet ins: [String] = [" + inputs + "]\n"
            "var out: [String] = []\n"
            + render +
            "print(\"[\" + out.joined(separator: \",\") + \"]\")\n")
        (Path(d) / "main.swift").write_text(body)
        c = subprocess.run(["swiftc", "-O", "rt.swift", "main.swift", "-o", "prog"],
                           cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("swiftc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
        r = subprocess.run([str(Path(d) / "prog")], capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError("swift: " + (r.stderr.strip().splitlines() or ["?"])[-1][:140])
        return json.loads(r.stdout.strip())


def run_typescript(src: Path, task: dict) -> list:
    from to_typescript import ToTypeScript, mangle
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "rt.ts").write_text((ROOT / "backend" / "ts" / "rt.ts").read_text())
        body = ToTypeScript().transpile_program(
            __import__("modules").load(src, p=ToTypeScript().parser))
        inputs = ", ".join(json.dumps(i) for i, _ in task["cases"])
        fn = mangle(task["entry"])
        if task.get("result") == "string":
            render = f"  out.push(JSON.stringify({fn}(i)))\n"
        else:
            # Keys are emitted in sorted order, which is the order the language
            # specifies for map iteration.
            # RT.mKeys/mGet, not the JS Map API: ASMap wraps a Map keyed by a
            # canonical rendering, and mKeys is what sorts, which is the order
            # the language specifies for map iteration.
            render = (f"  const g = {fn}(i)\n"
                      "  const kv: string[] = []\n"
                      "  for (const k of RT.mKeys(g)) {\n"
                      "    const v = RT.mGet(g, k)\n"
                      "    kv.push(JSON.stringify(k) + \":\" + (v as any).value.toString())\n"
                      "  }\n"
                      "  out.push(\"{\" + kv.join(\",\") + \"}\")\n")
        body += ("\nconst ins: string[] = [" + inputs + "]\n"
                 "const out: string[] = []\n"
                 "for (const i of ins) {\n" + render + "}\n"
                 "console.log(\"[\" + out.join(\",\") + \"]\")\n")
        (p / "main.ts").write_text(body)
        c = subprocess.run([str(ROOT / "node_modules" / ".bin" / "tsc"),
                            "--strict", "--target", "ES2022", "--module", "commonjs",
                            "--types", "node",
                            "--typeRoots", str(ROOT / "node_modules" / "@types"),
                            "rt.ts", "main.ts"], cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("tsc: " + ((c.stdout or c.stderr).strip().splitlines()
                                          or ["?"])[0][:140])
        r = subprocess.run(["node", "main.js"], cwd=d, capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError("node: " + (r.stderr.strip().splitlines() or ["?"])[0][:140])
        return json.loads(r.stdout.strip())


BACKENDS = {"python": run_python, "typescript": run_typescript,
            "rust": run_rust, "swift": run_swift}


# Each entry is (task path, source path), both relative to the repository root.
#
# `bench/tasks/` holds generation tasks — `bench/harness/run.py` globs that
# directory and asks a model to solve everything in it. `bench/differential/`
# holds fixtures that only ever run here: they pin behaviour and have known
# answers, so putting them under `tasks/` would have the harness spend pilot
# budget generating solutions to problems it was handed the answers to.
SUITE = [("bench/tasks/histogram.json", "bench/algo/variants/tight.as"),
         ("bench/differential/arith.json", "bench/algo/variants/arith.as"),
         ("bench/differential/cron.json", "examples/port/cron/cron.as")]


def main() -> int:
    sys.path.insert(0, str(ROOT / "backend"))
    bad, cases = 0, 0
    for task_file, src_file in SUITE:
        task = json.loads((ROOT / task_file).read_text())
        src = ROOT / src_file
        got, broken = {}, {}
        for name, run in BACKENDS.items():
            try:
                got[name] = run(src, task)
            except Exception as exc:      # noqa: BLE001 — name the backend, not the frame
                broken[name] = f"{type(exc).__name__}: {exc}"

        print(f"== {task['id']}  ({', '.join(BACKENDS)})")
        # A backend that could not answer is a disagreement with all of them, and
        # saying which one and why beats the traceback this used to raise from
        # inside whichever runner failed first.
        for name, why in broken.items():
            print(f"  BROKEN    {name}: {why}")
            bad += len(task["cases"])
        if broken:
            cases += len(task["cases"])
            print()
            continue
        for k, (inp, want) in enumerate(task["cases"]):
            row = {n: v[k] for n, v in got.items()}
            agree = all(v == want for v in row.values())
            bad += 0 if agree else 1
            cases += 1
            # Agreement is the common case and its detail is noise; a
            # disagreement prints every backend's answer in full, because that
            # is the only time the values matter.
            if agree:
                print(f"  ok        {inp!r}")
            else:
                print(f"  DISAGREE  {inp!r}")
                print(f"      expected  {json.dumps(want)}")
                for n in got:
                    mark = " " if row[n] == want else "*"
                    print(f"    {mark} {n:<8} {json.dumps(row[n])}")
        print()
    print(f"{bad} disagreement(s) across {cases} cases x {len(BACKENDS)} backends")
    return bad


if __name__ == "__main__":
    sys.exit(main())
