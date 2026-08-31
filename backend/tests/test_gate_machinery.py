"""The gates themselves, tested where their failure is silent.

A gate that reports success it did not establish is worse than a defect, because
it converts every downstream green into a claim nobody checked. Each test here
is one such conversion: a diagnostic that named no probe and left every probe
"admissible", a `zip` that dropped surplus arguments and passed, a panic that
arrived as a JSON decode error, an oracle that never looked at stderr, a
process-global left naming a deleted directory, and cleanup that aborted the run
it was cleaning up after.
"""
import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

BACKEND = Path(__file__).parent.parent
ROOT = BACKEND.parent
sys.path.insert(0, str(BACKEND))
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "grammar"))

import check_corpus as cc  # noqa: E402
import differential as d  # noqa: E402
import exec_coverage as ec  # noqa: E402
import monomorphism as mono  # noqa: E402
from resolve import Diagnostic  # noqa: E402

TWO_PARAM = "(defun add2 [(a Int64) (b Int64)] -> Int64 (+ a b))\n"

TRAPS = ("(defun divzero [(a Int64) (b Int64)] -> Int64 (/ a b))\n"
         "(defun mulover [(a Int64)] -> Int64 (* a a))\n")

QUIET_PROGRAM = """\
(module quiet
  :doc "A program that reads nothing, so its seeded file is untouched."
  :export [main])

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Print one line."
  (println "quiet"))
"""


@pytest.fixture
def source(tmp_path):
    def write(text: str, name: str = "probe.agentscript") -> Path:
        path = tmp_path / name
        path.write_text(text)
        return path
    return write


# --- F1: a diagnostic that maps to no probe -------------------------------


def _diag(line: int) -> Diagnostic:
    return Diagnostic("internal", "the checker raised", line, 0, "probes.agentscript")


@pytest.mark.parametrize("line", [0, 10 ** 6])
def test_a_diagnostic_naming_no_probe_stops_the_sweep(monkeypatch, line):
    """`check_file` answers a parse error or a checker crash with line 0.
    Subtracting the header offset turned that into index -2, which is a valid
    Python index: every probe stayed "admissible" and an unrelated probe was
    reported as narrowed."""
    monkeypatch.setattr(mono, "check_file", lambda path, roots: [_diag(line)])
    with pytest.raises(mono.ProbeMismatch) as exc:
        mono.admissible_set()
    assert "no probe line" in str(exc.value)


def test_the_sweep_does_not_report_a_set_it_did_not_narrow(monkeypatch):
    monkeypatch.setattr(mono, "check_file", lambda path, roots: [_diag(0)])
    monkeypatch.setattr(sys, "argv", ["monomorphism.py", "--quiet"])
    assert mono.main() == 1


def test_a_probe_line_maps_to_its_own_index():
    probes = mono.candidates()[:5]
    by_line = mono.probe_index_by_line(mono.probe_source(probes))
    assert sorted(by_line.values()) == list(range(5))
    src = mono.probe_source(probes).splitlines()
    for line, i in by_line.items():
        assert src[line - 1].startswith(f"(defun probe-{i} ")


def test_a_real_narrowing_still_names_its_own_probe():
    _, narrowed = mono.admissible_set()
    assert narrowed and all(p["codes"] == ["map-key-order"] for p in narrowed)


# --- F2: a panic must arrive as the panic ---------------------------------


def test_a_failing_runner_reports_its_stderr_not_a_decode_error():
    r = subprocess.CompletedProcess(
        args=[], returncode=101, stdout="",
        stderr="thread 'main' panicked at rt.rs:41:23:\ndivision by zero\n"
               "note: run with `RUST_BACKTRACE=1` environment variable\n")
    with pytest.raises(RuntimeError) as exc:
        d.check_run(r, "rust divzero")
    assert "division by zero" in str(exc.value)
    assert "exit 101" in str(exc.value)


