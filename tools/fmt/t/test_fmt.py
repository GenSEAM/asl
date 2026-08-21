"""The formatter's three claims, each checked against the whole corpus.

Canonical means idempotent: the second pass must be a no-op, byte for byte, or a
later stage cannot use formatted output as an identity. Meaning-preserving means the
formatted text parses to the same tree, which is the only definition that does not
depend on the printer's own opinions. And comments must survive: Lark discards them,
so the recovery pass is the part most likely to lose something, and losing a comment
is the one failure a reader cannot see in a diff of the code.

The corpus is the subject rather than a handful of snippets because a printer is only
canonical over the shapes it has actually met.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest
from lark import Token

HERE = Path(__file__).parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "tools" / "fmt"))

import fmt  # noqa: E402  (needs the path above)

CLI = ROOT / "as-lang"
VALID = sorted((ROOT / "grammar" / "corpus" / "valid").rglob("*.as"))
SEMANTIC = sorted((ROOT / "grammar" / "corpus" / "semantic").rglob("*.as"))
OTHER = sorted((ROOT / "examples").rglob("*.as")) + \
    sorted((ROOT / "backend" / "t").rglob("*.as")) + \
    sorted((ROOT / "bench").rglob("*.as"))
CORPUS = VALID + SEMANTIC + OTHER
INVALID = sorted((ROOT / "grammar" / "corpus" / "invalid").rglob("*.as"))


def ids(paths):
    return [str(p.relative_to(ROOT)) for p in paths]


def shape(n):
    """A tree stripped to what the language means: rule names, token types, text."""
    if isinstance(n, Token):
        return (n.type, str(n))
    return (n.data, tuple(shape(c) for c in n.children))


def run_cli(*argv) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CLI), *argv],
                          capture_output=True, text=True, cwd=ROOT)


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


# ---------- comments in the places a tree cannot hold them ----------
#
# The corpus's own 77 comments all sit at column 1 above a top-level form, so passing
# the whole-corpus test above says nothing about the placements a person actually
# writes. The probe test below manufactures the missing coverage, and the named cases
# after it pin the placements whose handling is a deliberate choice.

def fmt_str(src: str) -> str:
    return fmt.format_source(src, "<t>")


# One module rather than several, and every form in it once: the probe below inserts
# a comment before each of its lines in turn, so the cost is one parse per line and
# the coverage is one comment position per syntactic construct.
PROBE_SUBJECT = '''; header
(module probe/every-form
  :doc "Every construct the printer has a rule for."
  :export [pick]
  :import [(core/strings :as s)])

(defopaque Handle
  :doc "A host value.")

(defschema Point
  (:field x Int64 "across" :default 0)
  (:field y Int64 "down"))

(defenum {T} Shape
  (:case dot  []                "nothing")
  (:case box  [(w T) (h T)]     "a box"))

(defextern s/upper [(a String)] -> String
  :doc "host upper"
  :target :py)

(defun pick [(n Int64) (p Point) (o (Option Int64))] -> (Result String String)
  :doc "Every expression form in one body."
  (let [(m (Point :x 1 :y 2))
        (k (.-x p))]
    (cond
      ((= n 0) (ok "zero"))
      ((< n 0) (ok (if (> k 0) "a" "b")))
      (:else
       (match o
         ((some v) (ok (s/upper (str "v" (string-from-int64 v)))))
         ((none)   (err (str "none " (string-from-int64 (try (ok k)))))))))))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Run it."
  :effects [console]
  (println (str "n=" (string-from-int64 (list-length argv)))))
'''


def test_a_comment_inserted_anywhere_survives():
    """A probe comment before every line of a module that uses every form.

    This is the coverage the corpus cannot give: all 77 of its comments sit at
    column 1 above a declaration, so a printer that dropped every comment written
    inside a form would still pass a corpus-wide count unchanged.
    """
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


# A comment claims the rest of its line, so a closing delimiter appended after one is
# inside it and the module no longer parses. Every route that closes a form is
# exercised: `_stack`, `_fill` under a call, `_fill` under a bracketed keyword list.
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
    """It belongs to the item it follows, and must not drift on a second pass."""
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
    """The tree ends a form at its last child, so this position needs the closer map.

    Without it the comment reads as if it were outside the declaration: it would be
    hoisted to top level on one pass and change the alignment on the next.
    """
    out = fmt_str('(defun f [] -> Int64\n  1\n  ; a closing note\n  )\n')
    assert out == "(defun f [] -> Int64\n  1\n  ; a closing note\n)\n"
    assert fmt_str(out) == out


def test_a_comment_inside_a_signature_moves_but_is_not_lost():
    """The one place the printer cannot hold a comment, asserted rather than hidden.

    A parameter list is printed flat, so a comment between two parameters has no line
    to sit on; it is pushed to the front of the body instead of being dropped.
    """
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
    "defun-list-params.as": (2, 22, "`)` closes the `[` opened at 2:12"),
    "fn-typeparams.as": (4, 8, "unexpected `{`"),
    "missing-arrow.as": (2, 24, "unexpected `I`"),
    "pascal-function.as": (2, 8, "unexpected `B`"),
    "unbalanced.as": (1, 1, "`(` is never closed"),
}


@pytest.mark.parametrize("path", INVALID, ids=ids(INVALID))
def test_the_invalid_corpus_is_refused_at_a_real_position(path):
    src = path.read_text()
    with pytest.raises(fmt.FormatError) as caught:
        fmt.format_source(src, str(path))
    d = caught.value.diag
    assert d.rule == 1 and d.file == str(path)
    line, col, fragment = INVALID_POSITIONS[path.name]
    assert (d.line, d.col) == (line, col)
    assert fragment in d.message
    assert src.splitlines()[d.line - 1][d.col - 1:d.col].strip(), \
        "the position points at whitespace"


def test_every_invalid_fixture_has_a_pinned_position():
    """A new fixture must be given an expected position rather than pass by default."""
    assert {p.name for p in INVALID} == set(INVALID_POSITIONS)


def test_a_refusal_leaves_the_file_alone(tmp_path):
    p = tmp_path / "bad.as"
    p.write_text("(defun f [] -> Int64 1\n")
    changed, diags = fmt.format_file(p, write=True)
    assert changed is False and len(diags) == 1
    assert p.read_text() == "(defun f [] -> Int64 1\n"


def test_output_that_does_not_mean_the_input_is_refused_not_written(monkeypatch, tmp_path):
    """The last line of defence: a printer bug must refuse, never corrupt a file.

    A layout defect that swallowed a closing paren was real, and `format_file` had no
    way to notice before overwriting the source. Re-parsing the printed text is what
    turns that class of bug into a diagnostic.
    """
    p = tmp_path / "m.as"
    p.write_text("(defun f [] -> Int64\n  1)\n")
    monkeypatch.setattr(fmt.Printer, "emit", lambda self, n, col: "(defun f [] -> Int64")
    changed, diags = fmt.format_file(p, write=True)
    assert changed is False and len(diags) == 1
    assert "does not parse" in diags[0].message
    assert p.read_text() == "(defun f [] -> Int64\n  1)\n"


# ---------- the formatted tree still passes the toolchain ----------

def test_formatted_corpus_still_checks_clean(tmp_path):
    """Meaning is preserved in the checker's eyes, not only the parser's."""
    for p in VALID + [q for q in OTHER if "examples" in str(q)]:
        flat = str(p.relative_to(ROOT)).replace("/", "--")
        (tmp_path / flat).write_text(fmt.format_source(p.read_text(), str(p)))
    run = subprocess.run([sys.executable, str(ROOT / "checker" / "check.py"),
                          "--json", str(tmp_path)], capture_output=True, text=True)
    assert json.loads(run.stdout) == [], run.stdout


# ---------- the CLI ----------

def test_diagnostics_use_the_toolchain_shape():
    run = run_cli("--json", "check", "grammar/corpus/semantic/try-outside-result.as")
    diags = json.loads(run.stdout)
    assert diags and all(set(d) == {"file", "line", "col", "rule", "message"}
                         for d in diags)
    assert run.returncode == len(diags)


def test_check_agrees_with_the_script_it_delegates_to():
    args = ["--json", "grammar/corpus/semantic"]
    mine = run_cli("--json", "check", "grammar/corpus/semantic")
    theirs = subprocess.run([sys.executable, str(ROOT / "checker" / "check.py"), *args],
                            capture_output=True, text=True, cwd=ROOT)
    assert json.loads(mine.stdout) == json.loads(theirs.stdout)
    assert mine.returncode == theirs.returncode


def test_a_clean_check_exits_zero():
    assert run_cli("check", "grammar/corpus/valid").returncode == 0


def test_build_writes_the_backend_output_to_stdout():
    run = run_cli("build", "grammar/corpus/valid/02-match.as", "--target", "rs")
    assert run.returncode == 0
    assert "pub fn sum_list" in run.stdout


def test_build_reports_a_refusal_as_one_diagnostic():
    run = run_cli("--json", "build", "grammar/corpus/valid/08-ffi.as", "--target", "rs")
    diags = json.loads(run.stdout)
    assert run.returncode == 1 and len(diags) == 1
    assert "TargetMismatch" in diags[0]["message"]


def test_fmt_check_reports_without_writing(tmp_path):
    """The count comes from files whose state is known, not from the formatter itself."""
    (tmp_path / "already.as").write_text("(defun f [] -> Int64\n  1)\n")
    (tmp_path / "not-yet.as").write_text("(defun g [] -> Int64 2)\n")
    (tmp_path / "also-not.as").write_text("(defun h []   ->   Int64\n 3)\n")
    before = {p: p.read_text() for p in sorted(tmp_path.glob("*.as"))}
    run = run_cli("fmt", "--check", str(tmp_path))
    assert run.returncode == 2, run.stdout
    assert all(p.read_text() == s for p, s in before.items())


def test_fmt_check_leaves_the_repository_corpus_untouched():
    before = {p: p.read_text() for p in VALID}
    run_cli("fmt", "--check", "grammar/corpus/valid")
    assert all(p.read_text() == s for p, s in before.items())


def test_fmt_rewrites_in_place_and_then_reports_clean(tmp_path):
    p = tmp_path / "m.as"
    p.write_text("(defun f [] -> Int64 1)\n")
    assert run_cli("fmt", str(p)).returncode == 0
    assert p.read_text() == "(defun f [] -> Int64\n  1)\n"
    assert run_cli("fmt", "--check", str(p)).returncode == 0


def test_fmt_refuses_a_file_it_cannot_parse(tmp_path):
    p = tmp_path / "bad.as"
    p.write_text("(defun f [] -> Int64 1\n")
    run = run_cli("--json", "fmt", str(p))
    diags = json.loads(run.stdout)
    assert run.returncode == 1 and diags[0]["rule"] == 1
    assert diags[0]["line"] == 1 and diags[0]["col"] == 1


def test_ast_runs_a_tree_sitter_query():
    run = run_cli("ast", "grammar/corpus/valid/06-module.as")
    if "npm install" in run.stdout:
        pytest.skip("tree-sitter is not installed in this checkout")
    assert run.returncode == 0 and "capture:" in run.stdout


def test_no_sources_is_an_error_not_a_silent_pass():
    run = run_cli("fmt")
    assert run.returncode == 1 and "no .as files" in run.stderr


@pytest.mark.parametrize("argv", [
    ("check", "/tmp/as-lang-does-not-exist.as"),
    ("fmt", "--check", "/tmp/as-lang-does-not-exist.as"),
])
def test_a_missing_path_is_reported_not_raised(argv):
    run = run_cli(*argv)
    assert run.returncode == 1
    assert "no such file" in run.stderr and "Traceback" not in run.stderr


def test_a_missing_file_is_reported_by_build():
    run = run_cli("--json", "build", "/tmp/as-lang-does-not-exist.as", "--target", "py")
    assert run.returncode == 1 and "Traceback" not in run.stderr
    assert json.loads(run.stdout)[0]["message"] == "no such file"


@pytest.mark.parametrize("place", ["global", "subcommand"])
def test_json_is_accepted_before_or_after_the_subcommand(place):
    argv = (("--json", "fmt", "--check") if place == "global"
            else ("fmt", "--json", "--check"))
    run = run_cli(*argv, "grammar/corpus/valid/01-basics.as")
    assert run.returncode == 1
    assert json.loads(run.stdout)[0]["file"].endswith("01-basics.as")


@pytest.mark.parametrize("target", sorted(["py", "rs", "sw"]))
def test_build_reaches_every_backend(target):
    run = run_cli("build", "grammar/corpus/valid/02-match.as", "--target", target)
    assert run.returncode == 0 and run.stdout.strip()


def test_check_target_refuses_effects_the_target_cannot_provide():
    """wasm has no filesystem, and 07-io reads one; delegation must carry that through."""
    clean = run_cli("--json", "check", "--target", "rs",
                    "grammar/corpus/valid/07-io.as")
    refused = run_cli("--json", "check", "--target", "wasm",
                      "grammar/corpus/valid/07-io.as")
    assert clean.returncode == 0
    assert refused.returncode > 0
    assert all(d["rule"] == 12 for d in json.loads(refused.stdout))


def test_an_unknown_target_is_refused_by_the_parser_not_a_traceback():
    run = run_cli("check", "--target", "bogus", "grammar/corpus/valid")
    assert run.returncode == 2 and "invalid choice" in run.stderr


def test_rules_is_reachable_through_the_one_entry_point():
    run = run_cli("check", "--rules")
    assert run.returncode == 0
    assert "NOT CHECKED:" in run.stdout


def test_ast_accepts_a_query_of_its_own():
    run = run_cli("ast", "grammar/corpus/valid/07-io.as",
                  "-q", "grammar/tree-sitter-as-lang/queries/highlights.scm")
    if "npm install" in run.stdout:
        pytest.skip("tree-sitter is not installed in this checkout")
    assert run.returncode == 0 and "comment" in run.stdout


def test_ast_reports_a_bad_query_as_a_diagnostic(tmp_path):
    bad = tmp_path / "bad.scm"
    bad.write_text("(this_node_does_not_exist) @x\n")
    run = run_cli("--json", "ast", "grammar/corpus/valid/07-io.as", "-q", str(bad))
    if "npm install" in run.stdout:
        pytest.skip("tree-sitter is not installed in this checkout")
    assert run.returncode == 1
    assert set(json.loads(run.stdout)[0]) == {"file", "line", "col", "rule", "message"}


def test_a_message_carries_no_terminal_colouring():
    run = run_cli("--json", "build", "grammar/corpus/valid/08-ffi.as", "--target", "rs")
    assert "\x1b" not in run.stdout
