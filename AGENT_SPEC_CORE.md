# AGENT_SPEC_CORE.md — AgentS-Core v0.1

**Status:** normative for the concept-validation experiment (`EXPERIMENT.md`).
Supersedes [`AGENT_SPEC.md`](AGENT_SPEC.md) (frozen as v0) for everything it covers.

This document is **closed**: every identifier used in any example here is defined here. That is
the property [`SPEC_REVIEW.md`](SPEC_REVIEW.md) §7 found missing in v0 (20 defined forms against
24 undefined ones), and it is a precondition for measuring generation reliability — a model
cannot be judged on forms the specification never gave it.

## 0. Scope

**In:** `defschema`, `defun`, `fn`, `let`, `if`, `cond`, `match`, `try`, records, `Result`,
`Option`, `Pair`, lists, strings, arithmetic, comparison, `Bool` / `Int32` / `Int64` / `Float64` /
`String` / `Unit`.

**Deliberately out of Core v0.1:** `defagent`, `defui`, `meta:async`, `if-target`, FFI, modules,
JSON serialization, user-defined sum types.

Two exclusions are load-bearing and deliberate:

* **No user-defined sum types.** HumanEval-class programs do not need them; a compiler does. Their
  absence is what makes the Stage 5 lexer probe informative rather than decorative. Prediction on
  record: the probe will fail without them (`EXPERIMENT.md` §7).
* **No FFI.** Core therefore contains no `(.method obj)` form at all, so the v0 collision
  ([`SPEC_REVIEW.md`](SPEC_REVIEW.md) C3) cannot arise. The `.-` field accessor is specified now
  anyway, so that reintroducing FFI later is additive rather than breaking.

### Deviation from the approved plan

