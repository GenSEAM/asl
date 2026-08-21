# Lang / Host

This file groups d/c/r/l entries for the lang/host module.

### [d-2030] The compiler is hosted in Rust, not Go
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/host
- **Description**: One host language was to be chosen for the compiler, with self-hosting as the
  eventual goal. Rust is chosen.
- **Rationale**: The language's defining constructs are closed unions, exhaustive matching, and
  option/result types. The chosen host has all three natively, with exhaustiveness checked by its
  own compiler, so those constructs survive translation intact. The alternative has none of them:
  a closed union must be encoded through an interface and a runtime type switch, and no
  exhaustiveness check exists — meaning the safety property this language is built on would be
  silently discarded at exactly the layer meant to preserve it. A compiler is the most
  union-saturated program there is, so the mismatch would be paid on every AST and IR node.
- **Counter-argument weighed**: the chosen host requires an ownership decision that remains
  unrecorded, which the alternative would not have. That is a decision to be made and can be made
  conservatively at first. The alternative's missing unions are not a decision — they are a
  permanent impedance mismatch with no conservative fallback.
- **Why Non-Obvious**: The alternative looks cheaper on every surface metric: simpler language,
  faster builds, no ownership question, easier hiring. The cost is invisible until the first
  recursive variant type is written, which for a compiler is immediately.

### [c-1d90] The self-hosting probe found the language cannot yet host its compiler
- **Date**: 2026-08-21
- **Status**: Active — blocks self-hosting
- **Cluster**: lang/host
- **Description**: `compiler/lex.as` is a working lexer for the language, written in the language.
  It classifies every token class, round-trips real source, and transpiles to all three backends.
  It cannot lex itself. `ROADMAP.md` §7 registered this probe as the cheap place to find out what
  the language is missing, and it found four things.
- **1. There is no loop, and no backend eliminates tail calls.** This is the blocking one. A lexer's
  loop is "while input remains, consume a variable amount", which is not a fold over a list that
  already exists — so it has to recurse, once per token. The Python backend runs out of stack at
  roughly 900 tokens; `compiler/lex.as` is about 1,400 atoms. The `for` form was deliberately
  omitted from Core on the reasoning that `map`/`filter`/`fold` plus recursion cover iteration.
  They cover iteration over a known collection. They do not cover an unbounded loop.
- **2. A function type cannot be written.** The type grammar is `TypeName | (TypeName type+)` and
  has no function form, so `map`, `filter` and `fold` take functions only because they are
  builtins. A user function cannot. One `take-while` taking a predicate became three near-identical
  `take-*` functions, and no `.as` file in the repository declares a function-typed parameter
  because none can.
- **3. The recursion ceiling differs by target and no gate can see it.** Python fails at ~900
  tokens, Rust handles 15,000. The differential gate compares answers on inputs both backends
  survive, so a program that works on one target and overflows on another passes it.
- **4. Accumulating with `list-append` is quadratic.** Prepending with `list-cons` and reversing
  once is the O(n) idiom, and nothing says so. The naive version took the Rust build past ten
  minutes on twenty thousand tokens.
- **What it also found, in the backends**: a nested `match` on a `cons`-bound tail emitted
  `as_slice()` on a value that was already a slice, because the tail's materialisation was read
  after the body was lowered and an inner pattern had overwritten it. Fixed.
- **Why Non-Obvious**: the probe was predicted to turn on whether closed unions existed, and they
  were the part that worked perfectly — the AST enum, the exhaustive matching and the Result
  threading all came out clean and readable. What failed was iteration, which nobody listed as a
  risk because `fold` looks like it covers looping. It covers folding.
