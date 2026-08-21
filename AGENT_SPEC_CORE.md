# AGENT_SPEC_CORE.md — AgentScript Core v0.3

**Status:** normative for the concept-validation experiment (`EXPERIMENT.md`).
Supersedes [`AGENT_SPEC.md`](AGENT_SPEC.md) (frozen as v0) for everything it covers.

This document is **closed**: every identifier used in any example here is defined here. That is
the property [`SPEC_REVIEW.md`](SPEC_REVIEW.md) §7 found missing in v0 (20 defined forms against
24 undefined ones), and it is a precondition for measuring generation reliability — a model
cannot be judged on forms the specification never gave it.

## 0. Scope

**In:** modules, `defschema`, `defenum`, `defun`, `defentry`, `fn`, type parameters, `let`, `if`,
`cond`, `match`, `try`, records, `Result`, `Option`, `Pair`, `List`, `Map`, strings, arithmetic,
comparison, `Bool` / `Int32` / `Int64` / `Float64` / `String` / `Unit`, an I/O surface (§10), and a
foreign-function boundary — `defextern`, `defopaque`, `:extern` (§11).

**Deliberately out of Core:** `defagent`, `defui`, `meta:async`, `if-target`, JSON serialization,
concurrency.

### Why v0.2 exists

v0.1 was scoped to what a HumanEval-class benchmark exercises, and that scope was wrong for the
product. A suite of small self-contained functions cannot reveal the absence of a module system or
of user-declarable polymorphism, because no task in it spans two files or needs a shared
abstraction. Scoping to the benchmark therefore optimised the measurement and not the language.

Three additions follow directly from the stated goal that an agent should produce reusable work,
and that the unit of one pass is a **working module** (PCP `r-43ea`, `r-8f23`, `r-b539`):

* **Modules by default** — every file is a module with an explicit exported surface, so a later
  pass can compose an earlier one having read only that surface.
* **Type parameters** — without them only the prelude is polymorphic and every user abstraction
  must be duplicated per concrete type, which caps reuse at zero.
* **Closed unions and a keyed collection** — without the first, domain states get encoded as
  strings, defeating type safety exactly where it pays; without the second, ordinary programs are
  inexpressible.

### Why v0.3 exists

v0.2 excluded both I/O and foreign calls. Each exclusion has since become untenable, for a
different reason.

* **I/O** — the benchmark is whole programs that read and write (PCP `r-56bf`), so the exclusion
  stopped being a scope boundary and became a blocker: no measurement arm can run without it.
* **Foreign calls** — a total boundary over an untyped ecosystem is the language's *central
  rationale* (PCP `d-4b8c`). A specification that listed it under "deliberately out" contradicted
  the reason the language exists.

The v0 collision that made FFI dangerous ([`SPEC_REVIEW.md`](SPEC_REVIEW.md) C3) does not arise:
Core has no `(.method obj)` form, `.-` is the only accessor, and a foreign function is reached
through an ordinary qualified name resolved by an explicit `defextern`. Nothing is dispatched on
spelling.

**The boundary is total by construction, and that is the whole claim.** A `defextern` declares the
type of the *success* value; every call site sees `(Result T String)`. There is no form that
yields a bare host value and no escape hatch. This is strictly more than the host's own checker
can express — host type stubs declare argument and return types and carry no exception information
whatsoever, so a statically checked host program still cannot see that a call may fail.

**What it costs.** A module carrying any `defextern` is no longer portable: it names one ecosystem
and a transpiler for another target refuses it. Portability survives for the pure core, and the
effectful edges belong to one host. That cost is accepted, not worked around.

### Deviation from the approved plan

The plan listed `for` among Core's iteration forms. It is **omitted**: bindings are immutable and
there is no mutation, so `for` would add nothing `fold` does not already provide. Iteration is
`map` / `filter` / `fold` / `range` plus recursion.

---

## 1. Design rationale — why S-expressions

One evidence-backed reason, and the specification should not claim others.

Format-restricted generation degrades reasoning when the grammar **commits a result before the
reasoning that produced it**. Measured on GSM8K with GPT-3.5-turbo: natural language 75.99%,
JSON-shaped *instructions* 74.70%, JSON-*mode* constrained decoding **49.25%** — and the mechanism
is explicit, with 100% of JSON-mode responses emitting the `answer` key before the `reason` key,
converting chain-of-thought into direct answering (`RESEARCH_REPORT.md` §3).

Constraint itself costs ~1.3 points. **Ordering costs ~27.**

A Lisp body is a sequence whose value is its tail expression: `let` bindings and intermediate
computation necessarily precede the returned value. The grammar therefore puts derivation before
result *structurally*, which is the opposite of a schema whose key order can commit an answer
first.

