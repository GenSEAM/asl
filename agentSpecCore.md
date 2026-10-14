# agentSpecCore.md — AgentSlang Core

**Status:** normative for the language as the stage-0 host `asl/host/out/asl-host` reads, checks
and runs it (`asl-host check FILE`, `test FILE`, `run FILE`, `eval EXPR`). Where this document
states a rule the host does not enforce, it says so; such a rule is a target, not a description of
today. §9 lists every rule with its status. The concept-validation protocol that first scoped this
document is `EXPERIMENT.md`.

The vocabulary is not restated here in full. `prelude/prelude.asn` lists the builtins the host
binds, with types and docs, and `asl '(:help :builtin <text>)'` searches it (§6).

## 0. Scope

**In:** modules, `schema` (records), `enum` (closed unions), `fn` (named and anonymous), `let`,
`if`, `cond`, `mt` (`match`), `do`, `when`, `unless`, `assert`, `refute`, record update with
`with`, field access `x.f`, `Option`, `Result`, `Pair`, `List`, `Map`, strings, bytes, numeric
arrays, arithmetic and comparison over `Bool` / `Int32` / `Int64` / `Float64` / `String` /
`Unit`.

**Not in the language today:** a foreign-function form, a `try` or `?` propagation operator (the
host answers `ERR_UNKNOWN_SYMBOL try`), `for`, mutation (`set!`), and JSON naming: the host
accepts a field's `:json "name"` and does nothing with it, and a schema-level case option such as
`:jsonCase camel` is `ERR_BAD_DEFINITION`.

**I/O is in**, with its effects tracked: a function that touches the world carries `!` (§5.7),
`fileRead` fails with the closed union `IoError` (§3), and a program's entry point is `main`
(§4.0).

### Design commitments

The unit of one agent pass is a **working module**, so three things are in the language from the
start:

* **Modules by default** — every file is a module with an explicit exported surface, so a later
  pass can compose an earlier one having read only that surface.
* **Polymorphic signatures** — a type name the module does not declare, such as `A`, stands for
  any type (§4.2), so a user abstraction need not be duplicated per concrete type.
* **Closed unions and a keyed collection** — without the first, domain states get encoded as
  strings; without the second, ordinary programs are inexpressible.

Iteration is `map` / `filter` / `fold` / `range` plus recursion. There is no `for`: bindings are
immutable, so it would add nothing `fold` does not already provide.

---

## 1. Design rationale — why S-expressions

One evidence-backed reason, and the specification should not claim others.

Format-restricted generation degrades reasoning when the grammar **commits a result before the
reasoning that produced it**. Measured on GSM8K with GPT-3.5-turbo: natural language 75.99%,
JSON-shaped *instructions* 74.70%, JSON-*mode* constrained decoding **49.25%** — and the mechanism
is explicit, with 100% of JSON-mode responses emitting the `answer` key before the `reason` key,
converting chain-of-thought into direct answering (`researchReport.md` §3).

Constraint itself costs ~1.3 points. **Ordering costs ~27.**

A Lisp body is a sequence whose value is its tail expression: `let` bindings and intermediate
computation necessarily precede the returned value. The grammar therefore puts derivation before
result *structurally*, which is the opposite of a schema whose key order can commit an answer
first.

This is a claim about grammar shape, and it survives the fact that guaranteed syntactic validity
is commodity (`researchReport.md` §2.2). Claims about parser convenience or token efficiency are
**not** supported by located evidence and must not be made.

---

## 2. Lexical structure

The host's reader is `asl/host/src/reader.c`.

```
note       ::= string-lit                     ; free-standing, bound to nothing
meta       ::= ";" (:m ...)                   ; the only ; line the reader admits
ident      ::= any run of characters other than whitespace, ( ) [ ] { } " ; ,
qualified  ::= alias "/" name                 ; e.g. s/upper, s/Shape
field      ::= ident "." name ("." name)*     ; x.f, a.b.c; also ")" "." name after a form
keyword    ::= ":" ident
int-lit    ::= [+-]? [0-9]+
float-lit  ::= [+-]? [0-9]+ ( "." [0-9]+ )? ( [eE] [+-]? [0-9]+ )?   ; with a point or an exponent
string-lit ::= '"' ( char | newline | escape )* '"'
escape     ::= "\" ( '"' | "\" | "n" | "t" | "r" | "x" hex hex | "u" hex{4} | "u{" hex{1,6} "}" )
bool-lit   ::= "true" | "false"
unit-lit   ::= "()"
```

