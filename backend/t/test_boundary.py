"""The two ways a backend can decline a foreign module are not the same failure.

`TargetMismatch` means the module names another ecosystem: refusing it is correct
and permanent. `NotLowered` means the module names *this* ecosystem and the
backend cannot emit it yet: that is a gap in the backend. Collapsing them once
made a backend report an unimplemented lowering as a well-formed refusal, with a
message that was simply untrue.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))

PY_FFI = ROOT / "grammar" / "corpus" / "valid" / "08-ffi.as"   # :target :py
RS_FFI = Path(__file__).parent / "rs-ffi.as"                   # :target :rs


def transpilers():
    from to_python import Transpiler
    from to_rust import ToRust
    from to_swift import ToSwift
    return {"py": Transpiler, "rs": ToRust, "sw": ToSwift}


def test_the_target_that_owns_the_module_lowers_it():
    from to_python import Transpiler
    out = Transpiler().transpile(PY_FFI.read_text())
    assert "import polars as _host_pl" in out
    # The declared type is the success type, so the wrapper must produce a value.
    assert "_as.attempt(lambda: _host_pl.read_csv(path))" in out


@pytest.mark.parametrize("target", ["rs", "sw"])
def test_a_module_for_another_ecosystem_is_a_target_mismatch(target):
    from boundary import TargetMismatch
    cls = transpilers()[target]
    with pytest.raises(TargetMismatch) as exc:
        cls().transpile(PY_FFI.read_text())
    # The message has to name the declaration, or a refusal is unactionable.
    assert "pl/read-csv" in str(exc.value)
    assert ":py" in str(exc.value)


def test_a_module_for_this_ecosystem_that_cannot_be_lowered_says_so():
    from boundary import NotLowered
    from to_rust import ToRust
    with pytest.raises(NotLowered) as exc:
        ToRust().transpile(RS_FFI.read_text())
    assert "does not lower" in str(exc.value)


@pytest.mark.parametrize("target", ["py", "sw"])
def test_that_same_module_is_a_mismatch_for_the_other_backends(target):
    from boundary import TargetMismatch
    with pytest.raises(TargetMismatch):
        transpilers()[target]().transpile(RS_FFI.read_text())


def test_a_defextern_without_a_target_names_no_ecosystem():
    from boundary import TargetMismatch
    from to_python import Transpiler
    src = (ROOT / "grammar" / "corpus" / "semantic" / "extern-without-target.as").read_text()
    with pytest.raises(TargetMismatch) as exc:
        Transpiler().transpile(src)
    assert "no :target" in str(exc.value)


def test_symbol_overrides_the_mangled_host_name():
    from to_python import Transpiler
    out = Transpiler().transpile(PY_FFI.read_text())
    assert "_host_pl.read_csv(" in out      # :symbol "read_csv"
    assert "_host_pl.height(" in out        # no :symbol, so §8 mangling stands
