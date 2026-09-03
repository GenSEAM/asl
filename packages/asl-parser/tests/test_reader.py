import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "tools"))

from transcoder import to_ultra_nano  # noqa: E402

# `:json-case` leads the fields: that is where the grammar's `schema_opt*` sits.
VERBOSE = """
(module asl-parser/sample
  :doc "A sample module for dual projection."
  :export [add area Shape]
  :import [(core/strings :as s)])

(defschema Point
  :json-case camel
  (:field x Int64 "Horizontal coordinate")
  (:field y Int64 "Vertical coordinate" :default 0))

(defenum Shape
  (:case circle [(radius Float64)] "A circle")
  (:case point [] "A degenerate shape"))

(defun add [(a Int64) (b Int64)] -> Int64
  :doc "Adds two integers."
  (+ a b))

(defun area [(sh Shape)] -> Float64
  :doc "Area of a shape, zero for degenerate cases."
  (match sh
    ((circle r) r)
    ((point) 0)))
"""

NANO_HAND = """
(module asl-parser/sample
  :d "A sample module for dual projection."
  :x [add area Shape]
  :i [(core/strings :a s)])

(dfs Point
  :json-case camel
  (:f x Int64 "Horizontal coordinate")
  (:f y Int64 "Vertical coordinate" :default 0))

(dfe Shape
  (:c circle [(radius Float64)] "A circle")
  (:c point [] "A degenerate shape"))

(df add [(a Int64) (b Int64)] -> Int64
  :d "Adds two integers."
  (+ a b))

(df area [(sh Shape)] -> Float64
  :d "Area of a shape, zero for degenerate cases."
  (mt sh
    ((circle r) r)
    ((point) 0)))
"""

# Hand-written from the fixture by applying the transcoder mapping once, at the
# field level: module path, module doc, 3 exports, one import, four
# declarations, then per form the name/effect/param-count/return/json-case/
# case-count values.
EXPECT_PARSE = ('module|asl-parser/sample|"A sample module for dual projection."|3|1|4'
                "|schema|Point|2|camel"
                "|enum|Shape|2"
                "|defun|add|F|2|Int64|T"
                "|defun|area|F|1|Float64|T")

# Per-form projection covering every mapped head — defun/df, defschema/dfs,
# defenum/dfe, match/mt, :field/:f, :case/:c, :doc/:d, :export/:x, :import/:i
# and :as/:a — traced by hand from the fixture and the canonical render.
EXPECT_HEADS = ('"A sample module for dual projection."|add,area,Shape|core/strings:s'
                '|schema|Point|x:Int64:"Horizontal coordinate",y:Int64:"Vertical coordinate"|camel'
                '|enum|Shape|circle:"A circle",point:"A degenerate shape"'
                '|defun|add|F|2|Int64|"Adds two integers."|(+ a b)'
                '|defun|area|F|1|Float64|"Area of a shape, zero for degenerate cases."'
                '|(match sh ((circle r) r) ((point) 0))')

# Canonical verbose render of every top form, traced by hand from render-node.
EXPECT_RENDER = ('(module asl-parser/sample :doc "A sample module for dual projection." '
                 ":export [add area Shape] :import [(core/strings :as s)])"
                 "\n"
                 "(defschema Point :json-case camel (:field x Int64 \"Horizontal coordinate\") "
                 "(:field y Int64 \"Vertical coordinate\" :default 0))"
                 "\n"
                 "(defenum Shape (:case circle [(radius Float64)] \"A circle\") "
                 "(:case point [] \"A degenerate shape\"))"
                 "\n"
                 "(defun add [(a Int64) (b Int64)] -> Int64 "
                 ":doc \"Adds two integers.\" (+ a b))"
                 "\n"
                 "(defun area [(sh Shape)] -> Float64 "
                 ":doc \"Area of a shape, zero for degenerate cases.\" "
                 "(match sh ((circle r) r) ((point) 0)))")


def _render(ns, src):
    """The driver's `(Result String ParseError)` unwrapped, failing on `err`."""
    res = ns["render_all"](src)
    assert res[0] == "ok", f"parse failed: {res}"
    return res[1]


