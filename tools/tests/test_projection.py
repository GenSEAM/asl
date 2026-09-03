"""The Nano projection is positional (@pcp:d-1eed).

A Nano alias names a head or an option keyword only where the grammar admits its
terminal. Every tool that projects a module has to honour that, so these tests pin
the one case a text substitution gets wrong — a record whose field names are
exactly the six option letters — across the transcoder, the formatter, the
interface compressor and the viewer.
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "prelude"))

from resolve import check_file  # noqa: E402
from tools.fmt import fmt  # noqa: E402
from tools.mcp.compressor import CompressError, compress_module  # noqa: E402
from tools.transcoder import (NANO, VERBOSE, TranscodeError,  # noqa: E402
                              to_ultra_nano, to_verbose, transcode_text)
from vocab import (head_aliases, head_spellings, nano_head,  # noqa: E402
                   nano_option, option_spellings, reserved_widths, type_aliases)

MODULE_ROOT = ROOT / "grammar" / "corpus" / "modules"

# Every aliased form in one module, in canonical Nano: the four heads, the six
# option keywords, the type aliases, and a record whose six keys are spelled
# exactly like the option keywords.
NANO_SRC = '''"This comment mentions :doc, :export and defun and must survive verbatim."
(module t/projection
  :d "Every aliased form, and a record keyed by the six option letters."
  :x [P Tag mk read-back pick]
  :i [(core/strings :a s)])

(dfs P
  (:f x I64 "A field named for the :export alias.")
  (:f d I64 "A field named for the :doc alias.")
  (:f a I64 "A field named for the :as alias.")
  (:f i I64 "A field named for the :import alias.")
  (:f f I64 "A field named for the :field alias.")
  (:f c I64 "A field named for the :case alias."))

(dfe Tag
  (:c lo [] "The low case.")
  (:c hi [(by I64)] "The high case, carrying a magnitude."))

(df mk [] -> P
  :d "Construct the record with the six option letters as keys."
  (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6))

(df read-back [(p P)] -> Str
  :d "Read every field back in declaration order."
  (string-join (list (string-from-int64 (.-x p))
                     (string-from-int64 (.-d p))
                     (string-from-int64 (.-a p))
                     (string-from-int64 (.-i p))
                     (string-from-int64 (.-f p))
                     (string-from-int64 (.-c p)))
               "|"))

(df pick [(t Tag)] -> Str
  :d "A match over the enum."
  (mt t
    ((lo)    (s/upper "lo"))
    ((hi by) (string-from-int64 by))))
'''

VERBOSE_SRC = to_verbose(NANO_SRC)

RECORD_KEYS = "(P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6)"


# ---------- the transcoder ----------

def test_record_keys_survive_both_directions():
    """The six option letters as record keys are ordinary keys, not options."""
    assert RECORD_KEYS in NANO_SRC
    assert RECORD_KEYS in VERBOSE_SRC
    assert RECORD_KEYS in to_ultra_nano(VERBOSE_SRC)
    assert ":export 1" not in VERBOSE_SRC


def test_heads_and_options_are_projected():
    assert "(defschema P" in VERBOSE_SRC
    assert "(defenum Tag" in VERBOSE_SRC
    assert "(defun mk" in VERBOSE_SRC
    assert "(match t" in VERBOSE_SRC
    assert "(:field x Int64" in VERBOSE_SRC
    assert "(:case lo []" in VERBOSE_SRC
    assert ':doc "Every aliased form' in VERBOSE_SRC
    assert ":export [P Tag" in VERBOSE_SRC
    assert ":import [(core/strings :as s)]" in VERBOSE_SRC


def test_nano_verbose_nano_is_byte_stable():
    assert to_ultra_nano(VERBOSE_SRC) == NANO_SRC
    assert to_verbose(NANO_SRC) == VERBOSE_SRC
    assert to_ultra_nano(NANO_SRC) == NANO_SRC
    assert to_verbose(VERBOSE_SRC) == VERBOSE_SRC


def test_comments_and_layout_are_untouched():
    """Only keyword spans move; a transcoder that reflowed would not be reversible."""
    head = NANO_SRC.splitlines()[0]
    assert head in to_verbose(NANO_SRC)
    assert head in to_ultra_nano(VERBOSE_SRC)
    # Docstrings name the aliases in prose and are not code.
    assert "A field named for the :export alias." in to_ultra_nano(VERBOSE_SRC)
    assert len(VERBOSE_SRC.splitlines()) == len(NANO_SRC.splitlines())
    assert VERBOSE_SRC.count("\n\n") == NANO_SRC.count("\n\n")


def test_middle_spellings_project_to_canonical_nano():
    middle = NANO_SRC.replace("(dfs P", "(schema P").replace("(dfe Tag", "(enum Tag")
    assert to_ultra_nano(middle) == NANO_SRC
    assert to_verbose(middle) == VERBOSE_SRC


def test_every_head_spelling_projects_both_ways():
    """The alias table and the rewrite table cannot drift apart unnoticed."""
    for spelling, verbose in head_aliases().items():
        src = _head_module(spelling)
        assert to_verbose(src) == to_verbose(_head_module(verbose))
        assert to_ultra_nano(src) == to_ultra_nano(_head_module(nano_head(verbose)))
        assert f"({verbose} " in to_verbose(src)
        assert f"({nano_head(verbose)} " in to_ultra_nano(src)


def test_every_option_spelling_is_covered_by_the_fixture():
    """The fixture is the pin, so it has to exercise every option keyword."""
    for verbose, spellings in option_spellings().items():
        assert verbose in VERBOSE_SRC, verbose
        assert nano_option(verbose) in NANO_SRC, verbose
        assert set(spellings) == {verbose, nano_option(verbose)}
    assert len(head_spellings()) == 4


_HEAD_MODULES = {
    "defschema": '({head} T\n  (:field v Int64 "v"))\n',
    "defenum": '({head} T\n  (:case only [] "only"))\n',
    "match": '(defun f [(b Bool)] -> Int64\n  :doc "f"\n  ({head} b\n    (true 1)\n    (_ 0)))\n',
    "defun": '({head} f [] -> Int64\n  :doc "f"\n  1)\n',
}


def _head_module(head: str) -> str:
    """A one-declaration module in which `head` is the only aliasable spelling."""
    verbose = head_aliases()[head]
    exported = "T" if verbose in ("defschema", "defenum") else "f"
    body = _HEAD_MODULES[verbose].format(head=head)
    return f'(module t/h\n  :doc "h"\n  :export [{exported}])\n\n{body}'


def test_unparseable_source_is_refused_not_rewritten():
    with pytest.raises(TranscodeError):
        to_verbose("(module t/x :d")


def test_unknown_projection_is_refused():
    with pytest.raises(TranscodeError):
        transcode_text(NANO_SRC, "klingon")


# ---------- the formatter ----------

@pytest.mark.parametrize("src,head", [(NANO_SRC, "(dfs P"), (VERBOSE_SRC, "(defschema P")])
def test_fmt_preserves_the_source_projection(src, head):
    once = fmt.format_source(src, "<test>")
    assert head in once
    assert RECORD_KEYS in once
    assert once == fmt.format_source(once, "<test>")


def test_fmt_keeps_bracketed_options_under_their_nano_spelling():
    once = fmt.format_source(NANO_SRC, "<test>")
    assert ":x [P Tag" in once
    assert ":i [(core/strings :a s)]" in once


def test_asl_fmt_refuses_no_nano_file(tmp_path):
    target = tmp_path / "nano.asl"
    target.write_text(NANO_SRC)
    first = _asl("fmt", str(target))
    assert "0 file(s) refused" in _output(first), _output(first)
    assert first.returncode == 0, _output(first)
    formatted = target.read_text()
    second = _asl("fmt", str(target))
    assert "0 file(s) refused" in _output(second), _output(second)
    assert target.read_text() == formatted


def _asl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(ROOT / "agentscript"), *args],
                          cwd=ROOT, capture_output=True, text=True, timeout=120)


def _output(res: subprocess.CompletedProcess) -> str:
    return res.stdout + res.stderr


# ---------- the interface compressor ----------

def test_compressor_sees_nano_and_keeps_its_projection():
    compressed = compress_module(NANO_SRC)
    assert "(dfs P" in compressed
    assert "(dfe Tag" in compressed
    assert "(df mk [] -> P" in compressed
    assert ":d \"Construct the record" in compressed
    assert "string-join" not in compressed          # bodies are gone
    assert "(read-back p)" in compressed            # the stub is a self-call
    assert "panic" not in compressed


def test_compressed_nano_module_parses_and_checks(tmp_path):
    target = tmp_path / "interface.asl"
    target.write_text(compress_module(NANO_SRC))
    fmt.parse(target.read_text(), str(target))      # raises FormatError if it does not parse
    assert check_file(target, [MODULE_ROOT]) == []


def test_compressed_verbose_module_parses_and_checks(tmp_path):
    target = tmp_path / "interface.asl"
    target.write_text(compress_module(VERBOSE_SRC))
    assert check_file(target, [MODULE_ROOT]) == []


def test_compressor_refuses_unparseable_source():
    with pytest.raises(CompressError):
        compress_module("(defun f [] -> ")


# ---------- the viewer ----------

def test_asl_view_shows_verbose_text_for_a_nano_file(tmp_path):
    target = tmp_path / "nano.asl"
    target.write_text(NANO_SRC)
    res = _asl("view", str(target))
    assert res.returncode == 0, res.stderr
    assert "(defschema P" in res.stdout
    assert "(defun mk" in res.stdout
    assert "(dfs P" not in res.stdout
    assert RECORD_KEYS in res.stdout


def test_asl_view_shows_nano_text_for_a_verbose_file(tmp_path):
    target = tmp_path / "verbose.asl"
    target.write_text(VERBOSE_SRC)
    res = _asl("view", str(target), "--nano")
    assert res.returncode == 0, res.stderr
    assert "(dfs P" in res.stdout
    assert "(defschema P" not in res.stdout


def test_asl_view_does_not_touch_the_file(tmp_path):
    target = tmp_path / "nano.asl"
    target.write_text(NANO_SRC)
    _asl("view", str(target))
    assert target.read_text() == NANO_SRC


# ---------- the language server ----------

def test_lsp_virtual_document_projects_instead_of_echoing():
    from tools.lsp import AslLspServer
    server = AslLspServer()
    uri = "file:///t/projection.asl"
    server.documents[uri] = NANO_SRC
    verbose = server._compute_virtual_document(uri, VERBOSE, "postgres")
    assert "(defschema P" in verbose
    assert RECORD_KEYS in verbose
    assert server._compute_virtual_document(uri, "nano", "postgres") == NANO_SRC


JSON_CASE_SRC = '''(module wire/n
  :d "A record with a header option and a padded field table."
  :x [A])

(dfs A
  :json-case camel
  (:f holder-name String "Name")
  (:f opened-at   Int64  "Epoch seconds")
  (:f nickname    String "Label" :default "unnamed"))
'''


def test_fmt_keeps_a_schema_header_option_out_of_the_field_table():
    """`:json-case` is a header row, not a `:field` row, and neither is aliased."""
    once = fmt.format_source(JSON_CASE_SRC, "<test>")
    assert once == JSON_CASE_SRC
    assert once == fmt.format_source(once, "<test>")
    assert ":json-case camel" in to_verbose(once)
    assert ":json-case camel" in to_ultra_nano(once)


def test_compressor_keeps_a_schema_header_option():
    compressed = compress_module(JSON_CASE_SRC)
    assert ":json-case camel" in compressed
    assert "(:f nickname    String \"Label\" :default \"unnamed\")" in compressed


# ---------- type aliases ----------
# AGENT_SPEC_CORE.md §2.1 puts type aliases in the same table as heads and option
# keywords, so a projection that stops at the heads is only half a projection.

TYPES_NANO = '''(module t/types
  :d "Every kind of type name in a type position."
  :x [S widen])

(dfs S
  (:f a I64 "The default integer.")
  (:f b F64 "The default float.")
  (:f c Str "A string.")
  (:f d Bool "A boolean.")
  (:f e F32 "A reserved width Core has no type for.")
  (:f g (List F64) "A type application.")
  (:f h (Map Str I64) "A two-argument application."))

(df widen [(n I32)] -> I64
  :d "The narrow integer alias, widened."
  (int32-to-int64 n))
'''

TYPES_VERBOSE = to_verbose(TYPES_NANO)


def test_type_aliases_expand_and_tighten():
    assert "(:field a Int64 " in TYPES_VERBOSE
    assert "(:field b Float64 " in TYPES_VERBOSE
    assert "(:field c String " in TYPES_VERBOSE
    assert "(:field g (List Float64) " in TYPES_VERBOSE
    assert "(:field h (Map String Int64) " in TYPES_VERBOSE
    assert "[(n Int32)] -> Int64" in TYPES_VERBOSE
    assert to_ultra_nano(TYPES_VERBOSE) == TYPES_NANO


def test_reserved_widths_survive_both_directions():
    """`F32` names a width Core has no type for; resolving it erases the intent."""
    assert set(reserved_widths()) == {"F32"}
    assert "(:field e F32 " in TYPES_VERBOSE
    assert "(:f e F32 " in to_ultra_nano(TYPES_VERBOSE)


def test_middle_type_spellings_canonicalise():
    """`Int`, `Num` and `Float` are to types what `def` and `schema` are to heads."""
    middle = TYPES_NANO.replace("(:f a I64", "(:f a Int").replace("(:f b F64", "(:f b Num")
    assert to_ultra_nano(middle) == TYPES_NANO
    assert to_verbose(middle) == TYPES_VERBOSE


def test_bound_type_variables_are_never_rewritten():
    """A name is a type variable because it was declared one, not because of its spelling."""
    src = ('(module t/tv\n  :d "d"\n  :x [f])\n\n'
           '(df {Str} f [(x Str)] -> Str\n  :d "identity"\n  x)\n')
    assert to_verbose(src) == src.replace("(df ", "(defun ").replace(":d ", ":doc ", 1) \
        .replace("  :d ", "  :doc ").replace(":x [", ":export [")
    assert "String" not in to_verbose(src)
    assert to_ultra_nano(to_verbose(src)) == src


def test_type_names_outside_type_position_are_untouched():
    """An export entry and a constructor head are not type positions."""
    assert ":export [S widen]" in TYPES_VERBOSE
    assert "(P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6)" in VERBOSE_SRC
    assert "(defschema P" in VERBOSE_SRC          # the declaration's own name


def test_every_type_alias_projects_to_a_core_name():
    """The alias table and the projector cannot drift apart unnoticed."""
    for alias, core in type_aliases().items():
        rendered = to_verbose(_type_module(alias))
        want = alias if alias in reserved_widths() else core
        assert f"(:field v {want} " in rendered, alias
        assert to_ultra_nano(rendered) == to_ultra_nano(_type_module(alias))


def _type_module(name: str) -> str:
    return ('(module t/ty\n  :doc "t"\n  :export [S])\n\n'
            f'(defschema S\n  (:field v {name} "v"))\n')


def test_transcoded_types_still_check(tmp_path):
    for label, text in (("nano", TYPES_NANO), ("verbose", TYPES_VERBOSE)):
        target = tmp_path / f"{label}.asl"
        target.write_text(text)
        assert check_file(target, [MODULE_ROOT]) == [], label


def test_asl_transcode_accepts_the_to_flag(tmp_path):
    target = tmp_path / "nano.asl"
    target.write_text(TYPES_NANO)
    res = _asl("transcode", str(target), "--to", "verbose")
    assert res.returncode == 0, _output(res)
    assert "(defschema S" in res.stdout
    assert "(:field a Int64 " in res.stdout
    assert "(:field e F32 " in res.stdout
