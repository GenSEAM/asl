# Phase 2 — Vocabulary coverage inventory

Source of truth: `prelude/prelude.json` (107 builtins, v0.2). Exercised/unexercised computed by
re-running `grammar/closure_audit.py`'s own query (tree-sitter, `corpus/valid/*.agents` +
compilable spec fragments) — not re-derived by hand. Arity is the real parsed arity
(`prelude/vocab.parse_signature`), not `prelude/generate.py`'s `signature()` word-count heuristic,
which is wrong for any builtin taking a parenthesized compound-type argument (see caveat at end).

`py`/`rs` lowering presence: 100% by construction — `prelude/generate.py --check` (verified green,
exit 0) refuses to pass if any builtin lacks a `py`, `js`, or `rs` key. `go`: prelude.json has no
`go` key at all, and no `to_go.py` transpiler exists (`backend/golang/` holds only `rt/rt.go`, a
runtime skeleton with no builtin mapping). So the `go` column is `no` for all 107 rows uniformly —
tabulated below for completeness rather than repeated per row in prose.

## 1. Full builtin table

Columns: name | § group | arity | signature | exercised? | py | rs | go

### §1 Arithmetic

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `+` | 2 | `N N -> N` | yes | yes | yes | no |
| `-` | 2 | `N N -> N` | yes | yes | yes | no |
| `*` | 2 | `N N -> N` | yes | yes | yes | no |
| `/` | 2 | `N N -> N` | yes | yes | yes | no |
| `mod` | 2 | `N N -> N` | yes | yes | yes | no |
| `checked-div` | 2 | `N N -> (Option N)` | no | yes | yes | no |
| `checked-mod` | 2 | `N N -> (Option N)` | no | yes | yes | no |
| `neg` | 1 | `N -> N` | no | yes | yes | no |
| `abs` | 1 | `N -> N` | yes | yes | yes | no |
| `min` | 2 | `N N -> N` | no | yes | yes | no |
| `max` | 2 | `N N -> N` | yes | yes | yes | no |

### §2 Comparison and logic

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `=` | 2 | `T T -> Bool` | yes | yes | yes | no |
| `!=` | 2 | `T T -> Bool` | no | yes | yes | no |
| `<` | 2 | `T T -> Bool` | yes | yes | yes | no |
| `<=` | 2 | `T T -> Bool` | no | yes | yes | no |
| `>` | 2 | `T T -> Bool` | yes | yes | yes | no |
| `>=` | 2 | `T T -> Bool` | no | yes | yes | no |
| `and` | 2 | `Bool Bool -> Bool` | no | yes | yes | no |
| `or` | 2 | `Bool Bool -> Bool` | no | yes | yes | no |
| `not` | 1 | `Bool -> Bool` | no | yes | yes | no |

### §3 String

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `string-length` | 1 | `String -> Int64` | yes | yes | yes | no |
| `string-empty?` | 1 | `String -> Bool` | no | yes | yes | no |
| `str` | 1+ | `String... -> String` | yes | yes | yes | no |
| `string-slice` | 3 | `String Int64 Int64 -> (Option String)` | yes | yes | yes | no |
| `string-index-of` | 2 | `String String -> (Option Int64)` | no | yes | yes | no |
| `string-contains?` | 2 | `String String -> Bool` | no | yes | yes | no |
| `string-starts-with?` | 2 | `String String -> Bool` | no | yes | yes | no |
| `string-ends-with?` | 2 | `String String -> Bool` | no | yes | yes | no |
| `string-split` | 2 | `String String -> (List String)` | yes | yes | yes | no |
| `string-join` | 2 | `(List String) String -> String` | yes | yes | yes | no |
| `string-upper` | 1 | `String -> String` | yes | yes | yes | no |
| `string-lower` | 1 | `String -> String` | no | yes | yes | no |
| `string-trim` | 1 | `String -> String` | yes | yes | yes | no |
| `string-reverse` | 1 | `String -> String` | no | yes | yes | no |
| `string-replace` | 3 | `String String String -> String` | no | yes | yes | no |
| `string-chars` | 1 | `String -> (List String)` | yes | yes | yes | no |
| `string-from-int64` | 1 | `Int64 -> String` | yes | yes | yes | no |
| `string-from-float64` | 1 | `Float64 -> String` | no | yes | yes | no |
| `string-to-int64` | 1 | `String -> (Option Int64)` | yes | yes | yes | no |
| `string-to-float64` | 1 | `String -> (Option Float64)` | no | yes | yes | no |

