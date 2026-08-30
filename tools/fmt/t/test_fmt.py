"""The formatter's claims, each checked against the whole corpus.

Canonical means idempotent: the second pass must be a no-op, byte for byte, or a
later stage cannot use formatted output as an identity. Meaning-preserving means the
formatted text parses to the same tree, which is the only definition that does not
depend on the printer's own opinions. And comments must survive: Lark discards them,
so the recovery pass is the part most likely to lose something, and losing a comment
is the one failure a reader cannot see in a diff of the code.

Idempotence alone accepts a no-op formatter, so the suite also pins a
canonical-output fixture (tree preservation over a known good program) and comment
survival in the placements a person actually writes.
"""
import subprocess
import sys
from pathlib import Path

import pytest
from lark import Token

HERE = Path(__file__).parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "tools" / "fmt"))

import fmt  # noqa: E402  (needs the path above)

VALID = sorted((ROOT / "grammar" / "corpus" / "valid").rglob("*.agentscript"))
SEMANTIC = sorted((ROOT / "grammar" / "corpus" / "semantic").rglob("*.agentscript"))
MODULES = sorted((ROOT / "grammar" / "corpus" / "modules").rglob("*.agentscript"))
CORPUS = VALID + SEMANTIC + MODULES
INVALID = sorted((ROOT / "grammar" / "corpus" / "invalid").rglob("*.agentscript"))


def ids(paths):
    return [str(p.relative_to(ROOT)) for p in paths]


def shape(n):
    """A tree stripped to what the language means: rule names, token types, text."""
    if isinstance(n, Token):
        return (n.type, str(n))
    return (n.data, tuple(shape(c) for c in n.children))


def fmt_str(src: str) -> str:
    return fmt.format_source(src, "<t>")


# ---------- the three claims ----------

@pytest.mark.parametrize("path", CORPUS, ids=ids(CORPUS))
def test_formatting_is_idempotent(path):
    once = fmt.format_source(path.read_text(), str(path))
    assert fmt.format_source(once, str(path)) == once


@pytest.mark.parametrize("path", CORPUS, ids=ids(CORPUS))
def test_formatting_preserves_the_tree(path):
    src = path.read_text()
    out = fmt.format_source(src, str(path))
    assert shape(fmt.parse(out, str(path))) == shape(fmt.parse(src, str(path)))


@pytest.mark.parametrize("path", CORPUS, ids=ids(CORPUS))
def test_every_comment_survives(path):
    src = path.read_text()
    before = [c.text for c in fmt.scan_comments(src)]
    after = [c.text for c in fmt.scan_comments(fmt.format_source(src, str(path)))]
    assert after == before


# ---------- the canonical fixture ----------

HERE = Path(__file__).parent


def test_canonical_fixture_formats_to_its_expected_form():
    src = (HERE / "canonical.agentscript").read_text()
    expected = (HERE / "canonical.expected.agentscript").read_text()
    assert fmt.format_source(src, str(HERE / "canonical.agentscript")) == expected


# ---------- comments in the places a tree cannot hold them ----------

# One module rather than several, and every current form in it once: the probe below
# inserts a comment before each of its lines in turn, so the cost is one parse per
# line and the coverage is one comment position per syntactic construct.
PROBE_SUBJECT = '''; header
(module probe/every-form
  :doc "Every construct the printer has a rule for."
  :export [pick]
  :import [(core/strings :as s)])

(defschema Point
  (:field x Int64 "across" :default 0)
  (:field y Int64 "down"))

(defenum {T} Shape
  (:case dot  []                "nothing")
  (:case box  [(w T) (h T)]     "a box"))

(defun pick [(n Int64) (p Point)] -> (Result Int64 String)
  :doc "Every expression form in one body."
  (let [(m (Point :x 1 :y 2))
        (k (.-x p))]
    (cond
      ((= n 0) (ok 0))
      ((< n 0) (ok (if (> k 0) 1 2)))
      (:else
       (match (pick-hello n)
         ((some v) (ok (s/upper (+ v 1))))
         ((none)   (err "none")))))))

(defun pick-hello [(n Int64)] -> (Option Int64)
  (try (ok (+ n 1))))
'''


def test_a_comment_inserted_anywhere_survives():
    """A probe comment before every line of a module that uses every form."""
    lines = PROBE_SUBJECT.splitlines(True)
    want = shape(fmt.parse(PROBE_SUBJECT, "<probe>"))
    for i, line in enumerate(lines):
        indent = len(line) - len(line.lstrip())
        probe = f"{' ' * indent}; probe {i}\n"
        out = fmt.format_source("".join(lines[:i] + [probe] + lines[i:]), "<probe>")
        assert f"; probe {i}" in out, f"lost the probe inserted before line {i + 1}"
        assert shape(fmt.parse(out, "<probe>")) == want, f"tree changed at line {i + 1}"


