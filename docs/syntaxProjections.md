# ASL Syntax & Projections

The language rules live in one place: the `language` topic of `asl/grammar/tools.asn`, printed by `asl '(:help :topic language)'` and rendered into [`llms.txt`](../llms.txt). This page is orientation on short spellings; where the two differ, the topic wins and this page is the bug.

ASL has one saved form, the compact one. A verbose projection (`defun`, `defschema`, `defenum`, `df`, `dfs`, `dfe`) is not a saved form: the stage-0 host rejects `(defun ...)`, `(defschema ...)`, `(df ...)` and `(dfs ...)` with ERR_UNSUPPORTED_TOPLEVEL and `dfe` with ERR_UNKNOWN_SYMBOL (`asl/host/out/asl-host test`, 2026-09-24). No tool renders a verbose view today; such a view is a target.

## The spellings the host accepts

| Spelling | Longer form also accepted | Significant in |
|---|---|---|
| `fn name a: T -> R` (bare line) | none | declaration |
| `(schema Name (:f field Type "doc") ...)` | `:field` for `:f` | declaration |
| `enum Name (case a: T) ...` or `(enum Name (:c case [params] "doc") ...)` | none | declaration |
| `mt` | `match` | expression head |
| `:d` | none | module header, `fn` body line |
| `:x` | none (`:export` does not export) | module header |
| `:i`, `:a` | none | module header, import spec |

Canonical type names are `Int64`, `Float64`, `String`, `Bool`, `(List T)`. The host does not check type names today: a function typed `Zzzq -> Zzzq` passes `asl-host check` and runs.

## The rule that matters

**A short spelling counts only in the position named above.** Everywhere else it is an ordinary atom. A record whose field is called `x` is built with `(Point :x 1.5 :y 2.0)`, and that key means a field, not an export list.

So a tool that converts spellings has to work on the parse tree, not on text. A regex that rewrites `:x` wherever it appears turns that record into `(Point :export 1.5 ...)`, which is a different program.

## Example

```asl
(module math/vector
  :d "Dot product and squared Euclidean norm over coordinate lists."
  :x [Point dot normSquared runTests])

(schema Point
  (:f x Float64 "Horizontal coordinate")
  (:f y Float64 "Vertical coordinate"))

fn dot a: (List Float64) b: (List Float64) -> Float64
  :d "Sum of the pairwise products of two coordinate lists."
  (listSum (map (fn [p] (mt p ((pair u v) (* u v)))) (zip a b)))

fn normSquared v: (List Float64) -> Float64
  :d "The squared Euclidean norm, which needs no square root."
  (dot v v)

fn runTests -> Bool
  (do (assert (= (dot (list 1.0 2.0) (list 3.0 4.0)) 11.0) "dot") (assert (= (normSquared (list 3.0 4.0)) 25.0) "norm") (assert (= (.-x (Point :x 1.5 :y 2.0)) 1.5) "x is a field here") true)
```

`zip` yields `(pair a b)` values, which are constructors taken apart with `mt`; `(.-first p)` is a type error. Note what the example does **not** do: there is no `sqrt` and no `list-zip-with`, because neither is in the vocabulary. The stage-0 host binds exactly the builtins of `host/src` (prelude.c, arrays.c, parquet.c) and the public fns of `prelude/prelude.asl`, and `host/out/asl-host check` rejects any other name with ERR_UNKNOWN_SYMBOL.
