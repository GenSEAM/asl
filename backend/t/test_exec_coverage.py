"""The coverage tracer, tested where its predecessor could be faked.

A static scan counts a call head in a branch no case takes: a ten-line fixture
whose single case takes the `else` arm moved the previous design's figure by
eleven with nothing executed. The first test here is that exact program.

Every test that traces runs in its own process. Installing the recorder rewrites
`to_python.LOWER` and patches the transpiler, which is correct for a gate that
owns its process and wrong for anything sharing one — including pytest.
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import exec_coverage as ec  # noqa: E402

BACKEND = Path(__file__).parent.parent

DEAD_BRANCH = """\
(defun dead [(n Int64)] -> Int64
  (if (< n 0)
    (list-length (string-chars (string-lower (string-upper "x"))))
    n))
"""

# Installs the recorder, transpiles one probe, runs one call, prints what fired.
PROBE = """\
import json, os, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, %r)
import exec_coverage as ec

source, call = sys.argv[1], sys.argv[2]
d = Path(tempfile.mkdtemp())
src = d / "probe.agents"
src.write_text(source)
hits = d / "hits.txt"
hits.write_text("")
(d / "_rec.py").write_text(ec.RECORDER)
(d / "runtime.py").write_text((ec.ROOT / "backend" / "runtime.py").read_text())
with ec.recorder_installed():
    (d / "cand.py").write_text(ec._transpile(src))
(d / "drv.py").write_text("import cand\\ncand." + call + "\\n")
env = dict(os.environ, AGENTS_EXEC_COVERAGE=str(hits),
           AGENTS_EXEC_SOURCE=str(src), PYTHONPATH=str(d))
r = subprocess.run([sys.executable, str(d / "drv.py")], cwd=d, env=env,
                   capture_output=True, text=True)
assert r.returncode == 0, r.stderr
print(json.dumps(sorted(line.partition("\\t")[2]
                        for line in hits.read_text().splitlines()
                        if line.startswith("name\\t"))))