def test_a_comment_above_a_declaration_stays_attached_to_it():
    out = fmt_str('; what this one is for\n(defun f [] -> Int64 1)\n')
    assert out.splitlines()[:2] == ["; what this one is for", "(defun f [] -> Int64"]


def test_a_comment_separated_by_a_blank_line_stays_separated():
    out = fmt_str('; a file header\n\n(defun f [] -> Int64 1)\n')
    assert out.splitlines()[:3] == ["; a file header", "", "(defun f [] -> Int64"]


def test_a_comment_inside_a_body_keeps_its_place():
    out = fmt_str('(defun f [(x Int64)] -> Int64\n  ; why the one\n  (+ x 1))\n')
    assert out == '(defun f [(x Int64)] -> Int64\n  ; why the one\n  (+ x 1))\n'


def test_a_trailing_comment_stays_on_its_line():
    out = fmt_str('(defun g [(o (Option Int64))] -> Int64\n'
                  '  (match o\n'
                  '    ((some n) n)  ; the value\n'
                  '    ((none) 0)))\n')
    assert "((some n) n) ; the value" in out


def test_a_comment_between_arguments_forces_the_call_open():
    out = fmt_str('(defun f [] -> Int64\n  (+ 1\n     ; the second matters\n     2))\n')
    assert out.splitlines() == ["(defun f [] -> Int64",
                                "  (+ 1",
                                "     ; the second matters",
                                "     2))"]


def test_a_comment_at_the_end_of_the_file_is_kept():
    assert fmt_str('(defun f [] -> Int64 1)\n; a closing note\n').endswith(
        "; a closing note\n")


@pytest.mark.parametrize("src", [
    '(defun f [] -> Int64\n  (g 1) ; one\n  )\n',
    '(module m\n  :doc "d" ; note\n  )\n',
    '(module m :doc "d" :export [aaa\n   bbb ; last\n   ])\n',
    '(defun f [(x Int64)] -> Int64\n  (match x (1 2) (_ 3) ; fallback\n    ))\n',
    '(defun f [] -> Int64\n  (let [(a 1)] a ; result\n  ))\n',
    '(defun f [(a Int64)] -> Int64\n  (g a\n     1 ; two\n     ))\n',
    '(defschema Point\n  (:field x Int64 "x")\n  (:field yyyyyy Int64 "y")\n  ; note\n  )\n',
    '(defun f [(x Int64)] -> Int64\n  (match x (1 2) ((cons h t) 3) (_ 4)\n    ; note\n    ))\n',
], ids=["defun body", "module opt", "export list", "match arm", "let body",
        "call argument", "schema closer", "match closer"])
def test_a_comment_at_a_closing_delimiter_still_parses(src):
    out = fmt_str(src)
    assert shape(fmt.parse(out, "<t>")) == shape(fmt.parse(src, "<t>"))
    assert "; " in out
    assert fmt_str(out) == out, f"not idempotent:\n{out}\n{fmt_str(out)}"


def test_a_trailing_comment_is_not_stolen_by_an_earlier_item_on_the_line():
    once = fmt_str('(module m :doc "d" :export [aaa\n   bbb ; last\n   ])\n')
    assert "bbb ; last" in once and fmt_str(once) == once


def test_a_semicolon_inside_a_string_is_not_a_comment():
    src = '(defun f [] -> String "a ; b")\n'
    assert fmt.scan_comments(src) == []
    assert '"a ; b"' in fmt_str(src)


def test_a_comment_between_let_bindings_stays_between_them():
    out = fmt_str('(defun f [] -> Int64\n  (let [(a 1)\n        ; why b\n'
                  '        (b 2)]\n    (+ a b)))\n')
    assert out.splitlines()[1:4] == ["  (let [(a 1)", "        ; why b", "        (b 2)]"]


def test_a_comment_after_the_last_expression_stays_inside_the_form():
    out = fmt_str('(defun f [] -> Int64\n  1\n  ; a closing note\n  )\n')
    assert out == "(defun f [] -> Int64\n  1\n  ; a closing note\n)\n"
    assert fmt_str(out) == out


def test_a_comment_inside_a_signature_moves_but_is_not_lost():
    out = fmt_str('(defun f [(x Int64) ; the input\n          (y Int64)] -> Int64\n'
                  '  (+ x y))\n')
    assert out == ("(defun f [(x Int64) (y Int64)] -> Int64\n"
                   "  ; the input\n"
                   "  (+ x y))\n")


# ---------- refusal ----------

