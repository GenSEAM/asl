# AGENT_SPEC_CORE.md — AgentS-Core v0.2

**Status:** normative for the concept-validation experiment (`EXPERIMENT.md`).
Supersedes [`AGENT_SPEC.md`](AGENT_SPEC.md) (frozen as v0) for everything it covers.

This document is **closed**: every identifier used in any example here is defined here. That is
the property [`SPEC_REVIEW.md`](SPEC_REVIEW.md) §7 found missing in v0 (20 defined forms against
24 undefined ones), and it is a precondition for measuring generation reliability — a model
cannot be judged on forms the specification never gave it.

## 0. Scope

**In:** modules, `defschema`, `defenum`, `defun`, `fn`, type parameters, `let`, `if`, `cond`,
`match`, `try`, records, `Result`, `Option`, `Pair`, `List`, `Map`, strings, arithmetic,
comparison, `Bool` / `Int32` / `Int64` / `Float64` / `String` / `Unit`.

**Deliberately out of Core:** `defagent`, `defui`, `meta:async`, `if-target`, FFI, JSON
serialization.

**I/O is in**, with its effects tracked: a declaration that touches the world carries `!` in its
signature (§4.2), failures are values of the closed union `IoError` (§3), and a program's entry
point is `main` (§4.0). The exclusion was defensible while the benchmark was pure functions; it is
not, now that the unit of measurement is a whole working program.

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

**No FFI *yet*.** This is a staging decision, not a permanent boundary: a total foreign-call
surface is the language's central rationale (PCP `d-4b8c`), and it will land here. Core omits it
only until the checker exists, because an untotal boundary is worse than none. Core contains no
`(.method obj)` form, so the v0 collision
([`SPEC_REVIEW.md`](SPEC_REVIEW.md) C3) cannot arise. The `.-` accessor is specified so that
reintroducing FFI later is additive rather than breaking.

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
qual-type  ::= ident "/" type-name             ; alias-qualified type, e.g. s/Shape
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
`agents-` is a **reserved identifier prefix** for compiler-internal names; user code using it is
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
| `(Map K V)` | Immutable keyed collection; `K` must support ordering and equality. `Float64` is not a legal key type: its equality is IEEE-754, so a `NaN` key could never be looked up again |
| `IoError` | Closed union of I/O failures: `(not-found)`, `(permission-denied)`, `(already-exists)`, `(invalid-path)`, `(interrupted)`, `(other)`. Fixed so every target reaches the same case for the same condition |

`Int` is a documented alias for `Int64`. **There is no implicit numeric conversion** — mixing
`Int64` and `Float64` in one arithmetic form is a type error. Use §6.4's explicit conversions.

An unsuffixed integer literal takes whichever integer type its context requires, and `Int64` where
nothing constrains it; a literal with a decimal point is always `Float64`. Without this a literal
would have to be written with a width to be usable at all, which is the ceremony §5 exists to
avoid — and leaving it unstated made `(+ x 1)` mean different things to different implementations.

A literal whose value does not fit the type its context requires is a **static error**, not an
overflow: nothing has been computed yet. This has to be said, because one host has no width to
notice with — `2147483648` at `Int32` answered itself on Python while `rustc` refused the same
literal.

A leading `-` is part of the literal when it touches the digits and the subtraction operator when it
does not: `-1` is one token, `- 1` is two, and `(- 1 2)` is arithmetic while `(-1 2)` applies the
number `-1` to `2` and is rejected. Both readings are legal parses of the same characters, so the
choice is normative rather than an implementation detail: the grammar is the constrained-decoding
surface, and an ambiguity there is a decoder that can emit either. There is no exponent form — a
number is an optional sign, digits, and optionally a point and more digits — so `1.5e3` is the
float `1.5` followed by the name `e3`, and `.5` and `1.` are not numbers at all.

Fixing the widths resolves `SPEC_REVIEW.md` A3, which otherwise makes the same program overflow
differently on each of the four targets.

