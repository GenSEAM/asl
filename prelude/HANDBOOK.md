# AgentScript Core — agent handbook

**Generated from `prelude/prelude.json`. Do not edit.**

Language version 0.3. This is the complete vocabulary: if a name is not on this page, it does not exist. Write nothing else.

## Shape

```lisp
(module my/mod                  ; every file is a module
  :doc "One sentence."          ; required
  :export [f]                   ; NOTHING is public unless listed
  :import [(other/mod :as o)])  ; members reached as o/name

(defschema Point                ; a record
  (:field x Int64 "Doc."))      ; doc required on every field

(defenum Shape                  ; a closed union
  (:case circle [(r Float64)] "Doc.")
  (:case point  []            "Doc."))

(defun {A} id [(x A)] -> A      ; {A} binds a type variable
  :doc "Required when exported."
  x)
```

## Rules that have no exceptions

1. `if` takes exactly three parts — condition, then, else. There is no one-armed `if`.
2. `cond` must end with `:else`. `match` must cover every case.
3. Bindings never change. There is no assignment.
4. Numbers never convert implicitly. Mixing `Int64` and `Float64` is an error.
5. Lookups that can fail return `(Option T)`. They never throw.
6. Read a record field with `(.-field r)`. Build one with `(Point :x 1 :y 2)`.
7. A name is a type variable only if it appears in that declaration's `{ }`.
8. Anything that touches the outside returns a `Result`, and its caller declares the effects it reaches — transitively, so a wrapper declares them too.
9. Every foreign call is fallible. A `defextern` returning `T` is called as `(Result T String)` — there is no form that yields a bare host value.

## Handling failure

```lisp
(defun or-zero [(s String)] -> Int64
  :doc "match takes an Option or a Result apart."
  (match (string-to-int64 s)
    ((some n) n)
    ((none)   0)))

(defun f [(s String)] -> (Result Int64 String)
  :doc "try unwraps ok, or returns the err from f immediately."
  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]
    (ok (* n 2))))
```

`try` is legal only inside a `defun` returning a `Result`. Prefer it over nested `match`.

## Using another module

Only `:export`ed names are reachable, and only through the alias.

```lisp
(module report/render
  :doc "Render a tally line."
  :export [line]
  :import [(text/casing :as c)])

(defun line [(w String)] -> String
  :doc "Shout one word."
  (c/shout w))                  ; alias/name, never the module path
```

## Talking to the outside

`defentry` is the program's single entry point. Reading, writing and running programs are all fallible, so `try` does the unwrapping.

```lisp
(defun first-line [(path String)] -> (Result String String)
  :doc "First line of a file."
  :effects [fs]
  (let [(text (try (file-read path)))]
    (match (list-head (string-split text "\n"))
      ((some l) (ok l))
      ((none)   (err "empty file")))))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Print the commit, then the first line of the file named by argv."
  :effects [console fs proc]
  (let [(head (try (process-run "git" (list "rev-parse" "HEAD") "")))
        (line (try (first-line (option-or (list-head argv) ""))))]
    (try (print (.-stdout head)))   ; argv is a list — never a shell string
    (println line)))
```

## Using a host library

`:extern` names the host package, `defextern` declares one of its functions, and `defopaque` names a host type this language only passes along. **Every foreign call returns a `Result`** — the declared type is the success type.

```lisp
(module data/frames
  :doc "Typed total boundary over the host dataframe library."
  :export [row-count]
  :extern [(py "polars" :as pl)])

(defopaque DataFrame
  :doc "A host value this language passes but cannot inspect.")

(defextern pl/read-csv [(path String)] -> DataFrame
  :doc "Read a CSV into a dataframe."
  :target :py
  :symbol "read_csv")        ; the host spelling, which kebab-case cannot reach

(defextern pl/height [(df DataFrame)] -> Int64
  :doc "Row count of a dataframe."
  :target :py)

(defun row-count [(path String)] -> (Result Int64 String)
  :doc "Rows in a CSV, or the host failure as a value."
  (let [(df (try (pl/read-csv path)))]
    (ok (try (pl/height df)))))
```

A module with any `defextern` belongs to that one ecosystem: it is not portable, and a transpiler for another target refuses it by name.

## Never write this

| Wrong | Right |
|---|---|
| `(if c x)` | `(if c x y)` — else is required |
| `(set! x 1)` | there is no assignment; bind a new name with `let` |
| `(+ 1 2.0)` | `(+ 1 (float64-to-int64 2.0))` — no implicit conversion |
| `(.x p)` | `(.-x p)` — the dash is part of field access |
| `(defun f (x Int64) ...)` | `(defun f [(x Int64)] ...)` — parameters are a vector |
| `(string->int64 s)` | `(string-to-int64 s)` — `->` is the return arrow only |
| `(nth xs 0)` | `(list-get xs 0)` — only names on this page exist |
| `(string-length (file-read p))` | `(string-length (try (file-read p)))` — every outside call is a `Result` |
| `(process-run "git rev-parse HEAD" ...)` | `(process-run "git" (list "rev-parse" "HEAD") "")` — argv is a list |
| a `defun` calling `println` with no `:effects` | `:effects [console]` — name the effect you reach |
| `:effects [io]` | `io` is not an effect; it is `console`, `stdin`, `fs`, `env` or `proc` |
| `(defextern f [(x Int64)] -> Int64 :doc "…")` | add `:target` — a foreign declaration names its ecosystem |

## Forms

- Declarations: `module`, `defschema`, `defenum`, `defun`, `defentry`, `defextern`, `defopaque`
- Expressions: `fn`, `let`, `if`, `cond`, `match`, `try`
- Constructors: `ok`, `err`, `some`, `none`, `list`, `pair`
- Patterns: `ok`, `err`, `some`, `none`, `list`, `cons`, `pair`, a literal, a name (binds), or `_`
- Effects: `console`, `stdin`, `fs`, `env`, `proc` — the only names `:effects` accepts. Declare what you reach and nothing more: a target that cannot provide an effect refuses the module before it is built (a browser has `console` only).

## Types

- Primitive: `Bool`, `Int32`, `Int64`, `Float64`, `String`, `Unit`
- Constructed: `(List …)`, `(Option …)`, `(Result …)`, `(Pair …)`, `(Map …)`
- `Int` means `Int64`.
- Built-in records, read with `.-field`: `Pair` (`.-first`, `.-second`); `ProcessResult` (`.-exit-code`, `.-stdout`, `.-stderr`).

## Vocabulary

All 103 names. Nothing else exists.

### Arithmetic

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

### Comparison and logic

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

### String

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

### Numeric conversion

| Form | Type | Meaning |
|---|---|---|
| `(int32-to-int64 a)` | `Int32 -> Int64` | Widen. |
| `(int64-to-int32 a)` | `Int64 -> (Option Int32)` | Narrow, or none when out of range. |
| `(int64-to-float64 a)` | `Int64 -> Float64` | Convert to floating point. |
| `(float64-to-int64 a)` | `Float64 -> (Option Int64)` | Truncate toward zero, or none for NaN, infinity or out of range. |

### List

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

### Map

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

### Option, Result, Pair

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

### I/O

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