Identifiers are case-sensitive. Whitespace and commas separate tokens. A **note** is a string
literal bound to nothing, at top level or in a body; the host evaluates a top-level one at load and
discards it (`asl/grammar/corpus/valid/33-notes.asl`).

**Prose does not live in source.** A `;` line is legal only when it holds one `(:m ...)` meta form
without `:why`; any other `;` comment is `ERR_READ_COMMENT`, and a `:d` or `:doc` docstring is
`ERR_READ_DOC`. Documentation is a row `(:doc :symbol "path#name" :text "...")` in the package's
`doc.asn`, read by `asl '(:doc :symbol "path#name")'`.

**Names.** User and builtin names are camelCase whole words; a predicate ends in `?`, and an
effectful function may end in `!` (§5.7). The reader does not enforce the convention — `my-fn` and
`snake_name` load — but every builtin has exactly one camelCase spelling, and the hyphenated
spellings earlier versions used (`list-cons`, `read-line`, `str-find`, …) are
`ERR_UNKNOWN_SYMBOL`.

**Numbers.** A leading `-` is part of the literal when it touches the digits: `-1` is one token,
`- 1` is two, and `(-1 2)` applies the number `-1` and fails with `ERR_TYPE` when run. `.5` and `1.`
are not numbers (they read as names, so `.5` is `ERR_UNKNOWN_SYMBOL`). An integer literal outside
`Int64` is `ERR_INT_RANGE`; an exponent makes a float, so `1.5e3` is `1500.0`.

**Strings.** A raw newline inside a string literal is part of it. An escape outside the set above is
`ERR_BAD_ESCAPE`; there is no `\0`.

**Brackets.** Each kind pairs exactly: `( )` forms, `[ ]` vectors (lists, parameter and binding
vectors), `{ }` anonymous records, `{:a 1 :b "x"}`. A mismatch is `ERR_READ_UNBALANCED`.

`/` is both the division operator and the qualified-name separator. They never collide: division
is a standalone token, while a qualified name has no internal whitespace.

`agentslang-` is meant to be a **reserved identifier prefix** for compiler-internal names. The
host does not reject it (`asl/grammar/corpus/semantic/reservedPrefix.asl` checks clean).

### 2.1 Short and long spellings

A short spelling is significant only in the position named, and is an ordinary atom everywhere
else.

| Short | Long | Position | Host |
|---|---|---|---|
| `mt` | `match` | expression head | both read |
| `fn` | `lambda` | expression head | both read |
| `do` | `begin` | expression head | both read |
| `:x` | `:export` | module option | only `:x` is read; `:export` is ignored, so the module exports nothing |
| `:i` | `:import` | module option | only `:i` is read; `:import` is ignored |
| `:a` | `:as` | import entry | both read |
| `:f` | `:field` | list-form schema field | the host takes any keyword head |
| `:c` | `:case` | list-form enum case | only `:c`; `:case` is `ERR_BAD_DEFINITION` |

`(Point :x 3)` supplies a field called `x`, and no tool may rewrite it. This is why the table
carries a position column: a projection applied as text substitution corrupts any record whose
field is spelled like an option.

The list forms `(df ...)`, `(defun ...)`, `(def ...)`, `(dfs ...)`, `(defschema ...)`,
`(defenum ...)` and `(fn name ...)` at top level are `ERR_UNSUPPORTED_TOPLEVEL`.

Types have short spellings (`prelude/prelude.asn` `:types :aliases`):

| Alias | Type |
|---|---|
| `Int`, `I64` | `Int64` |
| `I32` | `Int32` |
| `F64`, `F32`, `Num`, `Float` | `Float64` |
| `Str` | `String` |

`F32` resolves to `Float64` — a **reserved width name** with none of that width's semantics: no
narrowing, no wrapping, no trap at the narrower boundary.

## 3. Types

