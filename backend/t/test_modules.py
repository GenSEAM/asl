"""Cross-module linking: resolution, ordering, naming and the failure modes.

None of this existed until now — `imports` was read only by the checker, so
`06-module.as` named `core/strings` for two versions while no such file did, and
every backend skipped the fixture rather than fail on it.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))

MULTI = ROOT / "grammar" / "corpus" / "valid" / "06-module.as"
ALIASES = ROOT / "grammar" / "corpus" / "valid" / "09-aliases.as"


def test_imports_resolve_and_dependencies_come_first():
    import modules
    prog = modules.load(MULTI)
    assert [m.path for m in prog.modules] == ["core/strings", "text/casing"]
    assert prog.entry.path == "text/casing"
    assert prog.entry.is_entry and not prog.modules[0].is_entry


def test_only_imported_modules_are_prefixed():
    # The entry module's names are the program's own surface; prefixing them
    # would rename every function the tests and the harness call by name.
    import modules
    prog = modules.load(MULTI)
    assert prog.entry.prefix() == ""
    assert prog.modules[0].prefix() == "core/strings/"


def test_an_unresolvable_import_names_what_it_could_not_find(tmp_path):
    import modules
    f = tmp_path / "m.as"
    f.write_text('(module app/m\n  :doc "d"\n  :export []\n  :import [(no/such :as n)])\n')
    with pytest.raises(modules.ModuleError) as exc:
        modules.load(f)
    assert "no/such" in str(exc.value)


def test_two_files_declaring_one_module_is_an_error(tmp_path):
    import modules
    for name in ("a.as", "b.as"):
        (tmp_path / name).write_text('(module dup/mod\n  :doc "d"\n  :export [])\n')
    with pytest.raises(modules.ModuleError) as exc:
        modules.index([tmp_path])
    assert "dup/mod" in str(exc.value)


def test_an_import_cycle_is_refused(tmp_path):
    import modules
    (tmp_path / "a.as").write_text(
        '(module cyc/a\n  :doc "d"\n  :export [f]\n  :import [(cyc/b :as b)])\n'
        '(defun f [(x Int64)] -> Int64\n  :doc "d"\n  (b/g x))\n')
    (tmp_path / "b.as").write_text(
        '(module cyc/b\n  :doc "d"\n  :export [g]\n  :import [(cyc/a :as a)])\n'
        '(defun g [(x Int64)] -> Int64\n  :doc "d"\n  (a/f x))\n')
    with pytest.raises(modules.ModuleError) as exc:
        modules.load(tmp_path / "a.as")
    assert "cycle" in str(exc.value)


def test_a_file_declaring_a_different_module_than_it_is_imported_as(tmp_path):
    import modules
    (tmp_path / "dep.as").write_text('(module real/name\n  :doc "d"\n  :export [])\n')
    (tmp_path / "m.as").write_text(
        '(module app/m\n  :doc "d"\n  :export []\n  :import [(real/name :as r)])\n')
    prog = modules.load(tmp_path / "m.as")     # resolves: the header is the index key
    assert [m.path for m in prog.modules] == ["real/name", "app/m"]


@pytest.mark.parametrize("backend,expect", [
    ("to_python", ["core_strings_show", "core_numbers_show"]),
    ("to_rust", ["core_strings_show", "core_numbers_show"]),
    ("to_swift", ["coreStringsShow", "coreNumbersShow"]),
    ("to_typescript", ["coreStringsShow", "coreNumbersShow"]),
])
def test_the_same_alias_in_two_modules_does_not_collide(backend, expect):
    # `app/labels` binds `s` to core/strings; `text/format` binds `s` to
    # core/numbers. Both call `s/show`. Mangling through the alias produced one
    # name for two functions, silently.
    r = subprocess.run([sys.executable, str(ROOT / "backend" / f"{backend}.py"), str(ALIASES)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    for name in expect:
        assert name in r.stdout


def test_a_name_collision_is_an_error_not_a_silent_rename(tmp_path):
    # §8 requires the compiler to error when two identifiers mangle alike.
    # Module `core/strings` member `concat` and module `core` member
    # `strings-concat` both flatten to `core_strings_concat`.
    import modules
    src_a = ('(module core/strings\n  :doc "d"\n  :export [concat])\n'
             '(defun concat [] -> Int64\n  :doc "d"\n  1)\n')
    src_b = ('(module core\n  :doc "d"\n  :export [strings-concat])\n'
             '(defun strings-concat [] -> Int64\n  :doc "d"\n  2)\n')
    p = modules.parser()
    mods = []
    for name, src in (("a.as", src_a), ("b.as", src_b)):
        f = tmp_path / name
        f.write_text(src)
        tops = [t.children[0] for t in p.parse(src).children]
        path, exports, imports = modules._header(tops)
        mods.append(modules.Loaded(path, f, tops, exports, imports, is_entry=False))
    with pytest.raises(modules.ModuleError) as exc:
        modules.check_collisions(mods)
    assert "mangle" in str(exc.value) and "core_strings_concat" in str(exc.value)


def test_the_transpiled_multi_module_program_runs():
    from to_python import Transpiler
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)
        (p / "runtime.py").write_text((ROOT / "backend" / "runtime.py").read_text())
        (p / "m.py").write_text(Transpiler().transpile_file(MULTI))
        r = subprocess.run([sys.executable, "-c",
                            "import m; print(m.shout('hi'))"], cwd=d,
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        assert r.stdout.strip() == "HI!"     # via core/strings, across the boundary


def test_a_record_two_modules_declare_is_refused_not_silently_merged(tmp_path):
    # Record types and enum cases have no qualified spelling, so every backend
    # emits them unprefixed. Two `Point`s produced one definition twice: the
    # typed backends rejected the redefinition and the Python backend kept the
    # last one, so the other module's constructor failed at run time.
    import modules
    (tmp_path / "dep.as").write_text(
        '(module dep/geom\n  :doc "d"\n  :export [origin])\n'
        '(defschema Point\n  (:field x Int64 "x")\n  (:field y Int64 "y"))\n'
        '(defun origin [] -> Point\n  :doc "d"\n  (Point :x 0 :y 0))\n')
    f = tmp_path / "m.as"
    f.write_text(
        '(module app/m\n  :doc "d"\n  :export [go]\n  :import [(dep/geom :as g)])\n'
        '(defschema Point\n  (:field lat Float64 "lat")\n  (:field lon Float64 "lon"))\n'
        '(defun go [] -> Point\n  :doc "d"\n  (Point :lat 1.0 :lon 2.0))\n')
    with pytest.raises(modules.ModuleError) as exc:
        modules.load(f)
    assert "Point" in str(exc.value)


def test_an_enum_case_two_modules_declare_is_refused(tmp_path):
    import modules
    (tmp_path / "dep.as").write_text(
        '(module dep/shape\n  :doc "d"\n  :export [name-of])\n'
        '(defenum Shape\n  (:case circle [(r Int64)] "a circle"))\n'
        '(defun name-of [(s Shape)] -> String\n  :doc "d"\n'
        '  (match s\n    ((circle r) "circle")))\n')
    f = tmp_path / "m.as"
    f.write_text(
        '(module app/m\n  :doc "d"\n  :export [go]\n  :import [(dep/shape :as s)])\n'
        '(defenum Marker\n  (:case circle [(a String) (b String)] "another circle"))\n'
        '(defun go [] -> Marker\n  :doc "d"\n  (circle "a" "b"))\n')
    with pytest.raises(modules.ModuleError) as exc:
        modules.load(f)
    assert "circle" in str(exc.value)
