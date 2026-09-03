"""The generator's output is checked in, so a change to it shows up as a diff.

The two cases that matter are the two a regex-based prototype got wrong: a
nested generic whose parameters contain a comma, and an optional return. Both
are in frames.pyi deliberately.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent.parent.parent
GEN = ROOT / "tools" / "bindgen" / "from_pyi.py"
ARGS = ["--module", "data/frames", "--package", "polars", "--alias", "pl", "--target", "py"]


def generate() -> str:
    r = subprocess.run([sys.executable, str(GEN), str(HERE / "frames.pyi"), *ARGS],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout


def test_output_matches_the_checked_in_expectation():
    assert generate() == (HERE / "frames.expected.agentscript").read_text()


def test_nested_generic_keeps_its_parameters():
    # `dict[str, list[int]]` — the comma is inside the brackets, and a splitter
    # that does not track them reads it as a second argument.
    assert "(options (Map String (List Int64)))" in generate()


def test_optional_return_becomes_an_option():
    assert "-> (Option (Map String String))" in generate()


def test_optional_parameter_becomes_an_option():
    assert "(percentiles (Option (List Float64)))" in generate()


def test_symbol_is_emitted_only_when_mangling_cannot_round_trip():
    out = generate()
    # readCSV cannot be reached from a kebab-case name by §8 mangling.
    assert ':symbol "readCSV"' in out
    # read_csv can, so no override is emitted for it.
    block = out.split("(defextern pl/read-csv [")[1].split("(defextern")[0]
    assert ":symbol" not in block


def test_none_return_is_unit():
    assert "-> Unit" in generate()


def test_unmappable_functions_are_reported_not_dropped_silently():
    out = generate()
    assert '"Not generated, and why:"' in out
    assert "scan_all" in out and "to_arrow" in out


def test_every_declaration_names_a_target():
    body = generate()
    externs = body.count("(defextern ")
    assert externs > 0
    assert body.count(":target :py") == externs