| Type | Notes |
|---|---|
| `Bool` | `true` / `false`. No truthiness: `if`, `cond`, `and`, `or`, `not` and `assert` take `Bool` only. |
| `Int64` | Two's complement; overflow traps (§3.1). |
| `Int32` | An annotation and a conversion target (`int64ToInt32`). The host keeps no separate 32-bit arithmetic: `(+ v 1)` on an `Int32` of 2147483647 gives 2147483648. |
| `Float64` | IEEE-754 binary64. |
| `String` | UTF-8 bytes. **Lengths and indices are in bytes**: `(stringLength "héllo")` is 6, and a slice inside a multi-byte character splits it. `stringChars` yields characters. |
| `Unit` | Exactly one value, written `()`. |
| `Bytes`, `F64Array`, `I64Array`, `I8Array` | Byte buffers and flat numeric arrays (§6). |
| `(List T)` | Homogeneous, immutable, ordered. |
| `(Option T)` | `(some v)` \| `(none)`. |
| `(Result T E)` | `(ok v)` \| `(err e)`. |
| `(Pair A B)` | Built with `pair`, read with `pairFirst` / `pairSecond` or the pattern `(pair a b)`. |
| `(Map K V)` | Immutable keyed collection with sorted keys. The host accepts any key type, `Float64` included; a `NaN` key is never found again. |
| `IoError` | Closed union `(notFound)`, `(permissionDenied)`, `(alreadyExists)`, `(invalidPath)`, `(interrupted)`, `(other)`. |

**There is no implicit numeric conversion** — mixing `Int64` and `Float64` in one arithmetic form
is `ERR_TYPE_MISMATCH`, at check time where the types are known and at run time otherwise. Use
§6's explicit conversions. An unsuffixed integer literal is `Int64`; a literal with a point or an
exponent is `Float64`.

There is no nil and no exception: absence is `(none)`, failure is `(err e)`.

### 3.1 Integer overflow and division

An `Int64` operation whose exact result is not representable **traps** with `ERR_INT_OVERFLOW`:
`(+ a b)`, `(- a b)`, `(* a b)`, `(abs a)` at the minimum, `(/ a b)` for `MIN / -1`, and
`(listSum xs)`. Negation is `(- a)`; there is no `neg`.

Integer `/` **floors**: `(/ -7 2)` is `-4`. `mod` is the floored remainder, so its sign follows the
divisor: `(mod -7 3)` is `2`. A zero `Int` divisor traps (`ERR_DIV_ZERO`).

`(checkedDiv a b)` answers `(none)` in exactly the cases `/` traps on — a zero divisor and
`MIN / -1`; `(checkedMod a b)` answers `(none)` for a zero divisor. A conversion that cannot
represent its argument answers `(none)` rather than the nearest value:
`(float64ToInt64 1e30)` and `(stringToInt64 "9223372036854775808")` are both `(none)`.

### 3.2 Ordering and NaN

Comparison is IEEE-754: `<`, `<=`, `>` and `>=` are false when either operand is `NaN`, and
`(= nan nan)` is false. `<` and its kin compare two values of one type — `Int`, `Float`, `String`
(bytewise) or keyword (by name); any other pair, enum values included, is `ERR_TYPE`.

`listSort` and `listSortBy` are stable and put a `NaN` last: `(listSort (list 3.0 nan 0.5))` is
`(0.5 3.0 nan)`, and `listMin` / `listMax` agree with that order. `min` and `max` do not: with a
`NaN` operand their result depends on operand order (`(min nan 1.0)` is `nan`, `(min 1.0 nan)` is
`1.0`).

## 4. Declarations

### 4.0 `module` — modularity by default

Every source file is a module. The header is its contract, and it is readable without the body.

```lisp
(module text/casing
  :x [shout initials]
  :i [(core/strings :a s)
      (core/lists :a l)])
```

* `:x` — the public surface. **Everything not listed is private to the module.** An entry is a
  function or a type name; exporting a `schema` or `enum` publishes its fields or cases with it.
* `:i` — each entry binds a module to an alias (`:a`); members are then reached as `alias/name`,
  and an exported type as `alias/TypeName`. Using a member the module does not export is
  `ERR_NOT_EXPORTED`.

An import names the module a file **declares**, not its path. The loader (`asl/host/src/loader.c`)
resolves it from the nearest `.asl.config.asn` above the importer: a name qualified by that
workspace resolves inside it (`rest.asl`, `src/rest.asl`, then the declared name); a path
`first/rest` resolves in the package named `first` or in a `:dependencies` entry of the config; a
bare name resolves in the importing package, then in its manifest dependencies. A file with no
config above it can import nothing (`ERR_UNRESOLVED_IMPORT`).

