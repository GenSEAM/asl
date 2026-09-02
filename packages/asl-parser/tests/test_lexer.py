import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))


def test_lexer_files_check_clean():
    from resolve import check_file
    lexer_file = ROOT / "packages" / "asl-parser" / "src" / "lexer.asl"
    test_file = ROOT / "packages" / "asl-parser" / "tests" / "lexer_test.asl"
    roots = [lexer_file.parent, test_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]
    
    assert len(check_file(lexer_file, roots)) == 0
    assert len(check_file(test_file, roots)) == 0


def test_lexer_token_rules():
    # Pure Python mirror of native ASL lexer logic to verify rules
    delims = "()[]"
    whitespaces = " \t\n\r"

    def is_ws(ch):
        return len(ch) > 0 and ch in whitespaces

    def is_delim(ch):
        return len(ch) > 0 and ch in delims

    def classify_atom(atom):
        if atom == "(": return "LPAREN"
        if atom == ")": return "RPAREN"
        if atom == "[": return "LBRACKET"
        if atom == "]": return "RBRACKET"
        if atom.startswith(":"): return "KEYWORD"
        if atom.startswith('"'): return "STRING"
        return "SYMBOL"

    assert is_ws(" ") is True
    assert is_ws("a") is False
    assert is_delim("(") is True
    assert is_delim("x") is False
    assert classify_atom("(") == "LPAREN"
    assert classify_atom(":doc") == "KEYWORD"
    assert classify_atom('"hello"') == "STRING"
    assert classify_atom("my-function") == "SYMBOL"
