# as-lang — AgentScript

An S-expression language designed so that an LLM agent can produce a **whole
working module in one pass**, transpiled to Python, Rust and Swift.

Three properties, in the order they matter:

* **A total foreign boundary.** A host library is declared with types, and every
  foreign call yields `(Result T String)`. There is no form that returns a bare
  host value. Host type stubs carry argument and return types but **no exception
  information at all**, so a statically checked program in the host language
  cannot see that a call may fail — wrapping the boundary makes it total by
  construction, which is strictly more than the host's own checker can express.
* **Totality throughout.** `if` needs both branches, `cond` needs `:else`,
  `match` must be exhaustive, lookups return `(Option T)` rather than trapping,
  and nothing converts numerically without being told to.
* **Modules by default.** Every file is a module, private by default, with an
  explicit `:export` list that a later pass can read without reading the body.

```lisp
(module port/cron
  :doc "Parse a five-field cron expression and describe it in English."
  :export [describe])

(defenum Field
  (:case every    []                      "Every value in the range")
  (:case exact    [(value Int64)]         "One value")
  (:case span     [(lo Int64) (hi Int64)] "An inclusive range"))

(defun field-text [(f Field) (unit String)] -> String
  :doc "One field in English."
  (match f                                 ; exhaustive, or it does not compile
    ((every)      (str "every " unit))
    ((exact v)    (str unit " " (string-from-int64 v)))
    ((span lo hi) (str unit " " (string-from-int64 lo)
                      " through " (string-from-int64 hi)))))
```

## Why an S-expression, and the one argument for it

Format-restricted generation damages reasoning mainly when the grammar **commits
a result before the reasoning that produced it**. Measured on GSM8K with
GPT-3.5-turbo: natural language 75.99%, JSON-shaped instructions 74.70%, JSON-mode
constrained decoding **49.25%** — with 100% of JSON-mode responses emitting the
answer key before the reason key. Constraint itself costs about 1.3 points;
*ordering* costs about 27.

A Lisp body is a sequence whose value is its tail expression, so derivation
precedes result structurally. That is the whole argument. Claims about parser
convenience or token efficiency are **not** supported by located evidence and are
not made here — guaranteed syntactic validity is commodity, available to any
grammar from a constrained decoder.

## State

Verified by a command whose output was read, not asserted.

| Area | State |
|---|---|
| Specification | v0.3 — `AGENT_SPEC_CORE.md`, normative |
| Grammars | two, agreeing — Lark (Earley) and tree-sitter |
| Python / Rust / Swift backends | working; output accepted by `compile()`, `rustc`, `swiftc` |
| Kotlin backend | priority target, no transpiler |
| WebAssembly (browser) | via the Rust backend; a module needing `fs`/`env`/`proc` is refused before the build |
| JavaScript backend | lowering rules in the prelude, no transpiler |
| Cross-module linking | whole-program; modules indexed by their declared header |
| Conformance gate | 23 fixtures × 2 grammars |
| Closure gate | no example calls an undefined name |
| Coverage gate | 103 of 103 builtins appear in an example |
| Differential gate | 28 cases × 3 backends, no disagreement |
| Semantic checker | 14 of §9's 15 rules — types included; fails open, so silence is not proof |
| Measurement | not run; blocked on gateway access |

### What is not true yet

**The type layer fails open.** `checker/check.py` decides fourteen of §9's
fifteen well-formedness rules — name resolution, types, exhaustiveness, effects,
the foreign boundary, import cycles — and runs in the gate sequence. The
fifteenth is delimiter balance, which the grammars own. But a construct the type
layer cannot type is reported as nothing rather than as an error, because a
checker that fires on valid code is worse than none. **Silence is not proof that
a module is well-typed** — so the gap is measured rather than assumed away:
`--coverage` reports it, and the gate holds it at 100%. All 519 expressions in
the corpus are typed today, and a form the layer cannot handle breaks that gate
instead of passing quietly.

**The core premise is unmeasured.** No located source evaluates whether LLMs
generate S-expressions more or less reliably than mainstream languages, and the
evidence that generation quality tracks training-corpus presence predicts that a
purpose-built language will underperform. Every gate above measures internal
consistency, which proves nothing about that claim. `EXPERIMENT.md` pre-registers
the protocol; `RESEARCH_REPORT.md` §1 and §5 carry the argument against.

## Try it

```bash
python3 -m venv .venv && .venv/bin/pip install lark pytest
npm install
cd grammar/tree-sitter-as-lang && ../../node_modules/.bin/tree-sitter generate && cd -

.venv/bin/python backend/to_python.py examples/port/cron/cron.as > cron.py
.venv/bin/python backend/differential.py     # same source, three backends, same answers
```

`prelude/HANDBOOK.md` is the agent-facing reference — the complete vocabulary in
4,531 measured tokens, generated from `prelude/prelude.json`. Every example in it
is parsed by `grammar/validate.py`, because a wrong example in the one document an
agent actually reads is worse than no example. It is what goes into a prompt; the
specification is what settles an argument.
