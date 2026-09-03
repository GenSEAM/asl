"""The ASN reader, writer and checker against the corpus, in pure AgentScript.

Normative source: docs/ASN_SPEC.md.

Four properties, each with a failure mode the others cannot see:

  * Canonical rendering. Every `corpus/asn/valid` fixture carries a
    `; canonical:` header written by hand, and the writer must reproduce it byte
    for byte. Asserting against a hand-written string rather than against the
    writer's own earlier output is what stops a writer that is merely consistent
    with itself from passing.

  * Idempotence. Writing a document twice changes nothing after the first pass,
    which is the round-trip property stated without reference to source
    formatting.

  * Two-implementation agreement. `grammar/asn.lark` and the pure-AgentScript
    reader must return the same verdict on every fixture, for the reason
    `grammar/validate.py` compares two grammars rather than trusting one: two
    implementations that disagree are enforcing two different formats, and the
    disagreement stays silent until a payload lands on the wrong side of it.

  * Rejection for the declared reason. Each `corpus/asn/semantic` fixture names
    a code in an `; expect:` header, and the checker must report THAT code
    first. A fixture rejected for another reason removes the pressure to write
    the rule it was meant to pin (checker/gate.py, PCP c-099a).
"""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from harness import CORPUS, run_asl  # noqa: E402

DRIVER = Path(__file__).resolve().parent / "asn_driver.asl"

VALID = sorted((CORPUS / "valid").glob("*.asn"))
INVALID = sorted((CORPUS / "invalid").glob("*.asn"))
SEMANTIC = sorted((CORPUS / "semantic").glob("*.asn"))

# Every code docs/ASN_SPEC.md §11 defines. A checker that invented a code outside
# this set would be reporting something no decoder is specified to handle.
SPEC_CODES = {
    "parse", "map-duplicate-key", "record-duplicate-key", "pool-kind",
    "ref-shape", "ref-dangling", "ref-no-pool", "ref-cycle", "table-ragged",
    "table-duplicate-column", "table-missing-column", "row-override-place",
    "row-override-multi", "row-override-unknown", "row-override-duplicate",
    "row-missing-field", "row-too-long", "nil-at-required-field",
    "unknown-schema", "envelope-data-kind", "envelope-scalar-element",
}


@pytest.fixture(scope="module")
def asn():
    return run_asl(DRIVER)


def header(path: Path, tag: str) -> str:
    m = re.search(rf"^; {tag}: (.*)$", path.read_text(), re.M)
    assert m, f"{path.name} has no `; {tag}:` header"
    return m.group(1).strip()


def lark_accepts(path: Path) -> bool:
    from validate_asn import accepts
    ok, _ = accepts(path.read_text())
    return ok


def test_corpus_is_not_empty():
    """A directory nothing reads is not a gate; assert it has fixtures at all."""
    assert len(VALID) >= 16
    assert len(INVALID) >= 16
    assert len(SEMANTIC) >= 10


@pytest.mark.parametrize("path", VALID, ids=lambda p: p.name)
def test_valid_writes_its_hand_written_canonical_form(asn, path):
    assert asn["canon"](path.read_text()) == header(path, "canonical")


@pytest.mark.parametrize("path", VALID, ids=lambda p: p.name)
def test_valid_write_is_idempotent(asn, path):
    assert asn["idem"](path.read_text()) is True


@pytest.mark.parametrize("path", VALID, ids=lambda p: p.name)
def test_valid_raises_no_conformance_code(asn, path):
    assert asn["verdict"](path.read_text()) == ""


@pytest.mark.parametrize("path", INVALID, ids=lambda p: p.name)
def test_invalid_is_rejected(asn, path):
    verdict = asn["verdict"](path.read_text())
    assert verdict.startswith("!"), f"reader accepted {path.name}: {verdict}"
    assert verdict[1:] in SPEC_CODES


@pytest.mark.parametrize("path", SEMANTIC, ids=lambda p: p.name)
def test_semantic_is_rejected_under_the_code_it_names(asn, path):
    want = header(path, "expect")
    got = asn["verdict"](path.read_text())
    assert got, f"{path.name} raised nothing; it must raise {want}"
    codes = got.split("|")
    assert codes[0] == want, f"{path.name} expected {want}, got {codes}"
    assert set(codes) <= SPEC_CODES


@pytest.mark.parametrize("path", VALID + INVALID + SEMANTIC,
                         ids=lambda p: f"{p.parent.name}/{p.name}")
def test_reader_and_grammar_agree(asn, path):
    """The Lark grammar and the AgentScript reader accept exactly the same texts."""
    reader_ok = not asn["canon"](path.read_text()).startswith("!")
    assert reader_ok == lark_accepts(path), (
        f"{path.name}: reader {'accepts' if reader_ok else 'rejects'}, "
        f"asn.lark {'accepts' if not reader_ok else 'rejects'}")


