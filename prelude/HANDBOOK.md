# AgentScript — agent handbook

**Generated from `prelude/prelude.json`. Do not edit.**

Language version 0.2. This is the complete vocabulary: if a name is not on this page, it does not exist. Write nothing else.

Write the **Nano** spelling shown here. The long spelling of every form is equally valid and means the same thing — see Projection — but Nano is what the language stores and sends, so generating it directly saves a conversion.

## Shape

```lisp
"A note is a string bound to nothing — the only comment form."

(module my/mod
  :d "One sentence."
  :x [f Point]
  :i [(other/mod :a o)])

"NOTHING is public unless listed; a PascalCase entry exports a type."
"o/name is a value; o/Type is a type."

(dfs Point
  (:f x I64 "Doc."))
"doc is required on every field."

(dfe Shape
  (:c circle [(r F64)] "Doc.")
  (:c point  []         "Doc."))
"a closed union."

(df area [(s o/Shape)] -> F64
  :d "Doc."
  0.0)
"an imported type in a signature; its cases are (o/circle r)."

(df {A} id [(x A)] -> A
  :d "Required when exported."
  x)
"{A} binds a type variable."
```

## Projection

Each row is one form under two spellings. They parse to the same tree.

| Nano | Long |
|---|---|
| `df` | `defun` |
| `dfs` | `defschema` |
| `dfe` | `defenum` |
| `mt` | `match` |
| `:d` | `:doc` |
| `:x` | `:export` |
| `:i` | `:import` |
| `:a` | `:as` |
| `:f` | `:field` |
| `:c` | `:case` |

**A short spelling counts only in the position it names.** `:x` is the export list of a module header and nothing else, so a record whose field is called `x` is built with `(P :x 1)` and that key is an ordinary key. Reading these as global find-and-replace is what corrupts a record.

These forms have one spelling: `module`, `fn`, `let`, `if`, `cond`, `try`, `:else`, `:default`, `:json`, `:json-case`.

## Rules that have no exceptions

1. `if` takes exactly three parts — condition, then, else. There is no one-armed `if`.
2. `cond` must end with `:else`. `mt` must cover every case.
3. Bindings never change. There is no assignment.
4. Numbers never convert implicitly. Mixing `I64` and `F64` is an error.
5. Lookups that can fail return `(Option T)`. They never throw.
6. Read a record field with `(.-field r)`. Build one with `(Point :x 1 :y 2)`.
7. A name is a type variable only if it appears in that declaration's `{ }`.

## Handling failure

```lisp
(df or-zero [(s Str)] -> I64
  :d "Take apart an Option or a Result with mt."
  (mt (string-to-int64 s)
    ((some n) n)
    ((none)   0)))

(df f [(s Str)] -> (Result I64 Str)
  :d "try unwraps ok, or returns the err from f immediately."
  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]
    (ok (* n 2))))
```

`try` is legal only inside a `df` returning a `Result`. Prefer it over nested `mt`.

## Never write this

| Wrong | Right |
|---|---|
| `(if c x)` | `(if c x y)` — else is required |
| `(set! x 1)` | there is no assignment; bind a new name with `let` |
| `(+ 1 2.0)` | `(+ 1 (float64-to-int64 2.0))` — no implicit conversion |
| `(.x p)` | `(.-x p)` — the dash is part of field access |
| `(df f (x I64) ...)` | `(df f [(x I64)] ...)` — parameters are a vector |
| `(string->int64 s)` | `(string-to-int64 s)` — `->` is the return arrow only |
| `(nth xs 0)` | `(list-get xs 0)` — only names on this page exist |

## Forms

- Declarations: `module`, `dfs`, `dfe`, `df`
- Expressions: `fn`, `let`, `if`, `cond`, `mt`, `try`
- Constructors: `ok`, `err`, `some`, `none`, `list`, `pair`, `not-found`, `permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`
- Patterns: `ok`, `err`, `some`, `none`, `list`, `cons`, `pair`, `not-found`, `permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`, a literal, a name (binds), or `_`

## Types

- Primitive: `Bool`, `I32` (`Int32`), `I64` (`Int64`), `F64` (`Float64`), `Str` (`String`), `Unit`
- Constructed: `(List …)`, `(Option …)`, `(Result …)`, `(Pair …)`, `(Map …)`
- A `Map` key must be orderable: `Float64` is not a legal key type.
- Reserved width names — `F32` is `Float64`. They are accepted so source written for a narrower host type parses, and they carry none of that width's behaviour: no narrowing, no wrap, no trap at the narrower boundary. Do not reach for one to get a smaller number.

## Vocabulary

All 107 names. Nothing else exists.

### Arithmetic

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
| `(string-to-int64 a)` | `String -> (Option Int64)` | Parse an integer, or none when it is malformed or outside Int64. |
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