A file with no `module` header is still a module, and exports nothing. Aliases are module-local.

**A module that exports `main` is a program.**

```lisp
(module tools/hello :x [main])

fn ! main args: (List String) -> (Result Unit IoError)
  (do (println "hello" (listLength args)) (ok ()))
```

`main` takes no parameter or one `(List String)`. `asl-host run FILE ARGS` exits 0 when it returns
`(ok v)`, exits `n` when it returns an `Int64` `n` or `(ok n)` with `n` in 0..255, and otherwise
fails with `ERR_MAIN_FAILED`. A module that exports `runTests` is a test (§5.8).

### 4.1 `schema` — records

Two spellings, the same declaration:

```lisp
(schema Config (:f name String) (:f retries Int64 :default 3))

schema Point
  x: Int64
  y: Int64
```

The list form is `(schema Name (:f field Type ["note"] [:default literal])...)`; the block form is a
bare column-0 line `schema Name` with one `field: Type` line per field below it. Only the list form
takes `:default`: the block form has no syntax for one, and a `:default` written there is ignored.
There are no type parameters on a schema: `(schema {T} Box ...)` is `ERR_BAD_DEFINITION`.

**Construction** names the fields; order is irrelevant: `(Point :x 3 :y 4)`, `(Config :name "svc")`
(retries defaults to 3). A PascalCase name in head position is a constructor. The host does not
reject a missing field or an unknown key at check time: a missing field fails when it is read
(`ERR_FIELD`), and an unknown key is stored on the record like a declared one.

**Field access** is `p.x`, chained as `a.b.c`, and on an expression as `(expr).f`. The earlier
accessor `(.-x p)` is `ERR_READ_FIELD`. **Update** is a copy: `(with p :x 5)` is `p` with field
`x` set to 5.

### 4.2 `fn` — named functions

```lisp
fn add a: Int64 b: Int64 -> Int64
  (+ a b)

fn safeDiv a: Int64 b: Int64 -> (Result Int64 String)
  (if (= b 0)
    (err "division by zero")
    (ok (/ a b)))
```

The header is a bare line starting in column 0, `fn [!] name p: Type ... -> Type`, and the body is
indented below it. The header is not a form, so the body closes only its own parentheses. The body
is one or more expressions evaluated in order; the value is the last one.

Every parameter carries a type (`ERR_UNTYPED_PARAM`), and the check pass compares argument and
return types against the signature (`ERR_TYPE_MISMATCH`) and call arity (`ERR_ARITY`). A name
defined twice is `ERR_DUPLICATE_DEFINITION`.

The optional `!` marks a function that **touches the world** (§5.7).

**Polymorphism.** A type name the module neither declares nor imports, such as `A` or `T`, stands
for any type:

```lisp
fn swap p: (Pair A B) -> (Pair B A)
  (mt p ((pair a b) (pair b a)))
```

There is no `{ }` binder: a misspelled concrete type name is read the same way, and the host
reports nothing for it (`asl/grammar/corpus/semantic/unboundTypevar.asl` checks clean).

Visibility comes from the module's `:x` list, not from position.

### 4.3 `fn` — lambdas

```lisp
(fn [(x Int64)] -> Int64 (* x 2))
(map (fn [x] (* x 2)) xs)
```

`(fn [<param>*] [-> Type] <body-expr>+)`, where each `<param>` is a name or `(name Type)`. A lambda
closes over the enclosing scope by value. Annotations may be elided where the call position
determines them. A lambda takes no `!` and no type parameters: `(fn ! [p] ...)` is
`ERR_BAD_LAMBDA`; its effects count toward the named function that encloses it (§5.7).

A lambda cannot name itself through the `let` that binds it (`ERR_LETREC`). Recursion is a
top-level `fn`, or a lambda that receives itself as a parameter.

### 4.4 `enum` — closed unions

```lisp
enum Shape (circle radius: Float64) (rectangle width: Float64 height: Float64) (point)

(enum Grade
  (:c steady [])
  (:c drifting [(by Float64)] "Spread too large."))
```