def test_a_head_is_compared_literally_with_no_type_projection(asn):
    """`Str` and `String` are two heads, not one head under two spellings.

    Core section 2.1's type axis aliases `Str` to `String` in the language. A head
    here names a SCHEMA and merely shares PascalCase with a type name, so applying
    that projection would silently merge two schemas whose names happen to collide
    with an alias pair. ASN names no types anywhere and resolves a head as written.
    """
    assert asn["shape"]("(Str [1])") == "rows Str/1"
    assert asn["shape"]("(String [1])") == "rows String/1"
    assert asn["shape"]("(I64 :x 1)") == "ctor I64/1"
    assert asn["shape"]("(Int64 :x 1)") == "ctor Int64/1"
    assert asn["canon"]("(Str [1])") == "(Str [1])"


def test_comments_are_separators_and_carry_no_value(asn):
    """Core §2 comments are insignificant except as separators.

    Pinned on its own because every corpus fixture opens with a header comment,
    so when comment handling regresses in the shared scanner this suite fails a
    hundred canonical-form assertions at once and not one of them names the
    cause. This test names it.
    """
    assert asn["canon"]("; a header\n1") == "1"
    assert asn["canon"]("(:a 1) ; trailing") == "(:a 1)"
    assert asn["canon"]("[1 ; inline\n 2]") == "[1 2]"


def test_shapes_are_what_the_spec_says_they_are(asn):
    """Each construct reads as its own kind, not as a lookalike.

    A row group and a named construction share a PascalCase head and are told
    apart only by the token after it; a table and a record share nothing but
    their parentheses. Written by hand from each fixture's body.
    """
    want = {
        "01-scalars.asn": "vec/11",
        "02-vectors.asn": "vec/3",
        "03-maps.asn": "map/5",
        "04-record.asn": "rec/4",
        "05-ctor.asn": "ctor Item/3",
        "06-row-group.asn": "rows Item/3",
        "07-row-override.asn": "rows Promo/2",
        "08-table.asn": "table/4x2",
        "09-envelope.asn": "rec/4",
        "12-case-values.asn": "vec/3",
        "13-nested-tree.asn": "ctor Element/2",
        "15-qualified-heads.asn": "rec/3",
    }
    for name, expected in want.items():
        assert asn["shape"]((CORPUS / "valid" / name).read_text()) == expected, name


def test_scalar_kinds_are_classified_not_echoed(asn):
    """`_`, `()`, `true` and a keyword are values, not bare names.

    The reader could pass every text-level test while classifying `_` as a
    symbol; only the kind projection sees the difference.
    """
    got = asn["kinds"]((CORPUS / "valid" / "01-scalars.asn").read_text())
    assert got == "int|int|float|float|str|str|bool|bool|unit|kw|nil"


def test_string_lexeme_is_kept_and_still_decodes(asn):
    """A string round-trips as its lexeme AND hands back decoded characters.

    These pull in opposite directions: a reader that decoded eagerly would lose
    the round trip, and one that never decoded would be useless as a decoder.
    """
    src = (CORPUS / "valid" / "14-multiline-text.asn").read_text()
    body = asn["decoded_field"](src, ":body")
    assert body == ('def query_users(db):\n'
                    '    cursor = db.cursor()\n'
                    "    cursor.execute('SELECT \"id\" FROM users')\n"
                    '    return cursor.fetchall()')
    assert '\\n' in asn["canon"](src), "the written form must keep the escape, not the newline"


def test_escape_decoding_handles_a_literal_backslash(asn):
    r"""`\\n` is a backslash then an n, never a newline.

    A decoder built from repeated string-replace gets this wrong whichever order
    it runs in, because any sentinel it picks for a decoded backslash can occur
    in the payload.
    """
    assert asn["decoded_field"](r'(:s "a\\nb")', ":s") == "a\\nb"
    assert asn["decoded_field"](r'(:s "a\nb")', ":s") == "a\nb"
    assert asn["decoded_field"](r'(:s "q\"q")', ":s") == 'q"q'


def test_unit_needs_its_two_delimiters_adjacent(asn):
    """`()` is one lexeme in Core §2, so a space between the two is not unit.

    Without this the reader would accept a text `asn.lark` rejects, and the
    agreement property above would be true only for the fixtures that happen not
    to write it.
    """
    assert asn["shape"]("()") == "unit"
    assert asn["shape"]("( )") == "!parse"
    assert asn["shape"]("[() ()]") == "vec/2"


def test_pool_scope_covers_the_pool_itself(asn):
    """A pool is in scope for its own elements, which is what makes a cycle legal.

    Checking the pool vector outside its own scope would report the cyclic
    fixture as two dangling references, and the format would lose graphs.
    """
    assert asn["verdict"]((CORPUS / "valid" / "11-cyclic-graph.asn").read_text()) == ""
    assert asn["verdict"]('(:pool [(:ref 0)] :data ["x" "y"])') == ""
    assert asn["verdict"]('(:pool [(:ref 1)] :data ["x"])') == "ref-dangling"


def test_nested_pool_shadows_the_outer_one(asn):
    """The inner pool governs its subtree, so an index is read against it alone."""
    assert asn["verdict"]('(:pool ["a" "b" "c"] :data [(:pool ["z"] :data [(:ref 2)])])') \
        == "ref-dangling"
    assert asn["verdict"]('(:pool ["a"] :data [(:pool ["y" "z"] :data [(:ref 1)])])') == ""