def test_reader_files_check_clean():
    from resolve import check_file
    reader_file = ROOT / "packages" / "asl-parser" / "src" / "reader.asl"
    ast_file = ROOT / "packages" / "asl-parser" / "src" / "ast.asl"
    test_file = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    roots = [reader_file.parent, test_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]

    assert len(check_file(reader_file, roots)) == 0
    assert len(check_file(ast_file, roots)) == 0
    assert len(check_file(test_file, roots)) == 0


def test_ast_nodes_run():
    """The four typed AST node kinds construct and project through the harness.

    Each exported driver entry builds one node — a module, a schema with a
    field carrying a :default and a :json-case, an enum with one case, a defun
    whose body holds a generic SExpr, and a TopForm wrapper unwrapped by a
    match on the enum payload — and projects fields to text. Every value is
    written by hand from the driver's construction, not read from its output.
    """
    from harness import run_asl
    fixture = ROOT / "packages" / "asl-parser" / "tests" / "fixtures" / "ast_driver.asl"
    ns = run_asl(fixture)
    assert ns["proj_module"]() == 'demo/mod|"module docs"|2|1|0'
    assert ns["proj_schema"]() == "Point|1|x|some camel"
    assert ns["proj_enum"]() == 'Shape|point|"a dot"'
    assert ns["proj_defun"]() == "twice|T|F|1|Int64|1"
    assert ns["proj_topform"]() == "id"


def test_parse_verbose():
    """Parsing a verbose module through the harness yields the hand-written AST."""
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    assert ns["proj_parse"](VERBOSE) == EXPECT_PARSE


def test_parse_nano():
    """Parsing the Ultra-Nano twin yields the same hand-written AST as verbose."""
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    assert ns["proj_parse"](NANO_HAND) == EXPECT_PARSE


def test_nano_verbose_roundtrip():
    """Ultra-Nano and verbose project to the same AST and the same canonical text.

    Two Ultra-Nano twins feed the check: one produced by the reference
    transcoder (`to_ultra_nano`) and one written by hand, so a parser that
    cheats by calling the transcoder internally cannot match its own output.
    For every top form the render is byte-identical across the three sources,
    and the per-form head projection is identical and hand-grounded.
    """
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    nano_auto = to_ultra_nano(VERBOSE)
    for src in (VERBOSE, nano_auto, NANO_HAND):
        assert ns["proj_parse"](src) == EXPECT_PARSE
        assert ns["proj_heads"](src) == EXPECT_HEADS
        assert _render(ns, src) == EXPECT_RENDER


def test_json_case_read_in_both_dialects():
    """`:json-case` written after the fields still renders in its grammar slot.

    The parser reads the option wherever it was written; the render puts it
    where `schema_opt*` admits it, which is what keeps the output re-parseable.
    """
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    verbose = '(defschema Tag :json-case camel (:field name String "The tag"))'
    trailing = '(defschema Tag (:field name String "The tag") :json-case camel)'
    nano = '(dfs Tag (:f name String "The tag") :json-case camel)'
    for src in (verbose, trailing, nano):
        assert ns["proj_parse"](src) == "schema|Tag|1|camel"
        assert _render(ns, src) == verbose


def test_parse_error_carries_line_and_column():
    """A rejected source yields a located diagnostic, not a silent empty form.

    The unclosed `(` opens on line 2 column 1, which is what the reader reports
    when the token stream ends with a frame still open.
    """
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    src = '(module t/x :doc "d")\n(defun broken [] -> Int64 :doc "b" (+ 1 2)\n'
    res = ns["render_all"](src)
    assert res[0] == "err", res
    assert res[1] == {"msg": "unclosed delimiter", "line": 2, "col": 1}
    assert ns["proj_parse"](src) == "2:1: unclosed delimiter"


def test_nested_forms_do_not_recurse_per_level():
    """A 3000-deep body renders without exhausting CPython's stack.

    The reader walks an explicit frame stack and the renderer drains an explicit
    work list, so neither depends on nesting depth for its own call depth.
    """
    from harness import run_asl
    driver = ROOT / "packages" / "asl-parser" / "tests" / "reader_test.asl"
    ns = run_asl(driver)
    depth = 3000
    body = "(id " * depth + "1" + ")" * depth
    src = f'(defun deep [] -> Int64 :doc "d" {body})'
    assert _render(ns, src) == f'(defun deep [] -> Int64 :doc "d" {body})'
