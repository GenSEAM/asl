---
name: as-lang
description: Write, check and transpile AgentScript (as-lang, .as files) — an S-expression language with closed unions, exhaustive matching, a total I/O surface and a typed foreign-function boundary, transpiled to Python, Rust and Swift. Use when creating or editing .as source, adding to the vocabulary, binding a host library through defextern, or running the project's grammar, closure, coverage, corpus and differential gates.
---

# as-lang

## Read this first

`prelude/HANDBOOK.md` is the complete vocabulary, 4,531 measured tokens. **If a name
is not on that page it does not exist.** Read it before writing any `.as`, and do
not widen the vocabulary to make an error go away — add the name to
`prelude/prelude.json` and regenerate, or use what is there.

`AGENT_SPEC_CORE.md` is normative when the handbook is not specific enough. It is
long; reach for it for a rule, not for orientation.

## Write a whole module per pass

The unit of one pass is a working module, not a function. Start with the header,
which is the part a later pass reads instead of the body:

```lisp
(module text/casing
  :doc "One sentence."          ; mandatory
  :export [shout]               ; nothing is public unless listed
  :import [(core/strings :as s)]
  :extern [(py "polars" :as pl)])  ; only for a module that binds a host library
```

Then the declarations. Every exported `defun` needs a `:doc`. Every function that
reaches the outside needs `:effects [io]`.

## The four rules that catch most mistakes

1. **Totality.** `if` takes three parts, `cond` ends with `:else`, `match` covers
   every case. There is no one-armed anything.
2. **No implicit conversion.** `(+ 1 2.0)` is an error. Convert explicitly.
3. **Everything effectful is a `Result`.** `(file-read p)` is not a `String`;
   `(try (file-read p))` is. Same for every `defextern` call.
4. **`try` only inside a `defun` returning a compatible `Result`.**

## Check it

Run these from the repository root, in this order. Each is fast, and each
catches a different class of error.

```bash
.venv/bin/python grammar/validate.py          # both grammars, same verdict AND same shape
.venv/bin/python checker/check.py <file>      # 14 of the 15 §9 rules
.venv/bin/python grammar/closure_audit.py     # no call to an undefined name
.venv/bin/python prelude/coverage_audit.py    # every builtin has an example
.venv/bin/python prelude/generate.py --check  # generated artifacts are current
.venv/bin/python backend/check_corpus.py      # transpiles AND the target accepts it
.venv/bin/python backend/differential.py      # the backends agree
.venv/bin/python -m pytest backend/t bench/algo tools/bindgen/t checker/t -q
```

`checker/check.py` decides twelve of the fifteen §9 rules. The three it does not
are delimiter balance (the grammars decide it), and rules 3 and 6 — the type
rules, which need inference that does not exist yet. So a clean check does
**not** mean the module type-checks; `check_corpus.py` invoking `rustc` and
`swiftc` is still the strongest signal there. `--rules` prints the split, and
`--json` gives machine-readable diagnostics for a repair loop.

## Transpile and run one file

```bash
.venv/bin/python backend/to_python.py path/to/mod.as > mod.py
.venv/bin/python backend/to_rust.py   path/to/mod.as > prog.rs
.venv/bin/python backend/to_swift.py  path/to/mod.as > prog.swift
```

To build and run a module with a `defentry`:

```bash
cp backend/rust/rt.rs . && rustup run stable rustc --edition 2021 -o prog prog.rs
cp backend/swift/rt.swift . && swiftc -o prog rt.swift prog.swift
```

**Do not name the generated Swift file `main.swift`.** Swift treats that filename
as top-level code and then rejects the `@main` the backend emits.

## Add to the vocabulary

`prelude/prelude.json` is the single source of truth. The specification's §6
tables and `prelude/HANDBOOK.md` are **generated** — editing them by hand is
work the `--check` gate will reject.

```bash
.venv/bin/python prelude/generate.py
```

A new builtin needs a lowering for all four targets (`py`, `js`, `rs`, `sw`) and
an example, or the coverage gate fails. Literal braces in a template must be
doubled or they are read as format placeholders and fail far from their cause.

## Bind a host library

Generate the declarations; do not hand-write them.

```bash
python3 tools/bindgen/from_pyi.py <stub.pyi> \
    --module data/frames --package polars --alias pl --target py
```

Then remember what the boundary guarantees: a `defextern` declares the **success**
type, and every call site sees `(Result T String)`. A module holding any
`defextern` is not portable — it names one ecosystem, and the other backends
refuse it by name.

## Change a grammar

Both grammars change together — `grammar/as-lang.lark` drives constrained
decoding, `grammar/tree-sitter-as-lang/grammar.js` drives tooling — and
`validate.py` fails when they disagree, not only when a verdict is wrong.

```bash
cd grammar/tree-sitter-as-lang && ../../node_modules/.bin/tree-sitter generate
```

A new keyword terminal also has to be added to `FORM_KW` in all three backends,
or `kids()` leaves it in the child list and the declaration mis-parses.

## Setup, if the gates cannot run

```bash
python3 -m venv .venv && .venv/bin/pip install lark pytest
npm install
cd grammar/tree-sitter-as-lang && ../../node_modules/.bin/tree-sitter generate
.venv/bin/python backend/to_python.py backend/t/smoke.as > backend/t/smoke.py
```

The last line is required before `pytest`: `smoke.py` is generated and git-ignored.
