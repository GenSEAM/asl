"""Semantic equivalence and safety test suite for the native checker (@pcp:d-8d4c).

Verifies 100% equivalence between the self-hosted pure AgentScript checker
(tools/native_checker) and the reference Python checker (checker/resolve.py),
as well as stack safety on deeply nested expressions.
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
CORPUS = ROOT / "grammar" / "corpus"
MODULES = CORPUS / "modules"

sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "tools"))

from resolve import check_file as py_check_file  # noqa: E402
from gate import expected  # noqa: E402
from native_checker import native_check_file, native_check_source  # noqa: E402


def test_corpus_valid_equivalence():
    """All 34 valid corpus files must produce exactly 0 diagnostics with native checker."""
    valid_files = sorted(CORPUS.glob("valid/*.agentscript"))
    assert len(valid_files) == 36, f"Expected 36 valid fixtures, found {len(valid_files)}"
    roots = [MODULES]
    for path in valid_files:
        native_diags = native_check_file(path, roots)
        assert native_diags == [], f"{path.name} failed native check: {native_diags}"


def test_corpus_semantic_equivalence():
    """All 47 semantic corpus files must match expected diagnostic codes."""
    semantic_files = sorted((CORPUS / "semantic").rglob("*.agentscript"))
    assert len(semantic_files) == 47, f"Expected 47 semantic fixtures, found {len(semantic_files)}"
    roots = [MODULES]
    for path in semantic_files:
        want, exact = expected(path)
        assert want is not None, f"No expectation note in {path}"
        native_diags = native_check_file(path, roots)
        codes = [d.code for d in native_diags]
        if exact:
            assert set(codes) == {want}, f"{path.name}: expected only {want}, got {codes}"
        else:
            assert want in codes, f"{path.name}: expected {want}, got {codes}"


def test_iterative_depth_safety():
    """Checking an expression nested 2,000 deep completes without RecursionError (Arch B4)."""
    depth = 2000
    expr = "1"
    for _ in range(depth):
        expr = f"(+ 1 {expr})"
    src = f"(defun deep [] -> Int64 {expr})"
    diags = native_check_source(src, path="deep.asl")
    assert diags == [], f"Deep expression failed: {diags}"


def test_cli_native_flag():
    """./asl check --native returns exit code 0 on valid and non-zero on semantic fixtures."""
    valid_fixture = "grammar/corpus/valid/01-basics.agentscript"
    cmd_valid = ["./asl", "check", "--native", valid_fixture]
    res_valid = subprocess.run(cmd_valid, cwd=str(ROOT), capture_output=True, text=True)
    assert res_valid.returncode == 0, f"asl check --native failed on {valid_fixture}: {res_valid.stderr}"

    semantic_fixture = "grammar/corpus/semantic/unbound-name.agentscript"
    cmd_invalid = ["./asl", "check", "--native", semantic_fixture]
    res_invalid = subprocess.run(cmd_invalid, cwd=str(ROOT), capture_output=True, text=True)
    assert res_invalid.returncode != 0, f"asl check --native unexpectedly succeeded on {semantic_fixture}"