### §4 Numeric conversion

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `int32-to-int64` | 1 | `Int32 -> Int64` | no | yes | yes | no |
| `int64-to-int32` | 1 | `Int64 -> (Option Int32)` | no | yes | yes | no |
| `int64-to-float64` | 1 | `Int64 -> Float64` | no | yes | yes | no |
| `float64-to-int64` | 1 | `Float64 -> (Option Int64)` | no | yes | yes | no |

### §5 List

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `list` | 1+ | `T... -> (List T)` | no | yes | yes | no |
| `list-empty?` | 1 | `(List T) -> Bool` | no | yes | yes | no |
| `list-length` | 1 | `(List T) -> Int64` | no | yes | yes | no |
| `list-get` | 2 | `(List T) Int64 -> (Option T)` | yes | yes | yes | no |
| `list-head` | 1 | `(List T) -> (Option T)` | yes | yes | yes | no |
| `list-tail` | 1 | `(List T) -> (Option (List T))` | no | yes | yes | no |
| `list-cons` | 2 | `T (List T) -> (List T)` | no | yes | yes | no |
| `list-append` | 2 | `(List T) (List T) -> (List T)` | no | yes | yes | no |
| `list-reverse` | 1 | `(List T) -> (List T)` | no | yes | yes | no |
| `list-slice` | 3 | `(List T) Int64 Int64 -> (Option (List T))` | no | yes | yes | no |
| `list-contains?` | 2 | `(List T) T -> Bool` | no | yes | yes | no |
| `list-index-of` | 2 | `(List T) T -> (Option Int64)` | no | yes | yes | no |
| `list-sort` | 1 | `(List T) -> (List T)` | no | yes | yes | no |
| `list-sort-by` | 2 | `(fn [T] -> K) (List T) -> (List T)` | yes | yes | yes | no |
| `map` | 2 | `(fn [A] -> B) (List A) -> (List B)` | yes | yes | yes | no |
| `filter` | 2 | `(fn [T] -> Bool) (List T) -> (List T)` | yes | yes | yes | no |
| `fold` | 3 | `(fn [B A] -> B) B (List A) -> B` | yes | yes | yes | no |
| `range` | 2 | `Int64 Int64 -> (List Int64)` | yes | yes | yes | no |
| `zip` | 2 | `(List A) (List B) -> (List (Pair A B))` | yes | yes | yes | no |
| `list-sum` | 1 | `(List N) -> N` | no | yes | yes | no |
| `list-min` | 1 | `(List T) -> (Option T)` | no | yes | yes | no |
| `list-max` | 1 | `(List T) -> (Option T)` | no | yes | yes | no |

### §6 Map

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `map-empty` | 0 | `-> (Map K V)` | yes | yes | yes | no |
| `map-get` | 2 | `(Map K V) K -> (Option V)` | yes | yes | yes | no |
| `map-set` | 3 | `(Map K V) K V -> (Map K V)` | yes | yes | yes | no |
| `map-remove` | 2 | `(Map K V) K -> (Map K V)` | no | yes | yes | no |
| `map-has?` | 2 | `(Map K V) K -> Bool` | no | yes | yes | no |
| `map-size` | 1 | `(Map K V) -> Int64` | no | yes | yes | no |
| `map-keys` | 1 | `(Map K V) -> (List K)` | no | yes | yes | no |
| `map-values` | 1 | `(Map K V) -> (List V)` | no | yes | yes | no |
| `map-pairs` | 1 | `(Map K V) -> (List (Pair K V))` | no | yes | yes | no |
| `map-from-pairs` | 1 | `(List (Pair K V)) -> (Map K V)` | no | yes | yes | no |