""" % str(BACKEND)


def _record(tmp_path, source: str, call: str) -> set[str]:
    script = tmp_path / "probe.py"
    script.write_text(PROBE)
    r = subprocess.run([sys.executable, str(script), source, call],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return set(json.loads(r.stdout))


def test_a_builtin_in_an_untaken_branch_is_not_recorded(tmp_path):
    recorded = _record(tmp_path, DEAD_BRANCH, "dead(1)")
    assert "<" in recorded
    assert {"list-length", "string-chars", "string-lower", "string-upper"} & recorded == set()


def test_the_same_builtins_are_recorded_when_the_branch_is_taken(tmp_path):
    recorded = _record(tmp_path, DEAD_BRANCH, "dead(-1)")
    assert {"list-length", "string-chars", "string-lower", "string-upper"} <= recorded


def test_every_builtin_declared_over_N_is_identified():
    numeric = ec.numeric_builtins()
    assert {"/", "mod", "min", "max", "list-sum", "checked-div"} <= numeric
    assert "string-upper" not in numeric


def _gate(lock: Path | None = None) -> subprocess.CompletedProcess:
    env = None
    if lock is not None:
        import os
        env = dict(os.environ, AGENTS_COVERAGE_LOCK=str(lock))
    return subprocess.run([sys.executable, str(BACKEND / "exec_coverage.py")],
                          capture_output=True, text=True, env=env)


def test_the_checked_in_lock_is_in_sync():
    r = _gate()
    assert r.returncode == 0, r.stdout
    assert "107/107" in r.stdout


def test_an_instantiation_the_executed_sites_never_reached_fails_the_gate(tmp_path):
    lock = json.loads((ec.ROOT / "prelude" / "coverage.lock").read_text())
    lock["instantiations"]["string-upper"] = ["Float64", "Int64"]
    forged = tmp_path / "coverage.lock"
    forged.write_text(json.dumps(lock))
    r = _gate(forged)
    assert r.returncode != 0
    assert "instantiations[string-upper]" in r.stdout


# --- forged locks for the new gate conditions -----------------------------

import monomorphism as mono  # noqa: E402


def _forged_lock(tmp_path, patch=None, instantiations=None) -> Path:
    base = json.loads((ec.ROOT / "prelude" / "coverage.lock").read_text())
    for key, value in (patch or {}).items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key].update(value)
        else:
            base[key] = value
    if instantiations is not None:
        base["instantiations"] = instantiations
    path = tmp_path / "coverage.lock"
    path.write_text(json.dumps(base))
    return path


def _check_forged(tmp_path, monkeypatch, *, lock_patch=None, instantiations=None,
                  numeric=(), covered=None):
    """ec.check() with the tracer, tier-A sweep and numeric set stubbed, so one
    condition is exercised at a time against a forged lock."""
    if instantiations is None:
        instantiations = json.loads(
            (ec.ROOT / "prelude" / "coverage.lock").read_text())["instantiations"]
    forged = _forged_lock(tmp_path, lock_patch, instantiations)
    monkeypatch.setattr(ec, "LOCK", forged)
    executed = sorted(ec.declared_builtins())
    if covered is None:
        covered = {str(p.relative_to(ec.ROOT))
                   for p in (ec.ROOT / "grammar" / "corpus" / "valid").glob("*.agents")}
    monkeypatch.setattr(ec, "stats", lambda: {
        "executed": executed,
        "unreached": [],
        "declared": len(executed),
        "pct": 100 * len(executed) // max(len(executed), 1),
        "covered": covered,
    })
    monkeypatch.setattr(ec, "instantiations", lambda: instantiations)
    monkeypatch.setattr(ec, "numeric_builtins", lambda: set(numeric))
    monkeypatch.setattr(mono, "tier_a_summary", lambda: {})
    monkeypatch.setattr(mono, "check_lock", lambda summary: [])
    return ec.check()


def test_an_unexecuted_reason_without_a_pcp_id_fails(tmp_path, monkeypatch):
    victim = "01-basics.agents"
    covered = {str(p.relative_to(ec.ROOT))
               for p in (ec.ROOT / "grammar" / "corpus" / "valid").glob("*.agents")}
    covered.remove(f"grammar/corpus/valid/{victim}")
    failures, _ = _check_forged(
        tmp_path, monkeypatch,
        lock_patch={"unexecuted": {victim: "not executed"}},
        covered=covered)
    assert any("names no PCP id" in f for f in failures)


def test_an_unexecuted_reason_with_a_pcp_id_is_admitted(tmp_path, monkeypatch):
    victim = "01-basics.agents"
    covered = {str(p.relative_to(ec.ROOT))
               for p in (ec.ROOT / "grammar" / "corpus" / "valid").glob("*.agents")}
    covered.remove(f"grammar/corpus/valid/{victim}")
    failures, _ = _check_forged(
        tmp_path, monkeypatch,
        lock_patch={"unexecuted": {victim: "PCP c-15f3: parked deliberately"}},
        covered=covered)
    assert failures == []


def test_write_refuses_a_lower_count_without_allow_regression(tmp_path, monkeypatch, capsys):
    forged = tmp_path / "coverage.lock"
    forged.write_text(json.dumps({"executed": 107}))
    monkeypatch.setattr(ec, "LOCK", forged)
    monkeypatch.setattr(ec, "build_lock", lambda: {"executed": 106})
    monkeypatch.setattr(sys, "argv", ["exec_coverage.py", "--write"])
    assert ec.main() == 1
    assert json.loads(forged.read_text())["executed"] == 107
    assert "refusing to write" in capsys.readouterr().out


def test_write_accepts_a_lower_count_with_allow_regression(tmp_path, monkeypatch):
    forged = tmp_path / "coverage.lock"
    forged.write_text(json.dumps({"executed": 107}))
    monkeypatch.setattr(ec, "LOCK", forged)
    monkeypatch.setattr(ec, "build_lock", lambda: {"executed": 106})
    monkeypatch.setattr(sys, "argv", ["exec_coverage.py", "--write", "--allow-regression"])
    assert ec.main() == 0
    assert json.loads(forged.read_text())["executed"] == 106


def test_an_unproven_builtin_that_acquires_a_user_type_fails(tmp_path, monkeypatch):
    base = json.loads((ec.ROOT / "prelude" / "coverage.lock").read_text())
    instantiations = dict(base["instantiations"])
    instantiations["list-sort"] = ["(List Color)"]
    failures, _ = _check_forged(tmp_path, monkeypatch, instantiations=instantiations)
    assert any("list-sort" in f and "user-defined type" in f for f in failures)


def test_list_sort_at_a_primitive_type_stays_unproven(tmp_path, monkeypatch):
    failures, _ = _check_forged(tmp_path, monkeypatch)
    assert failures == []


def test_the_N_domain_rule_is_exact_not_substring(tmp_path, monkeypatch):
    base = json.loads((ec.ROOT / "prelude" / "coverage.lock").read_text())
    instantiations = dict(base["instantiations"])
    instantiations["+"] = ["(List Float64)", "Int64"]
    failures, _ = _check_forged(tmp_path, monkeypatch,
                                instantiations=instantiations, numeric=["+"])
    assert any("reaches Float64" in f and "reaches Int64" not in f for f in failures)


def test_the_N_domain_rule_covers_N_nested_in_a_List(tmp_path, monkeypatch):
    """`list-sum` is `(List N) -> N`, so its executed strings are `(List Int64)`
    and `(List Float64)`. Exact matching must render the N inside the List, not
    demand a bare `Int64`/`Float64` that this signature never produces."""
    failures, _ = _check_forged(tmp_path, monkeypatch, numeric=["list-sum"])
    assert not any("list-sum" in f for f in failures)


def test_build_lock_preserves_the_note(tmp_path, monkeypatch):
    forged = tmp_path / "coverage.lock"
    forged.write_text(json.dumps({"note": "the caveat"}))
    monkeypatch.setattr(ec, "LOCK", forged)
    monkeypatch.setattr(ec, "stats", lambda: {"executed": []})
    monkeypatch.setattr(ec, "instantiations", lambda: {})
    monkeypatch.setattr(mono, "tier_a_summary", lambda: {})
    lock = ec.build_lock()
    assert lock["note"] == "the caveat"