The block form is a bare line `enum Name (case field: Type ...) ...`; the list form is
`(enum Name (:c case [(field Type)...] ["note"])...)`. Case names are camelCase, and are used as
both constructors and patterns, exactly like the built-in `ok` / `some`; an importer writes them
`alias/case` in both positions:

```lisp
(mt sh
  ((circle r) (* 3.14159 (* r r)))
  ((rectangle w h) (* w h))
  ((point) 0.0))
```

Cases are positional: `(circle 2.0)`. Matching an enum must be exhaustive (§5.4).

## 5. Expressions

### 5.1 `let` — sequential, immutable

```lisp
(let [(n (stringLength s))
      (half (/ n 2))]
  (stringSlice s 0 half))
```

Bindings are evaluated **in order**, and each may refer to those before it. The flat spelling
`(let [n 1 m (+ n 1)] m)` is the same form. Bindings are **immutable** — there is no `set!`.
Shadowing an outer name is permitted. `let` is not recursive (`ERR_LETREC`).

### 5.2 `if`

```lisp
(if (< a b) a b)
```

The condition must be `Bool` (`ERR_TYPE_MISMATCH`). A two-armed `if` is total. A one-armed `if` is
accepted and yields `()` when the condition is false, so it type-checks only where `Unit` is
wanted; `when` and `unless` are the one-armed forms.

### 5.3 `cond`

```lisp
(cond
  ((< n 0) "negative")
  ((= n 0) "zero")
  (else "positive"))
```

Clauses are tested in order; the catch-all is `(else v)`. `(:else v)` is a keyword test and fails
with `ERR_TYPE_MISMATCH`. The host does not require the `else` clause: a `cond` with no clause
taken yields `()`.

### 5.4 `mt` (`match`)

```lisp
(mt (stringToInt64 s)
  ((some n) (* n 2))
  ((none) 0))
```

| Pattern | Matches |
|---|---|
| `(ok p)` / `(err p)` | a `Result` |
| `(some p)` / `(none)` | an `Option` |
| `(pair a b)` | a `Pair` |
| `(<case> p ...)` | an `enum` case, binding its fields positionally |
| literal | an equal `Int64`/`Bool`/`String` value |
| `<name>` | anything, binding it |
| `_` or `else` | anything, binding nothing |

A constructor argument is a name or `_`, so **patterns nest one level** (`ERR_BAD_PATTERN`). A list
is not a pattern — `(list)` and `(cons h t)` are `ERR_UNKNOWN_SYMBOL` there; take a list apart with
`listHead` and `listTail`. `:else` as a pattern is `ERR_ELSE_KEYWORD`.

A match over an `enum` must cover every case or end in a catch-all (`ERR_MATCH_NONEXHAUSTIVE`).

### 5.5 Results and options

There is no propagation operator. A `Result` or `Option` is taken apart with `mt`, or collapsed
with a fallback by `optionOr` / `resultOr`; `optionMap`, `resultMap`, `resultMapErr`,
`optionToResult` and `resultToOption` transform one without unwrapping it.

```lisp
fn parsePort text: String -> (Result Int64 String)
  (mt (listGet (stringSplit text ":") 1)
    ((none) (err "missing port"))
    ((some raw)
      (mt (stringToInt64 (stringTrim raw))
        ((none) (err "port is not a number"))
        ((some n) (if (> n 65535) (err "port out of range") (ok n))))))
```

### 5.6 Evaluation order

Strict, left to right, depth first. Arguments are fully evaluated before the call. `and` / `or`
short-circuit; nothing else does. `(do e1 e2 ...)` evaluates in order and yields the last value.

### 5.7 Effects

A named function is **effectful** when its body, including the lambdas inside it, names an
effectful builtin (the I/O section of §6) or a function marked effectful. It must then carry the
marker, written `fn ! name ...` or as a name ending in `!` (`fn readAll! ...`); otherwise
`asl-host check` reports `ERR_EFFECT_UNMARKED`. The check runs in `check` only; `test` and `run` do
not repeat it.

The marker is written on the signature and not inferred away, because the signature is what a
caller reads (§4.0). A marker on a function that performs no effect is legal.

### 5.8 Tests