### §7 Option, Result, Pair

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `some` | 1 | `T -> (Option T)` | no | yes | yes | no |
| `none` | 0 | `-> (Option T)` | no | yes | yes | no |
| `ok` | 1 | `T -> (Result T E)` | no | yes | yes | no |
| `err` | 1 | `E -> (Result T E)` | no | yes | yes | no |
| `is-some?` | 1 | `(Option T) -> Bool` | no | yes | yes | no |
| `is-none?` | 1 | `(Option T) -> Bool` | no | yes | yes | no |
| `is-ok?` | 1 | `(Result T E) -> Bool` | no | yes | yes | no |
| `is-err?` | 1 | `(Result T E) -> Bool` | no | yes | yes | no |
| `option-or` | 2 | `(Option T) T -> T` | no | yes | yes | no |
| `result-or` | 2 | `(Result T E) T -> T` | no | yes | yes | no |
| `option-map` | 2 | `(fn [A] -> B) (Option A) -> (Option B)` | no | yes | yes | no |
| `result-map` | 2 | `(fn [A] -> B) (Result A E) -> (Result B E)` | no | yes | yes | no |
| `result-map-err` | 2 | `(fn [E] -> F) (Result T E) -> (Result T F)` | no | yes | yes | no |
| `option-to-result` | 2 | `(Option T) E -> (Result T E)` | yes | yes | yes | no |
| `result-to-option` | 1 | `(Result T E) -> (Option T)` | no | yes | yes | no |
| `pair` | 2 | `A B -> (Pair A B)` | no | yes | yes | no |

### §8 I/O

| name | arity | signature | exercised | py | rs | go |
|---|---|---|---|---|---|---|
| `not-found` | 0 | `-> IoError` | no | yes | yes | no |
| `permission-denied` | 0 | `-> IoError` | no | yes | yes | no |
| `already-exists` | 0 | `-> IoError` | no | yes | yes | no |
| `invalid-path` | 0 | `-> IoError` | no | yes | yes | no |
| `interrupted` | 0 | `-> IoError` | no | yes | yes | no |
| `other` | 0 | `-> IoError` | no | yes | yes | no |
| `read-line` | 0 | `-> (Result (Option String) IoError)` | no | yes | yes | no |
| `read-all` | 0 | `-> (Result String IoError)` | no | yes | yes | no |
| `print` | 1 | `String -> (Result Unit IoError)` | no | yes | yes | no |
| `println` | 1 | `String -> (Result Unit IoError)` | yes | yes | yes | no |
| `eprintln` | 1 | `String -> (Result Unit IoError)` | yes | yes | yes | no |
| `file-read` | 1 | `String -> (Result String IoError)` | yes | yes | yes | no |
| `file-write` | 2 | `String String -> (Result Unit IoError)` | yes | yes | yes | no |
| `file-append` | 2 | `String String -> (Result Unit IoError)` | no | yes | yes | no |
| `file-exists?` | 1 | `String -> (Result Bool IoError)` | no | yes | yes | no |

## 2. Missing-lowering list, per target

- **py**: none. Every builtin has a `py` key (`generate.py --check` enforces this; verified green).
- **rs**: none. Every builtin has an `rs` key, same enforcement.
- **go**: **all 107.** `prelude.json`'s schema has no `go` field at all, and no `backend/to_go.py`
  consumes the vocabulary. `backend/golang/rt/rt.go` is a standalone runtime skeleton (Option/Result
  generics, string/list/map helpers) with nothing wiring it to `prelude.json`'s builtin list. This
  matches ROADMAP.md §4 item 6 ("Native backends... Go") being un-started, not a per-builtin gap.

## 3. Smoke-compile findings (unexercised builtins only, 71 total)

61 of the 71 are **looks fine** on template inspection: arity matches the declared signature's
argument count, argument order in the template agrees with the declared parameter order, and (for
Rust) the runtime helper's own signature order agrees. `generate.py --check` also currently passes
(exit 0), so no un-doubled literal brace escapes the existing check for any of these 107 templates.

The following 10 do **not** look fine:

