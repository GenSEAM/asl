import sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "bench"))

from token_audit import get_tokenizers, load_vocabulary, audit_primitives, audit_builtins, run_audit


def test_token_ceiling_on_primitives():
    enc = get_tokenizers()["cl100k_base"]
    vocab = load_vocabulary()
    records, errors, warnings = audit_primitives(enc, vocab)

    assert len(records) >= 20
    assert len(errors) == 0, f"Primitives exceeding 2 tokens: {errors}"


def test_builtins_audit_warns_on_inflation():
    enc = get_tokenizers()["cl100k_base"]
    vocab = load_vocabulary()
    records, warnings = audit_builtins(enc, vocab)

    assert len(records) == 107
    # All 107 builtins now have aliases conforming to <=2 tokens ceiling
    assert len(warnings) == 0, f"Expected 0 warnings, got {warnings}"


def test_token_audit_check_mode():
    assert run_audit(check_mode=True, verbose=False) == 0