A test module exports `fn runTests -> Bool`. `asl-host test FILE` runs it and passes when it
returns `true` after at least one `(assert cond "msg")` or `(refute cond "msg")` executed; zero
assertions is `ERR_TEST_FAILED`, and an assertion over a constant is `ERR_CONSTANT_ASSERT`. The
executed count is printed.

---

## 6. Closed vocabulary

`prelude/prelude.asn` is the list of builtins the host binds, as probed on its date, with each
one's type, section, defining source and doc; every name in it binds on the host. The host also
binds system builtins it does not list, such as the socket and file-descriptor calls `asl-net`
uses. `asl '(:help :builtin stringTo)'` searches the list by name, then by doc.

By section:

- **Arithmetic** — `+ - * / mod checkedDiv checkedMod abs min max trap floor ceil round clamp pow
  exp log log2 log10 sqrt sin cos tan atan2 isNan? isFinite? floatNan floatInf floatNegInf`
- **Comparison and logic** — `= == != not= < <= > >= and or not`
- **String** — `str stringConcat stringLength stringLines stringRepeat stringCountChar fnv1a64
  stringEmpty? stringSlice stringIndexOf stringContains? stringStartsWith? stringEndsWith?
  stringSplit stringJoin stringUpper stringLower stringTrim stringReverse stringReplace stringChars
  stringFromInt64 stringFromFloat64 stringToInt64 stringToFloat64`
- **Numeric conversion** — `int32ToInt64 int64ToInt32 int64ToFloat64 float64ToInt64`
- **List** — `list cons listEmpty? listLength listGet listHead listTail listAppend listReverse
  listSlice listContains? listIndexOf listSort listSortBy map filter fold parMap parFold range
  listTake listDrop listLast listAny? listAll? enumerate zip listSum listMin listMax partial`
- **Map** — `mapEmpty mapGet mapSet mapRemove mapHas? mapSize mapKeys mapValues mapPairs
  mapFromPairs`
- **Option, Result, Pair** — `some none ok err pair pairFirst pairSecond some? none? ok? err?
  optionOr resultOr optionMap resultMap resultMapErr optionToResult resultToOption`
- **I/O** (effectful) — the `IoError` cases, `print println eprintln fileExists? fileRead
  fileReadString fileReadBytes fileReadRange fileSize fileWrite fileAppend dirList fileStat
  fileLstat fileChmod fileFsync fileReadlink fileUtime pathSymlink processRun processSpawn
  processWait cpuCount procRusage platformInfo localDate procAlive? nowNs monotonicNs sleepMs envGet
  getHomeDir fileCreateExclusive dirCreate pathRemove pathRename realPath pathCanonicalize`
- **Bytes**, **Arrays**, **Parquet** — byte buffers and bit operations, `F64Array` / `I64Array` /
  `I8Array` kernels, and a Parquet reader; see `prelude/prelude.asn`.

Points that differ from what an LLM may expect: `print`, `println` and `eprintln` take any values,
separate them by spaces and return `()`; only `fileRead` and `pathCanonicalize` fail with
`IoError`, the other file calls with a `String` message; `resultMap` takes the `Result` first,
unlike `optionMap`; `stringLength`, `stringSlice` and `stringIndexOf` count bytes (§3).

`prelude/prelude.asn` `:absent` records names earlier versions declared and the host does not
bind: `read-line`, `read-all`, `file-append`, `try`.

## 7. Worked example

Complete, uses only forms defined above, and passes `asl-host check`.

```lisp
(module text/runs :x [longestRun])

fn runLength chars: (List String) cur: String n: Int64 best: (Pair String Int64) -> (Pair String Int64)
  (let [(better (mt best ((pair c k) (if (> n k) (pair cur n) best))))
        (rest (optionOr (listTail chars) (list)))]
    (mt (listHead chars)
      ((none) better)
      ((some h)
        (if (= h cur)
          (runLength rest cur (+ n 1) best)
          (runLength rest h 1 better)))))

fn longestRun s: String -> (Option (Pair String Int64))
  (let [(cs (stringChars s))]
    (mt (listHead cs)
      ((none) (none))
      ((some h) (some (runLength (optionOr (listTail cs) (list)) h 1 (pair h 1))))))
```

`(longestRun "aabbbc")` is `(some (pair "b" 3))` and `(longestRun "")` is `(none)`. Note the
ordering property from §1: every intermediate value is bound and computed before the returned
expression, in every branch. The same program is the fixture
`asl/grammar/corpus/valid/04-longest-run.asl`.