def test_a_silent_success_is_not_read_as_a_result():
    r = subprocess.CompletedProcess(args=[], returncode=0, stdout="\n", stderr="")
    with pytest.raises(RuntimeError, match="no output"):
        d.check_run(r, "rust quiet")


@pytest.mark.parametrize("entry,args,expected", [
    ("divzero", [1, 0], "division by zero"),
    ("mulover", [3037000500], "overflow"),
])
def test_a_rust_trap_is_reported_as_the_trap(source, entry, args, expected):
    """A trap leaves stdout empty; `json.loads` on that said `Expecting value:
    line 1 column 1` and threw the panic away."""
    src = source(TRAPS)
    task = {"id": entry, "entry": entry, "cases": [[args, 0]]}
    with pytest.raises(RuntimeError) as exc:
        d.run_rust(src, task)
    assert expected in str(exc.value)
    assert "Expecting value" not in str(exc.value)


# --- F3: arguments and parameters must correspond -------------------------


def test_a_case_with_a_surplus_argument_is_rejected():
    specs = [{"con": "Int64", "args": []}] * 3
    with pytest.raises(RuntimeError, match="declares 3 parameter"):
        d.bind(specs, [1, 2, 3, 99], {"id": "t", "entry": "band"})


def test_a_case_with_a_missing_argument_is_rejected():
    specs = [{"con": "Int64", "args": []}] * 3
    with pytest.raises(RuntimeError, match="declares 3 parameter"):
        d.bind(specs, [1, 2], {"id": "t", "entry": "band"})


def test_a_stale_case_no_longer_runs_to_completion(source):
    """The surplus was dropped and the truncated call returned the expected
    value, so a case left behind by a removed parameter went green."""
    src = source(TWO_PARAM)
    task = {"id": "add2", "entry": "add2", "cases": [[[1, 2, 3], 3]]}
    with pytest.raises(RuntimeError, match="the case supplies 3"):
        d.run_python(src, task)


@pytest.mark.parametrize("results", [1, 3])
def test_results_and_cases_must_correspond_in_length(source, monkeypatch, results):
    """`zip(cases, py)` truncated to the shorter: a backend returning fewer
    results left the remaining cases uncompared and the gate reported zero
    disagreements."""
    src = source(TWO_PARAM)
    task = {"id": "add2", "entry": "add2", "src": src,
            "cases": [[[1, 2], 3], [[2, 3], 5]]}
    monkeypatch.setattr(d, "run_rust", lambda s, t: [3, 5][:results] + [0] * (results - 2))
    with pytest.raises(RuntimeError, match="truncated comparison"):
        d.functions(task)


# --- F4: stderr is part of the oracle -------------------------------------


def test_a_program_case_must_declare_its_stderr():
    src = ROOT / "grammar" / "corpus" / "valid" / "08-io.agentscript"
    with pytest.raises(RuntimeError, match="declares no stderr"):
        d.programs(src, [{"argv": [], "stdout": "", "exit": 0}])


def test_the_failing_write_is_told_apart_from_a_crash():
    """`file-write`'s only executed site fails, and stdout "" with exit 1 is
    also what a crash looks like. The IoError case name on stderr is the whole
    difference, so declaring the wrong one has to fail."""
    src = ROOT / "grammar" / "corpus" / "valid" / "08-io.agentscript"
    case = {"argv": ["sample.txt", "nodir/out.txt"],
            "files": {"sample.txt": ("hello from a file\n", 0o644)},
            "stdout": "", "exit": 1}
    assert d.programs(src, [dict(case, stderr="not-found\n")]) == 0
    assert d.programs(src, [dict(case, stderr="")]) == 1
    assert d.programs(src, [dict(case, stderr="permission-denied\n")]) == 1


def test_every_declared_program_case_names_its_stderr():
    for src, cases in d.program_cases():
        for case in cases:
            assert "stderr" in case, f"{src.name} {case.get('argv')}"


# --- F5: the recorder and the environment are scoped ----------------------

