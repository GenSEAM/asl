# Lang / Checker

This file groups d/c/r/l entries for the lang/checker module.

### [l-78ae] Semantic checker is the next load-bearing component, not the backends
- **Date**: 2026-08-20
- **Status**: **Partly resolved 2026-08-21** — `checker/check.py` decides twelve of §9's fifteen
  rules and is in the gate sequence. What remains is the part that needs a type system: rules 3
  and 6, inference at call sites and the numeric-kind judgement. Those are reported as *unchecked*
  by `--rules` rather than counted as passing, so a clean report is not read as a type check.
- **Cluster**: lang/checker
- **Description**: Most of the conformance checklist cannot be enforced by any grammar: name
  resolution across module boundaries, import cycles, type-variable binding, match exhaustiveness,
  arity, and the reserved-prefix rule are all semantic. Two independent grammars currently agree
  with each other and neither checks any of it.
- **Rationale for priority**: Located evidence puts the great majority of failures in
  LLM-generated code at the type level rather than the syntactic one, with grammar-level
  constraints capturing only a small fraction of the achievable error reduction. Building
  transpiler backends before the checker would be optimising the part already known to be small.
- **Why Non-Obvious**: The conformance gate is green, which reads as "the language is validated".
  It validates only that two parsers agree on shape. Nothing yet rejects a program that imports a
  cycle, calls a function with the wrong arity, or fails to handle a union case.


### [d-c4a1] The checker is written in Python first, and is the oracle for the Rust one
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/checker
- **Description**: `d-2030` puts the compiler in Rust, and a semantic checker is compiler frontend
  code. It was nevertheless written in Python, alongside the existing gates.
- **Rationale**: A checker that enforces twelve rules today is worth more than a better-hosted one
  in several weeks, because nothing enforced any of them and that was the largest gap in the
  project. The Python one is not throwaway: when the Rust frontend is written it must agree with
  this one on the whole corpus, which is the same technique that de-risks porting the transpilers —
  the existing implementation becomes the differential oracle for its replacement.
- **Costs accepted**: two implementations of the same rules will exist for a while, and they can
  drift. The mitigation is that the drift is mechanically detectable, which is not true of a rule
  that exists in only one place and is wrong.
- **Why Non-Obvious**: hosting decisions read as binding for every component they touch, so
  "the compiler is in Rust" reads as "therefore the checker is". The decision was about the
  compiler that ships, not about the first thing that enforces a rule.

### [c-2f7e] Two grammars can accept the same file and read it differently
- **Date**: 2026-08-21
- **Status**: **Resolved 2026-08-21** by a shape comparison in `grammar/validate.py`
- **Cluster**: lang/checker
- **Description**: `(s/concat a b)` parsed as a four-argument call to `s` under Lark and as a call
  to the qualified name `s/concat` under tree-sitter. Both grammars accepted the file. The gate
  compared accept/reject and therefore could not see it; the defect surfaced only when the new
  semantic checker reported `s` and `concat` as undefined names.
- **Mechanism**: under the dynamic lexer both tokenizations are valid, and in call-head position
  Earley resolved the ambiguity the wrong way. In argument position it resolved correctly, so every
  fixture that only passed qualified names as arguments looked fine. Fixed with a terminal priority
  on `QUALIFIED`.
- **Why Non-Obvious**: "both grammars agree" was being enforced as "both return the same verdict",
  which is a strictly weaker claim than "both accept the same language" and reads identically in a
  green gate. The one backend that would have caught it — Python — was also the one with no
  compiler gate, so its visibly wrong output was reported as `ok`.


### [d-a3f7] The type layer is bidirectional and fails open
- **Date**: 2026-08-21
- **Status**: Active — closes the type half of `l-78ae`
- **Cluster**: lang/checker
- **Description**: §9 rules 3 and 6 are now decided by `checker/typecheck.py`, which brings the
  checker to fourteen of fifteen rules; the fifteenth is delimiter balance, which the grammars own.
- **Why bidirectional rather than Hindley–Milner**: the language annotates every binding site —
  parameters and returns on `defun` and `fn`, schema fields, enum cases — so the only unannotated
  position in the whole language is a `let` binding. That removes generalisation entirely and
  leaves first-order unification, used in one place: instantiating a `{A B}` binder at a call site.
  "Needs a type system" had been recorded as the reason these rules were undecidable; the property
  that makes them cheap was already in the language.
- **Fails open, deliberately**: a construct the layer cannot type yields an unknown that unifies
  with anything, rather than an error. A checker that fires on the programs the handbook teaches is
  worse than no checker, so every gap is silent. The cost is that silence is **not** proof of
  well-typedness, and `--rules` says so rather than leaving a clean report to imply it.
- **Failing open is measured, not trusted**: `--coverage` counts typed against untyped expressions
  and the gate holds the floor at 100%. Without it, "checked and clean" and "declined to look"
  print identically. Measured at 519 of 519 on the corpus, so the caveat is currently vacuous —
  which is worth knowing, and is a stronger claim than the caveat alone.
- **Why Non-Obvious**: the honest-looking move is to report everything uncertain and let the author
  suppress the noise. For an artifact whose whole purpose is to be generated against, a false
  positive is worse than a miss: it teaches the generator to avoid a construct that was correct.
  The second non-obvious part is that "fails open" is not a caveat you can simply write down — it
  hides exactly the information that would tell you how much the caveat costs.
