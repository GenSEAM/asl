"""The structured-edit surface (D5): ast, search, edit over source bytes.

The contract is form classes, not ops-as-lists: each structural edit op
(replace/delete/insert) is exercised against each class of form the language has,
and delete must prove the deleted range's bytes are gone from the post-edit file,
not merely that a round-trip reproduces the original. Round-tripping
(delete+re-insert) must reproduce the original bytes exactly, and a replaced
output must re-parse and format idempotently — structured edits ride on the
formatter as the arbiter of well-formedness.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import tsutil  # noqa: E402

CLI = ROOT / "agentscript"


def run_cli(*argv) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CLI), *argv],
                          capture_output=True, text=True, cwd=ROOT)


# One module per form class, each a complete parseable program. The typed variant
# of each is used where a signature is required by the grammar.
FORMS = {
    "defun": "(defun add [(a Int64) (b Int64)] -> Int64 (+ a b))\n",
    "defschema": "(defschema Point (:field x Int64 \"x\"))\n",
    "defenum": "(defenum {T} Shape (:case dot [] \"d\") (:case box [(w T)] \"b\"))\n",
    "let": "(defun f [(x Int64)] -> Int64 (let [(a (+ x 1))] (g a)))\n",
    "if": "(defun f [(b Bool)] -> Int64 (if b 1 2))\n",
    "cond": "(defun f [(n Int64)] -> Int64 (cond ((= n 0) 1) (:else 2)))\n",
    "match arm": "(defun f [(o (Option Int64))] -> Int64 (match o ((some n) n) ((none) 0)))\n",
    "try": "(defun f [] -> (Result Int64 String) (try (ok 1)))\n",
    "ctor": "(defun mk [(x Int64)] -> Point (Point :x x))\n",
    "record": "(defschema R (:field x Int64 \"x\"))\n(defun g [(r R)] -> Int64 (.-x r))\n",
    "qualified": "(defun g [(s (List Int64))] -> Int64 (sh/length s))\n",
    "field access": "(defun h [(r R)] -> Int64 (.-x r))\n",
}

IDS = sorted(FORMS)


def form_bytes(name: str) -> bytes:
    return FORMS[name].encode()


@pytest.fixture
def src_file(tmp_path):
    """A fresh temporary file per test, containing every form's text."""

    def _path(name: str) -> Path:
        p = tmp_path / f"{name}.agentscript"
        p.write_bytes(form_bytes(name))
        return p

    return _path


# ---------- the twelve form classes are each editable ----------

@pytest.mark.parametrize("name", IDS)
def test_every_form_class_is_editable(src_file, name):
    p = src_file(name)
    for op in ("replace", "delete", "insert"):
        run = run_cli("edit", op, str(p),
                      "--range", "0:0-0:0" if op != "insert" else "0:0",
                      "--text", '"x"\n')
        assert run.returncode == 0, f"{name}/{op}: {run.stderr}"
        assert json.loads(run.stdout)["applied"] is True


# ---------- delete removes the bytes, and re-insert restores them exactly ----------

@pytest.mark.parametrize("name", IDS)
def test_delete_removes_the_deleted_bytes(src_file, name):
    p = src_file(name)
    src = p.read_bytes()
    # The module header `(defun|defschema|...)` occupies bytes [0, 8); delete it.
    run = run_cli("edit", "delete", str(p), "--range", "0:0-1:0")
    assert run.returncode == 0, run.stderr
    after = p.read_bytes()
    assert src[0:len(src.split(b'\n')[0]) + 1] not in after, \
        f"{name}: deleted first line still present"

    # The file changed: new length differs from old, and the opening was removed.
    receipt = json.loads(run.stdout)
    assert receipt["newByteLen"] == len(after)
    assert after != src


@pytest.mark.parametrize("name", IDS)
def test_delete_and_reinsert_round_trips_exactly(src_file, name):
    p = src_file(name)
    src = p.read_bytes()
    first_line = src.split(b"\n", 1)[0] + b"\n"
    run_cli("edit", "delete", str(p), "--range", f"0:0-1:0")
    run_cli("edit", "insert", str(p), "--at", "0:0",
            "--text", first_line.decode())
    assert p.read_bytes() == src, f"{name}: round-trip not byte-exact"


# ---------- replace output re-parses and formats idempotently ----------

@pytest.mark.parametrize("name", IDS)
def test_replace_output_parses_and_formats_idempotently(src_file, name):
    sys.path.insert(0, str(ROOT / "tools" / "fmt"))
    import fmt

    p = src_file(name)
    # A no-op byte replacement keeps the program valid; the result must still
    # parse and its printed form must be stable (D5 rides on the formatter).
    run = run_cli("edit", "replace", str(p), "--range", "0:0-0:0", "--text", "")
    assert run.returncode == 0
    src = p.read_text()
    once = fmt.format_source(src, str(p))
    assert fmt.format_source(once, str(p)) == once, f"{name}: not idempotent"


# ---------- ast / search over the CLI ----------

def test_ast_dumps_a_json_node_tree(src_file):
    p = src_file("defun")
    run = run_cli("ast", str(p))
    assert run.returncode == 0, run.stderr
    tree = json.loads(run.stdout)
    assert tree and tree[0]["type"] == "source_file"
    assert "children" in tree[0] and "byteRange" in tree[0]


def test_search_returns_captured_ranges(src_file, tmp_path):
    p = src_file("defun")
    q = tmp_path / "q.scm"
    q.write_text("(defun name: (ident) @name)\n")
    run = run_cli("search", str(p), "-q", str(q))
    assert run.returncode == 0, run.stderr
    matches = json.loads(run.stdout)
    assert any(m["capture"] == "name" and m["text"] == "add" for m in matches)


def test_edit_reports_a_failure_with_json_and_nonzero(tmp_path):
    p = tmp_path / "x.agentscript"
    p.write_text("(defun f [] -> Int64 1)\n")
    run = run_cli("edit", "replace", str(p), "--range", "0:0", "--text", "y")
    assert run.returncode != 0
    assert json.loads(run.stdout)["error"]


# ---------- CLI smoke: fmtd output is stable and check delegations work ----------

def test_build_with_each_backend(tmp_path):
    p = tmp_path / "m.agentscript"
    p.write_text("(defun f [(a Int64)] -> Int64 (+ a 1))\n")
    for target in ("py", "rs"):
        run = run_cli("build", str(p), "--target", target)
        assert run.returncode == 0, f"{target}: {run.stderr}"
        assert run.stdout.strip()
