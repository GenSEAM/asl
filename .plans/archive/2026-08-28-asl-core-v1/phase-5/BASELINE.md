# Phase 5 — Baseline battery

Recorded 2026-08-30 by the Phase 5 implementer against the current HEAD, prior to any Phase 5
changes. Full battery run verbatim with the results below.

baseline: 8e6966ade51138fdf5200f94caa24f51506227f9

## Re-run gate counts

```
validate: 98 ok
checker gate: 79 ok
check_corpus: 31
differential: 0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm)
pytest: 161 passed
```

These match the counts recorded in PLAN.md v2 (±0 on every figure). The baseline tree is green;
I0 does not halt.