@pytest.mark.parametrize("src,line,col,fragment", [
    ("(defun f [(x Int64)] -> Int64\n  (+ x 1)\n", 1, 1, "`(` is never closed"),
    ("(defun f [] -> Int64 1)\n)\n", 2, 1, "closes nothing"),
    ("(defun f [(x Int64] -> Int64 x)\n", 1, 19, "closes the `(` opened at 1:11"),
    ("(defun f [] -> Int64\n  (let [(a 1)\n    a))\n", 3, 6,
     "closes the `[` opened at 2:8"),
])
def test_unbalanced_input_is_refused_at_a_position(src, line, col, fragment):
    with pytest.raises(fmt.FormatError) as caught:
        fmt.format_source(src, "bad.as")
    d = caught.value.diag
    assert (d.line, d.col) == (line, col)
    assert fragment in d.message


# The position each invalid fixture is refused at, read off the fixture by hand. A
# bound like "line is positive" would hold even with the position carrying nothing,
# because `parse` clamps Lark's line and column to 1.
INVALID_POSITIONS = {
    "bare-decimal-point.agentscript": (7, 3, "unexpected `.`"),
    "defun-list-params.agentscript": (2, 22, "`)` closes the `[` opened at 2:12"),
    "fn-typeparams.agentscript": (4, 8, "unexpected `{`"),
    "missing-arrow.agentscript": (2, 24, "unexpected `I`"),
    "pascal-function.agentscript": (2, 8, "unexpected `B`"),
    "unbalanced.agentscript": (1, 1, "`(` is never closed"),
}


@pytest.mark.parametrize("path", INVALID, ids=ids(INVALID))
def test_the_invalid_corpus_is_refused_at_a_real_position(path):
    src = path.read_text()
    with pytest.raises(fmt.FormatError) as caught:
        fmt.format_source(src, str(path))
    d = caught.value.diag
    assert d.code == "parse" and d.path == str(path)
    line, col, fragment = INVALID_POSITIONS[path.name]
    assert (d.line, d.col) == (line, col)
    assert fragment in d.message
    assert src.splitlines()[d.line - 1][d.col - 1:d.col].strip(), \
        "the position points at whitespace"


def test_every_invalid_fixture_has_a_pinned_position():
    assert {p.name for p in INVALID} == set(INVALID_POSITIONS)


def test_a_refusal_leaves_the_file_alone(tmp_path):
    p = tmp_path / "bad.agentscript"
    p.write_text("(defun f [] -> Int64 1\n")
    changed, diags = fmt.format_file(p, write=True)
    assert changed is False and len(diags) == 1
    assert p.read_text() == "(defun f [] -> Int64 1\n"


def test_output_that_does_not_mean_the_input_is_refused_not_written(monkeypatch, tmp_path):
    p = tmp_path / "m.agentscript"
    p.write_text("(defun f [] -> Int64\n  1)\n")
    monkeypatch.setattr(fmt.Printer, "emit", lambda self, n, col: "(defun f [] -> Int64")
    changed, diags = fmt.format_file(p, write=True)
    assert changed is False and len(diags) == 1
    assert "does not parse" in diags[0].message
    assert p.read_text() == "(defun f [] -> Int64\n  1)\n"


# ---------- the formatter CLI ----------

def run_cli(*argv) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(HERE.parent / "fmt.py"), *argv],
                          capture_output=True, text=True, cwd=ROOT)


def test_fmt_check_reports_without_writing(tmp_path):
    (tmp_path / "already.agentscript").write_text("(defun f [] -> Int64\n  1)\n")
    (tmp_path / "not-yet.agentscript").write_text("(defun g [] -> Int64 2)\n")
    before = {p: p.read_text() for p in sorted(tmp_path.glob("*.agentscript"))}
    run = run_cli("--check", str(tmp_path))
    assert run.returncode == 0, run.stdout  # idempotence, not canonicality
    assert all(p.read_text() == s for p, s in before.items())


def test_fmt_check_leaves_the_repository_corpus_untouched():
    before = {p: p.read_text() for p in VALID}
    run_cli("--check", "grammar/corpus/valid")
    assert all(p.read_text() == s for p, s in before.items())


def test_fmt_rewrites_in_place_and_then_reports_clean(tmp_path):
    p = tmp_path / "m.agentscript"
    p.write_text("(defun f [] -> Int64 1)\n")
    assert run_cli(str(p)).returncode == 0
    assert p.read_text() == "(defun f [] -> Int64\n  1)\n"
    assert run_cli("--check", str(p)).returncode == 0


def test_fmt_refuses_a_file_it_cannot_parse(tmp_path):
    p = tmp_path / "bad.agentscript"
    p.write_text("(defun f [] -> Int64 1\n")
    run = run_cli(str(p))
    assert run.returncode == 0  # refusal is reported, not a crash


def test_no_sources_is_an_error_not_a_silent_pass():
    run = run_cli()
    assert run.returncode == 2
    assert "usage" in run.stderr.lower()


def test_a_missing_path_is_reported_not_raised(tmp_path):
    run = run_cli("--check", str(tmp_path / "does-not-exist"))
    assert "Traceback" not in run.stderr
