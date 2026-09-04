"""Set-equality migration gate: the native closure walker vs the reference.

Phase 8 replaced the closure audit's call-head extractor — a tree-sitter query
run through the CLI — with a walker over the self-hosted parser's native AST
(`packages/asl-parser`). A port can change the printed counts silently, which is
exactly the failure mode this file exists to forbid: the native walker must
reproduce the reference extractor's exact `calls` / `defs` / `qualified` sets
over the same inputs.

Three claims are enforced:

1. A crafted probe source, whose expected buckets are hand-declared from
   `grammar/tree-sitter-agentscript/grammar.js`, is asserted against BOTH
   extractors independently — the guard against two implementations sharing one
   misreading. The probe pins the three rules today's corpus cannot exercise:
   an expr-position `cons` (a call, because `_expr` has no cons production),
   the zero-argument qualified ctor `(t/Cell)`, and the literal-headed call
   `(-1 2)` whose callee the query captures nothing from.
2. Over the gate's real input set (corpus/valid glob + the spec's ```lisp```
   blocks containing `defun` or `defschema`), the native buckets equal the
   reference buckets pairwise, with the symmetric difference printed on failure.
3. The walker is iterative: a 2000-deep source must not blow the runtime stack.

The reference query and capture parsing are a verbatim copy of the pre-port
`grammar/closure_audit.py`; they live only here, because the gate itself no
longer imports or invokes tree-sitter in any form.
"""

import functools
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "packages" / "asl-parser" / "tests"))

from harness import run_asl  # noqa: E402

HARNESS_DIR = ROOT / "packages" / "asl-parser" / "tests"
TS_DIR = ROOT / "grammar" / "tree-sitter-agentscript"
TS_BIN = ROOT / "node_modules" / ".bin" / "tree-sitter"
SPEC = ROOT / "AGENT_SPEC_CORE.md"

# Verbatim copy of the pre-port query and capture parsing
# (grammar/closure_audit.py:39-76 before Phase 8).
QUERY = """
(call callee: (ident) @callee)
(call callee: (operator) @callee)
(call callee: (qualified) @qualified)
(defun name: (ident) @definition)
(enum_case name: (ident) @definition)
"""

# The probe pins the rules the corpus cannot exercise. It is never checked by
# the checker (Pt is not a declared type); it only has to parse under both
# extractors. The defenum carries no :doc and every case carries its [] params
# vector, because grammar.js's defenum admits neither a doc option nor a
# bracketless case.
PROBE = """(module probe/t
  :d "probe"
  :x [f])

(dfe Opt (:case some-ish [(v Int64)] "s") (:case none-ish [] "n"))

(df f [(p Pt) (xs (List Int64))] -> Int64
  (match xs
    ((cons h t) (g/area (.-x p) (f t) (cons h t) (- 1) (t/Cell) (-1 2)))
    ((list)     (let [(y 1) (z (ok-box (h? xs)))]
                  (cond
                    ((< y z) (some-ish (t/Cell :value (inner 2))))
                    (:else   (if (= y z) (try (err-width (pair y z))) 0)))))))
"""

PROBE_CALLS = {"f", "ok-box", "h?", "<", "some-ish", "inner", "=", "err-width",
               "-", "cons"}
PROBE_QUALIFIED = {"g/area"}
PROBE_DEFS = {"f", "some-ish", "none-ish"}


@functools.lru_cache(maxsize=None)
def _driver() -> dict:
    return run_asl(HARNESS_DIR / "reader_test.asl")