| name | verdict | reason |
|---|---|---|
| `list-sum` | **certainly broken** | Declared type is `(List N) -> N` — `N` is generic over `Int32`/`Int64`/`Float64`. Rust lowering is `rt::sum({0})`, and `rt.rs:82` is `pub fn sum(xs: Vec<i64>) -> i64 { xs.iter().sum() }` — hardcoded to `Vec<i64>`. Calling `list-sum` on a `(List Float64)` or `(List Int32)` will not typecheck. This is the same shape of bug ROADMAP.md §6 cites for the original `filter`/`list-sort-by` breakage: a generic-looking signature backed by a monomorphic helper. |
| `min` | suspicious | Rust lowering `std::cmp::min({0}, {1})` requires `N: Ord`. `N` includes `Float64` (`f64`), which implements only `PartialOrd`, not `Ord` (no total order — NaN). Calling `min` with two `Float64` arguments will not typecheck. (The already-exercised `max` shares this exact defect via `std::cmp::max` — untested because the corpus only calls it on integers.) |
| `list-sort` | suspicious | `rt::sort({0})` → `rt.rs:66 pub fn sort<T: Ord>(...)`. Requires `T: Ord`. A user `defenum` case only derives `Debug, Clone, PartialEq` (`backend/to_rust.py:137`) — no `Eq`/`PartialOrd`/`Ord`. Sorting a `(List MyEnum)` will not typecheck. `defschema` records do derive full `Ord` (`to_rust.py:128`), so this only bites enum element types. |
| `list-min` | suspicious | `rt::least(&{0})` → `rt.rs:83`, bound `T: Ord + Clone`. Same enum-derive gap as `list-sort`. |
| `list-max` | suspicious | `rt::greatest(&{0})` → `rt.rs:84`, bound `T: Ord + Clone`. Same enum-derive gap. |
| `map-keys` | suspicious | Underlying `BTreeMap<K, V>` requires `K: Ord` for essentially every operation. If `K` is a user `defenum` type, no map operation over it will typecheck — this template itself (`{0}.keys().cloned()...`) is fine, but it inherits the same root cause as the next four rows, and as the already-exercised `map-set`/`map-get` (untested with an enum key). |
| `map-has?` | suspicious | `{0}.contains_key(&{1})` — `BTreeMap::contains_key` requires `K: Ord`. Same root cause. |
| `map-remove` | suspicious | `rt::m_del({0}, &{1})` → `rt.rs:91`, bound `K: Ord`. Same root cause. |
| `map-pairs` | suspicious | `rt::m_pairs(&{0})` → `rt.rs:92`, bound `K: Ord + Clone`. Same root cause. |
| `map-from-pairs` | suspicious | `rt::m_from({0})` → `rt.rs:95`, bound `K: Ord`. Same root cause. |

Net: **the enum-Ord gap is one root cause** (`defenum` in `backend/to_rust.py:137` derives only
`Debug, Clone, PartialEq`), surfacing as 8 separate "suspicious" builtins above, plus it already
lurks — untested — behind exercised `map-set`/`map-get`/`max` whenever their type parameter is
instantiated to a user enum or to `Float64`. Fixing it once (derive `Eq, PartialOrd, Ord` on
non-recursive, all-comparable-field enums, or documenting the restriction) resolves all 8 at once.

## 4. Grouping proposal — 9 fixture themes for the 71 unexercised builtins

1. **I/O error surface** (11): `not-found`, `permission-denied`, `already-exists`, `invalid-path`,
   `interrupted`, `other`, `read-line`, `read-all`, `print`, `file-append`, `file-exists?`.
   Program: a log-appender CLI — check the log file exists, read one line from stdin, append it,
   and `match` every `IoError` case to a distinct exit message on failure.
2. **Option/Result constructors and predicates** (9): `some`, `none`, `ok`, `err`, `is-some?`,
   `is-none?`, `is-ok?`, `is-err?`, `pair`.
   Program: a coordinate parser that returns `(Pair (Option Int64) (Option Int64))` from split
   input, then reports presence/success with the predicates before combining.