RESTORED = """\
import json, os, sys
sys.path.insert(0, %r)
import exec_coverage as ec
import to_python

before = {"lower": dict(to_python.LOWER),
          "pythonpath": os.environ.get("PYTHONPATH"),
          "coverage": os.environ.get("AGENTSCRIPT_EXEC_COVERAGE")}
ec.check()
after = {"lower": dict(to_python.LOWER),
         "pythonpath": os.environ.get("PYTHONPATH"),
         "coverage": os.environ.get("AGENTSCRIPT_EXEC_COVERAGE")}
emitted = to_python.Transpiler().transpile(%r)
print(json.dumps({"same_lower": before["lower"] == after["lower"],
                  "same_path": before["pythonpath"] == after["pythonpath"],
                  "same_cov": before["coverage"] == after["coverage"],
                  "imports_rec": "_rec" in emitted}))
""" % (str(BACKEND), TWO_PARAM)


def test_tracing_leaves_the_process_as_it_found_it(tmp_path):
    """The recorder's tempdir is on PYTHONPATH and is deleted on the way out, and
    the wrapped transpiler prepends `import _rec`. Left installed, the next
    in-process transpile emits code importing a module that is gone —
    grammar/closure_audit.py imports this module, so an unrelated consumer is one
    reordering away."""
    script = tmp_path / "restored.py"
    script.write_text(RESTORED)
    r = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    got = json.loads(r.stdout)
    assert got == {"same_lower": True, "same_path": True, "same_cov": True,
                   "imports_rec": False}


def test_the_recorder_is_installed_only_inside_its_block():
    import to_python
    before = dict(to_python.LOWER)
    with ec.recorder_installed():
        assert "_rec.hit" in to_python.LOWER["+"]
        assert "import _rec" in to_python.Transpiler().transpile(TWO_PARAM)
    assert dict(to_python.LOWER) == before
    assert "import _rec" not in to_python.Transpiler().transpile(TWO_PARAM)


def test_the_recorder_refuses_to_nest():
    with ec.recorder_installed():
        with pytest.raises(RuntimeError, match="does not nest"):
            with ec.recorder_installed():
                pass
    import to_python
    assert "_rec.hit" not in to_python.LOWER["+"]


def test_a_traced_program_that_does_not_do_what_the_case_says_is_a_failure():
    """Coverage recorded from a run that crashed halfway is coverage of nothing;
    the runner's exit status was discarded entirely."""
    src = ROOT / "grammar" / "corpus" / "valid" / "13-module-program.agentscript"
    with pytest.raises(RuntimeError, match="traced run gave"):
        ec._run_program(src, {"argv": [], "stdout": "not what it prints", "exit": 0})


def test_the_environment_helper_restores_an_absent_name():
    name = "AGENTS_TEST_SCOPED"
    os.environ.pop(name, None)
    with ec._environment(**{name: "x"}):
        assert os.environ[name] == "x"
    assert name not in os.environ


def test_an_executed_site_the_checker_has_no_record_for_is_not_dropped(monkeypatch):
    """The intersection of executed sites with checker records made an absent
    record indistinguishable from a site that ran at no interesting type, and
    the instantiation figures are the sole enforcement of the N-at-both-widths
    rule."""
    src = ROOT / "grammar" / "corpus" / "valid" / "01-basics.agentscript"
    monkeypatch.setattr(ec, "trace",
                        lambda: (set(), {src}, {(str(src), 10 ** 6, 1): "list-sum"}))
    with pytest.raises(RuntimeError, match="no instantiation for"):
        ec.instantiations()


def test_a_variadic_site_without_a_record_is_admitted(monkeypatch):
    """`(list)` has no fixed argument positions to instantiate, so the three
    executed sites the checker reports nothing for are all legitimate."""
    src = ROOT / "grammar" / "corpus" / "valid" / "01-basics.agentscript"
    monkeypatch.setattr(ec, "trace",
                        lambda: (set(), {src}, {(str(src), 10 ** 6, 1): "list"}))
    assert ec.instantiations() == {}
    assert "list" in ec.variadic_builtins()


