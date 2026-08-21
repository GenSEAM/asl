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


def test_rules_command_states_what_it_does_not_decide():
    # The honest half matters more than the list: the type layer fails open, and
    # a clean report must not be read as proof of well-typedness.
    r = subprocess.run([sys.executable, str(CHECK), "--rules"], capture_output=True, text=True)
    assert r.returncode == 0
    assert "NOT CHECKED" in r.stdout
    assert "FAIL OPEN" in r.stdout
    assert "not proof" in r.stdout
    for rule in (3, 6):
        assert f" {rule}. " in r.stdout.split("NOT CHECKED")[0]   # now decided


# ---------- the type layer (rules 3 and 6) ----------

def test_mixing_numeric_types_is_rule_6(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun total [(count Int64) (rate Float64)] -> Float64
  :doc "d"
  (+ count rate))
''')
    assert 6 in rules(d)
    msg = next(x["message"] for x in d if x["rule"] == 6)
    # The message has to name the mix, not just the symptom at one operand.
    assert "Int64" in msg and "Float64" in msg


def test_an_explicit_conversion_is_accepted(tmp_path):
    assert check_src(tmp_path, HEAD + '''
(defun total [(count Int64) (rate Float64)] -> Float64
  :doc "d"
  (+ (int64-to-float64 count) rate))
''') == []


def test_a_non_numeric_operand_is_not_called_a_numeric_mix(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(s String)] -> Int64
  :doc "d"
  (+ s 1))
''')
    assert d and 6 not in rules(d)      # a String is not a number being mixed


def test_wrong_argument_type(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun size [(n Int64)] -> Int64
  :doc "d"
  (string-length n))
''')
    assert 3 in rules(d) and "String" in d[0]["message"]


def test_wrong_arity(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun parts [(s String)] -> (List String)
  :doc "d"
  (string-split s))
''')
    assert 3 in rules(d) and "argument" in d[0]["message"]


def test_return_type_must_match_the_body(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun label [(n Int64)] -> String
  :doc "d"
  n)
''')
    assert 3 in rules(d)


def test_if_branches_must_agree(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(b Bool)] -> Int64
  :doc "d"
  (if b 1 "two"))
''')
    assert 3 in rules(d) and "disagree" in " ".join(x["message"] for x in d)


def test_an_if_condition_must_be_bool(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defun f [(n Int64)] -> Int64
  :doc "d"
  (if n 1 2))
''')
    assert 3 in rules(d)


def test_unknown_record_field(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defschema Point
  (:field x Int64 "d"))
(defun f [(p Point)] -> Int64
  :doc "d"
  (.-y p))
''')
    assert 3 in rules(d) and "`y`" in d[0]["message"]


def test_constructing_a_record_with_the_wrong_field_type(tmp_path):
    d = check_src(tmp_path, HEAD + '''
(defschema Point
  (:field x Int64 "d"))
(defun f [] -> Point
  :doc "d"
  (Point :x "origin"))
''')
    assert 3 in rules(d)


def test_generics_unify_per_call_site(tmp_path):
    # Two calls to one generic function must not share its type variable.
    assert check_src(tmp_path, HEAD + '''
(defun {A B} swap [(p (Pair A B))] -> (Pair B A)
  :doc "d"
  (pair (.-second p) (.-first p)))

(defun use-both [] -> String
  :doc "d"
  (let [(a (swap (pair 1 "x")))
        (b (swap (pair true 2.0)))]
    (.-first a)))
''') == []


def test_try_unwraps_the_result(tmp_path):
    assert check_src(tmp_path, HEAD + '''
(defun f [(s String)] -> (Result Int64 String)
  :doc "d"
  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]
    (ok (+ n 1))))
''') == []


def test_the_type_layer_fails_open_rather_than_guessing(tmp_path):
    # An opaque host value has no structure this layer models; it must stay
    # silent rather than invent a mismatch.
    assert check_src(tmp_path, '(module t/m\n  :doc "d"\n  :export []\n'
                                '  :extern [(py "x" :as x)])\n'
                                '(defopaque Thing\n  :doc "d")\n'
                                '(defextern x/make [] -> Thing\n  :doc "d"\n  :target :py)\n'
                                '(defun f [] -> (Result Thing String)\n  :doc "d"\n'
                                '  (x/make))\n') == []


