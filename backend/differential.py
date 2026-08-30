#!/usr/bin/env python3
"""Differential gate: one AgentScript source, every backend, identical results.

Portability across targets is a claim, not a property. Runtimes disagree by
default — measured on this machine, Python and JavaScript already differ on
2**53+1 and on rounding a .5 — so equivalence only exists where it is enforced.
This is the enforcement.

Two modes. The function mode calls an entry with cases and compares returns. The
program mode runs a whole program and compares its stdout *and* its exit status,
which is the only way to check the I/O surface: an error case is chosen from the
host's errno on one target and its ErrorKind on the other, and nothing but
running both proves those land on the same case.

Both modes compare against a value written down in the repository as well as
across backends. Agreement alone cannot see a defect the two share: both are
generated from one prelude.json declaration, so a wrong declaration agrees with
itself, and a `cond` clause dropping its leading effect was dropped by both at
once while the gate stayed green.

Argument and return types come from the entry's own declaration in the source,
not from a field beside the cases: a restated signature is a second source, and a
second source is free to drift from the one the backends actually compile.

Exit code is the number of disagreements.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))
sys.path.insert(0, str(ROOT / "checker"))

from collect import collect  # noqa: E402
from vocab import parse_signature, type_aliases  # noqa: E402

# Imports are linked into one artifact, so every transpile here needs the search
# root the corpus module fixtures live under.
ROOTS = [ROOT / "grammar" / "corpus" / "modules"]
CASES = ROOT / "backend" / "cases"
TASKS = ROOT / "bench" / "tasks"

ALIASES = type_aliases()
PRIMITIVE_RUST = {"Int32": "i32", "Int64": "i64", "Float64": "f64",
                  "String": "String", "Bool": "bool"}
NONFINITE = {"nan": "f64::NAN", "inf": "f64::INFINITY", "-inf": "f64::NEG_INFINITY"}


def render_type(node) -> str:
    """A parsed type back to the vocabulary's own notation, so one parser reads
    both the builtin signatures and a user declaration."""
    head = str(node.children[0])
    if len(node.children) == 1:
        return head
    return "(" + head + " " + " ".join(render_type(a) for a in node.children[1:]) + ")"


def entry_types(src: Path, entry: str) -> list[dict]:
    fun = collect(src).funs.get(entry)
    if fun is None:
        raise RuntimeError(f"{src.name}: no entry named {entry}")
    sig = " ".join(render_type(ty) for _, ty in fun.params) + " -> " + render_type(fun.ret)
    return parse_signature(sig)[0]


def con(spec: dict) -> str:
    name = spec.get("con")
    if name is None:
        raise RuntimeError(f"a type variable is not an admissible input: {spec}")
    return ALIASES.get(name, name)


def rust_type(spec: dict) -> str:
    name = con(spec)
    if name in PRIMITIVE_RUST:
        return PRIMITIVE_RUST[name]
    if name == "List":
        return f"Vec<{rust_type(spec['args'][0])}>"
    raise RuntimeError(f"{name} is not an admissible differential input type")


def rust_string(text: str) -> str:
    """Rust source is UTF-8, so a non-ASCII character is written as itself;
    json.dumps would emit \\uXXXX, which is not a Rust escape."""
    out = ['"']
    for ch in text:
        if ch in '"\\':
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 0x20:
            out.append(f"\\u{{{ord(ch):x}}}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def rust_literal(spec: dict, value) -> str:
    """A Rust literal of the declared type. Anything the harness cannot spell
    fails here rather than as Rust that will not compile."""
    name = con(spec)
    if name == "String":
        return rust_string(value) + ".to_string()"
    if name == "Bool":
        return "true" if value else "false"
    if name in ("Int32", "Int64"):
        return f"{int(value)}{PRIMITIVE_RUST[name]}"
    if name == "Float64":
        if isinstance(value, str):
            return NONFINITE[value]
        return f"{float(value)!r}f64"
    if name == "List":
        inner = spec["args"][0]
        if not value:
            return f"Vec::<{rust_type(inner)}>::new()"
        return "vec![" + ", ".join(rust_literal(inner, v) for v in value) + "]"
    raise RuntimeError(f"{name} is not an admissible differential input type")


def py_literal(spec: dict, value) -> str:
    """The same value as Python source. JSON cannot carry a non-finite float, so
    the case file writes it as a name and both sides expand it here."""
    name = con(spec)
    if name == "Float64":
        return f"float({value!r})" if isinstance(value, str) else repr(float(value))
    if name in ("Int32", "Int64"):
        return repr(int(value))
    if name == "List":
        inner = spec["args"][0]
        return "[" + ", ".join(py_literal(inner, v) for v in value) + "]"
    if name in ("String", "Bool"):
        return repr(value)
    raise RuntimeError(f"{name} is not an admissible differential input type")


NORMALISE = '''
def _norm(v):
    if isinstance(v, (tuple, list)):
        return [_norm(x) for x in v]
    if isinstance(v, dict):
        return {k: _norm(x) for k, x in v.items()}
    if isinstance(v, float):
        if v != v:
            return "nan"
        if v == float("inf"):
            return "inf"
        if v == float("-inf"):
            return "-inf"
    return v
'''


def bind(specs: list[dict], args: list, task: dict) -> list[tuple[dict, object]]:
    """Arguments paired with the declared parameter types, refusing to pair a
    list with one of a different length. `zip` dropped the surplus, so a case
    left stale after a parameter was removed ran to completion and agreed."""
    if len(specs) != len(args):
        raise RuntimeError(
            f"{task['id']}: {task['entry']} declares {len(specs)} parameter(s), "
            f"the case supplies {len(args)}: {args!r}")
    return list(zip(specs, args))


def stderr_tail(stderr: str) -> str:
    """The part of a runner's stderr that names the failure. `note: run with
    RUST_BACKTRACE` is the last line of every panic and says nothing, so the last
    line alone would report the advice and drop the message above it."""
    lines = [line.rstrip() for line in stderr.strip().splitlines() if line.strip()]
    useful = [line for line in lines if not line.lstrip().startswith("note:")] or lines
    return " / ".join(useful[-2:])[:200] if useful else "no stderr"


def check_run(r: subprocess.CompletedProcess, what: str) -> str:
    """A runner's stdout, or the failure that produced no stdout. A panic leaves
    stdout empty, and parsing empty stdout as JSON reports a decode error while
    discarding the message on stderr that says what actually happened. Overflow
    and division traps make that an expected outcome, not a rare one."""
    if r.returncode != 0:
        raise RuntimeError(f"{what}: exit {r.returncode}: {stderr_tail(r.stderr)}")
    if not r.stdout.strip():
        raise RuntimeError(f"{what}: exit 0 but no output: {stderr_tail(r.stderr)}")
    return r.stdout


def run_python(src: Path, task: dict) -> list:
    from to_python import Transpiler
    specs = entry_types(src, task["entry"])
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "cand.py").write_text(
            Transpiler().transpile(src.read_text(), path=src, roots=ROOTS))
        calls = ", ".join(
            "fn(" + ", ".join(py_literal(s, a) for s, a in bind(specs, args, task)) + ")"
            for args, *_ in task["cases"])
        drv = Path(d) / "drv.py"
        drv.write_text(
            f"import sys, json\nsys.path[:0]=[{str(ROOT/'backend')!r},{d!r}]\nimport cand\n"
            f"fn=getattr(cand,{task['entry'].replace('-','_')!r})\n"
            + NORMALISE
            + f"print(json.dumps([_norm(x) for x in [{calls}]], sort_keys=True))\n")
        r = subprocess.run([sys.executable, str(drv)], capture_output=True, text=True)
        return json.loads(check_run(r, f"python {task['entry']}"))


def run_rust(src: Path, task: dict) -> list:
    from to_rust import ToRust
    specs = entry_types(src, task["entry"])
    with tempfile.TemporaryDirectory() as d:
        rust = ROOT / "backend" / "rust"
        (Path(d) / "rt.rs").write_text((rust / "rt.rs").read_text())
        (Path(d) / "harness.rs").write_text((rust / "harness.rs").read_text())
        fn = task["entry"].replace("-", "_")
        calls = ", ".join(
            f"{fn}(" + ", ".join(rust_literal(s, a) for s, a in bind(specs, args, task))
            + ").j()"
            for args, *_ in task["cases"])
        body = ToRust().transpile(src.read_text(), path=src, roots=ROOTS)
        body += ("\nmod harness;\nuse harness::J;\n"
                 "fn main() {\n"
                 f"    let out: Vec<String> = vec![{calls}];\n"
                 "    println!(\"[{}]\", out.join(\",\"));\n}\n")
        (Path(d) / "main.rs").write_text(body)
        c = subprocess.run(["rustup", "run", "stable", "rustc", "--edition", "2021",
                            "main.rs", "-o", "prog"], cwd=d, capture_output=True, text=True)
        if c.returncode:
            raise RuntimeError("rustc: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
        r = subprocess.run([str(Path(d) / "prog")], capture_output=True, text=True)
        return json.loads(check_run(r, f"rust {task['entry']}"))


def run_interp(src: Path, task: dict) -> list:
    """The reference interpreter's function-mode arm.

    The binary evaluates the entry `defun` directly from the tree-sitter AST and
    serializes each return in the same canonical JSON the python/rust harnesses
    produce. Each case's argument JSON is passed as its own `--arg`, so one
    process prints the whole result array.
    """
    binp = ROOT / "target" / "debug" / "agentscript-interp"
    if not binp.exists():
        subprocess.run(["rustup", "run", "stable", "cargo", "build",
                        "--manifest-path", str(ROOT / "Cargo.toml")],
                       check=True, cwd=ROOT, capture_output=True, text=True)
    cmd = [str(binp)]
    for r in ROOTS:
        cmd += ["--root", str(r)]
    cmd += ["--call", task["entry"], str(src)]
    for args, *_ in task["cases"]:
        cmd += ["--arg", json.dumps(args)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(check_run(r, f"interp {task['entry']}"))


def function_tasks() -> list[dict]:
    """Every declared function-mode task, with `src` resolved against the repo.

    Fixture cases live under backend/cases/, not bench/tasks/, because
    bench/harness/run.py globs bench/tasks/*.json and would take them for
    measurement tasks.
    """
    out = []
    for path in sorted(CASES.glob("*.json")) + sorted(TASKS.glob("*.json")):
        task = json.loads(path.read_text())
        task["path"] = path
        task["src"] = ROOT / task["src"]
        out.append(task)
    return out


def functions(task: dict) -> int:
    src = task["src"]
    py = run_python(src, task)
    rs = run_rust(src, task)
    ip = run_interp(src, task)
    if not (len(py) == len(rs) == len(ip) == len(task["cases"])):
        raise RuntimeError(
            f"{task['id']}: {len(task['cases'])} case(s) produced {len(py)} python, "
            f"{len(rs)} rust and {len(ip)} interp result(s); a truncated comparison "
            f"is not a comparison")
    bad = 0
    print(f"\n{task['id']} — {task['entry']}")
    print(f"{'input':<12} {'expected':<22} {'python':<22} {'rust':<22} {'interp':<22}")
    print("-" * 106)
    for k, (case, p, r, i) in enumerate(zip(task["cases"], py, rs, ip)):
        args, want = case[0], case[1]
        agree = (p == want) and (r == want) and (i == want)
        bad += 0 if agree else 1
        shown = ", ".join(repr(a) for a in args)
        # Sorted keys because a Map has no declared iteration order: BTreeMap and
        # a Python dict reach the same object by different routes, and an
        # insertion-ordered rendering of an equal value reads as a disagreement.
        show = {"sort_keys": True}
        print(f"{shown:<12} {json.dumps(want, **show):<22} {json.dumps(p, **show):<22} "
              f"{json.dumps(r, **show):<22} {json.dumps(i, **show):<22}"
              + ("" if agree else "  <-- DISAGREE"))
    return bad


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


def build_rust_wasm(src: Path, d: Path) -> list[str]:
    """The same Rust program compiled to wasm32-wasip1, run under node:wasi.

    Program mode compares stdout, stderr and exit status, which Route B (see
    .plans/phase-4/FEASIBILITY.md) proved observable through WASI: proc_exit's
    code reaches the JS caller and std I/O reaches the process's own descriptors.
    """
    from to_rust import ToRust
    (d / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
    (d / "main.rs").write_text(ToRust().transpile(src.read_text(), path=src, roots=ROOTS))
    c = subprocess.run(["rustup", "run", "stable", "rustc", "--target",
                        "wasm32-wasip1", "-O", "--edition", "2021", "main.rs",
                        "-o", "main.wasm"], cwd=d, capture_output=True, text=True)
    if c.returncode:
        raise RuntimeError("rustc wasm: " + (c.stderr.strip().splitlines() or ["?"])[0][:120])
    return ["node", "--no-warnings", str(ROOT / "backend" / "rust" / "wasi.mjs"),
            str(d / "main.wasm")]


def build_interpreter(src: Path, d: Path) -> list[str]:
    """The reference interpreter, evaluated directly from the tree-sitter AST.

    Same shape as the other arms: SOURCE first (the corpus file), then the
    search root the module fixtures live under. argv append after --root/SOURCE,
    matching the other arms' `cmd + argv` form. The binary is built by the
    workspace before the gate runs (I1; replay.py shares build_interpreter).
    """
    binp = ROOT / "target" / "debug" / "agentscript-interp"
    if not binp.exists():
        subprocess.run(["rustup", "run", "stable", "cargo", "build",
                        "--manifest-path", str(ROOT / "Cargo.toml")],
                       check=True, cwd=ROOT, capture_output=True, text=True)
    cmd = [str(binp)]
    for r in ROOTS:
        cmd += ["--root", str(r)]
    cmd += [str(src)]
    return cmd


def programs(src: Path, cases: list[dict]) -> int:
    """Run a whole program on every target and compare stdout, stderr and exit
    status against each other and against the case's declared values.

    Each backend gets its own working directory, seeded from the case: a case
    that appends to a file would otherwise hand the second runner the first
    runner's output and call the difference agreement.

    stderr is compared unconditionally and declared per case rather than left
    optional. It is where `main_exit` writes the failing IoError's case name, so
    it carries the errno-versus-ErrorKind mapping this harness exists to prove;
    and a case declaring stdout "" with exit 1 is otherwise indistinguishable
    from a crash. Making the key mandatory is what stops a new case from
    re-opening that hole by omission.
    """
    bad = 0
    print(f"\n{'argv':<20} {'python':<20} {'rust':<20} {'wasm':<20} {'interp':<20} {'stderr':<18} exit")
    print("-" * 130)
    for case in cases:
        argv = case.get("argv", [])
        files = case.get("files", {})
        stdin = case.get("stdin", "")
        if "stderr" not in case:
            raise RuntimeError(f"{src.name} {argv}: the case declares no stderr")
        want = (case["stdout"], case["stderr"], case["exit"])
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            runners = {"python": build_python(src, d), "rust": build_rust(src, d),
                       "wasm": build_rust_wasm(src, d), "interp": build_interpreter(src, d)}
            seen = {}
            for name, cmd in runners.items():
                run = d / f"run-{name}"
                run.mkdir()
                for fname, (content, mode) in files.items():
                    target = run / fname
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(content)
                    target.chmod(mode)
                r = subprocess.run(cmd + argv, cwd=run, input=stdin,
                                   capture_output=True, text=True)
                seen[name] = (r.stdout, r.stderr, r.returncode)
            agree = seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"]
            declared_ok = seen["python"] == want
            bad += 0 if (agree and declared_ok) else 1
            note = ("" if agree else "  <-- DISAGREE") + \
                   ("" if declared_ok else "  <-- NOT THE DECLARED OUTPUT/STATUS")
            print(f"{' '.join(argv):<20} {seen['python'][0]!r:<20} "
                  f"{seen['rust'][0]!r:<20} {seen['wasm'][0]!r:<20} "
                  f"{seen['interp'][0]!r:<20} {seen['python'][1]!r:<18} "
                  f"{seen['python'][2]}/{seen['rust'][2]}/{seen['wasm'][2]}/{seen['interp'][2]}" + note)
    return bad


def program_cases() -> list[tuple[Path, list[dict]]]:
    """Every program-mode source with its cases, so one list serves the gate and
    the coverage tracer rather than each keeping its own."""
    valid = ROOT / "grammar" / "corpus" / "valid"
    return [
        # The failing path is checked, not only the happy one: it is the error
        # mapping, not the read itself, that the two runtimes derive independently.
        (valid / "08-io.agentscript", [
            {"argv": ["sample.txt"], "files": {"sample.txt": ("hello from a file\n", 0o644)},
             "stdout": "hello from a file\n\n", "stderr": "", "exit": 0},
            {"argv": ["missing.txt"], "stdout": "missing\n", "stderr": "", "exit": 0},
            # A successful `file-write`, observed by reading the destination back
            # in the same invocation and echoing it: the declared stdout pins the
            # content, so a write that silently vanished cannot agree with it.
            {"argv": ["sample.txt", "out.txt"],
             "files": {"sample.txt": ("hello from a file\n", 0o644)},
             "stdout": "hello from a file\n\n", "stderr": "", "exit": 0},
            # The failing write, and the error mapping both runtimes derive
            # independently. stdout "" with exit 1 is what a crash also looks
            # like; the case name on stderr distinguishes the two and pins which
            # IoError the write produced.
            {"argv": ["sample.txt", "nodir/out.txt"],
             "files": {"sample.txt": ("hello from a file\n", 0o644)},
             "stdout": "", "stderr": "not-found\n", "exit": 1},
            {"argv": [], "stdout": "", "stderr": "usage: io-demo SRC [DST]\n", "exit": 0},
        ]),
        # An imported union is a tagged tuple on one target and a namespaced
        # variant on the other, each derived independently; and the program
        # reaches one module through two aliases, which is the cheap
        # discriminator for a lowering keyed on the alias rather than on the
        # defining module path.
        (valid / "13-module-program.agentscript", [
            {"argv": [], "stdout": "rectangle\n6.0\n", "stderr": "", "exit": 0},
        ]),
        # Bodies with more than one expression, in every position that admits
        # one. The defect this covers was a leading effect dropped by both
        # backends at once, which is why the output is written down here.
        (valid / "14-sequenced-bodies.agentscript", [
            {"argv": [], "exit": 0, "stderr": "",
             "stdout": "function-1\nlet-1\ncond-1\nelse-1\nmatch-ok-1\n"
                       "match-err-1\nlambda-1\nlambda-1\ncond-bare\nelse-bare\n"
                       "15\n13\n30\n"},
        ]),
        # A binder inside an imported module, shadowing a top-level name of that
        # module. Reaching the definition instead of the binding also agrees
        # across the two, and the higher-order case compiles cleanly on both.
        (valid / "15-shadowed-binders.agentscript", [
            {"argv": [], "stdout": "7 6 101 102\n", "stderr": "", "exit": 0},
        ]),
        (valid / "19-io-errors.agentscript", [
            {"argv": ["log.txt"], "files": {"log.txt": ("A\n", 0o644)}, "stdin": "B",
             "stdout": "A\nB\n", "stderr": "", "exit": 0},
            {"argv": ["absent.txt"], "stdout": "absent\n", "stderr": "", "exit": 0},
            # `label e` reaches stdout and `main_exit` writes the same case name
            # to stderr, so the two channels have to name the same failure.
            {"argv": ["nodir/out.txt"], "stdout": "not-found\n",
             "stderr": "not-found\n", "exit": 1},
            {"argv": ["noperm.txt"], "files": {"noperm.txt": ("", 0o000)},
             "stdout": "permission-denied\n", "stderr": "permission-denied\n",
             "exit": 1},
            {"argv": ["log.txt"], "files": {"log.txt": ("A\n", 0o644)},
             "stdout": "A\n", "stderr": "", "exit": 0},
            {"argv": ["--labels"], "stderr": "",
             "stdout": "not-found,permission-denied,already-exists,"
                       "invalid-path,interrupted,other\n", "exit": 0},
            {"argv": ["--slurp"], "stdin": "x\ny\n", "stdout": "x\ny\n",
             "stderr": "", "exit": 0},
        ]),
    ]


def main() -> int:
    tasks = function_tasks()
    bad = 0
    cases = 0
    for task in tasks:
        bad += functions(task)
        cases += len(task["cases"])
    program_total = 0
    for src, group in program_cases():
        bad += programs(src, group)
        program_total += len(group)
    print(f"\n{bad} disagreement(s) across {cases} function cases "
          f"+ {program_total} program cases (python/rust/wasm/interp)")
    return bad


if __name__ == "__main__":
    sys.exit(main())