The plan listed `for` among Core's iteration forms. It is **omitted**: Core has immutable bindings
and no mutation, so `for` would have no useful semantics that `fold` does not already provide.
Iteration is `map` / `filter` / `fold` / `range` plus recursion.

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
`agents-` is a **reserved identifier prefix** for compiler-internal names; user code using it is
rejected (precedent: Haxe's `_hx_`, `SPEC_REVIEW.md` §11.8). The prefix is deliberately spelled in
a form the identifier rule above can actually produce — a reserved word the lexer cannot emit
reserves nothing, and its conformance fixture would pass for an unrelated reason.

## 3. Types

| Type | Notes |
|---|---|
| `Bool` | `true` / `false`. No truthiness — `if` accepts `Bool` only. |
| `Int32`, `Int64` | Two's complement, wrapping is an error not a behavior; see §7.1 |
| `Float64` | IEEE-754 binary64 |
| `String` | Sequence of Unicode scalar values. **All indices are in characters, never bytes.** |
| `Unit` | Exactly one value, written `()` |
| `(List T)` | Homogeneous, immutable, ordered |
| `(Option T)` | `(some v)` \| `(none)` |
| `(Result T E)` | `(ok v)` \| `(err e)` |
| `(Pair A B)` | Built-in record, fields `first` / `second` |

`Int` is a documented alias for `Int64`. **There is no implicit numeric conversion** — mixing
`Int64` and `Float64` in one arithmetic form is a type error. Use §7.4's explicit conversions.

Fixing the widths resolves `SPEC_REVIEW.md` A3, which otherwise makes the same program overflow
differently on each of the four targets.

## 4. Declarations

### 4.1 `defschema`

```lisp
(defschema Point
  (:field x Int64 "Horizontal coordinate")
  (:field y Int64 "Vertical coordinate"))

(defschema Config
  (:field name    String "Display name")
  (:field retries Int64  "Attempt count" :default 3))
```

`(:field <ident> <Type> <doc-string> [:default <literal>] [:json <string>])`.
The doc-string is mandatory — it is cheap, and it is what an LLM reads.

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

`(defun <ident> [<params>] -> <Type> <body-expr>+)`. The parameter list is a **vector**, and `->`
is a literal token in the form, not an expression (resolves A9). The body is one or more
expressions evaluated in order; the value is the last one.

Parameters are vectors throughout the language — v0 used a list for `defun` and a vector for
`defui`, which was inconsistent (C4). Core standardizes on the vector.

Top-level `defun` and `defschema` are public; everything bound inside a body is local. Core has no
modules, so this is the only visibility distinction, and it is what drives Go's capitalization
(§9).

### 4.3 `fn`

```lisp
(fn [(x Int64)] -> Int64 (* x 2))
```

Anonymous function. Closes over the enclosing scope by value. Same shape as `defun` without a name.

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

Every builtin, with its type. Nothing outside this table and §4–5 exists in Core.

### 6.1 Arithmetic

`N` is `Int32`, `Int64`, or `Float64`; both operands and the result share one `N`.

| Form | Type |
|---|---|
| `(+ a b)` `(- a b)` `(* a b)` | `N N -> N` |
| `(/ a b)` | `N N -> N` — integer division truncates toward zero; **traps on zero divisor** |
| `(mod a b)` | `N N -> N` — sign follows the dividend; traps on zero |
| `(checked-div a b)` `(checked-mod a b)` | `N N -> (Option N)` — `(none)` on zero divisor |
| `(neg a)` `(abs a)` | `N -> N` |
| `(min a b)` `(max a b)` | `N N -> N` |

Overflow of `Int32`/`Int64` traps; it is never wrapping. This is one behavior across all four
targets by construction, which Go and TypeScript do not give for free.

### 6.2 Comparison and logic

| Form | Type |
|---|---|
| `(= a b)` `(!= a b)` | `T T -> Bool` — structural equality |
| `(< a b)` `(<= a b)` `(> a b)` `(>= a b)` | `T T -> Bool` for `N` and `String` |
| `(and a b)` `(or a b)` | `Bool Bool -> Bool`, short-circuiting |
| `(not a)` | `Bool -> Bool` |

### 6.3 String

Indices are character offsets. Out-of-range slicing yields `(none)`, never a trap.

| Form | Type |
|---|---|
| `(string-length s)` | `String -> Int64` |
| `(string-empty? s)` | `String -> Bool` |
| `(str a b …)` | `String… -> String` — variadic, `String` only |
| `(string-slice s start end)` | `String Int64 Int64 -> (Option String)` — half-open |
| `(string-index-of s sub)` | `String String -> (Option Int64)` |
| `(string-contains? s sub)` | `String String -> Bool` |
| `(string-starts-with? s p)` `(string-ends-with? s p)` | `String String -> Bool` |
| `(string-split s sep)` | `String String -> (List String)` |
| `(string-join parts sep)` | `(List String) String -> String` |
| `(string-upper s)` `(string-lower s)` `(string-trim s)` `(string-reverse s)` | `String -> String` |
| `(string-replace s from to)` | `String String String -> String` |
| `(string-chars s)` | `String -> (List String)` — one-character strings |
| `(string-from-int64 n)` `(string-from-float64 x)` | `Int64 -> String`, `Float64 -> String` |
| `(string-to-int64 s)` | `String -> (Option Int64)` |
| `(string-to-float64 s)` | `String -> (Option Float64)` |

Conversion builtins are named `-to-`, not `->`. Scheme's `->` convention collides directly with
the return-type token in `defun`, making `(string->int64 s)` ambiguous to any lexer. Found while
writing the grammar; recorded here because the ambiguity is invisible until you try to parse it.

`str` takes `String` only. Converting first is deliberate: it keeps the type rules total and gives
the transpiler nothing to guess.

### 6.4 Numeric conversion

| Form | Type |
|---|---|
| `(int32-to-int64 x)` | `Int32 -> Int64` |
| `(int64-to-int32 x)` | `Int64 -> (Option Int32)` |
| `(int64-to-float64 x)` | `Int64 -> Float64` |
| `(float64-to-int64 x)` | `Float64 -> (Option Int64)` — truncates; `(none)` if NaN/∞/out of range |

### 6.5 List

| Form | Type |
|---|---|
| `(list a b …)` | `T… -> (List T)` |
| `(list-empty? xs)` | `(List T) -> Bool` |
| `(list-length xs)` | `(List T) -> Int64` |
| `(list-get xs i)` | `(List T) Int64 -> (Option T)` |
| `(list-head xs)` | `(List T) -> (Option T)` |
| `(list-tail xs)` | `(List T) -> (Option (List T))` |
| `(list-cons x xs)` | `T (List T) -> (List T)` |
| `(list-append xs ys)` | `(List T) (List T) -> (List T)` |
| `(list-reverse xs)` | `(List T) -> (List T)` |
| `(list-slice xs start end)` | `(List T) Int64 Int64 -> (Option (List T))` |
| `(list-contains? xs x)` | `(List T) T -> Bool` |
| `(list-index-of xs x)` | `(List T) T -> (Option Int64)` |
| `(list-sort xs)` | `(List T) -> (List T)`, ordered `T`, stable ascending |
| `(list-sort-by f xs)` | `(fn [T] -> K) (List T) -> (List T)`, ordered `K`, stable |
| `(map f xs)` | `(fn [A] -> B) (List A) -> (List B)` |
| `(filter p xs)` | `(fn [T] -> Bool) (List T) -> (List T)` |
| `(fold f init xs)` | `(fn [B A] -> B) B (List A) -> B` — left fold |
| `(range start end)` | `Int64 Int64 -> (List Int64)` — half-open, empty if `start >= end` |
| `(zip xs ys)` | `(List A) (List B) -> (List (Pair A B))` — truncates to the shorter |
| `(list-sum xs)` | `(List N) -> N` |
| `(list-min xs)` `(list-max xs)` | `(List T) -> (Option T)`, ordered `T` |

### 6.6 Option, Result, Pair

| Form | Type |
|---|---|
| `(some v)` / `(none)` | `T -> (Option T)` / `(Option T)` |
| `(ok v)` / `(err e)` | `T -> (Result T E)` / `E -> (Result T E)` |
| `(is-some? o)` `(is-none? o)` | `(Option T) -> Bool` |
| `(is-ok? r)` `(is-err? r)` | `(Result T E) -> Bool` |
| `(option-or o default)` | `(Option T) T -> T` |
| `(result-or r default)` | `(Result T E) T -> T` |
| `(option-map f o)` | `(fn [A] -> B) (Option A) -> (Option B)` |
| `(result-map f r)` | `(fn [A] -> B) (Result A E) -> (Result B E)` |
| `(result-map-err f r)` | `(fn [E] -> F) (Result T E) -> (Result T F)` |
| `(option-to-result o e)` | `(Option T) E -> (Result T E)` |
| `(result-to-option r)` | `(Result T E) -> (Option T)` |
| `(pair a b)` | `A B -> (Pair A B)` |

`Pair` fields are read with `(.-first p)` and `(.-second p)` like any record.

---

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

Rules: strip a trailing `?` and prefix `is-`; strip a trailing `!` and suffix `-mut`; then split on
`-` and recase. Acronyms are not special-cased — `html` becomes `Html`, always.

If a mangled name collides with a target keyword, append `_`. **If two distinct AgentS identifiers
mangle to the same target identifier, the compiler errors** — it does not silently rename. v0 had
no collision policy at all.

---

## 9. Conformance checklist

A Core program is well-formed iff:

1. Delimiters balance, and every form is a list, vector, or atom.
2. Every identifier is defined in §6, bound by `defun`/`fn`/`let`, or is a `defschema` name.
3. Every `defun` declares parameter types and a return type.
4. Every `if` and `cond` is total; every `match` is exhaustive.
5. Every `try` sits in a `defun` returning a compatible `(Result _ E)`.
6. No numeric operation mixes types; all conversions are explicit.
7. No identifier begins with `agents-`.