---

## 8. Identifier mangling

**Target design, partly implemented.** Output that is not byte-reproducible cannot be
differentially tested, so a name should mangle deterministically, and two distinct AgentSlang
names that mangle to one target name should be a compile error rather than a silent rename. Each
emitter carries its own mangler today, and no emitter implements the collision error:

| Emitter | Function | What it does |
|---|---|---|
| shared, Rust-style | `mangleIdent` in `asl/packages/asl-codegen/src/mangle.asl` | trailing `?` → `is_` prefix, trailing `!` → `_mut` suffix, `-` → `_`, a Rust keyword gets `_`; `core/strings` → `core_strings` |
| Rust | `rustMangleIdent` in `asl/packages/asl-target-rs/src/types.asl` | as above, with `r#` for raw-identifier keywords |
| TypeScript | `tsMangleIdent` in `asl/packages/asl-target-ts/src/types.asl` | trailing `?` → `is` prefix, hyphenated → camelCase, a keyword gets `_`, `a/b` → `a.b` |
| JS, Python, Go | `mangle` in `asl/packages/asl-ir/src/blocks.asl` | `f_`/`v_` prefix, every byte outside `[A-Za-z0-9]` becomes an escape and two hex digits (`$` in JS, `_` in Python and Go), so no keyword can clash |
| C | `mangleCIdent` in `asl/packages/asl-codegen/src/c99Mangle.asl` | C identifiers and module prefixes |

Sources are camelCase (§2), so most names pass through unchanged and only the `?` and `!` suffixes,
qualified names and keyword clashes are rewritten.

---

## 9. Conformance checklist

A Core program is well-formed iff the rules below hold. The status column is what
`asl-host check` does today; "not enforced" marks a target.

| # | Rule | Host |
|---|---|---|
| 1 | Delimiters balance and each bracket kind pairs exactly. | `ERR_READ_UNBALANCED` |
| 2 | Every name is a builtin (§6), bound by `fn`/`let`/a pattern, declared by `schema`/`enum`, or `alias/member` of an import. | `ERR_UNKNOWN_SYMBOL` |
| 3 | Every named `fn` declares its parameter types and return type. | `ERR_UNTYPED_PARAM` |
| 4 | Every `mt` over an enum is exhaustive. | `ERR_MATCH_NONEXHAUSTIVE` |
| 5 | Every `cond` ends in `(else v)`. | not enforced; an untaken `cond` yields `()` |
| 6 | No arithmetic mixes `Int64` and `Float64`; argument and return types match the signature. | `ERR_TYPE_MISMATCH`; `Int32` and `Int64` are not told apart |
| 7 | No identifier begins with `agentslang-`. | not enforced |
| 8 | No `:d` docstring and no free `;` comment. | `ERR_READ_DOC`, `ERR_READ_COMMENT` |
| 9 | Every `alias/member` uses an alias bound in `:i`, and the member is exported by that module; calls match its arity. | `ERR_NOT_EXPORTED`, `ERR_ARITY` |
| 10 | Every type variable in a signature is meant as one. | not enforced: there is no binder (§4.2) |
| 11 | There are no import cycles. | not enforced |
| 12 | Every function that names an effect is marked `!`. | `ERR_EFFECT_UNMARKED` |
| 13 | Every type in the signature of an exported `fn`, and in the fields or cases of an exported type, is a built-in, a type variable, or a type exported by the module that defines it. | not enforced |
| 14 | `:x` names only what the module declares, and never a bare enum case. | not enforced |
| 15 | A constructor supplies every field without a `:default`, and no unknown key. | not enforced; a missing field is `ERR_FIELD` when read |

`asl/grammar/corpus/semantic/` holds a fixture per rule violation, with the rule it violates in
its `asl/doc/grammar.asn` row. No suite asserts that the host rejects them: on 2026-10-14,
`asl-host check` rejects 18 of the 45 fixtures and checks the other 27 clean, and two of the 18
(`tryInLambda.asl`, `tryOutsideResult.asl`) fail only because `try` does not exist.
`asl/grammar/tests/corpusTest.asl` checks delimiter balance of the corpus, nothing more.
