#!/usr/bin/env python3
"""Tier B: which builtins the gate suite actually *evaluates*.

The old coverage number counted a call head found by a static scan over the
corpus and the specification's markdown. It was wrong in both directions — 17
counted builtins had never run, 12 running builtins were outside the scan root —
and, worse, a ten-line fixture whose single case takes the `else` arm past sixty
builtin calls moved that number by eleven with nothing executed.

So the numerator is traced, not scanned. Every entry of `to_python.LOWER` is
rewritten in this process as `(_rec.hit('<name>') or (<template>))`. `hit`
returns None, so `or` always yields the original expression, and the placeholders
are untouched because the rewrite happens on the template, before `.format`. The
recorder therefore fires exactly when that expression is *evaluated* — not when
it is emitted, and not when it is parsed. Nothing else transpiles wrapped code:
the differential gate and check_corpus run the ordinary output.

Call sites are recorded the same way, keyed by (source, line, column), and
intersected with the checker's per-site instantiations. That is what makes the
rule "an N-typed builtin must run at Int64 and at Float64" enforceable: a builtin
may well be *called* at Float64 on a line no case reaches.

What this does not prove, stated rather than implied: execution is recorded on
the Python side only. The Rust lowering of the same builtin is compile-gated by
backend/monomorphism.py and executed by backend/differential.py on the same case
with the two results compared, but the tracer itself sees one backend.

Exit code is the number of failed conditions.
"""
import argparse
import contextlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from lark import Token, Tree

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT / "prelude"))
sys.path.insert(0, str(ROOT / "checker"))

import check_corpus  # noqa: E402
import differential  # noqa: E402
import monomorphism  # noqa: E402
import to_python  # noqa: E402
from resolve import call_instantiations  # noqa: E402
from vocab import builtins as declared_builtins, parse_signature, signatures  # noqa: E402

VALID = ROOT / "grammar" / "corpus" / "valid"
# Overridable so a test can point the gate at a forged lock without editing the
# checked-in one; the recorder is a one-way monkeypatch, so every consumer that
# traces has to be its own process anyway.
LOCK = Path(os.environ.get("AGENTS_COVERAGE_LOCK", ROOT / "prelude" / "coverage.lock"))

# A parked `unexecuted` fixture must cite the PCP decision that parked it (the
# `c-15f3` in `PCP c-15f3`), so an absence cannot be parked behind a bare
# "not executed" with no trace to why.
_PCP_ID = re.compile(r"[ldc]-[0-9a-f]{4}")

# The type names that are not user declarations. An `unproven` entry whose
# builtin acquires an instantiation at any PascalCase name outside this set has
# grown an instantiation the parking reason no longer covers.
_BUILTIN_TYPES = {
    "Bool", "Int32", "Int64", "Float64", "String", "Unit",
    "List", "Option", "Result", "Pair", "Map", "IoError",
}


def is_user_defined_type(shown: str) -> bool:
    """A concrete type string names a user declaration iff it carries a
    PascalCase identifier that is not a built-in type name. `(List Color)` and
    `Node` do; `(List Float64)` does not."""
    return any(word not in _BUILTIN_TYPES
               for word in re.findall(r"[A-Z][A-Za-z0-9]*", shown))

RECORDER = '''\
import os

_PATH = os.environ["AGENTS_EXEC_COVERAGE"]
_seen = set()


def _write(line):
    if line not in _seen:
        _seen.add(line)
        with open(_PATH, "a") as fh:
            fh.write(line + "\\n")


def hit(name):
    """Called from inside the emitted expression, so it fires on evaluation."""
    _write("name\\t" + name)
    return None


def site(line, col, name):
    _write("site\\t%s\\t%d\\t%d\\t%s"
           % (os.environ["AGENTS_EXEC_SOURCE"], line, col, name))
    return None
'''

_TRACE: tuple[set[str], set[Path], dict[tuple[str, int, int], str]] | None = None


_INSTALLED = False


