"""Unit tests for the parts of the type layer the corpus cannot reach.

The gate proves the checker's verdict on whole programs. These cover the pieces
whose failure modes are silent: a unifier that accepts everything also makes the
gate green.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "prelude"))

import resolve  # noqa: E402
from resolve import CONSTRUCTOR_ARITY, check_file  # noqa: E402
from types_ import Con, Fun, Mismatch, Var, prune, show, unify  # noqa: E402
from vocab import parse_signature, signatures  # noqa: E402


def check(tmp_path, src: str) -> list[str]:
    f = tmp_path / "case.agents"
    f.write_text(src)
    return [d.code for d in check_file(f, [])]


def test_every_builtin_signature_parses():
    for name, sig in signatures().items():
        args, variadic, ret = parse_signature(sig)
        assert isinstance(args, list) and isinstance(ret, dict), name


def test_nullary_signature_has_no_arguments():
    args, variadic, ret = parse_signature("-> (Map K V)")
    assert args == [] and not variadic
    assert ret == {"con": "Map", "args": [{"var": "K"}, {"var": "V"}]}


def test_variadic_is_flagged():
    args, variadic, _ = parse_signature("String... -> String")
    assert variadic and len(args) == 1


def test_higher_order_argument_keeps_its_shape():
    args, _, _ = parse_signature("(fn [B A] -> B) B (List A) -> B")
    assert args[0] == {"fn": [{"var": "B"}, {"var": "A"}], "ret": {"var": "B"}}


def test_var_binds_to_concrete_type():
    v = Var()
    unify(v, Con("String"))
    assert isinstance(prune(v), Con) and prune(v).name == "String"


def test_numeric_var_rejects_a_string():
    with pytest.raises(Mismatch):
        unify(Var("num"), Con("String"))


def test_integer_var_rejects_a_float():
    with pytest.raises(Mismatch) as exc:
        unify(Var("int"), Con("Float64"))
    assert exc.value.numeric          # reported as rule 6, not a generic mismatch


def test_two_vars_narrow_to_the_tighter_kind():
    a, b = Var("num"), Var("int")
    unify(a, b)
    unify(a, Con("Int64"))
    assert prune(b).name == "Int64"


def test_one_numeric_type_per_form():
    """(+ a b) shares one N, so mixing widths cannot unify — rule 6."""
    n = Var("num")
    unify(n, Con("Int32"))
    with pytest.raises(Mismatch) as exc:
        unify(n, Con("Int64"))
    assert exc.value.numeric


def test_constructor_arity_and_name_must_match():
    with pytest.raises(Mismatch):
        unify(Con("List", [Con("Int64")]), Con("Option", [Con("Int64")]))
    with pytest.raises(Mismatch):
        unify(Con("Result", [Var(), Var()]), Con("Result", [Var()]))


def test_nested_arguments_unify_through():
    a = Var()
    unify(Con("List", [Con("Option", [a])]), Con("List", [Con("Option", [Con("Bool")])]))
    assert prune(a).name == "Bool"


def test_rigid_variable_does_not_unify_with_a_concrete_type():
    with pytest.raises(Mismatch):
        unify(Con("#T"), Con("Int64"))


def test_function_types_unify_pointwise():
    r = Var()
    unify(Fun([Con("Int64")], r), Fun([Var()], Con("String")))
    assert prune(r).name == "String"


def test_same_name_from_different_modules_does_not_unify():
    """Nominal identity is keyed by the defining module. Without the key this is
    the one failure of the phase that leaves every gate green."""
    with pytest.raises(Mismatch):
        unify(Con("Shape", (), "core/shapes"), Con("Shape", (), "text/clash"))


def test_one_module_reached_through_two_aliases_is_one_type():
    """The other direction, which no corpus fixture can reach on its own: an
    alias is module-local and must not participate in identity."""
    a = Con("Shape", (), "core/shapes", "s/Shape")
    b = Con("Shape", (), "core/shapes", "sh/Shape")
    unify(a, b)
    assert show(a) == "s/Shape"


def test_show_hides_the_rigid_marker():
    assert show(Con("#T")) == "T"
    assert show(Con("List", [Con("Int64")])) == "(List Int64)"


def test_type_constructor_arities_are_derived_not_restated():
    """§3's arities are recorded in the prelude only by being used, so they are
    read back off the builtin signatures. A constructed type named in no
    signature would derive as nullary and silently accept `(Map)`."""
    assert {c: CONSTRUCTOR_ARITY[c] for c in ("List", "Option", "Result", "Pair", "Map")} == \
        {"List": 1, "Option": 1, "Result": 2, "Pair": 2, "Map": 2}
    assert CONSTRUCTOR_ARITY["Int64"] == 0
    assert CONSTRUCTOR_ARITY["IoError"] == 0
    assert CONSTRUCTOR_ARITY["Int"] == 0                 # the documented alias


def test_unapplied_constructor_is_refused_before_the_type_layer_reads_it(tmp_path):
    src = '(defun f [(p Pair)] -> Int64\n  (.-first p))\n'
    assert check(tmp_path, src) == ["type-arity"]


def test_field_default_must_be_a_value_of_its_field(tmp_path):
    """A `:default` is a child of `field`, not an expression, so no traversal of
    the body reaches it; unchecked, its mismatch belongs to every caller that
    omits the key and to no construction site."""
    src = ('(defschema Point\n'
           '  (:field x Int64 "x" :default "zero")\n'
           '  (:field y Int64 "y"))\n\n'
           '(defun f [] -> Int64 (.-y (Point :y 1)))\n')
    assert check(tmp_path, src) == ["type"]


def test_a_checker_bug_reaches_the_caller_as_a_diagnostic(tmp_path, monkeypatch):
    """check_file promises diagnostics rather than tracebacks — the measurement
    harness feeds it generated code. `internal` is a code no fixture declares, so
    the gate still reports a bug caught here as a failure."""
    monkeypatch.setattr(resolve.Checker, "run",
                        lambda self: (_ for _ in ()).throw(IndexError("boom")))
    assert check(tmp_path, "(defun f [] -> Int64 1)\n") == ["internal"]
