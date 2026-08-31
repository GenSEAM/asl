"""The map-key-order narrowing, at the places the corpus gate cannot pin.

`; expect-only:` compares a SET of codes, so no fixture can state "one
diagnostic". The nested case reported its Float64 twice for exactly that reason
and every gate stayed green. These tests pin the count, and they pin the routes
by which a key type is determined without ever being written down.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "prelude"))

from resolve import check_file  # noqa: E402

CORPUS = ROOT / "grammar" / "corpus" / "semantic"


def codes(tmp_path, src: str) -> list[str]:
    f = tmp_path / "case.agentscript"
    f.write_text(src)
    return [d.code for d in check_file(f, [])]


def test_written_key_is_still_rejected(tmp_path):
    assert codes(tmp_path, "(defun f [(m (Map Float64 Int64))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_inferred_key_is_rejected(tmp_path):
    """The Map is never written: map-from-pairs takes the key from its argument."""
    assert codes(tmp_path, "(defun f [(ps (List (Pair Float64 Int64)))] -> Int64 "
                           "(map-size (map-from-pairs ps)))") == ["map-key-order"]


def test_key_through_a_type_variable_is_rejected(tmp_path):
    assert codes(tmp_path, "(defun {K} blank [(s K)] -> (Map K Int64) (map-empty))\n"
                           "(defun f [(x Float64)] -> Int64 (map-size (blank x)))") \
        == ["map-key-order"]


def test_key_through_a_record_field_is_rejected(tmp_path):
    assert codes(tmp_path, '(defschema P (:field x Float64 "x"))\n'
                           "(defun f [(m (Map P Int64))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_key_through_a_union_case_is_rejected(tmp_path):
    assert codes(tmp_path, '(defenum S (:case circle [(r Float64)] "c") '
                           '(:case dot [] "d"))\n'
                           "(defun f [(m (Map S Int64))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_key_through_two_records_is_rejected(tmp_path):
    assert codes(tmp_path, '(defschema I (:field x Float64 "x"))\n'
                           '(defschema O (:field i I "i"))\n'
                           "(defun f [(m (Map O Int64))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_io_error_key_is_rejected(tmp_path):
    assert codes(tmp_path, "(defun f [(m (Map IoError Int64))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_nested_map_key_reports_once(tmp_path):
    """Two Map keys reaching one Float64 is one defect. scan_values already found
    the inner key before the recursion re-found it, so this read two."""
    assert codes(tmp_path,
                 "(defun f [(m (Map (Map Float64 Int64) String))] -> Int64 (map-size m))") \
        == ["map-key-order"]


def test_key_used_all_over_a_body_reports_once(tmp_path):
    assert codes(tmp_path,
                 "(defun f [(m (Map Float64 Int64)) (k Float64)] -> Int64\n"
                 "  (map-size (map-remove (map-set m k 1) k)))") == ["map-key-order"]


def test_two_functions_are_two_diagnostics(tmp_path):
    """Deduplication is per declaration, not per module: each site is separately
    editable, and collapsing them would hide the second from whoever fixes the
    first."""
    assert codes(tmp_path, "(defun f [(m (Map Float64 Int64))] -> Int64 (map-size m))\n"
                           "(defun g [(m (Map Float64 Int64))] -> Int64 (map-size m))") \
        == ["map-key-order", "map-key-order"]


def test_orderable_keys_are_accepted(tmp_path):
    for key in ("Int32", "Int64", "String", "Bool", "(List Int64)",
                "(Pair Int64 String)", "(Map String Int64)"):
        assert codes(tmp_path, f"(defun f [(m (Map {key} Int64))] -> Int64 "
                               "(map-size m))") == [], key


def test_a_record_of_orderable_fields_is_an_admissible_key(tmp_path):
    """The rule is that a key has an order, not that a key is primitive: a record
    whose fields are all orderable derives Ord and lowers."""
    assert codes(tmp_path, '(defschema P (:field x Int64 "x") (:field s String "s"))\n'
                           "(defun f [(m (Map P Int64))] -> Int64 (map-size m))") == []


def test_a_recursive_schema_key_terminates(tmp_path):
    assert codes(tmp_path, '(defschema N (:field next (Option N) "next") '
                           '(:field v Int64 "v"))\n'
                           "(defun f [(m (Map N Int64))] -> Int64 (map-size m))") == []


def test_float_elsewhere_in_the_map_is_admissible(tmp_path):
    """Only the key is ordered. A Float64 VALUE has always been fine, and a rule
    that scanned the whole type would have taken it too."""
    assert codes(tmp_path, "(defun f [(m (Map String Float64))] -> Int64 "
                           "(map-size m))") == []


def test_every_map_key_fixture_reports_exactly_one_diagnostic():
    for path in sorted(CORPUS.glob("map-*.agentscript")):
        assert [d.code for d in check_file(path, [])] == ["map-key-order"], path.name