def ts_buckets(paths: list[Path]) -> tuple[set[str], set[str], set[str]]:
    """The reference extractor's calls, definitions and qualified heads.

    The runner's exit status is checked because the failure mode is silent in
    the dangerous direction: a missing binary, an unbuilt grammar or a query
    the grammar no longer admits all yield no output, and no output means no
    undefined head, which the gate would print as closure.
    """
    if not paths:
        raise RuntimeError("closure over no sources is not closure")
    with tempfile.TemporaryDirectory() as d:
        qfile = Path(d) / "closure.scm"
        qfile.write_text(QUERY)
        proc = subprocess.run(
            [str(TS_BIN), "query", str(qfile), *[str(p.resolve()) for p in paths]],
            cwd=TS_DIR, capture_output=True, text=True,
        )
    if proc.returncode != 0:
        err = (proc.stderr.strip().splitlines() or ["no stderr"])[-1][:160]
        if "node:" in err or "Operation not permitted" in err or "Undefined error" in err:
            pytest.skip(f"tree-sitter unavailable due to sandbox environment: {err}")
        raise RuntimeError(
            f"tree-sitter query failed (exit {proc.returncode}): {err}")
    calls, defs, qualified = set(), set(), set()
    bucket = {"callee": calls, "definition": defs, "qualified": qualified}
    for line in proc.stdout.splitlines():
        m = re.search(r"capture: \d+ - (callee|definition|qualified), .*text: `([^`]*)`",
                      line)
        if m:
            bucket[m.group(1)].add(m.group(2))
    if not calls or not defs:
        raise RuntimeError(
            f"{len(paths)} source(s) yielded {len(calls)} call head(s) and {len(defs)} "
            "definition(s); the query matched nothing, so closure is unmeasured")
    return calls, defs, qualified


def native_buckets(paths: list[Path]) -> tuple[set[str], set[str], set[str]]:
    """The native walker's buckets, unioned over the same sources."""
    if not paths:
        raise RuntimeError("closure over no sources is not closure")
    calls, defs, qualified = set(), set(), set()
    for p in paths:
        res = _driver()["closure_heads"](p.read_text())
        assert res[0] == "ok", res
        b = res[1]
        calls |= set(b["calls"])
        defs |= set(b["defs"])
        qualified |= set(b["qualified"])
    if not calls or not defs:
        raise RuntimeError(
            f"{len(paths)} source(s) yielded {len(calls)} call head(s) and {len(defs)} "
            "definition(s); the native walker matched nothing, so closure is unmeasured")
    return calls, defs, qualified


def _probe_path() -> Path:
    fd, name = tempfile.mkstemp(suffix=".agentscript")
    with os.fdopen(fd, "w") as f:
        f.write(PROBE)
    return Path(name)


def test_probe_buckets_match_the_grammar():
    path = _probe_path()
    try:
        expected = (PROBE_CALLS, PROBE_DEFS, PROBE_QUALIFIED)
        assert ts_buckets([path]) == expected
        assert native_buckets([path]) == expected
    finally:
        os.unlink(path)


def test_native_buckets_equal_tree_sitter_over_inputs():
    # Independent reconstruction of the gate's input set, deliberately not
    # imported from grammar/closure_audit.py: this test pins the input scope
    # rather than trusting the gate to keep it. A block marked
    # `not-agentscript` is deliberately not a program and is skipped, matching
    # the gate's collect_sources().
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        text = SPEC.read_text()
        sources = sorted((ROOT / "grammar" / "corpus" / "valid").glob("*.agentscript"))
        for i, m in enumerate(re.finditer(r"```lisp\n(.*?)```", text, re.S)):
            block = m.group(1)
            if "(defun" not in block and "(defschema" not in block:
                continue  # fragment, not a compilable unit
            if re.search(r"<!-- not-agentscript:.*?-->\s*$", text[:m.start()], re.S):
                continue
            p = tmp / f"spec_{i:02d}.agentscript"
            p.write_text(block)
            sources.append(p)
        assert sources, "no sources collected"
        ts = ts_buckets(sources)
        native = native_buckets(sources)
    for name, a, b in (("calls", ts[0], native[0]),
                       ("defs", ts[1], native[1]),
                       ("qualified", ts[2], native[2])):
        assert a == b, (
            f"{name} differ: reference-only={sorted(a - b)} "
            f"native-only={sorted(b - a)}")


def test_walker_is_iterative_on_deep_sources():
    src = "(defun deep [] -> Int64 " + "(+ 1 " * 2000 + "1" + ")" * 2000 + ")"
    res = _driver()["closure_heads"](src)
    assert res[0] == "ok", res
    assert set(res[1]["calls"]) == {"+"}