This is a claim about grammar shape, and it survives the fact that guaranteed syntactic validity
is commodity (`RESEARCH_REPORT.md` §2.2). Claims about parser convenience or token efficiency are
**not** supported by located evidence and must not be made.

---

## 2. Lexical structure

```
comment    ::= ";" <any char except newline>* 
ident      ::= [a-z] [a-z0-9-]* [?!]?          ; kebab-case
qualified  ::= ident "/" ident                 ; alias-qualified, e.g. s/upper
mod-path   ::= ident ( "/" ident )*            ; module path, e.g. core/strings
type-var   ::= [A-Z] [A-Za-z0-9]*              ; only inside a { } binder
type-name  ::= [A-Z] [A-Za-z0-9]*              ; PascalCase
keyword    ::= ":" ident
int-lit    ::= "-"? [0-9]+
float-lit  ::= "-"? [0-9]+ "." [0-9]+
string-lit ::= '"' ( char | escape )* '"'
escape     ::= "\\" ( '"' | "\\" | "n" | "t" | "r" | "0" )
bool-lit   ::= "true" | "false"
unit-lit   ::= "()"
```

Identifiers are case-sensitive. Whitespace and comments are insignificant except as separators.

`/` is both the division operator and the qualified-name separator. They never collide: division
is a standalone token surrounded by separators, while a qualified name has no internal whitespace.
Clojure resolves it the same way, and for the same reason.
`as-` is a **reserved identifier prefix** for compiler-internal names; user code using it is
rejected (precedent: Haxe's `_hx_`, `SPEC_REVIEW.md` §11.8). The prefix is deliberately spelled in
a form the identifier rule above can actually produce — a reserved word the lexer cannot emit
reserves nothing, and its conformance fixture would pass for an unrelated reason.

## 3. Types

| Type | Notes |
|---|---|
| `Bool` | `true` / `false`. No truthiness — `if` accepts `Bool` only. |
| `Int32`, `Int64` | Two's complement, wrapping is an error not a behavior; see §6.1 |
| `Float64` | IEEE-754 binary64 |
| `String` | Sequence of Unicode scalar values. **All indices are in characters, never bytes.** |
| `Unit` | Exactly one value, written `()` |
| `(List T)` | Homogeneous, immutable, ordered |
| `(Option T)` | `(some v)` \| `(none)` |
| `(Result T E)` | `(ok v)` \| `(err e)` |
| `(Pair A B)` | Built-in record, fields `first` / `second` |
| `ProcessResult` | Built-in record, fields `exit-code` / `stdout` / `stderr`; see §10 |
| `(Map K V)` | Immutable keyed collection; `K` must support equality |

`Int` is a documented alias for `Int64`. **There is no implicit numeric conversion** — mixing
`Int64` and `Float64` in one arithmetic form is a type error. Use §6.4's explicit conversions.

Fixing the widths resolves `SPEC_REVIEW.md` A3, which otherwise makes the same program overflow
differently on every target it is lowered to.

## 4. Declarations

### 4.0 `module` — modularity by default

Every source file is a module. The header is its contract, and it is deliberately readable without
the body: a later pass composes a module by reading only this.

```lisp
(module text/casing
  :doc "Case-conversion helpers for report rendering."
  :export [shout initials]
  :import [(core/strings :as s)
           (core/lists   :as l)])
```

* `:doc` — mandatory. One sentence on what the module is for.
* `:export` — the public surface. **Everything not listed is private to the module.**
* `:import` — each entry binds a module path to a short alias; members are then reached as
  `alias/name`.

A file with no `module` header is still a module: its path relative to the source root becomes its
name, its `:doc` is absent, and **nothing is exported**. Modularity is the default; the header
only names and opens it.

Private-by-default is the deliberate choice. An explicit export list is a stable surface to
program against, and it is the one part of a module another pass must read — which is exactly the
property being optimised when the unit of work is a whole module.

Import cycles are an error. Aliases are module-local and may be chosen freely.

### 4.1 `defschema`

```lisp
(defschema Point
  (:field x Int64 "Horizontal coordinate")
  (:field y Int64 "Vertical coordinate"))

(defschema Config
  (:field name    String "Display name")
  (:field retries Int64  "Attempt count" :default 3))
```

`(defschema [{<type-vars>}] <TypeName> <field>+)`, with
`(:field <ident> <Type> <doc-string> [:default <literal>] [:json <string>])`.
The doc-string is mandatory — it is cheap, and it is what an LLM reads.

Records may be parameterised. Type variables are bound in a leading `{ }`, so a name is a type
variable because it was declared one, never because of how it is spelled:

```lisp
(defschema {T} Box
  (:field value T "The wrapped value"))
```

**Construction** (resolves `SPEC_REVIEW.md` B2, which left records unconstructable):

```lisp
(Point :x 3 :y 4)
(Config :name "svc")          ; retries defaults to 3
```

A PascalCase identifier in head position is a constructor. Every field without a `:default` must
be supplied; order is irrelevant; unknown or duplicate keys are errors.

**Field access** uses the `.-` prefix (resolves C3, precedent Clojure §11.1):

```lisp
(.-x p)
```

**JSON naming** is pinned now even though Core ships no serializer, so that adding one later cannot
silently change the wire format (resolves A2): `:json-case` on the schema selects
`kebab` (default, name verbatim) / `camel` / `snake` / `pascal`, and `:json "..."` on a field
overrides it. Shape copied from serde and pydantic, which converged independently (§11.5).

### 4.2 `defun`

```lisp
(defun add [(a Int64) (b Int64)] -> Int64
  (+ a b))

(defun safe-div [(a Int64) (b Int64)] -> (Result Int64 String)
  (if (= b 0)
    (err "division by zero")
    (ok (/ a b))))
```

`(defun [{<type-vars>}] <ident> [<params>] -> <Type> [:doc <string>] <body-expr>+)`. The parameter
list is a **vector**, and `->` is a literal token in the form, not an expression (resolves A9). The
body is one or more expressions evaluated in order; the value is the last one.

`:doc` is **mandatory for every exported function** and optional otherwise. v0.1 required a
doc-string on record fields but gave functions nowhere to put one, which is backwards: an agent
composing a module reads its functions, not its field layouts.

Functions may be parameterised over types, bound in a leading `{ }`:

```lisp
(defun {A B} swap [(p (Pair A B))] -> (Pair B A)
  :doc "Exchange the two components of a pair."
  (pair (.-second p) (.-first p)))
```

Without this, only the prelude is polymorphic and every shared abstraction has to be rewritten per
concrete type (PCP `r-8f23`).

Parameters are vectors throughout the language — v0 used a list for `defun` and a vector for
`defui`, which was inconsistent (C4). Core standardizes on the vector.

Visibility comes from the module's `:export` list (§4.0), not from position. A top-level
definition that is not exported is private to its module, and the backends express that with the
target's own visibility modifier — `pub` in Rust, `public`/`internal` in Kotlin and Swift. It is a
modifier, never a spelling: §8's mangling is independent of whether a name is exported.

### 4.3 `fn`

```lisp
(fn [(x Int64)] -> Int64 (* x 2))
```

`(fn [<params>] -> <Type> <body-expr>+)`. Anonymous function, closing over the enclosing scope by
value.

It is **not** simply `defun` without a name: a lambda takes neither type parameters nor `:doc`.
Type parameters are bound by the named declaration that encloses it, and a lambda has no exported
surface to document. Both grammars enforce this, and a fixture pins it.

### 4.4 `defenum` — closed unions

```lisp
(defenum Shape
  (:case circle    [(radius Float64)]                  "A circle")
  (:case rectangle [(width Float64) (height Float64)]  "An axis-aligned rectangle")
  (:case point     []                                  "A degenerate zero-area shape"))
```

`(defenum [{<type-vars>}] <TypeName> <case>+)` with
`(:case <ident> [<fields>] <doc-string>)`. Case names are kebab-case identifiers and are used as
both constructors and patterns, exactly like the built-in `ok` / `some`:

```lisp
(circle 2.0)
(match sh
  ((circle r)      (* 3.14159 (* r r)))
  ((rectangle w h) (* w h))
  ((point)         0.0))
```

Enums may be parameterised, which is what makes recursive container types expressible:

```lisp
(defenum {T} Tree
  (:case leaf []                            "An empty subtree")
  (:case node [(value T) (left (Tree T)) (right (Tree T))] "An interior node"))
```

Matching an enum must be exhaustive, as for every other `match`. Without closed unions a domain
state is encoded as a string or an integer, which discards type safety at precisely the points
where it would have paid, and the compiler's own AST is inexpressible (PCP `r-b539`).

### 4.5 `defentry` — the single entry point

```lisp
(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Summarise the file named by the first argument."
  :effects [io]
  (let [(path (option-or (list-head argv) ""))]
    (println (str "reading " path))))
```

`(defentry [<params>] -> <Type> [:doc <string>] [:effects [<effect>*]] <expr>+)`.

It carries **no name**. An entry point identified by spelling — a function that becomes the program
because it happens to be called `main` — would be the one construct in this language dispatched on
how a name is written, which §4.1 and the type-parameter rule exist to avoid. There is at most one
per program.

Backends lower it to `as-entry` plus the target's own startup convention. That is what the reserved
`as-` prefix (§2) is for, and it is the first use of it.

### 4.6 `:effects` — declared, checked, not inferred

Any `defun` or `defentry` that reaches the outside names what it reaches:

```lisp
(defun save [(path String) (body String)] -> (Result Unit String)
  :doc "Write a report."
  :effects [fs]
  (file-write path body))
```

The vocabulary is closed, and it is finer than one name on purpose:

| Effect | Covers |
|---|---|
| `console` | `print`, `println`, `eprintln` |
| `stdin` | `read-line`, `read-all` |
| `fs` | `file-read`, `file-write`, `file-exists?` |
| `env` | `env-get`, `args` |
| `proc` | `process-run` |

**Effects are transitive.** A function that only calls an effectful function is
effectful too, and declares the same names; a rule that stopped at direct calls would be
satisfied by one wrapper.

**A target that cannot provide an effect refuses the module.** A browser has `console` and
nothing else — no filesystem, no environment, no subprocesses — and this is what makes that
decidable before a build rather than at run time. It is the same shape as §11's `:target`
refusal for foreign declarations, applied to capabilities instead of ecosystems.

One name would have been simpler and is what v0.3 shipped first. It was split once WebAssembly
became a target, because `io` claimed a filesystem on a host that has none, and splitting it later
would have been a breaking change to every signature already written.

Purity is the default and stays verifiable: a declaration that omits `:effects` may not call an
effectful builtin, directly or transitively.

The alternative was to leave effects implicit. That is cheaper today and is precisely the choice
that forces function colouring later, when a concurrent construct arrives and every signature has
to be re-typed. An annotation is a mild colouring paid at one line per effectful function, and it
makes adding `:effects [async]` additive rather than breaking. Recorded as a decision under
`lang/io`; the trade is deliberate, not incidental.

## 5. Expressions

### 5.1 `let` — sequential, immutable

```lisp
(let [(n (string-length s))
      (half (/ n 2))]
  (string-slice s 0 half))
```

Bindings are evaluated **in order**, and each may refer to those before it (`let*` semantics,
resolving A6). Bindings are **immutable** — Core has no `set!`. Shadowing an outer name is
permitted. `let` is not recursive; use `defun` for recursion.

### 5.2 `if` — total

```lisp
(if (< a b) a b)
```

Both branches are **mandatory** and must have the same type; the condition must be `Bool`
(resolves A7). There is no single-armed `if`.

### 5.3 `cond`

```lisp
(cond
  ((< n 0)  "negative")
  ((= n 0)  "zero")
  (:else    "positive"))
```

Clauses are tested in order. `:else` is **mandatory** and must be last — a `cond` is always total,
for the same reason `if` is.

### 5.4 `match`

```lisp
(match (string-to-int64 s)
  ((some n) (* n 2))
  ((none)   0))

(match (option-to-result (list-head xs) "empty list")
  ((ok n)    n)
  ((err msg) (string-length msg)))

(match xs
  ((list)      0)
  ((cons h t)  (+ h (sum-list t))))
```

Patterns, and nothing else:

| Pattern | Matches |
|---|---|
| `(ok p)` / `(err p)` | a `Result` |
| `(some p)` / `(none)` | an `Option` |
| `(list)` | the empty list |
| `(cons <p> <p>)` | a non-empty list, binding head and tail |
| `(pair <p> <p>)` | a `Pair` |
| literal | equal `Int32`/`Int64`/`Bool`/`String` value |
| `(<case> <p>*)` | a `defenum` case, binding its fields (§4.4) |
| `<ident>` | anything, binding it |
| `_` | anything, binding nothing |

Match must be **exhaustive**; a non-exhaustive `match` is a compile error. All arms must share a
type.

### 5.5 `try` — Result propagation

```lisp
(defun parse-port [(text String)] -> (Result Int64 String)
  (let [(raw (try (option-to-result (list-get (string-split text ":") 1)
                                    "missing port")))
        (n   (try (option-to-result (string-to-int64 (string-trim raw))
                                    "port is not a number")))]
    (if (> n 65535)
      (err "port out of range")
      (ok n))))
```

`(try e)` where `e : (Result T E)` evaluates to `T`, or returns `(err …)` from the enclosing
`defun` immediately. Legal only inside a `defun` whose return type is `(Result _ E)` with a
matching `E`.

Together `match` and `try` resolve `SPEC_REVIEW.md` B1 — v0 could construct `ok`/`err` and had no
way to consume them, making every I/O-shaped program unwritable. Precedent: Gleam's
`use`/`result.try` and Rust's `?` (§11.2). `try` exists specifically because `match`-only code
nests deeply, and nesting depth is the dominant LLM syntax-failure mode.

### 5.6 Evaluation order

Strict, left to right, depth first. Arguments are fully evaluated before the call. `and` / `or`
short-circuit; nothing else does. The compiler may not reorder or elide any call (resolves G9).

---

## 6. Closed vocabulary

Every builtin, with its type. Nothing outside this table and §4-5 exists in Core.

**Generated from `prelude/prelude.json`** — edit there, not here.

### 6.1 Arithmetic

| Form | Type | Meaning |
|---|---|---|
| `(+ a b)` | `N N -> N` | Sum. |
| `(- a b)` | `N N -> N` | Difference. |
| `(* a b)` | `N N -> N` | Product. |
| `(/ a b)` | `N N -> N` | Division; integer division truncates toward zero. Traps on a zero divisor. |
| `(mod a b)` | `N N -> N` | Remainder; the sign follows the dividend. Traps on a zero divisor. |
| `(checked-div a b)` | `N N -> (Option N)` | Division, or none on a zero divisor. |
| `(checked-mod a b)` | `N N -> (Option N)` | Remainder, or none on a zero divisor. |
| `(neg a)` | `N -> N` | Arithmetic negation. |
| `(abs a)` | `N -> N` | Absolute value. |
| `(min a b)` | `N N -> N` | Lesser of two values. |
| `(max a b)` | `N N -> N` | Greater of two values. |

### 6.2 Comparison and logic

| Form | Type | Meaning |
|---|---|---|
| `(= a b)` | `T T -> Bool` | Structural equality. |
| `(!= a b)` | `T T -> Bool` | Structural inequality. |
| `(< a b)` | `T T -> Bool` | Ordered comparison, for numbers and strings. |
| `(<= a b)` | `T T -> Bool` | Ordered comparison, for numbers and strings. |
| `(> a b)` | `T T -> Bool` | Ordered comparison, for numbers and strings. |
| `(>= a b)` | `T T -> Bool` | Ordered comparison, for numbers and strings. |
| `(and a b)` | `Bool Bool -> Bool` | Conjunction; short-circuits. |
| `(or a b)` | `Bool Bool -> Bool` | Disjunction; short-circuits. |
| `(not a)` | `Bool -> Bool` | Negation. |

### 6.3 String

| Form | Type | Meaning |
|---|---|---|
| `(string-length a)` | `String -> Int64` | Length in characters. |
| `(string-empty? a)` | `String -> Bool` | True when the string has no characters. |
| `(str a b …)` | `String... -> String` | Concatenate strings. Takes strings only; convert first. |
| `(string-slice a b c)` | `String Int64 Int64 -> (Option String)` | Half-open character slice, or none when out of range. |
| `(string-index-of a b)` | `String String -> (Option Int64)` | Character index of the first occurrence. |
| `(string-contains? a b)` | `String String -> Bool` | True when the substring occurs. |
| `(string-starts-with? a b)` | `String String -> Bool` | True when the string begins with the prefix. |
| `(string-ends-with? a b)` | `String String -> Bool` | True when the string ends with the suffix. |
| `(string-split a b)` | `String String -> (List String)` | Split on a separator. |
| `(string-join a b)` | `(List String) String -> String` | Join with a separator. |
| `(string-upper a)` | `String -> String` | Upper case. |
| `(string-lower a)` | `String -> String` | Lower case. |
| `(string-trim a)` | `String -> String` | Remove leading and trailing whitespace. |
| `(string-reverse a)` | `String -> String` | Reverse the character sequence. |
| `(string-replace a b c)` | `String String String -> String` | Replace every occurrence. |
| `(string-chars a)` | `String -> (List String)` | Characters as one-character strings. |
| `(string-from-int64 a)` | `Int64 -> String` | Decimal rendering of an integer. |
| `(string-from-float64 a)` | `Float64 -> String` | Decimal rendering of a float. |
| `(string-to-int64 a)` | `String -> (Option Int64)` | Parse an integer, or none. |
| `(string-to-float64 a)` | `String -> (Option Float64)` | Parse a float, or none. |

### 6.4 Numeric conversion

| Form | Type | Meaning |
|---|---|---|
| `(int32-to-int64 a)` | `Int32 -> Int64` | Widen. |
| `(int64-to-int32 a)` | `Int64 -> (Option Int32)` | Narrow, or none when out of range. |
| `(int64-to-float64 a)` | `Int64 -> Float64` | Convert to floating point. |
| `(float64-to-int64 a)` | `Float64 -> (Option Int64)` | Truncate toward zero, or none for NaN, infinity or out of range. |

### 6.5 List

| Form | Type | Meaning |
|---|---|---|
| `(list a b …)` | `T... -> (List T)` | Construct a list. |
| `(list-empty? a)` | `(List T) -> Bool` | True when the list has no elements. |
| `(list-length a)` | `(List T) -> Int64` | Element count. |
| `(list-get a b)` | `(List T) Int64 -> (Option T)` | Element at an index, or none. |
| `(list-head a)` | `(List T) -> (Option T)` | First element, or none. |
| `(list-tail a)` | `(List T) -> (Option (List T))` | All but the first element, or none when empty. |
| `(list-cons a b)` | `T (List T) -> (List T)` | Prepend an element. |
| `(list-append a b)` | `(List T) (List T) -> (List T)` | Concatenate two lists. |
| `(list-reverse a)` | `(List T) -> (List T)` | Reverse order. |
| `(list-slice a b c)` | `(List T) Int64 Int64 -> (Option (List T))` | Half-open slice, or none when out of range. |
| `(list-contains? a b)` | `(List T) T -> Bool` | True when the element occurs. |
| `(list-index-of a b)` | `(List T) T -> (Option Int64)` | Index of the first occurrence. |
| `(list-sort a)` | `(List T) -> (List T)` | Stable ascending sort. |
| `(list-sort-by a b)` | `(fn [T] -> K) (List T) -> (List T)` | Stable ascending sort by a derived key. |
| `(map a b)` | `(fn [A] -> B) (List A) -> (List B)` | Apply a function to every element. |
| `(filter a b)` | `(fn [T] -> Bool) (List T) -> (List T)` | Keep elements satisfying a predicate. |
| `(fold a b c)` | `(fn [B A] -> B) B (List A) -> B` | Left fold with an initial accumulator. |
| `(range a b)` | `Int64 Int64 -> (List Int64)` | Half-open integer range; empty when start is not below end. |
| `(zip a b)` | `(List A) (List B) -> (List (Pair A B))` | Pair up elements, truncating to the shorter list. |
| `(list-sum a)` | `(List N) -> N` | Sum of elements. |
| `(list-min a)` | `(List T) -> (Option T)` | Least element, or none when empty. |
| `(list-max a)` | `(List T) -> (Option T)` | Greatest element, or none when empty. |

### 6.6 Map

| Form | Type | Meaning |
|---|---|---|
| `(map-empty)` | `-> (Map K V)` | The empty map. |
| `(map-get a b)` | `(Map K V) K -> (Option V)` | Value for a key, or none. |
| `(map-set a b c)` | `(Map K V) K V -> (Map K V)` | Map with the key bound to the value. |
| `(map-remove a b)` | `(Map K V) K -> (Map K V)` | Map without the key. |
| `(map-has? a b)` | `(Map K V) K -> Bool` | True when the key is present. |
| `(map-size a)` | `(Map K V) -> Int64` | Number of entries. |
| `(map-keys a)` | `(Map K V) -> (List K)` | Keys, sorted. |
| `(map-values a)` | `(Map K V) -> (List V)` | Values, ordered by sorted key. |
| `(map-pairs a)` | `(Map K V) -> (List (Pair K V))` | Entries as pairs, ordered by sorted key. |
| `(map-from-pairs a)` | `(List (Pair K V)) -> (Map K V)` | Build from pairs; later entries win. |

### 6.7 Option, Result, Pair

| Form | Type | Meaning |
|---|---|---|
| `(some a)` | `T -> (Option T)` | A present value. |
| `(none)` | `-> (Option T)` | An absent value. |
| `(ok a)` | `T -> (Result T E)` | A successful result. |
| `(err a)` | `E -> (Result T E)` | A failed result. |
| `(is-some? a)` | `(Option T) -> Bool` | True when a value is present. |
| `(is-none? a)` | `(Option T) -> Bool` | True when no value is present. |
| `(is-ok? a)` | `(Result T E) -> Bool` | True when the result succeeded. |
| `(is-err? a)` | `(Result T E) -> Bool` | True when the result failed. |
| `(option-or a b)` | `(Option T) T -> T` | The value, or a fallback when absent. |
| `(result-or a b)` | `(Result T E) T -> T` | The value, or a fallback on failure. |
| `(option-map a b)` | `(fn [A] -> B) (Option A) -> (Option B)` | Transform a present value. |
| `(result-map a b)` | `(fn [A] -> B) (Result A E) -> (Result B E)` | Transform a successful value. |
| `(result-map-err a b)` | `(fn [E] -> F) (Result T E) -> (Result T F)` | Transform a failure value. |
| `(option-to-result a b)` | `(Option T) E -> (Result T E)` | Absent becomes the given failure. |
| `(result-to-option a)` | `(Result T E) -> (Option T)` | Failure becomes absence. |
| `(pair a b)` | `A B -> (Pair A B)` | Construct a pair. |

### 6.8 I/O

| Form | Type | Meaning |
|---|---|---|
| `(read-line)` | `-> (Result (Option String) String)` | Read one line from standard input without its newline, or none at end of input. |
| `(read-all)` | `-> (Result String String)` | Read all of standard input. |
| `(print a)` | `String -> (Result Unit String)` | Write to standard output with no trailing newline. |
| `(println a)` | `String -> (Result Unit String)` | Write to standard output followed by a newline. |
| `(eprintln a)` | `String -> (Result Unit String)` | Write to standard error followed by a newline. |
| `(file-read a)` | `String -> (Result String String)` | Read a whole file as UTF-8 text. |
| `(file-write a b)` | `String String -> (Result Unit String)` | Write UTF-8 text to a file, replacing any existing contents. |
| `(file-exists? a)` | `String -> Bool` | True when the path exists. |
| `(env-get a)` | `String -> (Option String)` | Value of an environment variable, or none when unset. |
| `(args)` | `-> (List String)` | Command-line arguments, excluding the program name. |
| `(process-run a b c)` | `String (List String) String -> (Result ProcessResult String)` | Run a program with an argument list and standard input, capturing its output. The argument list is never a shell string, so there is no quoting to get wrong. |
## 7. Worked example

Complete, uses only forms defined above, and is the shape few-shot prompts should use.

```lisp
; Return the longest run of identical characters in s, as (Pair char length).
; Empty input yields (none).

(defun run-length [(chars (List String)) (cur String) (n Int64) (best (Pair String Int64))]
        -> (Pair String Int64)
  (match chars
    ((list)
     (if (> n (.-second best)) (pair cur n) best))
    ((cons h t)
     (if (= h cur)
       (run-length t cur (+ n 1) best)
       (let [(best2 (if (> n (.-second best)) (pair cur n) best))]
         (run-length t h 1 best2))))))

(defun longest-run [(s String)] -> (Option (Pair String Int64))
  (match (string-chars s)
    ((list)     (none))
    ((cons h t) (some (run-length t h 1 (pair h 1))))))
```

Note the ordering property from §1: every intermediate value is bound and computed before the
returned expression, in every branch.

---

## 8. Identifier mangling

Deterministic, because output that is not byte-reproducible cannot be differentially tested
(resolves A1).

| AgentScript | TypeScript | Python | Kotlin | Swift | Rust |
|---|---|---|---|---|---|
| `parse-html-url` | `parseHtmlUrl` | `parse_html_url` | `parseHtmlUrl` | `parseHtmlUrl` | `parse_html_url` |
| `Point` | `Point` | `Point` | `Point` | `Point` | `Point` |
| `empty?` | `isEmpty` | `is_empty` | `isEmpty` | `isEmpty` | `is_empty` |
| `set!` | `setMut` | `set_mut` | `setMut` | `setMut` | `set_mut` |

The Go columns were removed on 2026-08-21, when Go stopped being a priority target
(`EXPERIMENT.md` amendment `2026-08-21-b`). Go's two-case rule — capitalization carrying
visibility — is the one convention here that a target's *export list* would have had to drive.

Rules: strip a trailing `?` and prefix `is-`; strip a trailing `!` and suffix `-mut`; then split on
`-` and recase. Acronyms are not special-cased — `html` becomes `Html`, always.

**A qualified name flattens.** `alias/member` mangles as though the `/` were a `-`, so `s/concat`
becomes `s_concat` in Python and Rust and `sConcat` in Kotlin and Swift. The alias is a
module-local label, not a runtime object, so there is nothing to attribute-access on the target
side; leaving the separator in place produced output no target could parse.

| AgentScript | TypeScript | Python | Kotlin | Swift | Rust |
|---|---|---|---|---|---|
| `s/concat` | `sConcat` | `s_concat` | `sConcat` | `sConcat` | `s_concat` |
| `pl/read-csv` | `plReadCsv` | `pl_read_csv` | `plReadCsv` | `plReadCsv` | `pl_read_csv` |

This is also why §11's `:symbol` exists: the flattened name is what reaches the host, and mangling
cannot reproduce every host spelling.

If a mangled name collides with a target keyword, append `_`. **If two distinct AgentScript identifiers
mangle to the same target identifier, the compiler errors** — it does not silently rename. v0 had
no collision policy at all.

---

## 9. Conformance checklist

A Core program is well-formed iff:

1. Delimiters balance, and every form is a list, vector, map, or atom.
2. Every identifier is defined in §6, bound by `defun`/`fn`/`let`, declared by
   `defschema`/`defenum`, or imported under an alias declared in the module header.
3. Every `defun` declares parameter types and a return type.
4. Every `if` and `cond` is total; every `match` is exhaustive.
5. Every `try` sits in a `defun` returning a compatible `(Result _ E)`.
6. No numeric operation mixes types; all conversions are explicit.
7. No identifier begins with `as-`.
8. The module header carries a `:doc`, and every exported `defun` carries a `:doc`.
9. Every qualified name `alias/member` uses an alias bound in `:import`, and the member is
   exported by that module.
10. Every type variable used in a signature is bound in that declaration's `{ }`.
11. There are no import cycles.
12. Every `defun` or `defentry` that calls an effectful builtin (§10) declares `:effects [io]`,
    and so does every one that calls such a function transitively.
13. Every `defextern` carries a `:target`, and every module containing one is transpiled only to
    that target.
14. No `defopaque` value is inspected: it is passed to a `defextern` or bound, never destructured
    and never compared.
15. There is at most one `defentry` per program.

Rules 2, 5, 7-15 are **semantic**, not context-free: no grammar can enforce them, and the
conformance gate deliberately keeps such fixtures in `grammar/corpus/semantic/` so the untested
surface stays visible rather than appearing covered.

Rule 13's target half is the one semantic rule a *backend* enforces today rather than a checker:
each transpiler refuses a foreign declaration aimed elsewhere, and `backend/check_corpus.py`
asserts the refusal rather than skipping the fixture.

---

## 10. I/O

Every operation that touches the outside returns a `Result`. There is no trapping I/O and no
exception: a missing file, a closed stream and a program that will not start are all values.

The failure type is `String` — the host's own message. A structured `IoError` union was considered
and rejected for now: its cases would have to be identical across Python, Rust and Swift for the
differential gate to pass, and they are not. A host message is honest about what is actually
known at the boundary. The cost is that a caller can report a failure but cannot dispatch on its
kind; when that becomes load-bearing, a union is added and `String` becomes one of its cases.

The vocabulary is in §6 under **I/O**. Three properties are worth stating outside the table:

* **`process-run` takes an argv list, never a shell string.** `(process-run "git" (list "rev-parse"
  "HEAD") "")`. Nothing is re-parsed by a shell, so there is no quoting to get wrong and no
  injection surface to warn about — the shape removes it rather than documenting it.
* **`ProcessResult` is a built-in record**, read with `.-exit-code`, `.-stdout`, `.-stderr`, on the
  same footing as `Pair` (§3).
* **`read-line` returns `(Result (Option String) String)`.** End of input is `(none)`, which is not
  a failure; a failure is the outer `err`. Collapsing the two would make end-of-input
  indistinguishable from a broken pipe.

`file-exists?` and `env-get` are the two exceptions to the `Result` rule, and deliberately: neither
can fail, only answer. `file-exists?` returns `Bool` and `env-get` returns `(Option String)`. Both
are still effects (§4.6) — they read the outside world, and a target without one cannot run them.

### 10.1 Targets and capabilities

Not every target provides every effect, so the effect a function declares decides where it can
run:

| Target | Provides |
|---|---|
| `py`, `js`, `rs`, `sw` | `console`, `stdin`, `fs`, `env`, `proc` |
| `wasm` (browser) | `console` |

WebAssembly is reached through the Rust backend and `wasm32-unknown-unknown`; there is no separate
wasm code generator, and a pure module needs no new work to run in a browser. What does need
saying is the negative case: `rustc` links `std::fs` for that target without complaint, so a module
that reads files **compiles, ships, and fails at run time**. The capability check is what turns
that into a refusal naming the declaration.

## 11. Foreign functions

The reason the language exists (PCP `d-4b8c`). Three forms.

**`:extern` in the module header** names the host packages, and is the only place a host package
name appears — so a module's foreign dependencies are extractable without reading its body:

```lisp
(module data/frames
  :doc "Typed total boundary over the host dataframe library."
  :export [row-count]
  :extern [(py "polars" :as pl)])
```

**`defopaque`** names a host type this language passes but cannot inspect:

```lisp
(defopaque DataFrame
  :doc "A host dataframe: passed across the boundary, never inspected here.")
```

Without it, binding generation would stall on the first host type with no mapping. With it,
generation stays total: an unmodelled type becomes opaque rather than a failure.

**`defextern`** declares one host function:

```lisp
(defextern pl/read-csv [(path String)] -> DataFrame
  :doc "Read a CSV file into a dataframe."
  :target :py
  :symbol "read_csv")
```

`(defextern <alias>/<member> [<params>] -> <Type> [:doc <string>] :target <keyword> [:symbol
<string>])`.

* **The declared type is the SUCCESS type.** The call site sees `(Result T String)`. This is the
  rule the whole design rests on: there is no form that yields a bare host value, so a caller
  cannot use a foreign result without accounting for failure.
* **The name is kebab-case**, like every other identifier, and reaches the host through §8
  mangling. `:symbol` overrides that for the names mangling cannot reproduce — §8 does not
  special-case acronyms, so it cannot round-trip every host spelling, and pretending otherwise
  would make the escape hatch a silent wrong answer instead of an explicit one.
* **A host optional type maps onto `(Option T)`**, so absence is handled rather than discovered.
* **`:target` is mandatory.** A module containing any `defextern` belongs to that ecosystem; every
  other backend refuses it and names the offending declaration. This is not portable, and saying so
  in the type of the module is better than discovering it at run time.

**Bindings are generated, not written.** Runtime introspection of a host yields nothing useful, but
the separately shipped stub corpus covers the standard library broadly and a prototype produced
correct declarations from it, including optional types. Generation must parse stubs properly rather
than by pattern matching — a regex prototype produced visible defects. See `tools/bindgen/`.