def test_one_generic_record_does_not_fix_another_declaration_s_type(tmp_path):
    # The type layer spells every declaration's `{T}` as the same variable, so a
    # substitution carried between declarations made the second reader of a
    # generic record inherit the first one's instantiation.
    assert check_src(tmp_path, HEAD + '''
(defschema {T} Box
  (:field value T "the boxed value"))

(defun unbox-int [(b (Box Int64))] -> Int64
  :doc "d"
  (.-value b))

(defun unbox-str [(b (Box String))] -> String
  :doc "d"
  (.-value b))
''') == []


def test_a_record_name_two_modules_declare_is_declined_not_guessed(tmp_path):
    # `TYPE_NAME` cannot be qualified, so nothing in the source distinguishes the
    # two `Point`s. Resolving against the module being checked reported the
    # imported record's real field as missing.
    (tmp_path / "dep.as").write_text(
        '(module dep/geom\n  :doc "d"\n  :export [origin])\n'
        '(defschema Point\n  (:field x Int64 "x")\n  (:field y Int64 "y"))\n'
        '(defun origin [] -> Point\n  :doc "d"\n  (Point :x 0 :y 0))\n')
    f = tmp_path / "m.as"
    f.write_text(
        '(module app/m\n  :doc "d"\n  :export [go]\n  :import [(dep/geom :as g)])\n'
        '(defschema Point\n  (:field lat Float64 "lat")\n  (:field lon Float64 "lon"))\n'
        '(defun go [] -> Int64\n  :doc "d"\n  (.-x (g/origin)))\n')
    assert run(f) == []


def test_two_directories_importing_one_module_path_do_not_share_a_surface(tmp_path):
    # A module path resolves relative to the importing file's own directory, so
    # the two `shared/thing`s below are different modules. A cache keyed on the
    # path alone let the first answer for the second.
    for d, member in (("a", "helper"), ("b", "other")):
        sub = tmp_path / d
        sub.mkdir()
        (sub / "dep.as").write_text(
            f'(module shared/thing\n  :doc "d"\n  :export [{member}])\n'
            f'(defun {member} [] -> Int64\n  :doc "d"\n  1)\n')
        (sub / "main.as").write_text(
            f'(module app/{d}\n  :doc "d"\n  :export [go]\n'
            f'  :import [(shared/thing :as t)])\n'
            f'(defun go [] -> Int64\n  :doc "d"\n  (t/{member}))\n')
    assert run(tmp_path / "a" / "main.as", tmp_path / "b" / "main.as") == []


def test_an_entry_point_that_takes_no_argv_is_refused(tmp_path):
    # §4.5 fixes the signature and every backend lowers it to a shim that passes
    # the host's argument vector, so any other shape produced a program that
    # could not start.
    diags = check_src(tmp_path, HEAD + '''
(defentry [] -> (Result Unit String)
  :doc "d"
  (ok unit))
''')
    assert 15 in rules(diags), diags


def test_an_entry_point_taking_the_wrong_type_is_refused(tmp_path):
    diags = check_src(tmp_path, HEAD + '''
(defentry [(argv String)] -> (Result Unit String)
  :doc "d"
  (ok unit))
''')
    assert 15 in rules(diags), diags


def test_a_malformed_module_graph_is_a_diagnostic_not_a_traceback(tmp_path):
    # Two files declaring one module path made `modules.index` raise from inside
    # whichever rule touched it first, and the raise escaped the checker.
    for name in ("a.as", "b.as"):
        (tmp_path / name).write_text('(module dup/mod\n  :doc "d"\n  :export [])\n')
    f = tmp_path / "m.as"
    f.write_text('(module app/m\n  :doc "d"\n  :export []\n'
                 '  :import [(dup/mod :as d)])\n'
                 '(defun go [] -> Int64\n  :doc "d"\n  1)\n')
    diags = run(f)
    assert diags and "dup/mod" in diags[0]["message"]


def test_a_lambda_inside_the_entry_point_is_not_its_parameter(tmp_path):
    # The entry-point signature is read off the declaration's own `params`; a
    # walk of the whole node counts a nested `fn`'s parameters too.
    assert check_src(tmp_path, HEAD + '''
(defentry [(argv (List String))] -> (Result Unit String)
  :doc "d"
  :effects [console]
  (let [(f (fn [(x Int64)] -> Int64 (+ x 1)))]
    (println (string-from-int64 (f 1)))))
''') == []