### 3.1 Integer overflow

An integer operation whose exact result is not representable in the operand type **traps**. `Int32`
and `Int64` never wrap and never widen, so `(+ a b)`, `(- a b)`, `(* a b)`, `(neg a)`, `(abs a)`,
`(/ a b)` and `(list-sum xs)` all trap at their boundaries, and `(neg a)` and `(abs a)` do so at
`MIN` because two's complement is not symmetric. `(mod a b)` does not trap there: `MIN mod -1` is
`0`, which the type holds, and the rule is about the result rather than about the operands.

`(checked-div a b)` answers `(none)` in exactly the cases `/` traps on — a zero divisor and
`MIN / -1` — because being total is the reason it exists; `(checked-mod a b)` answers `(none)` only
for a zero divisor. A conversion that cannot represent its argument answers `(none)` rather than the
nearest value it can: `(float64-to-int64 1e30)` and `(string-to-int64 "9223372036854775808")` are
both `(none)`, not `9223372036854775807`.

A host without fixed integer widths has to impose them, and a host whose `-O` build wraps has to
check explicitly: the semantics are the language's, not the profile's.

### 3.2 Ordering and NaN

Comparison is IEEE-754. `<`, `<=`, `>` and `>=` are all false when either operand is `NaN`, and
`(= nan nan)` is false — including inside a container, so a list holding a `NaN` is not equal to
itself.

Ordering is not comparison. `list-sort`, `list-sort-by`, `list-min`, `list-max`, `min` and `max` use
one **sort order**, which is total because a sort with an unordered element has no defined output
and this language's output is defined on every target:

- a value holding a `NaN` sorts after every value that does not;
- values holding a `NaN` tie with one another, and every sort is stable, so they keep their input
  order;
- everything else is ordered as `<` orders it.

So `(list-sort (list 3.0 nan 0.5))` is `(0.5 3.0 nan)`, `(min nan 1.0)` and `(min 1.0 nan)` are both
`1.0`, and `(max …)` is `nan` from either side. Selection agrees with the sort — `(list-min xs)` is
the head of `(list-sort xs)` — rather than being a second rule that answers by operand position.
Leaving it to `<` alone is what made one host answer `(1.0 nan 2.0 3.0)` and the other
`(1.0 3.0 nan 2.0)` for the same input.

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
* `:export` — the public surface. **Everything not listed is private to the module.** An entry
  is a function name or a type name, and its case decides which: `:export [describe Shape]`
  publishes one of each. This is the only place in the language where spelling decides a kind,
  and it is a deliberate exception — a second `:export-types` vector would be a second
  contract, free to disagree with the first about what is public.
* `:import` — each entry binds a module path to a short alias; members are then reached as
  `alias/name`, and an exported type as `alias/TypeName`.

**An exported type is transparent.** Exporting a `defenum` publishes its cases, written
`alias/case-name` both as constructors and as patterns; exporting a `defschema` publishes its
fields, for construction and for `.-field` access. Exhaustiveness forces this: §9 rule 4
requires every `match` to cover its union, so an importer that cannot see every case cannot
write a legal one. There is no opaque form in v0.2, because an opaque type is an abstract
handle and what may be done with one depends on an ownership model this version deliberately
leaves unrecorded (PCP `l-880d`); the syntax is left additive so opacity can arrive later
without invalidating a program written now.

**A bare case name is not exportable.** Cases travel with their type, so `:export [circle]`
names nothing the module declares and violates rule 2. A second route to publishing a
constructor would be a second contract, and it would publish a constructor for a type no
importer can name.

**There is no re-export.** An entry must name a type or function this module declares, so
listing an imported type violates rule 2. A consumer of B need not import A to call a B
function whose signature mentions an A type — identity is by defining module, not by who is
looking — but it must import A the moment it needs to write that type itself.

