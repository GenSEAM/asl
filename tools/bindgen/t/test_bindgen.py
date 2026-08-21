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
    assert generate() == (HERE / "frames.expected.as").read_text()


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
    assert "; Not generated, and why:" in out
    assert "scan_all" in out and "to_arrow" in out


def test_every_declaration_names_a_target():
    body = generate()
    externs = body.count("(defextern ")
    assert externs > 0
    assert body.count(":target :py") == externs


def test_a_container_without_an_element_type_is_not_turned_into_an_opaque():
    # `xs: list` once produced `(defopaque List)` — a host type named `List`,
    # shadowing the language's own. Every gate accepted it, because `defopaque`
    # may name anything and nothing checked the name against the built-ins.
    out = generate()
    assert "defopaque List" not in out
    assert "defopaque Map" not in out
    assert "rows_untyped" in out.split("; Not generated, and why:")[1]


def test_no_opaque_shadows_a_built_in_type_name():
    import re
    names = set(re.findall(r"\(defopaque (\w+)", generate()))
    builtin = {"List", "Option", "Result", "Pair", "Map", "Bool", "Int32",
               "Int64", "Float64", "String", "Unit", "ProcessResult"}
    assert not (names & builtin), f"opaque shadows a built-in: {names & builtin}"


def test_the_generated_module_passes_the_semantic_checker(tmp_path):
    # The strongest check available: generated bindings must be a well-formed
    # module, not merely well-shaped text.
    import subprocess
    f = tmp_path / "gen.as"
    f.write_text(generate())
    r = subprocess.run([sys.executable, str(ROOT / "checker" / "check.py"), str(f)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout
