import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(Path(__file__).resolve().parent))


def test_harness_executes_asl():
    """The smoke driver runs real transpiled ASL and returns a computed value.

    The value is written by hand from the driver's semantics, not read from the
    harness output. `string-index-of "hello" "l"` is 2, `string-slice "hello"
    1 3` is "el", and the match on the TokenType enum of `(token-kind "(")` is
    the LPAREN tag.
    """
    from harness import run_asl
    fixture = ROOT / "packages" / "asl-parser" / "tests" / "fixtures" / "exec_smoke.asl"
    ns = run_asl(fixture)
    assert ns["run_smoke"]() == "LPAREN|5|el|2|T|T|a:b|ab|7|xy|2|2|9|1|T|3|2|k"
    assert ns["len_list"]([1, 2, 3, 4]) == 4


def test_tokenize_runs():
    """The self-hosted lexer tokenizes a multi-line sample through the harness.

    The sample is `(a 12` then a newline then `:b "xy")`.  Scanned left to
    right with 1-based line and column: `(` at 1:1, symbol `a` at 1:2, int `12`
    at 1:4, newline ends line 1, keyword `:b` at 2:1, string `"xy"` at 2:4,
    `)` at 2:8, and EOF sits after the last character at 2:9.  Every line is
    rendered as kind|raw|line|col by the driver.
    """
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "lexer_test.asl"
    ns = run_asl(driver)
    assert ns["run_tokenize"]() == [
        "LPAREN|(|1|1",
        "SYMBOL|a|1|2",
        "INT|12|1|4",
        "KEYWORD|:b|2|1",
        'STRING|"xy"|2|4',
        "RPAREN|)|2|8",
        "EOF||2|9",
    ]


def test_lexer_files_check_clean():
    from resolve import check_file
    lexer_file = ROOT / "packages" / "asl-parser" / "src" / "lexer.asl"
    test_file = ROOT / "packages" / "asl-parser" / "tests" / "lexer_test.asl"
    roots = [lexer_file.parent, test_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]

    assert len(check_file(lexer_file, roots)) == 0
    assert len(check_file(test_file, roots)) == 0


def _dump():
    from harness import run_asl
    fixture = ROOT / "packages" / "asl-parser" / "tests" / "fixtures" / "tokenize_driver.asl"
    return run_asl(fixture)["dump"]


def test_lexical_rules_of_section_2():
    """The uncontested lexical rules of AGENT_SPEC_CORE 2, on the token stream.

    Each was a defect the parity gate found once. They are pinned at the lexer
    rather than through a parse so that removing a rule fails here, naming the
    rule, instead of surfacing as an unrelated parse error later. Comment
    handling is deliberately absent: it is in flux, so the parity gate derives
    it from the reference grammar instead.
    """
    dump = _dump()

    # A `;` inside a string literal is text. What `;` means OUTSIDE one is not
    # asserted here: the project is replacing `;` comments with free-standing
    # string literals, so `tools/tests/test_native_parity.py` derives that answer
    # from the reference grammar rather than this file pinning it.
    assert dump('"; not a comment"') == ['STRING|"; not a comment"']

    # A float is one token, and the point does not split the run.
    assert dump("89.99") == ["FLOAT|89.99"]
    assert dump("(+ 89.99 0.5)") == [
        "LPAREN|(", "SYMBOL|+", "FLOAT|89.99", "FLOAT|0.5", "RPAREN|)"]

    # A sign belongs to the digits it touches, and to nothing else.
    assert dump("-1") == ["INT|-1"]
    assert dump("- 1") == ["SYMBOL|-", "INT|1"]
    assert dump("-2.5") == ["FLOAT|-2.5"]
    assert dump("->") == ["SYMBOL|->"]

    # An escaped quote stays inside the string.
    assert dump('"say \\"hi\\""') == ['STRING|"say \\"hi\\""']

    # `.5` and `1.` are not numbers, and an unclosed string is not a string.
    assert dump(".5") == ["ERROR|.5"]
    assert dump("1.") == ["ERROR|1."]
    assert dump('"unterminated') == ['ERROR|"unterminated']

    # Braces and quotes end a symbol run; `and` is binary, and the chain this
    # replaced dropped the clauses that said so.
    assert dump("{T}") == ["SYMBOL|{", "SYMBOL|T", "SYMBOL|}"]
    assert dump("a:b") == ["SYMBOL|a", "KEYWORD|:b"]