@contextlib.contextmanager
def recorder_installed():
    """Wrap every Python lowering template and every builtin call site for the
    duration of the block, then put `to_python` back as it was.

    Scoped rather than one-way: the wrapped transpiler prepends `import _rec`,
    and _rec only exists in the tracer's tempdir, so a transpile after the block
    would emit code importing a module that is gone. grammar/closure_audit.py
    imports this module, which puts an unrelated consumer one reordering away
    from that."""
    global _INSTALLED
    if _INSTALLED:
        raise RuntimeError("the recorder is already installed; it does not nest")
    _INSTALLED = True
    templates = dict(to_python.LOWER)
    original_transpile = to_python.Transpiler.transpile
    original_call = to_python.Transpiler.call

    def transpile(self, src, *, path=None, roots=()):
        return "import _rec\n" + original_transpile(self, src, path=path, roots=roots)

    def call(self, node, stmts, indent):
        lowered = original_call(self, node, stmts, indent)
        head = node.children[0]
        inner = head.children[0] if isinstance(head, Tree) and head.data == "expr" else head
        # Only the root unit: the checker collects an imported module's header
        # and never walks its body, so there is nothing to intersect there.
        if self.prefix == "" and isinstance(inner, Token) and str(inner) in to_python.LOWER:
            return (f"(_rec.site({inner.line}, {inner.column}, {str(inner)!r}) "
                    f"or ({lowered}))")
        return lowered

    try:
        for name, template in templates.items():
            to_python.LOWER[name] = f"(_rec.hit({name!r}) or ({template}))"
        to_python.Transpiler.transpile = transpile
        to_python.Transpiler.call = call
        yield
    finally:
        to_python.LOWER.clear()
        to_python.LOWER.update(templates)
        to_python.Transpiler.transpile = original_transpile
        to_python.Transpiler.call = original_call
        _INSTALLED = False


