#!/usr/bin/env python3
"""Differential gate: one AgentS source, every backend, identical results.

Portability across targets is a claim, not a property. Runtimes disagree by
default — measured on this machine, Python and JavaScript already differ on
2**53+1 and on rounding a .5 — so equivalence only exists where it is enforced.
This is the enforcement.

Two modes. The function mode calls an entry with cases and compares returns. The
program mode runs a whole program and compares its stdout *and* its exit status,
which is the only way to check the I/O surface: an error case is chosen from the
host's errno on one target and its ErrorKind on the other, and nothing but
running both proves those land on the same case.

Exit code is the number of disagreements.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
# Imports are linked into one artifact, so every transpile here needs the search
# root the corpus module fixtures live under.
ROOTS = [ROOT / "grammar" / "corpus" / "modules"]


def run_python(src: Path, task: dict) -> list:
    sys.path.insert(0, str(ROOT / "backend"))
    from to_python import Transpiler
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "cand.py").write_text(
            Transpiler().transpile(src.read_text(), path=src, roots=ROOTS))
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
        body = ToRust().transpile(src.read_text(), path=src, roots=ROOTS)
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


def build_python(src: Path, d: Path) -> list[str]:
    from to_python import Transpiler
    (d / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
    (d / "cand.py").write_text(
        Transpiler().transpile(src.read_text(), path=src, roots=ROOTS))
    return [sys.executable, str(d / "cand.py")]


def build_rust(src: Path, d: Path) -> list[str]:
    from to_rust import ToRust
    (d / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
    (d / "main.rs").write_text(ToRust().transpile(src.read_text(), path=src, roots=ROOTS))
    c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                        "main.rs", "-o", "prog"], cwd=d, capture_output=True, text=True)
    if c.returncode:
        raise RuntimeError("rustc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
    return [str(d / "prog")]


def programs(src: Path, cases: list[tuple]) -> int:
    """Run a whole program on both targets and compare stdout and exit status.

    A case may carry a third element: the stdout the program is *supposed* to
    produce. Agreement alone cannot see a defect both backends share — a `cond`
    clause dropping its leading effect was dropped by both, so the comparison
    was green on output neither should have produced.
    """
    bad = 0
    print(f"\n{'argv':<22} {'python':<28} {'rust':<28} exit")
    print("-" * 88)
    for argv, fixture, *declared in cases:
        want = declared[0] if declared else None
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "sample.txt").write_text(fixture)
            runners = {"python": build_python(src, d), "rust": build_rust(src, d)}
            seen = {}
            for name, cmd in runners.items():
                r = subprocess.run(cmd + argv, cwd=d, capture_output=True, text=True)
                seen[name] = (r.stdout, r.returncode)
            agree = seen["python"] == seen["rust"]
            declared_ok = want is None or seen["python"][0] == want
            bad += 0 if (agree and declared_ok) else 1
            note = ("" if agree else "  <-- DISAGREE") + \
                   ("" if declared_ok else "  <-- NOT THE DECLARED OUTPUT")
            print(f"{' '.join(argv):<22} {seen['python'][0]!r:<28} {seen['rust'][0]!r:<28} "
                  f"{seen['python'][1]}/{seen['rust'][1]}" + note)
    return bad


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
    # The failing path is checked, not only the happy one: it is the error
    # mapping, not the read itself, that the two runtimes derive independently.
    bad += programs(ROOT / "grammar" / "corpus" / "valid" / "08-io.agents",
                    [(["sample.txt"], "hello from a file\n"),
                     (["missing.txt"], ""),
                     (["sample.txt", "nodir/out.txt"], "hello from a file\n"),
                     ([], "")])
    # An imported union is a tagged tuple on one target and a namespaced variant
    # on the other, each derived independently; and the program reaches one
    # module through two aliases, which is the cheap discriminator for a lowering
    # keyed on the alias rather than on the defining module path.
    bad += programs(ROOT / "grammar" / "corpus" / "valid" / "13-module-program.agents",
                    [([], "")])
    # Bodies with more than one expression, in every position that admits one.
    # The expected output is written down rather than compared between backends:
    # the defect this covers was a leading effect dropped by both at once.
    bad += programs(ROOT / "grammar" / "corpus" / "valid" / "14-sequenced-bodies.agents",
                    [([], "", "function-1\nlet-1\ncond-1\nelse-1\nmatch-ok-1\n"
                              "match-err-1\nlambda-1\nlambda-1\ncond-bare\nelse-bare\n"
                              "15\n13\n30\n")])
    # A binder inside an imported module, shadowing a top-level name of that
    # module. Reaching the definition instead of the binding also agrees across
    # the two, and the higher-order case compiles cleanly on both.
    bad += programs(ROOT / "grammar" / "corpus" / "valid" / "15-shadowed-binders.agents",
                    [([], "", "7 6 101 102\n")])
    print(f"\n{bad} disagreement(s) across {len(py)} function cases + 7 program cases "
          f"x 2 backends")
    return bad


if __name__ == "__main__":
    sys.exit(main())