**The contract is this header together with the declarations of the types it exports.** Under
transparent export the vector seeds the public surface rather than being the whole of it, so a
mechanical extractor reads both; both are in the same file, which is what keeps the surface
readable without the bodies.

A file with no `module` header is still a module: its path relative to the source root becomes its
name, its `:doc` is absent, and **nothing is exported**. Modularity is the default; the header
only names and opens it.

Private-by-default is the deliberate choice. An explicit export list is a stable surface to
program against, and it is the one part of a module another pass must read — which is exactly the
property being optimised when the unit of work is a whole module.

Import cycles are an error. Aliases are module-local and may be chosen freely.

**A module that declares `main` is a program.** The entry point is

```lisp
(defun ! main [(args (List String))] -> (Result Unit IoError))
```

and its `Result` is the process's exit status: `ok` exits zero, `err` exits non-zero with the case
name on standard error. Arguments arrive as a parameter rather than through a hidden global, so the
program's input is visible in its contract and testable without substituting an environment. A
module without `main` is a library and gets no entry point.

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

`(defun [!] [{<type-vars>}] <ident> [<params>] -> <Type> [:doc <string>] <body-expr>+)`. The
parameter list is a **vector**, and `->` is a literal token in the form, not an expression
(resolves A9). The body is one or more expressions evaluated in order; the value is the last one.

The optional `!` marks a function that **touches the world** — anything in §6's I/O group, or
anything that calls something marked. It is written on the signature and not inferred away,
because the signature is what a caller reads (§4.0); a marker on a function that turns out to
perform no effect is legal, since tightening a contract later must not break its callers. Calling a
marked function from an unmarked one is an error (§5.7).

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
definition that is not exported is private to its module, and that is what drives Go's
capitalization (§8). A `defschema` or `defenum` is exported by naming it on that same list,
and its fields or cases travel with it.

### 4.3 `fn`

```lisp
(fn [(x Int64)] -> Int64 (* x 2))    ; annotated
(map (fn [x] (* x 2)) xs)            ; annotations elided: `map` fixes them
```

`(fn [!] [<param>*] [-> <Type>] <body-expr>+)`, where each `<param>` is `<ident>` or
`(<ident> <Type>)`. Anonymous function, closing over the enclosing scope by value. A lambda carries
its own effect marker: `(map (fn ! [p] (file-read p)) paths)` is how one `map` serves both kinds
without a second, effectful copy of it.

**Annotations are optional where the position determines them.** A lambda passed to a callee whose
signature fixes its parameter and return types cannot carry an annotation that differs from what
the position implies, so writing one carries no information. Where nothing determines them — a
lambda bound by `let` and never applied, say — they are **required**, and a checker rejects the
elision rather than typing the lambda by accident of what its body happens to allow.

Named declarations are the opposite case and keep their mandatory annotations: `defun`, `defschema`
and `defenum` are the module surface, read without the body (§4.0).

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
both constructors and patterns within their own module, exactly like the built-in `ok` /
`some`; an importer writes them `alias/case-name` in both positions (§4.0):

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
matching `E`, and **not inside an `fn`** — a lambda is not the function `try` returns from, so the
form there has no meaning to give it.

Together `match` and `try` resolve `SPEC_REVIEW.md` B1 — v0 could construct `ok`/`err` and had no
way to consume them, making every I/O-shaped program unwritable. Precedent: Gleam's
`use`/`result.try` and Rust's `?` (§11.2). `try` exists specifically because `match`-only code
nests deeply, and nesting depth is the dominant LLM syntax-failure mode.

### 5.6 Evaluation order

Strict, left to right, depth first. Arguments are fully evaluated before the call. `and` / `or`
short-circuit; nothing else does. The compiler may not reorder or elide any call (resolves G9).

### 5.7 Effects

