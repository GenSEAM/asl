"""The Tier-A sweep, tested where its failure would be silent.

A gate no test can make fail is not a gate. The two ways this one could report
success while covering less are: a runtime helper narrowed back to one concrete
type (the `list-sum` defect, which shipped), and the probe domain shrunk so the
instantiation that fails is never generated. Both are asserted to fail here.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import monomorphism as mono  # noqa: E402


def test_every_builtin_is_probed_or_excluded_with_a_reason():
    excluded, probed = mono.classify()
    total = len(probed) + sum(len(names) for names in excluded.values())
    assert total == len(mono.PRELUDE["builtins"])


def test_a_remonomorphised_sum_is_named_by_the_sweep(monkeypatch):
    generic = "pub fn sum<T: Num>(xs: Vec<T>) -> T { xs.into_iter().fold(T::ZERO, Num::plus) }"
    narrowed = "pub fn sum(xs: Vec<i64>) -> i64 { xs.iter().sum() }"
    src = mono.runtime_source()
    assert generic in src
    monkeypatch.setattr(mono, "runtime_source", lambda: src.replace(generic, narrowed))

    probes = [p for p in mono.candidates() if p["builtin"] == "list-sum"]
    reported = mono.guilty(probes)
    assert [r for r in reported if r.startswith("list-sum [N=Float64]")]
    assert [r for r in reported if r.startswith("list-sum [N=Int32]")]


def test_shrinking_the_numeric_domain_fails_the_lock_rather_than_the_count(monkeypatch):
    monkeypatch.setitem(mono.DOMAINS, "N", ["Int32", "Int64"])
    problems = mono.check_lock(mono.tier_a_summary())
    assert any("tier_a.domains" in p for p in problems)
    assert any("tier_a.probes" in p and "<" in p for p in problems)


def test_the_checked_in_lock_matches_the_sweep():
    problems = mono.check_lock(mono.tier_a_summary())
    # `narrowed` is migrating from a bare count to a label list; until the lock
    # is regenerated it is the one field allowed to disagree.
    assert all("tier_a.narrowed" in p for p in problems)


def test_narrowed_is_labels_not_a_count(monkeypatch):
    narrowed = mono.tier_a_summary()["narrowed"]
    assert isinstance(narrowed, list)
    assert narrowed == sorted(narrowed)
    assert narrowed and all(isinstance(x, str) for x in narrowed)

    # Swapping one narrowed probe for another keeps the length at 1 but must
    # change the recorded label list, or the lock would miss the swap.
    a = {"builtin": "map-size", "subst": {"K": "Float64", "V": "Int64"},
         "codes": ["map-key-order"]}
    b = {"builtin": "map-remove", "subst": {"K": "Float64", "V": "Int64"},
         "codes": ["map-key-order"]}
    monkeypatch.setattr(mono, "admissible_set", lambda: ([], [a]))
    assert mono.tier_a_summary()["narrowed"] == [mono.label(a)]
    monkeypatch.setattr(mono, "admissible_set", lambda: ([], [b]))
    assert mono.tier_a_summary()["narrowed"] == [mono.label(b)]