def test_data_alone_is_not_an_envelope(asn):
    """A record whose only key is `:data` has a field called data and no merge.

    The distinction matters: as an envelope, a scalar element would be an error,
    and a payload that never asked for a merge would be rejected.
    """
    assert asn["verdict"]('(:data ["a" "b"])') == ""
    assert asn["verdict"]('(:curr "USD" :data ["a"])') == "envelope-scalar-element"
    assert asn["verdict"]('(:pool ["p"] :data ["a"])') == ""


def test_nano_aliases_survive_as_ordinary_data_keys(asn):
    """`:f`, `:d`, `:x`, `:c`, `:i` and `:a` are keys called f, d, x, c, i and a.

    AGENT_SPEC_CORE.md §2.1 makes a Nano alias significant only in the position
    it names, and ASN has none of those positions. A reader that applied the
    projection as text substitution would rewrite every one of these.
    """
    src = '(:f 1 :d 2 :x 3 :c 4 :i 5 :a 6)'
    assert asn["canon"](src) == src
    assert asn["shape"](src) == "rec/6"
    assert asn["verdict"](src) == ""


def test_reader_survives_a_wide_row_without_recursing_per_element(asn):
    """A thousand-element row is a table's normal size, not a stress case.

    The scanner and both work lists step iteratively for this reason; a reader
    written with one stack frame per element overflows the Python host well
    before a real query result does.
    """
    row = " ".join(str(i) for i in range(1000))
    src = f"([:n] [{' '.join('[' + str(i) + ']' for i in range(1000))}])"
    assert asn["shape"](src) == "table/1x1000"
    assert asn["shape"](f"[{row}]") == "vec/1000"
    assert asn["canon"](f"[{row}]") == f"[{row}]"


# Texts the corpus does not reach: empty forms, every map-key kind, both head
# halves, and the shapes just outside Core §2's identifier rule. The two
# qualified-head cases here are the ones that found the reader classifying a
# head by its member alone, so `(S/x 1)` and `(a/b/c 1)` parsed for it and not
# for the grammar. A corpus of whole documents was never going to reach those.
AGREEMENT_PROBES = [
    "()", "( )", "(\n)", "[]", "{}", "[()]", "_", "[_ _]", "{:a _}", "{_ 1}",
    "(Item)", "(Item [])", "(Item [] [])", "(Item [1] [2 3])", "(Item :a 1 [2])",
    "([:a] [])", "([] [])", "([:a] [[1]] [[2]])", '([:a "b"] [[1]])', "([:a] [1])",
    "(:a 1)", "(:a)", "(:a 1 :b)", "(:a :b)", "{(:k 1)}", "{(:k 1 :j 2)}",
    '{("k" 1)}', "{(1 2)}", "{(true 2)}", "{(1.5 2)}", "{(_ 2)}", "{([1] 2)}",
    "(x)", "(x 1)", "(x y)", "(s/Point :x 1)", "(s/circle 1.0)", "(S/x 1)",
    "[1 2 3]", "[[1] [2]]", "(a/b/c 1)", "-1", "- 1", "(- 1 2)", "1.5", ".5", "1.",
    "true", "false", "[true]", '"s"', '["a" "b"]', ":k", "[:k]",
    "(Item [1] (:a 2))", "[(:a 1)]", "[(Item [1])]", "; c\n1", "1 ; c",
    "{:a 1 :b}", "(:pool [] :data [])", "((:a 1))", "[(1 2)]", '(Item "x")',
    "(item [1])", "(Item :a)", "{:a}", "[[]]", "(:a [])", "(:a {})", "(:a ())",
    "(a?/b 1)", "(a/b? 1)", "(fo&o 1)", "(a-- 1)", "(a- 1)", "(-a 1)", "(a1 1)",
    "(A1 :x 1)", "(A_ :x 1)", "(a/B :x 1)", "(a-b/C-d :x 1)", "(a-b/c-d 1)",
    "(ok 1)", "(none)", "(some 1)", "(x! 1)", "(x? 1)", "(x?! 1)", "(1a 1)",
    "(Ab/Cd :x 1)", "(a/ 1)", "(/a 1)", "(a// 1)",
    # The guarantees packages/asl-parser states for its scanner, exercised from
    # this side: a spaced `-` and `->` are symbols and so are not values here, a
    # `;` inside a string is text, a trailing comment is not, and a malformed
    # number or an unterminated string is an error rather than a symbol.
    "(:a -)", "(:a ->)", '(:a "x ; y")', "[1] ; tail", '(:a "unterm',
    "(:a 89.99)", "(:a -1)", "(:a .5)",
]


@pytest.mark.parametrize("text", AGREEMENT_PROBES, ids=lambda t: repr(t))
def test_reader_and_grammar_agree_on_edge_texts(asn, text):
    from validate_asn import accepts
    reader_ok = not asn["canon"](text).startswith("!")
    lark_ok, _ = accepts(text)
    assert reader_ok == lark_ok, (
        f"{text!r}: reader {'accepts' if reader_ok else 'rejects'}, "
        f"asn.lark {'accepts' if lark_ok else 'rejects'}")