A form is **effectful** when it calls an I/O builtin (§6), calls a function marked `!`, or hands a
lambda marked `!` to something. An effectful form is legal only inside a `defun` or `fn` that
carries the marker; otherwise it is an error (§9 rule 12).

Effects need no ordering rule of their own: §5.6 already fixes evaluation as strict, left to right,
with no reordering or elision, and `let` is already the sequencing form. What the marker buys is
not ordering but *visibility* — a caller sees that a function touches the world without reading its
body, and the language keeps the option of adding concurrency later without colouring every
function retroactively.

The rule over-approximates in one place, deliberately: a marked lambda that is passed somewhere and
never applied still makes the call that received it effectful. Deciding otherwise would mean
carrying effects inside the type of a function, which is the machinery this design is avoiding.

---

## 6. Closed vocabulary

Every builtin, with its type. Nothing outside this table and §4-5 exists in Core.

**Generated from `prelude/prelude.json`** — edit there, not here.

### 6.1 Arithmetic

| Form | Type | Meaning |
|---|---|---|
| `(+ a b)` | `N N -> N` | Sum. Traps on integer overflow. |
| `(- a b)` | `N N -> N` | Difference. Traps on integer overflow. |
| `(* a b)` | `N N -> N` | Product. Traps on integer overflow. |
| `(/ a b)` | `N N -> N` | Division; integer division truncates toward zero. Traps on a zero divisor and on a quotient outside the type. |
| `(mod a b)` | `N N -> N` | Remainder; the sign follows the dividend. Traps on a zero divisor. |
| `(checked-div a b)` | `N N -> (Option N)` | Division, or none on a zero divisor or a quotient outside the type. |
| `(checked-mod a b)` | `N N -> (Option N)` | Remainder, or none on a zero divisor; the remainder is always in range. |
| `(neg a)` | `N -> N` | Arithmetic negation. Traps on integer overflow. |
| `(abs a)` | `N -> N` | Absolute value. Traps on integer overflow. |
| `(min a b)` | `N N -> N` | Lesser of two values in the sort order, so NaN is the greater. |
| `(max a b)` | `N N -> N` | Greater of two values in the sort order, so NaN is the greater. |

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
| `(string-to-int64 a)` | `String -> (Option Int64)` | Parse an integer, or none when it is malformed or outside Int64. |
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
| `(list-sort a)` | `(List T) -> (List T)` | Stable ascending sort; a value holding a NaN sorts last. |
| `(list-sort-by a b)` | `(fn [T] -> K) (List T) -> (List T)` | Stable ascending sort by a derived key; a key holding a NaN sorts last. |
| `(map a b)` | `(fn [A] -> B) (List A) -> (List B)` | Apply a function to every element. |
| `(filter a b)` | `(fn [T] -> Bool) (List T) -> (List T)` | Keep elements satisfying a predicate. |
| `(fold a b c)` | `(fn [B A] -> B) B (List A) -> B` | Left fold with an initial accumulator. |
| `(range a b)` | `Int64 Int64 -> (List Int64)` | Half-open integer range; empty when start is not below end. |
| `(zip a b)` | `(List A) (List B) -> (List (Pair A B))` | Pair up elements, truncating to the shorter list. |
| `(list-sum a)` | `(List N) -> N` | Sum of elements, 0 when empty. Traps on integer overflow. |
| `(list-min a)` | `(List T) -> (Option T)` | Least element in the sort order, or none when empty. |
| `(list-max a)` | `(List T) -> (Option T)` | Greatest element in the sort order, or none when empty. |

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
| `(not-found)` | `-> IoError` | The not found failure. |
| `(permission-denied)` | `-> IoError` | The permission denied failure. |
| `(already-exists)` | `-> IoError` | The already exists failure. |
| `(invalid-path)` | `-> IoError` | The invalid path failure. |
| `(interrupted)` | `-> IoError` | The interrupted failure. |
| `(other)` | `-> IoError` | The other failure. |
| `(read-line)` | `-> (Result (Option String) IoError)` | Read one line from standard input; none at end of input. |
| `(read-all)` | `-> (Result String IoError)` | Read all of standard input. |
| `(print a)` | `String -> (Result Unit IoError)` | Write to standard output with no trailing newline. |
| `(println a)` | `String -> (Result Unit IoError)` | Write a line to standard output. |
| `(eprintln a)` | `String -> (Result Unit IoError)` | Write a line to standard error. |
| `(file-read a)` | `String -> (Result String IoError)` | Read a whole file as text. |
| `(file-write a b)` | `String String -> (Result Unit IoError)` | Write text to a file, replacing it. |
| `(file-append a b)` | `String String -> (Result Unit IoError)` | Append text to a file, creating it if absent. |
| `(file-exists? a)` | `String -> (Result Bool IoError)` | Whether a path exists. |
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