3. **Option/Result transformation combinators** (6): `option-or`, `result-or`, `option-map`,
   `result-map`, `result-map-err`, `result-to-option`.
   Program: a config-value resolver — parse a setting, `option-map`/`result-map` it through a
   validator, fall back with `option-or`/`result-or`, and downgrade a validation failure to an
   absent value with `result-to-option`.
4. **Boolean algebra** (6): `!=`, `<=`, `>=`, `and`, `or`, `not`.
   Program: a range-membership checker (`lo <= x`, `x <= hi`, combined with `and`/`or`/`not`/`!=`
   for an exclusion list).
5. **Numeric conversion and bounded arithmetic** (8): `int32-to-int64`, `int64-to-int32`,
   `int64-to-float64`, `float64-to-int64`, `min`, `neg`, `checked-div`, `checked-mod`.
   Program: a fixed-point-to-float unit converter that narrows/widens between `Int32`/`Int64`/
   `Float64`, takes the `min` of two converted readings, and guards a derived ratio with
   `checked-div`.
6. **List construction and reshaping** (6): `list`, `list-cons`, `list-append`, `list-reverse`,
   `list-slice`, `list-tail`.
   Program: build a playlist by consing/appending tracks, then reverse and window-slice it for a
   "recently added" view.
7. **List querying and aggregation** (8): `list-empty?`, `list-length`, `list-contains?`,
   `list-index-of`, `list-sum`, `list-min`, `list-max`, `list-sort`.
   Program: a grade-book — check for an empty roster, look up a student by index, and compute
   sum/min/max/sorted order of scores. (Doubles as the fixture that would have caught `list-sum`'s
   `Float64` break above, if scores are floats.)
8. **Map lifecycle** (7): `map-remove`, `map-has?`, `map-size`, `map-keys`, `map-values`,
   `map-pairs`, `map-from-pairs`.
   Program: a word-frequency counter — build the map from `(word, count)` pairs, query/remove
   entries, then report size, keys, values and pairs.
9. **String inspection and transformation** (10): `string-empty?`, `string-index-of`,
   `string-contains?`, `string-starts-with?`, `string-ends-with?`, `string-lower`, `string-reverse`,
   `string-replace`, `string-from-float64`, `string-to-float64`.
   Program: a text sanitizer — lower-case and trim a line, check/replace a banned substring, verify
   prefix/suffix, and round-trip a parsed float back to string.

## 5. Counts

- **Exercised:** 36 / 107 (33%)
- **Unexercised:** 71 / 107 (67%)
- **Per-group breakdown** (exercised / unexercised / total):
  - Arithmetic: 7 / 4 / 11
  - Comparison and logic: 3 / 6 / 9
  - String: 10 / 10 / 20
  - Numeric conversion: 0 / 4 / 4
  - List: 8 / 14 / 22
  - Map: 3 / 7 / 10
  - Option, Result, Pair: 1 / 15 / 16
  - I/O: 4 / 11 / 15

## Caveat — unrelated bug noticed in passing

`prelude/generate.py`'s `signature()` (used to render every doc/handbook call-form, e.g.
`(list-slice a b c)`) computes arity as `len(lhs.split())` on the raw type string. This overcounts
whenever an argument type is itself parenthesized and multi-token: e.g. `list-get`'s real arity is
2 (`(List T) Int64 -> (Option T)`) but `lhs.split()` yields 3 tokens (`'(List'`, `'T)'`, `'Int64'`),
so the generated handbook/spec entry renders a 3-parameter call form for a 2-parameter builtin.
Affects every builtin whose first LHS token starts with `(` — at least `list-get`, `list-head`,
`list-tail`, `list-cons`, `list-append`, `list-reverse`, `list-slice`, `list-contains?`,
`list-index-of`, `list-sort`, `list-sort-by` (wrong by 4, since `(fn [T] -> K) (List T)` splits
into 6 tokens for a real arity of 2). Doc-generation defect, not a lowering defect — out of this
inventory's scope but worth a follow-up ticket since it affects agent-facing documentation (the
`HANDBOOK.md` resent on every model call).
