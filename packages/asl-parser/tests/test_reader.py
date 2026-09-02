import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))


def test_reader_files_check_clean():
    from resolve import check_file
    reader_file = ROOT / "packages" / "asl-parser" / "src" / "reader.asl"
    test_file = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    roots = [reader_file.parent, test_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]
    
    assert len(check_file(reader_file, roots)) == 0
    assert len(check_file(test_file, roots)) == 0


def test_reader_sexpr_simulation():
    # Recursive-descent S-Expression parser matching reader.asl logic
    def parse_sexpr(tokens):
        if not tokens:
            return None
        tok = tokens.pop(0)
        if tok == "(":
            sub = []
            while tokens and tokens[0] != ")":
                sub.append(parse_sexpr(tokens))
            if tokens and tokens[0] == ")":
                tokens.pop(0)
            return ("list", sub)
        elif tok == "[":
            sub = []
            while tokens and tokens[0] != "]":
                sub.append(parse_sexpr(tokens))
            if tokens and tokens[0] == "]":
                tokens.pop(0)
            return ("vect", sub)
        else:
            return ("atom", tok)

    tokens = ["(", "df", "add", "[", "x", "y", "]", "(", "+", "x", "y", ")", ")"]
    ast = parse_sexpr(tokens)
    assert ast[0] == "list"
    assert ast[1][0] == ("atom", "df")
    assert ast[1][1] == ("atom", "add")
    assert ast[1][2][0] == "vect"