| AgentS | TypeScript | Python | Go (top-level) | Go (local) | Rust |
|---|---|---|---|---|---|
| `parse-html-url` | `parseHtmlUrl` | `parse_html_url` | `ParseHtmlUrl` | `parseHtmlUrl` | `parse_html_url` |
| `Point` | `Point` | `Point` | `Point` | `Point` | `Point` |
| `empty?` | `isEmpty` | `is_empty` | `IsEmpty` | `isEmpty` | `is_empty` |
| `set!` | `setMut` | `set_mut` | `SetMut` | `setMut` | `set_mut` |
| `s/parse-html-url` | — | `core_strings__parse_html_url` | — | — | `core_strings::parse_html_url` |
| `s/Point` | — | `core_strings__Point` | — | — | `core_strings::Point` |

Rules: strip a trailing `?` and prefix `is-`; strip a trailing `!` and suffix `-mut`; then split on
`-` and recase. Acronyms are not special-cased — `html` becomes `Html`, always.

A qualified name mangles as its member would unqualified, prefixed by its **defining module
path** — never by the alias, which is module-local and would give one definition two names.
The path itself mangles segment by segment and the segments are joined by the target's own
namespace separator, shown above for the two targets that have a backend; `—` marks a target
whose separator is fixed when that backend lands.

If a mangled name collides with a target keyword, append `_`. **If two distinct AgentS identifiers
mangle to the same target identifier, the compiler errors** — it does not silently rename. v0 had
no collision policy at all. The same applies to module paths: `core/shapes` and a module named
`core-shapes` mangle alike under either scheme above, and the collision is an error rather than
a silent merge.

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
7. No identifier begins with `agents-`.
8. The module header carries a `:doc`, and every exported `defun` carries a `:doc`.
9. Every qualified name `alias/member` uses an alias bound in `:import`, and the member — a
   function, a type name, or a case of an exported union — is exported by that module.
10. Every type variable used in a signature is bound in that declaration's `{ }`.
11. There are no import cycles.
12. Every effectful form sits inside a `defun` or `fn` marked `!`.
13. Every type named in the signature of an exported `defun`, in every field type of an
    exported `defschema`, and in every case-parameter type of an exported `defenum`, is a §3
    built-in, a type variable bound in that declaration's `{ }`, or a type exported by the
    module that defines it. A signature naming a private type is not a contract: no importer
    can write the type of what it receives.

Rules 2, 5, 6, 7-13 are **semantic**, not context-free, and so is the `match` half of rule 4 —
`if` and `cond` totality is the only part of it a grammar reaches. No grammar can enforce them, and the
conformance gate deliberately keeps such fixtures in `grammar/corpus/semantic/` so the untested
surface stays visible rather than appearing covered.

The list is necessary, not sufficient: §4.1's construction rules (every field without a `:default`
supplied, no unknown or duplicate keys) and type correctness generally are enforced alongside it.
Each fixture in `grammar/corpus/semantic/` names the rule it violates, and the gate asserts that
rule specifically — a fixture rejected for the wrong reason is a failure there.