def test_a_recorded_site_names_its_builtin():
    import re

    import to_python
    with ec.recorder_installed():
        emitted = to_python.Transpiler().transpile(TWO_PARAM)
    assert re.search(r"_rec\.site\(\d+, \d+, '\+'\)", emitted)


# --- F6: cleanup must not abort the run -----------------------------------


def test_a_case_whose_seeded_file_is_gone_does_not_abort_the_gate(source, monkeypatch):
    """The chmod was dead work — each runner's directory is inside the tempdir —
    and a program that removed or renamed its input raised FileNotFoundError
    mid-run, taking every later case with it."""
    src = source(QUIET_PROGRAM, "quiet.agentscript")
    real = subprocess.run

    def run(cmd, *a, **kw):
        r = real(cmd, *a, **kw)
        cwd = kw.get("cwd")
        if cwd and Path(cwd).name.startswith("run-"):
            for f in Path(cwd).iterdir():
                f.unlink()
        return r

    monkeypatch.setattr(subprocess, "run", run)
    case = {"argv": [], "files": {"seed.txt": ("x\n", 0o000)},
            "stdout": "quiet\n", "stderr": "", "exit": 0}
    assert d.programs(src, [case]) == 0


# --- the same class, elsewhere in the gate machinery ----------------------


def test_a_failing_tree_sitter_is_not_read_as_closure(tmp_path, monkeypatch):
    """No output means no undefined head, which the closure gate printed as
    "spec and corpus are closed"."""
    import closure_audit as ca
    fake = tmp_path / "ts"
    fake.write_text("#!/bin/sh\necho 'grammar not built' >&2\nexit 1\n")
    fake.chmod(0o755)
    monkeypatch.setattr(ca, "TS_BIN", fake)
    with pytest.raises(RuntimeError, match="tree-sitter query failed"):
        ca.run_query([ROOT / "grammar" / "corpus" / "valid" / "08-io.agentscript"])


def test_a_query_that_matches_nothing_is_not_read_as_closure(tmp_path, monkeypatch):
    import closure_audit as ca
    fake = tmp_path / "ts"
    fake.write_text("#!/bin/sh\nexit 0\n")
    fake.chmod(0o755)
    monkeypatch.setattr(ca, "TS_BIN", fake)
    with pytest.raises(RuntimeError, match="closure is unmeasured"):
        ca.run_query([ROOT / "grammar" / "corpus" / "valid" / "08-io.agentscript"])


def test_closure_over_no_sources_is_refused():
    import closure_audit as ca
    with pytest.raises(RuntimeError, match="no sources"):
        ca.run_query([])


def test_closure_does_not_claim_every_builtin_executed_when_some_are_unreached(monkeypatch, capsys):
    """The OK line once printed "every builtin is executed" right below its own
    `106/107` and the name of the builtin that never ran. It must only print
    when the executed count actually equals the declared one."""
    import closure_audit as ca
    monkeypatch.setattr(ca, "run_query", lambda paths: (set(), set(), set()))
    monkeypatch.setattr(ca.exec_coverage, "check", lambda: (
        [], {"executed": ["x"], "declared": 2, "pct": 50,
             "unreached": ["string-reverse"]}))
    assert ca.main() == 0
    assert "every builtin is executed" not in capsys.readouterr().out


def test_an_empty_corpus_fails_rather_than_passes(monkeypatch, capsys):
    monkeypatch.setattr(cc, "CORPUS", [])
    assert cc.main() == 1
    assert "would pass by having nothing to do" in capsys.readouterr().out


def test_the_probe_source_is_one_line_per_probe():
    """The whole line-to-probe mapping rests on it, and a probe rendered over two
    lines would shift every index after it."""
    probes = mono.candidates()
    lines = mono.probe_source(probes).splitlines()
    assert len(lines) == len(probes) + len(mono.HEADER.splitlines())
    assert textwrap.dedent(lines[-1]) == lines[-1]