@contextlib.contextmanager
def _environment(**values: str):
    """Process environment for the duration of the block. The tracer's PYTHONPATH
    names a tempdir that is deleted on the way out, so leaving it set hands the
    next in-process subprocess a search path that no longer exists."""
    before = {k: os.environ.get(k) for k in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for k, old in before.items():
            if old is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = old


def _transpile(src: Path) -> str:
    return to_python.Transpiler().transpile(
        src.read_text(), path=src, roots=differential.ROOTS)


def _run_program(src: Path, case: dict) -> None:
    """A program-mode case, on the Python side only: the tracer measures
    reachability and differential.py measures agreement."""
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
        (d / "cand.py").write_text(_transpile(src))
        run = d / "run"
        run.mkdir()
        for name, (content, mode) in case.get("files", {}).items():
            target = run / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
            target.chmod(mode)
        r = subprocess.run([sys.executable, str(d / "cand.py")] + case.get("argv", []),
                           cwd=run, input=case.get("stdin", ""),
                           capture_output=True, text=True)
    # The case already says what the program does; a tracer that ignores it
    # records the coverage of a run that crashed halfway as if it completed.
    if (r.stdout, r.returncode) != (case["stdout"], case["exit"]):
        raise RuntimeError(
            f"{src.name} {case.get('argv', [])}: traced run gave "
            f"{(r.stdout, r.returncode)!r}, the case declares "
            f"{(case['stdout'], case['exit'])!r}: "
            + (r.stderr.strip().splitlines() or ["no stderr"])[-1][:120])


def programs() -> list[tuple[str, Path, object]]:
    """Everything the gate suite executes, as (label, source, what to run).

    A source outside this union contributes nothing to the numerator, and
    condition 4 names it rather than letting the absence be silent.
    """
    out: list[tuple[str, Path, object]] = []
    for path in sorted(VALID.glob("*.agents")):
        expr = check_corpus.declared_run(path)
        if expr is not None:
            out.append((f"run:{path.name}", path, expr))
    for src, cases in differential.program_cases():
        for i, case in enumerate(cases):
            out.append((f"program:{src.name}#{i}", src, case))
    for task in differential.function_tasks():
        out.append((f"task:{task['id']}", task["src"], task))
    return out


def trace() -> tuple[set[str], set[Path], dict[tuple[str, int, int], str]]:
    """(builtins evaluated, sources that ran, evaluated call site -> its builtin).
    Memoised:
    the recorder is a one-way monkeypatch of this process."""
    global _TRACE
    if _TRACE is not None:
        return _TRACE
    covered: set[Path] = set()
    with tempfile.TemporaryDirectory() as d, recorder_installed():
        record = Path(d) / "hits.txt"
        record.write_text("")
        (Path(d) / "_rec.py").write_text(RECORDER)
        path_before = os.environ.get("PYTHONPATH")
        with _environment(AGENTS_EXEC_COVERAGE=str(record), AGENTS_EXEC_SOURCE="",
                          PYTHONPATH=os.pathsep.join(
                              [d] + ([path_before] if path_before else []))):
            for label, src, payload in programs():
                os.environ["AGENTS_EXEC_SOURCE"] = str(src)
                if isinstance(payload, str):
                    ok, why = check_corpus.execute(_transpile(src), payload)
                    if not ok:
                        raise RuntimeError(f"{label}: `{payload}` did not hold: {why}")
                elif isinstance(payload, dict) and "entry" in payload:
                    differential.run_python(payload["src"], payload)
                else:
                    _run_program(src, payload)
                covered.add(src)
        names, sites = set(), {}
        for line in record.read_text().splitlines():
            kind, _, rest = line.partition("\t")
            if kind == "name":
                names.add(rest)
            elif kind == "site":
                path, row, col, builtin = rest.rsplit("\t", 3)
                sites[(path, int(row), int(col))] = builtin
    _TRACE = (names, covered, sites)
    return _TRACE


def instantiations() -> dict[str, list[str]]:
    """Which concrete types each builtin was *executed* at, taken from the
    checker's own inference intersected with the sites that actually ran.

    This is the sole enforcement point of the rule that an `N`-typed builtin must
    run at Int64 and at Float64 — the rule that would have caught `/`, `mod` and
    `list-sum` — so a hand-written field would be a claim nothing checks.
    """
    _, covered, sites = trace()
    out: dict[str, set[str]] = {}
    seen: set[tuple[str, int, int]] = set()
    for src in sorted(covered):
        for record in call_instantiations(src, differential.ROOTS):
            key = (record["path"], record["line"], record["col"])
            seen.add(key)
            if key in sites:
                out.setdefault(record["builtin"], set()).update(record["args"])
    # An executed site the checker has no instantiation for contributes nothing,
    # and the intersection made that indistinguishable from a site that ran at no
    # interesting type. Variadic builtins have no fixed argument positions to
    # instantiate, so they are the one shape that legitimately has no record.
    variadic = variadic_builtins()
    orphans = sorted({name for key, name in sites.items()
                      if key not in seen and name not in variadic})
    if orphans:
        raise RuntimeError(
            "executed call sites the checker reported no instantiation for: "
            + " ".join(orphans) + " — the instantiation figures for those are "
            "silently absent, not empty")
    return {name: sorted(types) for name, types in sorted(out.items())}


def variadic_builtins() -> set[str]:
    return {name for name, sig in signatures().items() if parse_signature(sig)[1]}


def _mentions_n(spec: dict) -> bool:
    if "var" in spec:
        return spec["var"] == "N"
    if "fn" in spec:
        return any(_mentions_n(p) for p in spec["fn"]) or _mentions_n(spec["ret"])
    return any(_mentions_n(a) for a in spec["args"])


def numeric_builtins() -> set[str]:
    """Builtins declared over `N`. One executed instantiation is not coverage of
    a generic signature — that assumption is what left `/` and `mod` counted as
    exercised while two thirds of their declared domain did not compile."""
    out = set()
    for name, sig in signatures().items():
        args, _, ret = parse_signature(sig)
        if any(_mentions_n(a) for a in args) or _mentions_n(ret):
            out.add(name)
    return out


def _n_argument_strings(name: str, width: str) -> set[str]:
    """The concrete argument type strings an `N`-typed builtin takes when `N`
    is `width`, rendered only for the argument positions that mention `N`.

    `(List N)` renders as `(List Int64)`, so `list-sum` counts at both widths;
    a non-`N` argument such as `(List Float64)` contributes nothing, so a Float64
    that reaches only a non-`N` position cannot satisfy the rule (finding 8)."""
    args, _, _ = parse_signature(signatures()[name])
    return {monomorphism._render(spec, {"N": width})
            for spec in args if _mentions_n(spec)}


def executed() -> list[str]:
    names, _, _ = trace()
    return sorted(names & declared_builtins())


def stats() -> dict:
    names, covered, _ = trace()
    declared = declared_builtins()
    hit = sorted(names & declared)
    return {"executed": hit,
            "unreached": sorted(declared - names),
            "declared": len(declared),
            "pct": 100 * len(hit) // max(len(declared), 1),
            "covered": {str(p.relative_to(ROOT)) for p in covered}}


def build_lock() -> dict:
    old = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    return {"floor_pct": old.get("floor_pct", 95),
            "executed": len(stats()["executed"]),
            "tier_a": monomorphism.tier_a_summary(),
            "instantiations": instantiations(),
            "unproven": old.get("unproven", {}),
            "unexecuted": old.get("unexecuted", {}),
            "note": old.get("note", "")}


def check() -> tuple[list[str], dict]:
    """The five conditions. Each is a distinct way the number could rise without
    the coverage rising, so each is reported separately."""
    s = stats()
    if not LOCK.exists():
        return [f"{LOCK} does not exist; run backend/exec_coverage.py --write"], s
    lock = json.loads(LOCK.read_text())
    count = len(s["executed"])
    failures: list[str] = []

    if s["pct"] < lock["floor_pct"]:
        failures.append(f"executed {count}/{s['declared']} = {s['pct']}% is below the "
                        f"floor of {lock['floor_pct']}%")
    if count < lock["executed"]:
        failures.append(f"executed {count} is below the recorded {lock['executed']}: a "
                        "builtin stopped running. Never evaluated: "
                        + " ".join(s["unreached"]))
    if count > lock["executed"]:
        failures.append(f"executed {count} is above the recorded {lock['executed']}: the "
                        "lock is stale, so record the new count deliberately")

    parked = lock.get("unexecuted", {})
    for path in sorted(VALID.glob("*.agents")):
        if str(path.relative_to(ROOT)) in s["covered"]:
            continue
        reason = parked.get(path.name)
        if reason is None:
            failures.append(f"{path.name} is executed by no program and is not on "
                            "coverage.lock's unexecuted list")
        elif not _PCP_ID.search(reason):
            failures.append(f"{path.name}'s unexecuted reason names no PCP id "
                            f"({_PCP_ID.pattern}): {reason!r}")

    failures += monomorphism.check_lock(monomorphism.tier_a_summary())

    got = instantiations()
    for name in sorted(numeric_builtins()):
        seen = got.get(name, [])
        missing = [width for width in ("Int64", "Float64")
                   if not (_n_argument_strings(name, width) & set(seen))]
        if missing:
            failures.append(f"{name} is declared over N but no executed case reaches "
                            + " or ".join(missing) + f"; executed at {seen or 'nothing'}")

    unproven = lock.get("unproven", {})
    for name in sorted(set(unproven) & set(got)):
        for ty in got[name]:
            if is_user_defined_type(ty):
                failures.append(
                    f"{name} is parked in unproven but acquired the executed "
                    f"instantiation {ty!r} at a user-defined type; the parking "
                    f"reason no longer covers it")

    want = lock.get("instantiations", {})
    for name in sorted(set(want) | set(got)):
        if want.get(name) != got.get(name):
            failures.append(f"instantiations[{name}]: the lock claims "
                            f"{want.get(name)}, the executed sites give {got.get(name)}")
    return failures, s


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="record the current figures in prelude/coverage.lock")
    ap.add_argument("--allow-regression", action="store_true",
                    help="with --write, permit a lower executed count than recorded")
    args = ap.parse_args()

    if args.write:
        lock = build_lock()
        recorded = json.loads(LOCK.read_text()).get("executed", 0) if LOCK.exists() else 0
        if lock["executed"] < recorded and not args.allow_regression:
            print(f"refusing to write {lock['executed']}/{len(declared_builtins())} "
                  f"executed below the recorded {recorded}; re-run with "
                  f"--allow-regression to accept the regression")
            return 1
        LOCK.write_text(json.dumps(lock, indent=2) + "\n")
        print(f"wrote {LOCK} ({lock['executed']}/{len(declared_builtins())} executed)")
        return 0

    failures, s = check()
    print(f"programs executed : {len(programs())}")
    print(f"executed builtins : {len(s['executed'])}/{s['declared']}  ({s['pct']}%)")
    if s["unreached"]:
        print("never evaluated   : " + " ".join(s["unreached"]))
    for f in failures:
        print("  " + f)
    print(f"\n{len(failures)} coverage failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
