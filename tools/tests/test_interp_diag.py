"""Span-threading on interpreter runtime errors (W8).

The AST carries a `Span` on each of the 13 failable `Expr` variants; this test
proves the *value* of that span (not just the field): for each failable variant,
a fixture fails at runtime and the interpreter prints `path:line:col:` on stderr,
with line and column >= 1. `path:0:0:` is rejected — a default `Span{0,0}` passes
a bare regex but not this assertion.

Differential (program mode) compares stderr across all four arms, so the format
must be exactly `path:line:col: message` and the IoError case-name path (exit 1,
via `exit_glue`) must be untouched; only evaluator errors gain the location.
"""
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
INTERP = ROOT / "target" / "debug" / "agentscript-interp"

# One fixture per failable `Expr` variant. Each is a `--call` entry whose body
# fails at runtime at a real source position.
VARIANT_FIXTURES = {
    "Int": "(defun boom [] -> Int64 9223372036854775808)\n",
    "Ident": "(defun boom [] -> Int64 (dbg))\n",
    "Qualified": "(defun boom [] -> Int64 (s/missing))\n",
    "Call": "(defun boom [] -> Int64 (1 2))\n",
    "FieldAccess": "(defun boom [] -> Int64 (.-x 5))\n",
    "If": "(defun boom [] -> Int64 (if 1 2 3))\n",
    "Cond": "(defun boom [] -> Int64 (cond ((3) 4) (:else 5)))\n",
    "Match": "(defun boom [] -> Int64 (match 5 ((some n) n)))\n",
    "Try": "(defun boom [] -> Int64 (try 5))\n",
    "Ctor": "(defun boom [] -> Int64 (some (dbg)))\n",
    "Record": "(defschema Point (:field x Int64 \"x\")) "
              "(defun boom [] -> Int64 (.-x (Point :x (dbg))))\n",
    "Let": "(defun boom [] -> Int64 (let [(a (dbg))] a))\n",
    "Fn": "(defun boom [] -> Int64 ((fn [x] (dbg)) 1))\n",
}

LOC = re.compile(r"^.*:(\d+):(\d+): ")


def run_fixture(src: str, path: str) -> subprocess.CompletedProcess:
    Path(path).write_text(src)
    return subprocess.run([str(INTERP), "--call", "boom", path, "--arg", "[]"],
                          capture_output=True, text=True)


@pytest.fixture(scope="module", autouse=True)
def require_interp():
    if not INTERP.exists():
        subprocess.run(["rustup", "run", "stable", "cargo", "build",
                        "-p", "agentscript-interp"], check=True, cwd=ROOT,
                       capture_output=True, text=True)
    assert INTERP.exists(), "agentscript-interp not built"


@pytest.mark.parametrize("variant", sorted(VARIANT_FIXTURES))
def test_each_failable_variant_reports_a_located_error(variant, tmp_path):
    p = tmp_path / f"{variant}.agentscript"
    r = run_fixture(VARIANT_FIXTURES[variant], str(p))
    # A runtime evaluator error exits 2; IoError exits 1 — either is a failure.
    assert r.returncode in (1, 2), f"{variant}: expected exit 1 or 2, got {r.returncode}"
    assert r.returncode != 0
    m = LOC.match(r.stderr.strip().splitlines()[-1])
    assert m, f"{variant}: stderr not located: {r.stderr!r}"
    line, col = int(m.group(1)), int(m.group(2))
    assert line >= 1 and col >= 1, \
        f"{variant}: span is {line}:{col}, must be >= 1 (rejects path:0:0:)"


def test_iocase_exit_writes_only_the_case_name(tmp_path):
    """Exit-1 IoError output (program mode, via exit_glue) gains no location."""
    src = ("(defun main [(argv (List String))] -> (Result Unit IoError)\n"
           "  (err (not-found)))\n")
    src += "(defun ! run [] -> Unit ())\n"
    p = tmp_path / "io.agentscript"
    Path(p).write_text(src)
    r = subprocess.run([str(INTERP), str(p)], capture_output=True, text=True)
    assert r.returncode == 1
    assert r.stderr.strip() == "not-found"
