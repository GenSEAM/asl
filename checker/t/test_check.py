"""Each §9 rule the checker claims, exercised on a program that breaks it.

Two directions matter equally. A rule that never fires is a rule that is not
enforced, and a rule that fires on valid code is worse than no rule at all —
`grammar/corpus/valid` and `examples/` must stay silent, because those are the
programs the handbook teaches an agent to write.
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent.parent
CHECK = ROOT / "checker" / "check.py"
SEMANTIC = ROOT / "grammar" / "corpus" / "semantic"


def run(*paths) -> list[dict]:
    import json
    r = subprocess.run([sys.executable, str(CHECK), "--json", *[str(p) for p in paths]],
                       capture_output=True, text=True)
    return json.loads(r.stdout)


def check_src(tmp_path, src: str) -> list[dict]:
    f = tmp_path / "m.as"
    f.write_text(src)
    return run(f)


def rules(diags) -> set:
    return {d["rule"] for d in diags}


# ---------- the corpus, both directions ----------

def test_valid_corpus_and_examples_are_silent():
    diags = run(ROOT / "grammar" / "corpus" / "valid", ROOT / "examples")
    assert diags == [], f"false positives on valid code: {diags}"


@pytest.mark.parametrize("fixture,rule", [
    ("effect-undeclared.as", 12),
    ("exported-without-doc.as", 8),
    ("extern-without-target.as", 13),
    ("foreign-result-ignored.as", 5),
    ("opaque-inspected.as", 14),
    ("reserved-prefix.as", 7),
    ("try-outside-result.as", 5),
    ("two-entry-points.as", 15),
    ("unbound-typevar.as", 10),
])
def test_each_semantic_fixture_is_caught_by_its_own_rule(fixture, rule):
    # The rule number matters, not just the count: a fixture caught by the wrong
    # rule is a test passing for the wrong reason.
    assert rule in rules(run(SEMANTIC / fixture))


def test_every_semantic_fixture_is_caught_by_something():
    for f in sorted(SEMANTIC.glob("*.as")):
        assert run(f), f"{f.name} is a semantic fixture that nothing rejects"


# ---------- rules with no fixture of their own ----------

HEAD = '(module t/m\n  :doc "d"\n  :export [])\n'

ENUM = HEAD + '''
(defenum Shape
  (:case circle [(r Float64)] "A circle")
  (:case point  []            "A point"))
'''


def test_match_missing_an_enum_case(tmp_path):
    d = check_src(tmp_path, ENUM + '''
(defun area [(sh Shape)] -> Float64
  :doc "d"
  (match sh ((circle r) r)))
''')
    assert 4 in rules(d) and "point" in d[0]["message"]


def test_match_missing_none(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun peek [(o (Option Int64))] -> Int64
  :doc "d"
  (match o ((some n) n)))
''')
    assert 4 in rules(d)


def test_a_catch_all_makes_a_match_total(tmp_path):
    assert check_src(tmp_path, ENUM + '''
(defun area [(sh Shape)] -> Float64
  :doc "d"
  (match sh ((circle r) r) (_ 0.0)))
''') == []


def test_import_cycle(tmp_path):
    (tmp_path / "a.as").write_text(
        '(module app/a\n  :doc "d"\n  :export [f]\n  :import [(app/b :as b)])\n'
        '(defun f [(x Int64)] -> Int64\n  :doc "d"\n  (b/g x))\n')
    (tmp_path / "b.as").write_text(
        '(module app/b\n  :doc "d"\n  :export [g]\n  :import [(app/a :as a)])\n'
        '(defun g [(x Int64)] -> Int64\n  :doc "d"\n  (a/f x))\n')
    assert 11 in rules(run(tmp_path))


def test_unbound_alias(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(x String)] -> String
  :doc "d"
  (s/upper x))
''')
    assert 9 in rules(d)


def test_undefined_name(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(x Int64)] -> Int64
  :doc "d"
  (nope x))
''')
    assert 2 in rules(d)


def test_a_let_binding_is_in_scope_afterwards(tmp_path):
    assert check_src(tmp_path, HEAD + '''
(defun f [(x Int64)] -> Int64
  :doc "d"
  (let [(y (+ x 1))] (* y 2)))
''') == []


def test_effects_are_transitive(tmp_path):
    # The wrapper declares nothing and calls nothing effectful directly; a rule
    # that stopped at direct calls would be satisfied by exactly this shape.
    d = check_src(tmp_path, HEAD + '''
(defun inner [(p String)] -> (Result String String)
  :doc "d"
  :effects [fs]
  (file-read p))

(defun outer [(p String)] -> (Result String String)
  :doc "d"
  (inner p))
''')
    assert 12 in rules(d)
    assert any("outer" in x["message"] and "`fs`" in x["message"] for x in d)


def test_declaring_the_effect_satisfies_the_rule(tmp_path):
    assert check_src(tmp_path, HEAD + '''
(defun inner [(p String)] -> (Result String String)
  :doc "d"
  :effects [fs]
  (file-read p))

(defun outer [(p String)] -> (Result String String)
  :doc "d"
  :effects [fs]
  (inner p))
''') == []


def test_the_wrong_effect_does_not_satisfy_the_rule(tmp_path):
    # Declaring *an* effect is not declaring *the* effect; a coarse name would
    # have passed here, which is why the vocabulary is per-capability.
    d = check_src(tmp_path, HEAD + '''
(defun f [(p String)] -> (Result String String)
  :doc "d"
  :effects [console]
  (file-read p))
''')
    assert 12 in rules(d) and "`fs`" in d[0]["message"]


def test_an_effect_name_outside_the_vocabulary_is_rejected(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(p String)] -> (Result String String)
  :doc "d"
  :effects [io]
  (file-read p))
''')
    assert 12 in rules(d)
    assert any("not one of" in x["message"] for x in d)


def test_module_without_doc(tmp_path):
    d = check_src(tmp_path, '(module t/m\n  :export [])\n')
    assert 8 in rules(d)


# ---------- the contract ----------

def test_json_shape_is_the_one_contract():
    d = run(SEMANTIC / "reserved-prefix.as")
    assert d and set(d[0]) == {"file", "line", "col", "rule", "message"}
    assert isinstance(d[0]["line"], int) and isinstance(d[0]["rule"], int)


def test_exit_code_is_the_diagnostic_count():
    r = subprocess.run([sys.executable, str(CHECK), str(SEMANTIC / "reserved-prefix.as")],
                       capture_output=True, text=True)
    assert r.returncode == len(run(SEMANTIC / "reserved-prefix.as")) > 0


def test_rules_command_lists_what_is_not_checked():
    r = subprocess.run([sys.executable, str(CHECK), "--rules"], capture_output=True, text=True)
    assert r.returncode == 0
    assert "NOT CHECKED" in r.stdout and "type inference" in r.stdout
